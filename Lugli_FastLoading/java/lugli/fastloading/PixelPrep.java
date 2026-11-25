package lugli.fastloading;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.atomic.AtomicInteger;

import me.zed_0xff.zombie_buddy.Patch;
import org.lwjgl.system.MemoryUtil;
import zombie.core.textures.ImageData;
import zombie.core.textures.MipMapLevel;
import zombie.debug.DebugLog;
import zombie.debug.DebugOptions;

/**
 * The engine's premultiply and mip filters, byte for byte, on raw memory. -Dfastloading.pixelprep=off.
 *
 * ImageData.performPreMultipliedAlpha, scaleMipLevelMaxAlpha and scaleMipLevelAverage read and
 * write every byte through a direct ByteBuffer whose backing segment re-checks its session on each
 * access: on a heavy list that check alone was 52% of the asset workers' self time, and the two
 * filters 80% of a pack page's decode. The same arithmetic on MemoryUtil's unchecked int access
 * produces the same bytes.
 *
 * MUST produce exactly the engine's bytes: premultiply goes through a table built from the engine's
 * own expression, `(int)(c * a / 255.0F)`. The first VALIDATE calls of each filter run the engine
 * and this code on the same input and compare every byte; one difference turns the part off.
 * MUST leave the engine path whenever it cannot match it: big-endian memory, a buffer smaller than
 * its level, or the world mipmap debug colours switched on.
 */
public final class PixelPrep {

    public static final String TAG = "[FastLoading/pixelprep]";

    /** public: these are read from bodies inlined into zombie.core.textures.ImageData. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.pixelprep", "on"))
            && ByteOrder.nativeOrder() == ByteOrder.LITTLE_ENDIAN;

    public static volatile boolean broken;

    public static final int PREMULTIPLY = 0;
    public static final int MAX_ALPHA = 1;
    public static final int AVERAGE = 2;
    private static final String[] NAMES = {"premultiply", "max-alpha mip", "average mip"};

    private static final int VALIDATE = 32;
    public static final AtomicInteger[] VALIDATED = {new AtomicInteger(), new AtomicInteger(), new AtomicInteger()};
    public static final AtomicInteger[] FAST = {new AtomicInteger(), new AtomicInteger(), new AtomicInteger()};

    /** Validation input of the call in progress on this thread; null when the call takes the fast path. */
    public static final ThreadLocal<ByteBuffer> SNAPSHOT = new ThreadLocal<>();

    private static final byte[] PREMULTIPLIED = new byte[256 * 256];

    static {
        for (int a = 0; a < 256; a++) {
            for (int c = 0; c < 256; c++) {
                PREMULTIPLIED[a << 8 | c] = (byte) (int) (c * a / 255.0F);
            }
        }
    }

    private PixelPrep() {}

    public static String status() {
        if (!"off".equals(System.getProperty("fastloading.pixelprep", "on")) && !ON) {
            return "idle, memory is not little-endian";
        }
        if (!ON) return "off";
        if (broken) return "DEFECT";
        StringBuilder s = new StringBuilder("ok");
        for (int k = 0; k < NAMES.length; k++) {
            s.append(k == 0 ? ", " : "; ").append(NAMES[k]).append(' ').append(FAST[k].get())
             .append(" fast, ").append(VALIDATED[k].get()).append(" checked against the engine");
        }
        return s.toString();
    }

    // ---- advice entry points: true = the fast path did the work and the engine body is skipped ----

    public static boolean premultiplyEnter(MipMapLevel level) {
        if (broken || !fits(level, level.width, level.height)) return false;
        return enter(PREMULTIPLY, level.getBuffer(), level.width * level.height * 4,
                () -> premultiply(MemoryUtil.memAddress0(level.getBuffer()), level.width * level.height));
    }

    public static void premultiplyExit(MipMapLevel level) {
        ByteBuffer input = takeSnapshot();
        if (input == null) return;
        try {
            int bytes = level.width * level.height * 4;
            premultiply(MemoryUtil.memAddress0(input), level.width * level.height);
            check(PREMULTIPLY, input, level.getBuffer(), bytes, level.width, level.height);
        } finally {
            MemoryUtil.memFree(input);
        }
    }

    public static boolean mipEnter(int kind, ImageData data, MipMapLevel parent, MipMapLevel sub) {
        if (broken || !fits(parent, parent.width, parent.height) || !fits(sub, sub.width, sub.height)) return false;
        DebugOptions options = DebugOptions.instance;
        if (options == null || options.isoSprite.worldMipmapColors.getValue()) return false;
        boolean preserve = data.preserveTransparentColor;
        return enter(kind, parent.getBuffer(), parent.width * parent.height * 4, () -> {
            sub.getBuffer().rewind();
            mip(kind, preserve, MemoryUtil.memAddress0(parent.getBuffer()), parent.width, parent.height,
                MemoryUtil.memAddress0(sub.getBuffer()), sub.width, sub.height);
        });
    }

    public static void mipExit(int kind, ImageData data, MipMapLevel parent, MipMapLevel sub) {
        ByteBuffer input = takeSnapshot();
        if (input == null) return;
        int bytes = sub.width * sub.height * 4;
        ByteBuffer ours = MemoryUtil.memCalloc(bytes);
        try {
            mip(kind, data.preserveTransparentColor, MemoryUtil.memAddress0(input), parent.width, parent.height,
                MemoryUtil.memAddress0(ours), sub.width, sub.height);
            check(kind, ours, sub.getBuffer(), bytes, sub.width, sub.height);
        } finally {
            MemoryUtil.memFree(input);
            MemoryUtil.memFree(ours);
        }
    }

    private static boolean enter(int kind, ByteBuffer input, int bytes, Runnable fast) {
        SNAPSHOT.set(null);
        try {
            if (VALIDATED[kind].get() < VALIDATE) {
                ByteBuffer copy = MemoryUtil.memAlloc(bytes);
                MemoryUtil.memCopy(MemoryUtil.memAddress0(input), MemoryUtil.memAddress0(copy), bytes);
                SNAPSHOT.set(copy);
                return false;
            }
            fast.run();
            FAST[kind].incrementAndGet();
            return true;
        } catch (Throwable t) {
            disable(NAMES[kind] + " failed", t);
            return false;
        }
    }

    private static ByteBuffer takeSnapshot() {
        ByteBuffer input = SNAPSHOT.get();
        SNAPSHOT.set(null);
        return input;
    }

    private static boolean fits(MipMapLevel level, int w, int h) {
        ByteBuffer b = level.getBuffer();
        return b != null && b.isDirect() && w > 0 && h > 0 && (long) w * h * 4 <= b.capacity();
    }

    private static void check(int kind, ByteBuffer ours, ByteBuffer engine, int bytes, int w, int h) {
        long a = MemoryUtil.memAddress0(ours);
        long b = MemoryUtil.memAddress0(engine);
        for (int i = 0; i < bytes; i++) {
            byte x = MemoryUtil.memGetByte(a + i);
            byte y = MemoryUtil.memGetByte(b + i);
            if (x != y) {
                disable(NAMES[kind] + " differs from the engine at byte " + i + " of " + w + "x" + h
                        + " (engine " + (y & 0xFF) + ", ours " + (x & 0xFF) + ")", null);
                return;
            }
        }
        if (VALIDATED[kind].incrementAndGet() == VALIDATE) {
            DebugLog.log(TAG + " " + NAMES[kind] + ": " + VALIDATE + " calls byte-identical to the engine, fast path on");
        }
    }

    public static void disable(String why, Throwable t) {
        if (broken) return;
        broken = true;
        DebugLog.log(TAG + " disabled, engine path resumes: " + why + (t == null ? "" : ": " + t));
    }

    // ---- the filters: little-endian RGBA, so a texel read as an int is a | b << 16 | g << 8 | r ----

    static void premultiply(long addr, int texels) {
        for (int i = 0; i < texels; i++) {
            long at = addr + ((long) i << 2);
            int p = MemoryUtil.memGetInt(at);
            int a = p >>> 24;
            if (a == 255) continue;
            if (a == 0) {
                if (p != 0) MemoryUtil.memPutInt(at, 0);   // every channel times 0 is 0
                continue;
            }
            int row = a << 8;
            MemoryUtil.memPutInt(at, (PREMULTIPLIED[row | (p & 0xFF)] & 0xFF)
                    | (PREMULTIPLIED[row | (p >>> 8 & 0xFF)] & 0xFF) << 8
                    | (PREMULTIPLIED[row | (p >>> 16 & 0xFF)] & 0xFF) << 16
                    | a << 24);
        }
    }

    /**
     * MAX_ALPHA: the top-left texel (clamped) unless transparent and not preserved, plus each other
     * in-bounds texel of the 2x2 with alpha above 0. AVERAGE: the top-left texel (clamped) plus every
     * other in-bounds texel. Each channel is the integer mean over the texels taken.
     */
    static void mip(int kind, boolean preserve, long parent, int pw, int ph, long sub, int sw, int sh) {
        for (int y = 0; y < sh; y++) {
            int py = 2 * y;
            for (int x = 0; x < sw; x++) {
                int px = 2 * x;
                int p = MemoryUtil.memGetInt(parent + ((long) (Math.min(py, ph - 1) * pw + Math.min(px, pw - 1)) << 2));
                int r;
                int g;
                int b;
                int a;
                int n;
                if (kind == MAX_ALPHA && !preserve && p >>> 24 == 0) {
                    r = g = b = a = n = 0;
                } else {
                    r = p & 0xFF;
                    g = p >>> 8 & 0xFF;
                    b = p >>> 16 & 0xFF;
                    a = p >>> 24;
                    n = 1;
                }
                for (int s = 1; s < 4; s++) {
                    int qx = px + (s & 1);
                    int qy = py + (s >> 1);
                    if (qx >= pw || qy >= ph) continue;
                    int q = MemoryUtil.memGetInt(parent + ((long) (qy * pw + qx) << 2));
                    if (kind == MAX_ALPHA && q >>> 24 == 0) continue;
                    r += q & 0xFF;
                    g += q >>> 8 & 0xFF;
                    b += q >>> 16 & 0xFF;
                    a += q >>> 24;
                    n++;
                }
                // The sums are non-negative, so shifts and a constant divisor are the engine's division.
                if (n == 4) {
                    r >>= 2;
                    g >>= 2;
                    b >>= 2;
                    a >>= 2;
                } else if (n == 2) {
                    r >>= 1;
                    g >>= 1;
                    b >>= 1;
                    a >>= 1;
                } else if (n == 3) {
                    r /= 3;
                    g /= 3;
                    b /= 3;
                    a /= 3;
                }
                MemoryUtil.memPutInt(sub + ((long) (y * sw + x) << 2), r | g << 8 | b << 16 | a << 24);
            }
        }
    }

    @Patch(className = "zombie.core.textures.ImageData", methodName = "performPreMultipliedAlpha")
    public static final class Premultiply {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.Argument(0) MipMapLevel level) {
            return PixelPrep.ON && PixelPrep.premultiplyEnter(level);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) MipMapLevel level) {
            if (PixelPrep.ON) PixelPrep.premultiplyExit(level);
        }
    }

    @Patch(className = "zombie.core.textures.ImageData", methodName = "scaleMipLevelMaxAlpha")
    public static final class MaxAlpha {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This ImageData data, @Patch.Argument(0) MipMapLevel parent,
                                    @Patch.Argument(1) MipMapLevel sub) {
            return PixelPrep.ON && PixelPrep.mipEnter(PixelPrep.MAX_ALPHA, data, parent, sub);
        }

        @Patch.OnExit
        public static void exit(@Patch.This ImageData data, @Patch.Argument(0) MipMapLevel parent,
                                @Patch.Argument(1) MipMapLevel sub) {
            if (PixelPrep.ON) PixelPrep.mipExit(PixelPrep.MAX_ALPHA, data, parent, sub);
        }
    }

    @Patch(className = "zombie.core.textures.ImageData", methodName = "scaleMipLevelAverage")
    public static final class Average {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This ImageData data, @Patch.Argument(0) MipMapLevel parent,
                                    @Patch.Argument(1) MipMapLevel sub) {
            return PixelPrep.ON && PixelPrep.mipEnter(PixelPrep.AVERAGE, data, parent, sub);
        }

        @Patch.OnExit
        public static void exit(@Patch.This ImageData data, @Patch.Argument(0) MipMapLevel parent,
                                @Patch.Argument(1) MipMapLevel sub) {
            if (PixelPrep.ON) PixelPrep.mipExit(PixelPrep.AVERAGE, data, parent, sub);
        }
    }
}
