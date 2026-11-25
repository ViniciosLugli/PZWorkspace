package lugli.fastloading;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.GameWindow;
import zombie.core.opengl.RenderThread;
import zombie.debug.DebugLog;
import zombie.tileDepth.TileDepthTextures;
import zombie.tileDepth.TilesetDepthTexture;

/**
 * Moves the depth-map PNG decode out of TileDepthTextures' global monitor.
 * -Dfastloading.tiledepth=off.
 *
 * The engine wraps the whole LoadTask body in synchronized (textures), so every tileset decodes
 * one at a time. Only the map access needs the lock.
 *
 * MUST still hold `textures` for the getTilesetRows read: loadDepthTextureImages puts into that
 * map and submits the task in the same loop iteration, so narrowing the lock too far turns one
 * concurrent reader into ten on a plain HashMap mid-resize. A wrong row count builds a
 * wrong-sized tileset, which renders as a depth artefact rather than failing loudly.
 *
 * MUST bound the decoded tiles waiting for the render thread. Each tile keeps its float[] and an
 * RGBA direct buffer until its render items run, and the render thread drains only 10 ms of its queue per frame, so
 * parallel decoders outrun it: a 367-mod list queued 2.5 GB and died of OutOfMemoryError at 6 GB.
 * A tileset reserves its worst case before it decodes and releases it from a marker queued behind
 * its own tiles; a full budget makes the decoder wait on a blocking no-op, which forces the render
 * thread to drain everything ahead of it.
 */
@Patch(className = "zombie.tileDepth.TileDepthTextures$LoadTask", methodName = "call")
public final class TileDepthLock {

    public static final String TAG = "[FastLoading/tiledepth]";

    /** public: these are read from a body inlined into zombie.tileDepth.TileDepthTextures$LoadTask. */
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.tiledepth", "on"));

    public static final ConcurrentHashMap<String, Object> LOCKS = new ConcurrentHashMap<>();
    public static volatile boolean broken;
    public static int handled;
    public static boolean announced;

    public static final long QUEUE_BUDGET = Tuning.depthQueueBytes(Runtime.getRuntime().maxMemory());
    public static final AtomicLong QUEUED = new AtomicLong();
    public static final AtomicLong PEAK_QUEUED = new AtomicLong();
    public static final AtomicInteger DRAIN_WAITS = new AtomicInteger();

    public static Field fPath;
    public static Field fTextures;
    public static Field fTilesets;
    public static Method mGetRows;
    public static Constructor<TilesetDepthTexture> ctor;

    private TileDepthLock() {}

    /** For the menu handover line, so a part that did nothing says so. */
    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return "ok, " + handled + " depth tileset(s) decoded outside the lock, peak "
                + (PEAK_QUEUED.get() >> 20) + " of " + (QUEUE_BUDGET >> 20) + " MB awaiting upload, "
                + DRAIN_WAITS.get() + " drain wait(s)";
    }

    /** Blocks until bytes fit the budget. One tileset always fits an empty queue, so no task starves. */
    public static void reserve(long bytes) {
        for (;;) {
            long cur = QUEUED.get();
            if (cur == 0 || cur + bytes <= QUEUE_BUDGET) {
                if (QUEUED.compareAndSet(cur, cur + bytes)) {
                    long peak;
                    while ((peak = PEAK_QUEUED.get()) < cur + bytes) {
                        if (PEAK_QUEUED.compareAndSet(peak, cur + bytes)) {
                            if ((cur + bytes) * 4 / QUEUE_BUDGET > peak * 4 / QUEUE_BUDGET) {
                                DebugLog.log(TAG + " " + ((cur + bytes) >> 20) + " of " + (QUEUE_BUDGET >> 20)
                                        + " MB of decoded depth tiles awaiting upload");
                            }
                            break;
                        }
                    }
                    return;
                }
                continue;
            }
            if (GameWindow.gameThreadExited || RenderThread.isCloseRequested()) {
                QUEUED.addAndGet(bytes);
                return;
            }
            if (DRAIN_WAITS.incrementAndGet() == 1) {
                DebugLog.log(TAG + " upload budget full at " + (cur >> 20)
                        + " MB: decoders now wait for the render thread to drain");
            }
            RenderThread.invokeOnRenderContext(new Release(0L));
        }
    }

    /** Queued behind the tileset's own upload lambdas, so it runs after the last of them. */
    public static void release(long bytes) {
        RenderThread.queueInvokeOnRenderContext(new Release(bytes));
    }

    public static final class Release implements Runnable {
        private final long bytes;

        public Release(long bytes) {
            this.bytes = bytes;
        }

        @Override
        public void run() {
            if (bytes != 0L) {
                QUEUED.addAndGet(-bytes);
            }
        }
    }

    /** Resolve once. Any failure disables the patch rather than half-applying it. */
    public static synchronized boolean ready(Object task) {
        if (broken) {
            return false;
        }
        if (fPath != null) {
            return true;
        }
        try {
            fPath = task.getClass().getDeclaredField("path");
            fPath.setAccessible(true);
            fTextures = task.getClass().getDeclaredField("textures");
            fTextures.setAccessible(true);
            fTilesets = TileDepthTextures.class.getDeclaredField("tilesets");
            fTilesets.setAccessible(true);
            mGetRows = TileDepthTextures.class.getDeclaredMethod("getTilesetRows", String.class, boolean.class);
            mGetRows.setAccessible(true);
            ctor = TilesetDepthTexture.class.getConstructor(
                    TileDepthTextures.class, String.class, int.class, int.class, boolean.class);
            return true;
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, engine shape not as expected: " + t);
            return false;
        }
    }

    /** true = skip the engine's synchronized body, we did the work. */
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This Object task) {
        if (!ON || broken || !ready(task)) {
            return false;
        }
        try {
            Path path = (Path) fPath.get(task);
            TileDepthTextures textures = (TileDepthTextures) fTextures.get(task);
            String fileName = path.toFile().getName();
            String name = fileName.replaceFirst("DEPTH_", "").replace(".png", "");

            if (present(textures, name)) {
                return true;
            }
            // NO LAMBDA HERE. A lambda compiles to a private synthetic method, and advice bodies are
            // inlined into the engine class, which cannot reach it: IllegalAccessError at runtime.
            Object lock = LOCKS.get(name);
            if (lock == null) {
                Object fresh = new Object();
                Object prev = LOCKS.putIfAbsent(name, fresh);
                lock = prev != null ? prev : fresh;
            }
            synchronized (lock) {
                if (present(textures, name)) {
                    return true;
                }
                // MUST hold `textures` for this read. `loadDepthTextureImages` does
                // `tilesetRows.put(...)` and `runAsync(loadTask)` in the SAME loop iteration
                // (TileDepthTextures.java:134-139), so the main thread is still inserting while
                // earlier tasks run -- workers do NOT merely read a finished map. Stock serialises
                // this read because the whole body is `synchronized (textures)`; taking the same
                // monitor for the read alone keeps that guarantee while leaving the expensive
                // decode outside. Without it this patch turns stock's one concurrent reader into
                // ten reading a plain HashMap mid-resize: a wrong `rows` builds a wrong-sized
                // tileset, which renders as a depth artefact rather than failing loudly.
                int rows;
                synchronized (textures) {
                    rows = (int) mGetRows.invoke(textures, name, true);
                }
                if (rows == 0) {
                    // Engine parity: createTileset returns null and stores nothing.
                    return true;
                }
                TilesetDepthTexture tileset = ctor.newInstance(textures, name, 8, rows, true);
                if (tileset.fileExists()) {
                    // Per tile until its render items run: the float[] pixels, plus the RGBA
                    // direct buffer new Texture(w, h, name, 0) allocates and never uploads, plus
                    // DepthUpload's staged R8 bytes.
                    long bytes = (8L + DepthUpload.STAGED_BYTES_PER_PIXEL) * tileset.getWidth() * tileset.getHeight();
                    reserve(bytes);
                    DepthUpload.beginLoad();
                    try {
                        tileset.load();
                    } catch (Exception ex) {
                        DebugLog.log(TAG + " load failed for " + name + ": " + ex);
                    } finally {
                        DepthUpload.endLoad();
                        release(bytes);
                    }
                }
                store(textures, name, tileset);
            }
            handled++;
            if (!announced) {
                announced = true;
                DebugLog.log(TAG + " depth tilesets decode outside the global lock");
            }
            return true;
        } catch (Throwable t) {
            // Never leave a tileset unloaded: fall back to the engine for this task and all later
            // ones. A missing depth tileset is a visible rendering fault, not a silent one.
            broken = true;
            DebugLog.log(TAG + " disabled after error, engine path resumes: " + t);
            return false;
        }
    }

    @SuppressWarnings("unchecked")
    public static boolean present(TileDepthTextures textures, String name) throws Exception {
        synchronized (textures) {
            return ((HashMap<String, TilesetDepthTexture>) fTilesets.get(textures)).get(name) != null;
        }
    }

    @SuppressWarnings("unchecked")
    public static void store(TileDepthTextures textures, String name, TilesetDepthTexture t)
            throws Exception {
        synchronized (textures) {
            ((HashMap<String, TilesetDepthTexture>) fTilesets.get(textures)).put(name, t);
        }
    }
}
