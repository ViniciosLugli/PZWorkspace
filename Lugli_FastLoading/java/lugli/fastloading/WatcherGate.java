package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.Core;
import zombie.debug.DebugLog;

/**
 * Skips the hot-reload watcher's recursive directory registration, which does nothing in normal
 * play and costs a second full walk of every mod tree. -Dfastloading.watchergate=off, and
 * -Ddebug=true disables it too.
 *
 * Only recognisable media trees are skipped. The messaging folder carries live-toggle files and
 * must stay watched.
 */
public final class WatcherGate {

    public static final String TAG = "[FastLoading/watchgate]";
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.watchergate"));

    // public: the advice body is inlined into zombie.DebugFileWatcher and reads these there.
    public static int skipped;
    public static int kept;
    public static boolean announced;

    private WatcherGate() {}

    /**
     * true tells the advice to skip the recursive registration.
     *
     * @param start the tree being registered; only media trees are skipped.
     */
    public static boolean skip(Object start) {
        if (!ON) return false;
        // Core.debug comes from the -Ddebug system property (GameWindow:520,529). With it set
        // the player is deliberately using hot reload, so leave the watcher fully armed.
        if (Core.debug) return false;

        if (!isMediaTree(start)) {
            kept++;
            return false;
        }

        skipped++;
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " media hot-reload watch registration skipped"
                       + " (launch with -Ddebug=true to keep it)");
        }
        return true;
    }

    /**
     * Conservative by design: skip ONLY when the path is recognisably a media tree, and
     * register anything else. An unrecognised path therefore keeps the engine's behaviour
     * rather than silently losing a watch we did not anticipate.
     */
    public static boolean isMediaTree(Object start) {
        if (start == null) return false;
        return Tuning.isSkippableWatchRoot(start.toString(), java.io.File.separatorChar);
    }

    /** For the status panel, so a part that did nothing is visible rather than silent. */
    public static String status() {
        if (!ON) return "off";
        if (Core.debug) return "inactive: -Ddebug=true, hot reload is in use";
        return "ok, " + skipped + " media trees skipped, " + kept + " kept";
    }

    @Patch(className = "zombie.DebugFileWatcher", methodName = "registerDirRecursive")
    public static class Recurse {
        @Patch.OnEnter(skipOn = true)
        public static boolean in(@Patch.Argument(0) Object start) {
            return WatcherGate.skip(start);
        }
    }
}
