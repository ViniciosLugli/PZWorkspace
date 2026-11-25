package lugli.fastloading;

import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.VarHandle;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicIntegerArray;

import org.lwjgl.system.MemoryUtil;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.textures.PNGDecoder;
import zombie.core.utils.BooleanGrid;
import zombie.debug.DebugLog;

/**
 * PNGDecoder.markOpaquePixels a word at a time. -Dfastloading.pngmask=off.
 *
 * The engine reads each pixel's alpha through a direct ByteBuffer get, which re-checks its memory
 * session, and sets each opaque pixel's bit with a bounds-checked BooleanGrid.setValue: 9 % of the
 * asset workers' time in a server-list world load (JFR). This reads the alpha bytes from raw memory
 * and ORs 32 bits into the grid's row at once.
 *
 * MUST set exactly the engine's bits: those of opaque pixels x < min(frame width, grid width) on a row
 * inside the grid, never clearing one. The first rows run both ways and are compared; one difference
 * turns the part off. A heap buffer, or a row past the buffer's limit, takes the engine path.
 */
public final class PngMask {

    public static final String TAG = "[FastLoading/pngmask]";

    /** public: read from a body inlined into zombie.core.textures.PNGDecoder. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.pngmask", "on"));

    static final int CHECKED_ROWS = 256;

    public static volatile boolean broken;
    /** Rows checked per alpha offset (0 = ABGR, 3 = the rest); an offset goes fast at CHECKED_ROWS. */
    private static final AtomicIntegerArray checked = new AtomicIntegerArray(4);
    private static final ThreadLocal<Pending> PENDING = new ThreadLocal<>();

    private record Pending(int[] expect, int alphaOffset) {}

    private static final MethodHandle FRAME_WIDTH;
    private static final VarHandle VALUE;
    private static final VarHandle WORDS;
    private static final VarHandle BITS;
    private static final VarHandle HEIGHT;

    static {
        MethodHandle frameWidth = null;
        VarHandle value = null, words = null, bits = null, height = null;
        try {
            MethodHandles.Lookup png = MethodHandles.privateLookupIn(PNGDecoder.class, MethodHandles.lookup());
            frameWidth = png.findVirtual(PNGDecoder.class, "getCurrentFrameWidth", MethodType.methodType(int.class));
            MethodHandles.Lookup grid = MethodHandles.privateLookupIn(BooleanGrid.class, MethodHandles.lookup());
            value = grid.findVarHandle(BooleanGrid.class, "value", int[].class);
            words = grid.findVarHandle(BooleanGrid.class, "width", int.class);
            bits = grid.findVarHandle(BooleanGrid.class, "bitWidth", int.class);
            height = grid.findVarHandle(BooleanGrid.class, "height", int.class);
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, engine path resumes: engine members unreadable: " + t);
        }
        FRAME_WIDTH = frameWidth;
        VALUE = value;
        WORDS = words;
        BITS = bits;
        HEIGHT = height;
    }

    private PngMask() {}

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return "ok, alpha at byte 3 " + state(3) + ", at byte 0 (ABGR) " + state(0);
    }

    private static String state(int alphaOffset) {
        int n = checked.get(alphaOffset);
        return n >= CHECKED_ROWS ? "fast" : n + " checked";
    }

    /** True = the row's mask bits are set here and the engine body is skipped. */
    public static boolean enter(PNGDecoder decoder, ByteBuffer buffer, int lineStart, int y, PNGDecoder.Format fmt) {
        if (broken) return false;
        try {
            BooleanGrid mask = decoder.mask;
            if (mask == null || !buffer.isDirect()) return false;
            int alphaOffset = fmt == PNGDecoder.Format.ABGR ? 0 : 3;
            boolean validated = checked.get(alphaOffset) >= CHECKED_ROWS;
            int lineWidth = (int) FRAME_WIDTH.invokeExact(decoder);
            if (lineStart < 0 || (long) lineStart + 4L * lineWidth > buffer.limit()) return false;
            int height = (int) HEIGHT.get(mask);
            if (y < 0 || y >= height) {
                return validated;   // the engine sets nothing on such a row
            }
            int words = (int) WORDS.get(mask);
            int[] value = (int[]) VALUE.get(mask);
            int width = Math.min(lineWidth, (int) BITS.get(mask));
            long at = MemoryUtil.memAddress0(buffer) + lineStart + alphaOffset;
            if (validated) {
                orRow(value, y * words, at, width);
                return true;
            }
            int[] expect = new int[words];
            System.arraycopy(value, y * words, expect, 0, words);
            orRow(expect, 0, at, width);
            PENDING.set(new Pending(expect, alphaOffset));
            return false;
        } catch (Throwable t) {
            disable("row failed", t);
            return false;
        }
    }

    private static void orRow(int[] value, int base, long alphaAt, int width) {
        for (int x0 = 0; x0 < width; x0 += 32) {
            int end = Math.min(32, width - x0);
            int word = 0;
            long p = alphaAt + ((long) x0 << 2);
            for (int k = 0; k < end; k++) {
                if (MemoryUtil.memGetByte(p + ((long) k << 2)) != 0) word |= 1 << k;
            }
            if (word != 0) value[base + (x0 >> 5)] |= word;
        }
    }

    public static void exit(PNGDecoder decoder, int y) {
        Pending pending = PENDING.get();
        if (pending == null) return;
        PENDING.remove();
        int[] expect = pending.expect();
        try {
            BooleanGrid mask = decoder.mask;
            int words = (int) WORDS.get(mask);
            int[] value = (int[]) VALUE.get(mask);
            for (int i = 0; i < words; i++) {
                if (value[y * words + i] != expect[i]) {
                    disable("a row's mask differs from the engine", null);
                    return;
                }
            }
        } catch (Throwable t) {
            disable("row check failed", t);
            return;
        }
        if (checked.incrementAndGet(pending.alphaOffset()) == CHECKED_ROWS) {
            DebugLog.log(TAG + " " + CHECKED_ROWS + " rows with alpha at byte " + pending.alphaOffset()
                         + " identical to the engine, fast path on for that layout");
        }
    }

    public static void disable(String why, Throwable t) {
        if (broken) return;
        broken = true;
        DebugLog.log(TAG + " disabled, engine path resumes: " + why + (t == null ? "" : ": " + t));
    }

    @Patch(className = "zombie.core.textures.PNGDecoder", methodName = "markOpaquePixels")
    public static final class Hook {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This PNGDecoder decoder, @Patch.Argument(0) ByteBuffer buffer,
                                    @Patch.Argument(1) int lineStart, @Patch.Argument(2) int y,
                                    @Patch.Argument(3) PNGDecoder.Format fmt) {
            return PngMask.ON && PngMask.enter(decoder, buffer, lineStart, y, fmt);
        }

        @Patch.OnExit
        public static void exit(@Patch.This PNGDecoder decoder, @Patch.Argument(2) int y) {
            if (PngMask.ON) PngMask.exit(decoder, y);
        }
    }
}
