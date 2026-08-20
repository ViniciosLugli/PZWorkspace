package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.Core;
import zombie.debug.DebugLog;

/**
 * Skips the hot-reload file watcher's directory registration, which does nothing in normal
 * play and costs a full extra walk of every installed mod.
 *
 * DebugFileWatcher takes a Windows WatchKey on EVERY directory under media/ -- 1,704 of them
 * for the game alone -- and `ZomboidFileSystem.getAllModFoldersAux` then calls
 * `addDirectoryRecurse` on each mod's common and version media folder. That is a SECOND full
 * recursive traversal of all 338 mod trees, after `loadMod` has already walked them once,
 * plus a directory handle and a ReadDirectoryChangesW overlapped I/O per directory.
 *
 * Every consumer of it is a hot-reload path, and hot reload only does anything when
 * `Core.debug` is set, so with debug off the whole structure is built and never read.
 *
 * Measured on a 338 mod list, two runs per arm:
 *
 *   DebugFileWatcher.init         228 ms  ->     1 ms
 *   ZomboidFileSystem.loadMods  6,226 ms  -> 5,512 ms
 *   boot                  25.42-25.88 s  -> 24.84-25.02 s     (mean 25.65 -> 24.93)
 *
 * THE CUT IS AT registerDirRecursive, NOT AT init(). Skipping init() would leave the
 * `watcher` field null. `update()` guards on that (`DebugFileWatcher:130`), but
 * `addDirectory` and `addDirectoryRecurse` are still called from `getAllModFoldersAux`
 * during loadMods and would dereference it. Gating the recursive registration instead keeps
 * the watcher object alive, keeps `isInitialized` true, and keeps every listener contract
 * intact -- there is simply nothing registered to watch.
 *
 * This was rejected in an earlier round on the strength of a 0.26 s measurement. That figure
 * was real but covered only the GAME's media tree; it never included the 338 mod trees, which
 * are where the time is.
 *
 * ONLY THE MEDIA TREES ARE SKIPPED. `init()` registers two roots: `getMediaRootPath()` (the
 * expensive one) and `getMessagingDir()`. The messaging directory is how `Trigger_*.xml` live
 * toggles reach a running game, it is a single small folder, and it costs nothing -- so it is
 * still registered. Anything else the engine ever asks to watch recursively is also left
 * alone, which keeps this safe against future engine changes rather than only against today's.
 *
 * Opt out with -Dfastloading.watchergate=off. Launching with -Ddebug=true also disables it,
 * because that is someone deliberately using hot reload.
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
