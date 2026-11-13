package lugli.fastloading;

import java.io.File;
import java.util.ArrayList;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;
import zombie.debug.DebugLog;
import zombie.gameStates.ChooseGameInfo;
import zombie.tileDepth.TileGeometryManager;

/**
 * Parses media/tileGeometry.txt off the boot critical path. -Dfastloading.tilegeom=off.
 *
 * The file is several megabytes and the engine parses it inline. It cannot be deferred forward
 * because TileDepthTextureAssignmentManager.init needs the result immediately, so it is started
 * earlier instead and awaited where the engine would have parsed it.
 */
public final class TileGeometryPrefetch {

    public static final String TAG = "[FastLoading/tilegeom]";
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.tilegeom"));

    // public: these bodies are inlined into zombie.* classes, which access them from there.
    public static volatile Thread worker;
    public static volatile boolean failed;
    public static volatile boolean consumed;
    public static volatile boolean served;
    public static volatile long parseMs;

    private TileGeometryPrefetch() {}

    /** For the menu handover line, so a part that did nothing says so. */
    public static String status() {
        if (!ON) return "off";
        if (failed) return ScriptParse.ON ? "DEFECT" : "idle: needs the script parser fix, which is off";
        if (served) return "ok, parsed off the main thread in " + parseMs + " ms";
        if (consumed) return "DEFECT: the prefetch was never consumed";
        return worker == null ? "idle: not started" : "pending: started, not yet consumed";
    }

    public static void start() {
        if (!ON || worker != null || failed) return;

        // HARD DEPENDENCY: this parse runs off the main thread, and ScriptParser is only thread safe
        // because ScriptParse replaces its shared static buffer. If that patch is off, so is this.
        if (!ScriptParse.ON || ScriptParse.broken) {
            failed = true;
            DebugLog.log(TAG + " not started: the thread-safe script parser is unavailable");
            return;
        }

        try {
            final TileGeometryManager mgr = TileGeometryManager.getInstance();
            if (!mgr.getModIDs().isEmpty()) return;   // already initialised, do not touch it

            final ArrayList<ChooseGameInfo.Mod> mods = new ArrayList<>();
            for (String modID : ZomboidFileSystem.instance.getModIDs()) {
                ChooseGameInfo.Mod mod = ChooseGameInfo.getAvailableModDetails(modID);
                if (mod == null) continue;
                if (new File(mod.mediaFile.common.absoluteFile, "tileGeometry.txt").exists()) {
                    mods.add(mod);
                }
            }

            Thread t = new Thread(() -> {
                long t0 = System.nanoTime();
                try {
                    mgr.initGameData();
                    for (int i = 0; i < mods.size(); i++) {
                        mgr.initModData(mods.get(i));
                    }
                } catch (Throwable e) {
                    failed = true;
                    DebugLog.log(TAG + " prefetch failed, the engine will parse normally (" + e + ")");
                }
                parseMs = (System.nanoTime() - t0) / 1000000L;
            }, "FastLoading-tileGeometry");
            t.setDaemon(true);
            worker = t;
            t.start();
        } catch (Throwable e) {
            failed = true;
            DebugLog.log(TAG + " prefetch not started (" + e + ")");
        }
    }

    /**
     * true tells the advice to skip the engine's parse, because the worker already did it.
     *
     * The wait is uninterruptible on purpose. Giving up on an interrupt would let the engine
     * parse into the manager while the worker is still adding to it. And a worker that failed
     * part way has left some of its data in the manager, so that is cleared before the engine
     * parses, or the fall back to stock would duplicate it.
     */
    public static boolean join() {
        if (!ON || worker == null || consumed) return false;
        consumed = true;
        awaitWorker();
        if (!failed) {
            served = true;
            DebugLog.log(TAG + " tileGeometry.txt parsed off the main thread in " + parseMs + " ms");
            return true;
        }
        try {
            TileGeometryManager.getInstance().Reset();
        } catch (Throwable e) {
            DebugLog.log(TAG + " DEFECT: could not clear the failed prefetch (" + e + ")");
        }
        return false;
    }

    /** Waits for the worker to finish, keeping any interrupt for the caller afterwards. */
    public static void awaitWorker() {
        boolean interrupted = false;
        while (true) {
            try {
                worker.join();
                break;
            } catch (InterruptedException e) {
                interrupted = true;
            }
        }
        if (interrupted) Thread.currentThread().interrupt();
    }

    /**
     * Runs just after the engine's TileGeometryManager.init would have. If the prefetch was
     * never consumed the data is duplicated, so throw it away and rebuild it cleanly.
     */
    public static void verify() {
        if (!ON || worker == null || consumed) return;
        consumed = true;
        DebugLog.log(TAG + " DEFECT: prefetch was not consumed, rebuilding tile geometry cleanly");
        awaitWorker();
        try {
            TileGeometryManager mgr = TileGeometryManager.getInstance();
            mgr.Reset();
            mgr.init();
        } catch (Throwable e) {
            DebugLog.log(TAG + " rebuild failed (" + e + ")");
        }
    }

    /**
     * Started from initShared rather than at the end of loadMods: the mod tree must be registered
     * before the file can be resolved, and initShared is the first point where that is true.
     */
    @Patch(className = "zombie.GameWindow", methodName = "initShared")
    public static class Start {
        @Patch.OnEnter public static void in() { TileGeometryPrefetch.start(); }
    }

    @Patch(className = "zombie.tileDepth.TileGeometryManager", methodName = "init")
    public static class Join {
        @Patch.OnEnter(skipOn = true)
        public static boolean in() { return TileGeometryPrefetch.join(); }
    }

    @Patch(className = "zombie.tileDepth.TileDepthTextureAssignmentManager", methodName = "init")
    public static class Verify {
        @Patch.OnEnter public static void in() { TileGeometryPrefetch.verify(); }
    }
}
