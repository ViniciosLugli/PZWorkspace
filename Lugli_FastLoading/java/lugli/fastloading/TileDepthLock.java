package lugli.fastloading;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;
import me.zed_0xff.zombie_buddy.Patch;
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

    public static Field fPath;
    public static Field fTextures;
    public static Field fTilesets;
    public static Method mGetRows;
    public static Constructor<TilesetDepthTexture> ctor;

    private TileDepthLock() {}

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
                    try {
                        tileset.load();
                    } catch (Exception ex) {
                        DebugLog.log(TAG + " load failed for " + name + ": " + ex);
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
