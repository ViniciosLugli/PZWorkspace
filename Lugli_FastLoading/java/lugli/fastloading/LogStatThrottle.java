package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;

/**
 * Stops ZLogger stat-ing its own file once per written line.
 * -Dfastloading.logstat=off.
 *
 * checkSizeUnsafe() runs at the end of every write. The size check still happens, just on a
 * counter and periodically rather than on a filesystem call per line.
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
