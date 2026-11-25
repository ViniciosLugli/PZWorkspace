package lugli.fastloading;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import me.zed_0xff.zombie_buddy.Patch;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL11C;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL13C;
import org.lwjgl.stb.STBDXT;
import org.lwjgl.system.MemoryUtil;
import org.lwjglx.opengl.Display;
import zombie.asset.Asset;
import zombie.asset.AssetTask;
import zombie.asset.FileTask_LoadImageData;
import zombie.asset.FileTask_LoadPackImage;
import zombie.core.Core;
import zombie.core.textures.ImageData;
import zombie.core.textures.MipMapLevel;
import zombie.core.textures.TextureID;
import zombie.core.utils.DirectBufferAllocator;
import zombie.core.utils.WrappedBuffer;
import zombie.debug.DebugLog;

/**
 * Encodes DXT5 on the asset worker for every texture the engine would have the driver compress on
 * the render thread. -Dfastloading.dxtprep=off.
 *
 * With texture compression on, TextureID.generateHwId uploads each level as GL_COMPRESSED_RGBA and
 * the driver encodes it inside glTexImage2D, on the render thread that a heavy list's world load
 * waits on. Here the worker that decoded the image builds the engine's own mip chain, encodes each
 * level with stb_dxt, and the upload swaps each glTexImage2D for glCompressedTexImage2D.
 *
 * MUST prove on the render thread that the driver turns GL_COMPRESSED_RGBA into DXT5 before
 * anything is encoded: another driver may pick another format, and the swap would then change what
 * the player sees. Until the proof runs, every texture takes the stock path.
 * MUST encode exactly what generateHwId uploads: the premultiplied getMipMapData levels with
 * MIPMAPS, the raw getData() level without it.
 * MUST skip a texture limitMaxSize will shrink: it replaces the ImageData after the worker is done.
 * MUST hand a call back to the driver whenever it does not match the chain level for level.
 */
public final class DxtPrep {

    public static final String TAG = "[FastLoading/dxtprep]";

    /** public: these are read from bodies inlined into zombie.* and org.lwjgl.opengl.GL11. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.dxtprep", "on"));
    /** verify: also decode every VERIFY_EVERY-th chain against the pixels it replaces, and check every upload's GL error. */
    public static final boolean VERIFY = "verify".equals(System.getProperty("fastloading.dxtprep"));

    public static final int UNPROVEN = 0;
    public static final int PROVEN = 1;
    public static final int REFUSED = -1;
    public static volatile int proof = UNPROVEN;
    public static volatile boolean broken;

    public static final ConcurrentHashMap<Object, Integer> PENDING = new ConcurrentHashMap<>();
    /** ImageData keeps Object identity, so this map is keyed by instance. */
    public static final ConcurrentHashMap<ImageData, Chain> CHAINS = new ConcurrentHashMap<>();

    /** Render thread only, for the length of one generateHwId. */
    public static Chain uploading;

    /** Unconditional, before every guard: 0 here means the advice never attached. */
    public static final AtomicLong RECORD_CALLS = new AtomicLong();
    public static final AtomicLong ENCODE_CALLS = new AtomicLong();
    public static final AtomicInteger ENCODED = new AtomicInteger();
    public static final AtomicInteger SHRUNK = new AtomicInteger();
    public static final AtomicLong ENCODE_NANOS = new AtomicLong();
    public static final AtomicLong DXT_BYTES = new AtomicLong();
    /** Native bytes held by chains not yet uploaded or dropped, and the most ever held at once. */
    public static final AtomicLong LIVE_BYTES = new AtomicLong();
    public static final AtomicLong PEAK_BYTES = new AtomicLong();
    public static int uploaded;
    public static int handedBack;
    public static int unused;

    public static Field fFileTask;
    public static Field fFlags;

    private static final int GL_TEXTURE_2D = 3553;
    private static final int GL_RGBA = 6408;
    private static final int GL_UNSIGNED_BYTE = 5121;
    private static final int GL_COMPRESSED_RGBA = 34030;
    private static final int GL_COMPRESSED_RGBA_S3TC_DXT5 = 33779;
    private static final int GL_TEXTURE_INTERNAL_FORMAT = 4099;

    private static final int CHECKED_TEXTURES = 64;
    private static final int VERIFY_EVERY = 8;
    /** A level this far under the driver's own encode of the same pixels counts as worse. */
    private static final double VERIFY_MARGIN_DB = 1.0;
    /** Native bytes of chains waiting for upload past which a texture is left to the driver. */
    private static final long CHAIN_BUDGET = 512L << 20;

    public static final AtomicInteger OVER_BUDGET = new AtomicInteger();

    /** verify mode, render thread only. */
    public static int verifySeen;
    public static int verifiedTextures;
    public static int verifiedLevels;
    public static int levelsWorse;
    public static double sumDelta;
    public static double worstDelta = Double.MAX_VALUE;
    public static String worstName = "";
    public static long alphaMisses;
    public static long driverAlphaMisses;
    public static int glErrors;

    private static final int COMPRESS = 4;
    private static final int FBO = 16;
    private static final int MIPMAPS = 64;
    private static final int FBO_DEPTH = 512;

    private static final ThreadLocal<ByteBuffer> BLOCK = new ThreadLocal<>();

    private DxtPrep() {}

    public static final class Chain {
        final WrappedBuffer[] levels;
        final int[] width;
        final int[] height;
        final boolean mips;

        Chain(int n, boolean mips) {
            levels = new WrappedBuffer[n];
            width = new int[n];
            height = new int[n];
            this.mips = mips;
        }

        void release(int i) {
            if (levels[i] != null) {
                LIVE_BYTES.addAndGet(-levels[i].capacity());
                levels[i].dispose();
                levels[i] = null;
            }
        }

        void free() {
            for (int i = 0; i < levels.length; i++) {
                release(i);
            }
        }
    }

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        if (proof == REFUSED) return "idle, this driver does not compress to DXT5";
        if (proof == UNPROVEN) return "idle, no texture uploaded yet";
        return "ok, " + ENCODED.get() + " texture(s) encoded on workers in " + ENCODE_NANOS.get() / 1_000_000L
                + " ms (" + (DXT_BYTES.get() >> 20) + " MB of DXT5, at most " + (PEAK_BYTES.get() >> 20)
                + " MB held at once), " + uploaded + " uploaded precompressed, "
                + handedBack + " handed back to the driver, " + unused + " never uploaded, "
                + SHRUNK.get() + " left to the engine for a size limit, " + OVER_BUDGET.get()
                + " left to the driver over the " + (CHAIN_BUDGET >> 20) + " MB budget; hooks saw "
                + RECORD_CALLS.get() + " submit(s), " + ENCODE_CALLS.get() + " decode(s)"
                + (VERIFY ? "; " + verifyStatus() : "");
    }

    private static String verifyStatus() {
        if (verifiedLevels == 0) return "verified nothing yet";
        return "verified " + verifiedTextures + " texture(s), " + verifiedLevels + " level(s) against the driver's"
                + " own encode: mean " + String.format("%.2f", sumDelta / verifiedLevels) + " dB, worst "
                + String.format("%.2f", worstDelta) + " dB (" + worstName + "), " + levelsWorse
                + " level(s) over " + VERIFY_MARGIN_DB + " dB worse; alpha 0/255 texels changed: ours "
                + alphaMisses + ", driver " + driverAlphaMisses + "; " + glErrors + " GL error(s)";
    }

    public static synchronized boolean ready() {
        if (broken) return false;
        if (fFileTask != null) return true;
        try {
            Field task = Class.forName("zombie.asset.AssetTask_RunFileTask").getDeclaredField("fileTask");
            task.setAccessible(true);
            Field flags = TextureID.TextureIDAssetParams.class.getDeclaredField("flags");
            flags.setAccessible(true);
            fFlags = flags;
            fFileTask = task;
            return true;
        } catch (Throwable t) {
            disable("engine shape not as expected", t);
            return false;
        }
    }

    /** Submitting thread, before runAsync hands the task to a worker: flags as generateHwId reads them. */
    public static void record(AssetTask assetTask) {
        RECORD_CALLS.incrementAndGet();
        if (proof != PROVEN || broken || !ready()) return;
        try {
            Asset asset = assetTask.asset;
            if (!(asset instanceof TextureID)) return;
            Object fileTask = fFileTask.get(assetTask);
            if (!(fileTask instanceof FileTask_LoadImageData) && !(fileTask instanceof FileTask_LoadPackImage)) return;
            TextureID.TextureIDAssetParams params = ((TextureID) asset).assetParams;
            if (params == null) return;
            int flags = fFlags.getInt(params);
            if ((flags & COMPRESS) != 0 && (flags & (FBO | FBO_DEPTH)) == 0) {
                PENDING.put(fileTask, flags);
            }
        } catch (Throwable t) {
            disable("record failed", t);
        }
    }

    /** Worker, on the decoded image the main thread will hand to setImageData. */
    public static void encode(Object fileTask, Object result) {
        ENCODE_CALLS.incrementAndGet();
        Integer flags = PENDING.remove(fileTask);
        if (flags == null || broken || !(result instanceof ImageData)) return;
        Chain chain = null;
        try {
            ImageData data = (ImageData) result;
            int max = Core.getInstance().getMaxTextureSizeFromFlags(flags);
            if (data.getWidth() > max || data.getHeight() > max) {
                SHRUNK.incrementAndGet();
                return;
            }
            long t0 = System.nanoTime();
            boolean mips = (flags & MIPMAPS) != 0;
            if (mips) {
                data.initMipMaps();
            }
            int n = mips ? data.getMipMapCount() : 1;
            // The whole chain is under 4/3 of level 0's one byte per texel.
            long estimate = (long) data.getWidthHW() * data.getHeightHW() * (mips ? 4 : 3) / 3;
            if (LIVE_BYTES.get() + estimate > CHAIN_BUDGET) {
                OVER_BUDGET.incrementAndGet();
                return;
            }
            chain = new Chain(n, mips);
            long bytes = 0L;
            for (int i = 0; i < n; i++) {
                MipMapLevel level = mips ? data.getMipMapData(i) : data.getData();
                chain.width[i] = level.width;
                chain.height[i] = level.height;
                chain.levels[i] = encodeLevel(level.getBuffer(), level.width, level.height);
                LIVE_BYTES.addAndGet(chain.levels[i].capacity());
                bytes += chain.levels[i].capacity();
            }
            PEAK_BYTES.accumulateAndGet(LIVE_BYTES.get(), Math::max);
            CHAINS.put(data, chain);
            ENCODE_NANOS.addAndGet(System.nanoTime() - t0);
            DXT_BYTES.addAndGet(bytes);
            ENCODED.incrementAndGet();
        } catch (Throwable t) {
            if (chain != null) chain.free();
            disable("encode failed", t);
        }
    }

    /** DXT5 blocks of one level, edge texels repeated where a level is smaller than a block. */
    public static WrappedBuffer encodeLevel(ByteBuffer pixels, int w, int h) {
        if (!pixels.isDirect() || (long) w * h * 4 > pixels.capacity()) {
            throw new IllegalArgumentException("level buffer smaller than " + w + "x" + h);
        }
        int bw = (w + 3) / 4;
        int bh = (h + 3) / 4;
        WrappedBuffer out = DirectBufferAllocator.allocate(bw * bh * 16);
        ByteBuffer dst = out.getBuffer();
        ByteBuffer block = BLOCK.get();
        if (block == null) {
            block = MemoryUtil.memAlloc(64);
            BLOCK.set(block);
        }
        // Unchecked access: a checked ByteBuffer get re-validates its memory session per texel.
        long srcAddr = MemoryUtil.memAddress0(pixels);
        long blockAddr = MemoryUtil.memAddress0(block);
        long dstAddr = MemoryUtil.memAddress0(dst);
        for (int by = 0; by < bh; by++) {
            for (int bx = 0; bx < bw; bx++) {
                int or = 0;
                for (int row = 0; row < 4; row++) {
                    int y = Math.min(by * 4 + row, h - 1);
                    for (int col = 0; col < 4; col++) {
                        int x = Math.min(bx * 4 + col, w - 1);
                        int texel = MemoryUtil.memGetInt(srcAddr + ((long) (y * w + x) << 2));
                        MemoryUtil.memPutInt(blockAddr + ((row * 4 + col) << 2), texel);
                        or |= texel;
                    }
                }
                long off = dstAddr + (long) (by * bw + bx) * 16;
                if (or == 0) {
                    // Every texel (0,0,0,0): the all-zero DXT5 block decodes to exactly that.
                    MemoryUtil.memPutLong(off, 0L);
                    MemoryUtil.memPutLong(off + 8, 0L);
                } else {
                    STBDXT.nstb_compress_dxt_block(off, blockAddr, 1, STBDXT.STB_DXT_NORMAL);
                }
            }
        }
        dst.position(0).limit(bw * bh * 16);
        return out;
    }

    /** Render thread, before generateHwId generates its id. Proves the driver once, then picks the chain. */
    public static void begin(TextureID texture) {
        uploading = null;
        if (broken) return;
        if (proof == UNPROVEN) {
            prove();
        }
        if (proof != PROVEN) return;
        ImageData data = texture.getImageData();
        if (data != null) {
            uploading = CHAINS.remove(data);
            if (VERIFY && uploading != null && verifySeen++ % VERIFY_EVERY == 0) {
                verify(texture, data, uploading);
            }
        }
    }

    /**
     * Render thread, before generateHwId binds its own texture: decodes each level of the chain the
     * swap will upload, and the driver's own GL_COMPRESSED_RGBA encode of the buffer generateHwId
     * passes for that level, and scores both against that buffer. GL11C/GL13C, so the swap never
     * sees these uploads.
     */
    private static void verify(TextureID texture, ImageData data, Chain chain) {
        int id = 0;
        ByteBuffer ours = null;
        ByteBuffer driver = null;
        try {
            id = GL11C.glGenTextures();
            GL11C.glBindTexture(GL_TEXTURE_2D, id);
            for (int i = 0; i < chain.levels.length; i++) {
                int w = chain.width[i];
                int h = chain.height[i];
                int bytes = w * h * 4;
                ByteBuffer src = (chain.mips ? data.getMipMapData(i) : data.getData()).getBuffer();
                if (ours == null || ours.capacity() < bytes) {
                    if (ours != null) MemoryUtil.memFree(ours);
                    if (driver != null) MemoryUtil.memFree(driver);
                    ours = MemoryUtil.memAlloc(bytes);
                    driver = MemoryUtil.memAlloc(bytes);
                }
                GL13C.glCompressedTexImage2D(GL_TEXTURE_2D, 0, GL_COMPRESSED_RGBA_S3TC_DXT5, w, h, 0,
                        chain.levels[i].getBuffer());
                GL11C.glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, ours);
                int position = src.position();
                int limit = src.limit();
                src.position(0).limit(bytes);
                try {
                    GL11C.glTexImage2D(GL_TEXTURE_2D, 0, GL_COMPRESSED_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, src);
                } finally {
                    src.limit(limit).position(position);
                }
                GL11C.glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, driver);
                double sseOurs = 0.0;
                double sseDriver = 0.0;
                for (int b = 0; b < bytes; b++) {
                    int s = src.get(b) & 0xFF;
                    int o = ours.get(b) & 0xFF;
                    int d = driver.get(b) & 0xFF;
                    sseOurs += (s - o) * (s - o);
                    sseDriver += (s - d) * (s - d);
                    if ((b & 3) == 3 && (s == 0 || s == 255)) {
                        if (o != s) alphaMisses++;
                        if (d != s) driverAlphaMisses++;
                    }
                }
                double delta = psnr(sseOurs, bytes) - psnr(sseDriver, bytes);
                verifiedLevels++;
                sumDelta += delta;
                if (delta < -VERIFY_MARGIN_DB) levelsWorse++;
                if (delta < worstDelta) {
                    worstDelta = delta;
                    worstName = texture.getPathFileName() + " level " + i + " " + w + "x" + h;
                }
            }
            verifiedTextures++;
        } catch (Throwable t) {
            disable("verify failed", t);
        } finally {
            if (id != 0) {
                GL11C.glBindTexture(GL_TEXTURE_2D, 0);
                GL11C.glDeleteTextures(id);
            }
            if (ours != null) MemoryUtil.memFree(ours);
            if (driver != null) MemoryUtil.memFree(driver);
        }
    }

    /** Over all four channels; a lossless level reads as 99 dB. */
    private static double psnr(double sse, int bytes) {
        return sse == 0.0 ? 99.0 : 10.0 * Math.log10(255.0 * 255.0 * bytes / sse);
    }

    /** Render thread: true = this glTexImage2D call was replaced by its precompressed level. */
    public static boolean swap(int target, int level, int internalFormat, int w, int h, int border, int format, int type) {
        Chain chain = uploading;
        if (target != GL_TEXTURE_2D || internalFormat != GL_COMPRESSED_RGBA || format != GL_RGBA
                || type != GL_UNSIGNED_BYTE || border != 0 || level < 0 || level >= chain.levels.length
                || chain.levels[level] == null || chain.width[level] != w || chain.height[level] != h) {
            handBack();
            return false;
        }
        try {
            // glGetError can stall a threaded driver, and a bad level is systematic, so only the
            // first textures are checked.
            boolean checked = VERIFY || uploaded < CHECKED_TEXTURES;
            for (int i = 0; checked && i < 8 && GL11.glGetError() != 0; i++) {
                // drain errors the engine raised and never read, so the check below is ours
            }
            GL13.glCompressedTexImage2D(target, level, GL_COMPRESSED_RGBA_S3TC_DXT5, w, h, 0,
                    chain.levels[level].getBuffer());
            int err = checked ? GL11.glGetError() : 0;
            chain.release(level);
            if (err != 0) {
                glErrors++;
                disable("glCompressedTexImage2D error " + err + " at level " + level, null);
                handBack();
                return false;
            }
            if (level == 0) {
                uploaded++;
                if (uploaded == 1 || uploaded % 2000 == 0) {
                    DebugLog.log(TAG + " " + status());
                }
            }
            return true;
        } catch (Throwable t) {
            disable("swap failed", t);
            handBack();
            return false;
        }
    }

    /** The rest of this texture goes to the driver; proof showed it also stores DXT5, so levels agree. */
    private static void handBack() {
        handedBack++;
        Chain chain = uploading;
        uploading = null;
        if (chain != null) chain.free();
    }

    public static void end() {
        Chain chain = uploading;
        uploading = null;
        if (chain != null) chain.free();
    }

    /** Any thread: an image freed with its chain unused, so the chain goes with it. */
    public static void dropped(Object data) {
        Chain chain = CHAINS.remove(data);
        if (chain != null) {
            chain.free();
            synchronized (DxtPrep.class) {
                unused++;
            }
        }
    }

    private static void prove() {
        int id = 0;
        ByteBuffer texels = null;
        try {
            if (!Display.capabilities.GL_ARB_texture_compression || !Display.capabilities.GL_EXT_texture_compression_s3tc) {
                refuse("no GL_ARB_texture_compression or GL_EXT_texture_compression_s3tc");
                return;
            }
            texels = MemoryUtil.memAlloc(64);
            for (int i = 0; i < 16; i++) {
                texels.putInt(i * 4, 0x80402010 + i);
            }
            ByteBuffer encoded = MemoryUtil.memAlloc(16);
            try {
                STBDXT.stb_compress_dxt_block(encoded, texels, true, STBDXT.STB_DXT_NORMAL);
            } finally {
                MemoryUtil.memFree(encoded);
            }
            id = GL11.glGenTextures();
            GL11.glBindTexture(GL_TEXTURE_2D, id);
            GL11.glTexImage2D(GL_TEXTURE_2D, 0, GL_COMPRESSED_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, texels);
            int chosen = GL11.glGetTexLevelParameteri(GL_TEXTURE_2D, 0, GL_TEXTURE_INTERNAL_FORMAT);
            if (chosen != GL_COMPRESSED_RGBA_S3TC_DXT5) {
                refuse("the driver stores GL_COMPRESSED_RGBA as format " + chosen + ", not DXT5");
                return;
            }
            proof = PROVEN;
            DebugLog.log(TAG + " the driver stores GL_COMPRESSED_RGBA as DXT5: textures encode on asset workers");
        } catch (Throwable t) {
            refuse("proof failed: " + t);
        } finally {
            if (id != 0) {
                GL11.glBindTexture(GL_TEXTURE_2D, 0);
                GL11.glDeleteTextures(id);
            }
            if (texels != null) MemoryUtil.memFree(texels);
        }
    }

    private static void refuse(String why) {
        proof = REFUSED;
        DebugLog.log(TAG + " idle, engine path kept: " + why);
    }

    public static void disable(String why, Throwable t) {
        broken = true;
        PENDING.clear();
        DebugLog.log(TAG + " disabled, engine path resumes: " + why + (t == null ? "" : ": " + t));
    }

    @Patch(className = "zombie.asset.AssetTask_RunFileTask", methodName = "execute")
    public static final class Record {
        @Patch.OnEnter
        public static void enter(@Patch.This AssetTask task) {
            if (DxtPrep.ON) DxtPrep.record(task);
        }
    }

    @Patch(className = "zombie.asset.FileTask_LoadImageData", methodName = "call")
    public static final class EncodeLoose {
        @Patch.OnExit
        public static void exit(@Patch.This Object task, @Patch.Return Object result) {
            if (DxtPrep.ON) DxtPrep.encode(task, result);
        }
    }

    @Patch(className = "zombie.asset.FileTask_LoadPackImage", methodName = "call")
    public static final class EncodePage {
        @Patch.OnExit
        public static void exit(@Patch.This Object task, @Patch.Return Object result) {
            if (DxtPrep.ON) DxtPrep.encode(task, result);
        }
    }

    @Patch(className = "zombie.core.textures.TextureID", methodName = "generateHwId")
    public static final class Upload {
        @Patch.OnEnter
        public static void enter(@Patch.This TextureID texture) {
            if (DxtPrep.ON) DxtPrep.begin(texture);
        }

        @Patch.OnExit(onThrowable = Throwable.class)
        public static void exit() {
            if (DxtPrep.ON) DxtPrep.end();
        }
    }

    @Patch(className = "org.lwjgl.opengl.GL11", methodName = "glTexImage2D")
    public static final class Swap {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.Argument(0) int target, @Patch.Argument(1) int level,
                                    @Patch.Argument(2) int internalFormat, @Patch.Argument(3) int width,
                                    @Patch.Argument(4) int height, @Patch.Argument(5) int border,
                                    @Patch.Argument(6) int format, @Patch.Argument(7) int type) {
            return DxtPrep.uploading != null
                    && DxtPrep.swap(target, level, internalFormat, width, height, border, format, type);
        }
    }

    @Patch(className = "zombie.core.textures.ImageData", methodName = "dispose")
    public static final class Drop {
        @Patch.OnEnter
        public static void enter(@Patch.This Object data) {
            if (DxtPrep.ON && !DxtPrep.CHAINS.isEmpty()) DxtPrep.dropped(data);
        }
    }
}
