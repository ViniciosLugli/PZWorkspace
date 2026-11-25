package lugli.fastloading;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import me.zed_0xff.zombie_buddy.Patch;
import org.lwjgl.opengl.GL11;
import org.lwjgl.system.MemoryUtil;
import zombie.core.math.PZMath;
import zombie.core.opengl.RenderThread;
import zombie.core.textures.Texture;
import zombie.debug.DebugLog;
import zombie.tileDepth.TileDepthTexture;
import zombie.tileDepth.TilesetDepthTexture;

/**
 * Converts a depth tile's float pixels to its R8 upload on the asset worker that decoded it,
 * instead of on the render thread. -Dfastloading.depthupload=off.
 *
 * TileDepthTexture.updateGPUTexture queues one render item per tile that walks 32,768 floats
 * through a bounds-checked direct-buffer put before its glTexImage2D. On a heavy list that is
 * ~48,000 tiles at the very end of the world load, and TileDepthLock's upload budget then holds
 * every decoder until the render thread has converted the tiles ahead of it.
 *
 * MUST stay on the bulk load path only: the engine's item reads the pixels at render time, so a
 * caller that edits pixels after queueing would see a difference. TileDepthLock marks the thread
 * around tileset.load(), and nothing else is taken over.
 * MUST NOT call clampPixelToUpperFloor off the render thread: its table's init flag is set before
 * the table is filled, unsynchronised. The table is copied once, on the render thread.
 * MUST produce the engine's bytes: the first VALIDATE tiles go through the engine and are read
 * back from the GPU and compared; one difference turns the part off.
 */
public final class DepthUpload {

    public static final String TAG = "[FastLoading/depthupload]";

    /** public: read from a body inlined into zombie.tileDepth.TileDepthTexture. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.depthupload", "on"));

    /** Bytes per tile pixel staged until the upload: the R8 buffer. */
    public static final long STAGED_BYTES_PER_PIXEL = ON ? 1L : 0L;

    private static final int TABLE_WIDTH = 128;
    private static final int TABLE_ROWS = 64;
    private static final int VALIDATE = 32;

    public static volatile boolean broken;
    public static final ThreadLocal<Boolean> LOADING = new ThreadLocal<>();
    public static final ThreadLocal<Object[]> PENDING = new ThreadLocal<>();

    public static final AtomicLong FAST = new AtomicLong();
    public static final AtomicInteger CHECKED = new AtomicInteger();
    private static final AtomicInteger CHECKS_QUEUED = new AtomicInteger();

    private static volatile float[] clampTable;
    private static Field fTexture;
    private static Field fEmpty;
    private static Field fPixels;

    private DepthUpload() {}

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return "ok, " + FAST.get() + " depth tile(s) converted on the workers, " + CHECKED.get()
                + " checked against the engine";
    }

    public static void beginLoad() {
        LOADING.set(Boolean.TRUE);
    }

    public static void endLoad() {
        LOADING.remove();
    }

    /** True = the upload is queued here and the engine body is skipped. */
    public static boolean enter(TileDepthTexture tile) {
        PENDING.set(null);
        if (broken || LOADING.get() != Boolean.TRUE || Thread.currentThread() == RenderThread.renderThread) {
            return false;
        }
        try {
            float[] pixels = tile.getPixels();
            int w = tile.getWidth();
            int h = tile.getHeight();
            TilesetDepthTexture tileset = tile.getTileset();
            if (pixels == null || w != TABLE_WIDTH || h <= 0 || pixels.length < w * h || tileset == null) {
                return false;
            }
            float[] table = clampTable();
            boolean clamp = !tileset.getName().startsWith("roofs_");
            ByteBuffer bytes = MemoryUtil.memAlloc(w * h);
            boolean empty = convert(pixels, w, h, clamp, table, MemoryUtil.memAddress(bytes));
            // Fast only once every check has come back from the render thread, so no tile is
            // uploaded by this path before the engine has agreed with it.
            if (CHECKED.get() < VALIDATE) {
                if (CHECKS_QUEUED.getAndIncrement() < VALIDATE) {
                    PENDING.set(new Object[] {bytes, empty});
                } else {
                    MemoryUtil.memFree(bytes);
                }
                return false;
            }
            Texture texture = texture(tile);
            RenderThread.queueInvokeOnRenderContext(new Upload(tile, texture, bytes, w, h, empty));
            FAST.incrementAndGet();
            return true;
        } catch (Throwable t) {
            disable("conversion failed", t);
            return false;
        }
    }

    /** After a validated tile's engine body: its render item is queued, so the readback runs after it. */
    public static void exit(TileDepthTexture tile) {
        Object[] pending = PENDING.get();
        if (pending == null) return;
        PENDING.set(null);
        try {
            RenderThread.queueInvokeOnRenderContext(new Check(tile, (ByteBuffer) pending[0], (Boolean) pending[1]));
        } catch (Throwable t) {
            MemoryUtil.memFree((ByteBuffer) pending[0]);
            disable("could not queue the check", t);
        }
    }

    /** The engine's per-pixel rule from updateGPUTexture's render item. Returns `empty`. */
    static boolean convert(float[] pixels, int w, int h, boolean clamp, float[] table, long out) {
        boolean empty = true;
        for (int y = 0; y < h; y++) {
            int row = y * w;
            for (int x = 0; x < w; x++) {
                float pixel = pixels[x + row];
                if (pixel >= 0.0F && y < TABLE_ROWS && clamp) {
                    pixel = PZMath.max(pixel, table[x + y * TABLE_WIDTH]);
                }
                byte b;
                if (pixel < 0.0F) {
                    b = 0;
                } else {
                    pixel = PZMath.min(pixel, 1.0F);
                    int rgb = (int) Math.floor(pixel * 255.0F) & 0xFF;
                    if (rgb == 0) rgb = 1;
                    b = (byte) rgb;
                }
                MemoryUtil.memPutByte(out + x + row, b);
                if (pixel >= 0.0F && empty) empty = false;
            }
        }
        return empty;
    }

    private static float[] clampTable() throws Exception {
        float[] table = clampTable;
        if (table != null) return table;
        synchronized (DepthUpload.class) {
            if (clampTable == null) {
                CopyTable copy = new CopyTable();
                RenderThread.invokeOnRenderContext(copy);
                if (copy.error != null) throw copy.error;
                if (copy.table == null || copy.table.length < TABLE_WIDTH * TABLE_ROWS) {
                    throw new IllegalStateException("clamp table missing");
                }
                clampTable = copy.table;
            }
            return clampTable;
        }
    }

    private static synchronized void resolveFields() throws ReflectiveOperationException {
        if (fTexture != null) return;
        Field texture = TileDepthTexture.class.getDeclaredField("texture");
        Field empty = TileDepthTexture.class.getDeclaredField("empty");
        Field pixels = TileDepthTexture.class.getDeclaredField("pixels");
        texture.setAccessible(true);
        empty.setAccessible(true);
        pixels.setAccessible(true);
        fEmpty = empty;
        fPixels = pixels;
        fTexture = texture;
    }

    /** The engine body's first statement, on the same thread it runs on. */
    private static Texture texture(TileDepthTexture tile) throws ReflectiveOperationException {
        resolveFields();
        Texture texture = (Texture) fTexture.get(tile);
        if (texture == null) {
            texture = new Texture(tile.getWidth(), tile.getHeight(), "DEPTH_" + tile.getName(), 0);
            fTexture.set(tile, texture);
        }
        return texture;
    }

    public static void disable(String why, Throwable t) {
        if (broken) return;
        broken = true;
        DebugLog.log(TAG + " disabled, engine path resumes: " + why + (t == null ? "" : ": " + t));
    }

    private static final class CopyTable implements Runnable {
        float[] table;
        Exception error;

        @Override
        public void run() {
            try {
                Method init = TileDepthTexture.class.getDeclaredMethod("initClampedPixels");
                init.setAccessible(true);
                init.invoke(null);
                Field f = TileDepthTexture.class.getDeclaredField("s_clampedPixels");
                f.setAccessible(true);
                table = ((float[]) f.get(null)).clone();
            } catch (Exception e) {
                error = e;
            }
        }
    }

    /** The engine's render item minus the conversion, which already ran on the worker. */
    private static final class Upload implements Runnable {
        private final TileDepthTexture tile;
        private final Texture texture;
        private final ByteBuffer bytes;
        private final int w;
        private final int h;
        private final boolean empty;

        Upload(TileDepthTexture tile, Texture texture, ByteBuffer bytes, int w, int h, boolean empty) {
            this.tile = tile;
            this.texture = texture;
            this.bytes = bytes;
            this.w = w;
            this.h = h;
            this.empty = empty;
        }

        @Override
        public void run() {
            try {
                GL11.glBindTexture(GL11.GL_TEXTURE_2D, Texture.lastTextureID = texture.getID());
                GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);
                GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
                fEmpty.setBoolean(tile, empty);
                GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL11.GL_RED, w, h, 0, GL11.GL_RED, GL11.GL_UNSIGNED_BYTE, bytes);
                TilesetDepthTexture tileset = tile.getTileset();
                if (tileset != null && !tileset.isKeepPixels()) {
                    fPixels.set(tile, null);
                }
            } catch (Throwable t) {
                disable("upload failed for " + tile.getName(), t);
            } finally {
                MemoryUtil.memFree(bytes);
            }
        }
    }

    /** Reads back what the engine uploaded for a validated tile and compares it with ours. */
    private static final class Check implements Runnable {
        private final TileDepthTexture tile;
        private final ByteBuffer ours;
        private final boolean oursEmpty;

        Check(TileDepthTexture tile, ByteBuffer ours, boolean oursEmpty) {
            this.tile = tile;
            this.ours = ours;
            this.oursEmpty = oursEmpty;
        }

        @Override
        public void run() {
            ByteBuffer engine = null;
            try {
                resolveFields();
                Texture texture = (Texture) fTexture.get(tile);
                int w = tile.getWidth();
                int h = tile.getHeight();
                engine = MemoryUtil.memAlloc(w * h);
                GL11.glBindTexture(GL11.GL_TEXTURE_2D, Texture.lastTextureID = texture.getID());
                int align = GL11.glGetInteger(GL11.GL_PACK_ALIGNMENT);
                GL11.glPixelStorei(GL11.GL_PACK_ALIGNMENT, 1);
                GL11.glGetTexImage(GL11.GL_TEXTURE_2D, 0, GL11.GL_RED, GL11.GL_UNSIGNED_BYTE, engine);
                GL11.glPixelStorei(GL11.GL_PACK_ALIGNMENT, align);
                int n = w * h;
                for (int i = 0; i < n; i++) {
                    if (engine.get(i) != ours.get(i)) {
                        disable(tile.getName() + " byte " + i + ": engine " + (engine.get(i) & 0xFF)
                                + ", ours " + (ours.get(i) & 0xFF), null);
                        return;
                    }
                }
                boolean engineEmpty = fEmpty.getBoolean(tile);
                if (engineEmpty != oursEmpty) {
                    disable(tile.getName() + " empty: engine " + engineEmpty + ", ours " + oursEmpty, null);
                    return;
                }
                if (CHECKED.incrementAndGet() == VALIDATE) {
                    DebugLog.log(TAG + " " + VALIDATE + " tiles byte-identical to the engine's upload, fast path on");
                }
            } catch (Throwable t) {
                disable("check failed for " + tile.getName(), t);
            } finally {
                MemoryUtil.memFree(ours);
                if (engine != null) MemoryUtil.memFree(engine);
            }
        }
    }

    @Patch(className = "zombie.tileDepth.TileDepthTexture", methodName = "updateGPUTexture")
    public static final class Hook {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This TileDepthTexture tile) {
            return DepthUpload.ON && DepthUpload.enter(tile);
        }

        @Patch.OnExit
        public static void exit(@Patch.This TileDepthTexture tile) {
            if (DepthUpload.ON) DepthUpload.exit(tile);
        }
    }
}
