package lugli.fastloading;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.concurrent.atomic.AtomicIntegerArray;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.textures.PNGDecoder;
import zombie.debug.DebugLog;

/**
 * PNGDecoder.unfilterPaeth without data-dependent branches. -Dfastloading.paeth=off.
 *
 * Paeth rows are the largest single cost of decoding a tile pack page: 44 % of the asset workers'
 * time in a server-list world load (JFR). The engine picks the predictor with nested branches on
 * pixel data, which the CPU cannot predict; Tuning.unfilterPaeth computes the same value with masks.
 *
 * MUST write the same bytes as the engine: TuningTest checks the predictor over all 2^24 inputs and
 * random rows, and in game the first rows are decoded both ways and compared; one difference turns
 * the part off.
 */
public final class PngPaeth {

    public static final String TAG = "[FastLoading/paeth]";

    /** public: read from a body inlined into zombie.core.textures.PNGDecoder. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.paeth", "on"));

    static final int CHECKED_ROWS = 256;

    public static volatile boolean broken;
    /** Rows checked per bytes-per-pixel (1..8); a width takes the fast path once it reaches CHECKED_ROWS. */
    private static final AtomicIntegerArray checked = new AtomicIntegerArray(9);
    private static final ThreadLocal<Pending> PENDING = new ThreadLocal<>();

    private record Pending(byte[] mine, int bpp) {}
    private static final VarHandle BPP = bppHandle();

    private PngPaeth() {}

    private static VarHandle bppHandle() {
        try {
            return MethodHandles.privateLookupIn(PNGDecoder.class, MethodHandles.lookup())
                    .findVarHandle(PNGDecoder.class, "bytesPerPixel", int.class);
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, engine path resumes: bytesPerPixel unreadable: " + t);
            return null;
        }
    }

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        StringBuilder on = new StringBuilder();
        for (int bpp = 1; bpp < checked.length(); bpp++) {
            int n = checked.get(bpp);
            if (n > 0) on.append(on.isEmpty() ? "" : ", ").append(bpp).append(" B/px ")
                         .append(n >= CHECKED_ROWS ? "fast" : n + " checked");
        }
        return "ok" + (on.isEmpty() ? ", no Paeth row yet" : ", " + on);
    }

    /** True = the row is unfiltered here and the engine body is skipped. */
    public static boolean enter(PNGDecoder decoder, byte[] curLine, byte[] prevLine) {
        if (broken) return false;
        int bpp = (int) BPP.get(decoder);
        if (bpp < 1 || bpp >= checked.length()) return false;
        if (checked.get(bpp) >= CHECKED_ROWS) {
            Tuning.unfilterPaeth(curLine, prevLine, bpp);
            return true;
        }
        byte[] mine = curLine.clone();
        Tuning.unfilterPaeth(mine, prevLine, bpp);
        PENDING.set(new Pending(mine, bpp));
        return false;
    }

    public static void exit(byte[] curLine) {
        Pending pending = PENDING.get();
        if (pending == null) return;
        PENDING.remove();
        if (!java.util.Arrays.equals(pending.mine(), curLine)) {
            broken = true;
            DebugLog.log(TAG + " disabled, engine path resumes: a " + pending.bpp() + " B/px row differs from the engine");
            return;
        }
        if (checked.incrementAndGet(pending.bpp()) == CHECKED_ROWS) {
            DebugLog.log(TAG + " " + CHECKED_ROWS + " rows of " + pending.bpp()
                         + " B/px byte-identical to the engine, fast path on for that width");
        }
    }

    /**
     * Object, not byte[]: ZombieBuddy's matcher records an array-typed Argument as its component
     * type, so a byte[] parameter matches no method and the advice silently applies nowhere.
     */
    @Patch(className = "zombie.core.textures.PNGDecoder", methodName = "unfilterPaeth")
    public static final class Hook {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This PNGDecoder decoder, @Patch.Argument(0) Object curLine,
                                    @Patch.Argument(1) Object prevLine) {
            return PngPaeth.ON && PngPaeth.enter(decoder, (byte[]) curLine, (byte[]) prevLine);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) Object curLine) {
            if (PngPaeth.ON) PngPaeth.exit((byte[]) curLine);
        }
    }
}
