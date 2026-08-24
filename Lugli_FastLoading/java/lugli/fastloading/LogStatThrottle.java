package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;

/**
 * Stops the logger stat-ing its own file once per written line.
 * -Dfastloading.logstat=off
 *
 * `ZLogger.write` ends every line with `checkSizeUnsafe()` (`ZLogger.java:79-80`), and that is:
 *
 *     long currentKo = this.file.length() / 1024L;      // ZLogger.java:96
 *     if (currentKo > 10000L) { ...rotate... }
 *
 * `File.length()` is a Windows metadata syscall, paid per line, purely to notice a 10 MB
 * threshold. A boot on a 337-mod list writes **14,545 lines** to the menu.
 *
 * Measured with `tools/corpusbench.sh log`, 14,545 lines to a real file:
 *
 *     engine (flush + stat + formats)   519.2 ms   35.7 us/line
 *     without the per-line stat          58.3 ms    4.0 us/line
 *
 * so the stat alone is **~460 ms** of that. The same probe shows dropping the per-line FLUSH
 * would save only 10 ms, which is why that is not done: it would risk losing the tail of the
 * log on a native crash, and the tail is the most valuable part of a crash report, for nothing.
 *
 * WHY SKIPPING IS SAFE
 *   Checking every Nth call means rotation happens at most N lines late. At ~100 bytes a line
 *   and N = 512 that is ~50 KB against a 10,000 KB threshold -- 0.5 % overshoot on a file that
 *   is allowed to reach 10 MB. A whole boot log is 1.6 MB, so at boot the branch never fires at
 *   all; the throttle only matters for a very long session, where it still rotates.
 *
 *   Nothing about log CONTENT changes: every line is still written, still flushed, in order.
 *
 * The counter is deliberately not synchronised. ZLogger's methods are, but several ZLogger
 * instances share this counter and an occasional lost increment only shifts which call performs
 * the check -- it cannot skip rotation permanently, because the next call re-tests.
 */
@Patch(className = "zombie.core.logger.ZLogger", methodName = "checkSizeUnsafe")
public final class LogStatThrottle {

    public static final String TAG = "[FastLoading/logstat]";

    /** public: this advice body is inlined into zombie.core.logger.ZLogger. */
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.logstat", "on"));

    /** Lines between real size checks. 512 x ~100 B = ~50 KB against a 10 MB threshold. */
    public static final int EVERY = 512;

    public static int calls;
    public static int checks;
    public static boolean announced;

    private LogStatThrottle() {}

    /** true = skip the engine's size check for this line. */
    @Patch.OnEnter(skipOn = true)
    public static boolean in() {
        if (!ON) {
            return false;
        }
        calls++;
        if (calls % EVERY != 0) {
            return true;
        }
        checks++;
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " log size checked every " + EVERY + " lines, not every line");
        }
        return false;
    }
}
