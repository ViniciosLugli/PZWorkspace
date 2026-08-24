package lugli.fastloading;

import java.io.File;
import java.util.ArrayList;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;
import zombie.debug.DebugLog;
import zombie.gameStates.ChooseGameInfo;
import zombie.tileDepth.TileGeometryManager;

/**
 * Moves a 2.4 s parse of media/tileGeometry.txt (6.4 MB, 331,376 lines) off the boot critical
 * path. -Dfastloading.tilegeom=off.
 *
 * It cannot be deferred forward -- TileDepthTextureAssignmentManager.init runs immediately
 * after and reads TileGeometryManager.getTile -- but nothing reads the manager before init(),
 * so it can start as soon as the mod list exists and be joined where the engine would parse.
 *
 * The mod list is resolved on the CALLING thread, never the worker: ChooseGameInfo.getModDetails
 * populates a HashMap that ScriptManager.Load also writes, so resolving it off-thread races.
 *
 * docs/18-fastloading-internals.md#scriptparse-thread-safety
 */
public final class TileGeometryPrefetch {

    public static final String TAG = "[FastLoading/tilegeom]";
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.tilegeom"));

    // public: these bodies are inlined into zombie.* classes, which access them from there.
    public static volatile Thread worker;
    public static volatile boolean failed;
    public static volatile boolean consumed;
    public static volatile long parseMs;

    private TileGeometryPrefetch() {}

    public static void start() {
        if (!ON || worker != null || failed) return;

        // HARD DEPENDENCY, do not remove.
        //
        // This parse goes through ScriptParser.stripComments, which keeps ONE static
        // StringBuilder for every caller (ScriptParser.java:9). Running it on a worker while
        // the main thread parses corrupts both, and TileGeometryFile.read SWALLOWS the
        // exception, so boot continues with incomplete tile depth data and nothing looks wrong.
        // ScriptParse gives the buffer to the call; without it this prefetch is unsafe.
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

    /** true tells the advice to skip the engine's parse, because the worker already did it. */
    public static boolean join() {
        if (!ON || worker == null || consumed) return false;
        consumed = true;
        try {
            worker.join();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
        if (failed) return false;
        DebugLog.log(TAG + " tileGeometry.txt parsed off the main thread in " + parseMs + " ms");
        return true;
    }

    /**
     * Runs just after the engine's TileGeometryManager.init would have. If the prefetch was
     * never consumed the data is duplicated, so throw it away and rebuild it cleanly.
     */
    public static void verify() {
        if (!ON || worker == null || consumed) return;
        consumed = true;
        DebugLog.log(TAG + " DEFECT: prefetch was not consumed, rebuilding tile geometry cleanly");
        try {
            worker.join();
            TileGeometryManager mgr = TileGeometryManager.getInstance();
            mgr.Reset();
            mgr.init();
        } catch (Throwable e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            DebugLog.log(TAG + " rebuild failed (" + e + ")");
        }
    }

    /**
     * Triggered at the head of initShared, NOT at the end of loadMods.
     *
     * ZombieBuddy installs java mods from inside ZomboidFileSystem.loadMods, so that call is
     * already on the stack when our patch is applied. Retransformation cannot change a frame
     * that is already executing, so an OnExit advice there never fires: you cannot patch the
     * method that loads you, for the call that loads you. Verified by an unconditional log
     * line that never appeared.
     *
     * initShared runs afterwards and still calls TileGeometryManager.init roughly seven
     * seconds later, past ScriptManager.Load and the clothing phase.
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
