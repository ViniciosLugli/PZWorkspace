package lugli.fastloading;

import java.util.concurrent.ConcurrentHashMap;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;

/**
 * Stops ZLogger stat-ing its own file once per written line.
 * -Dfastloading.logstat=off.
 *
 * checkSizeUnsafe() runs at the end of every write. The size check still happens, just on a
 * counter and periodically rather than on a filesystem call per line.
 *
 * The counter is per logger. checkSizeUnsafe is synchronized on its ZLogger, so each counter is
 * only ever touched under that logger's monitor, while separate loggers write concurrently. One
 * shared counter would lose increments across them, and a busy logger could take every 512th
 * line so a quiet one was never checked at all.
 */
@Patch(className = "zombie.core.logger.ZLogger", methodName = "checkSizeUnsafe")
public final class LogStatThrottle {

    public static final String TAG = "[FastLoading/logstat]";

    /** public: this advice body is inlined into zombie.core.logger.ZLogger. */
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.logstat", "on"));

    /** Lines between real size checks. 512 x ~100 B = ~50 KB against a 10 MB threshold. */
    public static final int EVERY = 512;

    /** Lines since the last real check, per ZLogger, which does not override equals. */
    private static final ConcurrentHashMap<Object, int[]> LINES = new ConcurrentHashMap<>();
    private static volatile boolean announced;

    private LogStatThrottle() {}

    /** For the menu handover line, so a part that did nothing says so. */
    public static String status() {
        if (!ON) return "off";
        return "ok, size checked every " + EVERY + " lines on " + LINES.size() + " logger(s)";
    }

    /** public: called from the advice inlined into ZLogger, under that logger's monitor. */
    public static boolean skip(Object logger) {
        int[] lines = LINES.get(logger);
        if (lines == null) {
            lines = new int[1];
            LINES.put(logger, lines);
        }
        if (++lines[0] < EVERY) {
            return true;
        }
        lines[0] = 0;
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " log size checked every " + EVERY + " lines, not every line");
        }
        return false;
    }

    /** true = skip the engine's size check for this line. */
    @Patch.OnEnter(skipOn = true)
    public static boolean in(@Patch.This Object self) {
        return ON && LogStatThrottle.skip(self);
    }
}
