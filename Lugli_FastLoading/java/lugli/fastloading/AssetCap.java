package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.FutureTask;
import java.util.concurrent.ThreadPoolExecutor;

import zombie.GameWindow;
import zombie.core.logger.ExceptionLogger;
import zombie.debug.DebugLog;
import zombie.fileSystem.FileTask;
import zombie.gameStates.GameState;

/**
 * Raises the asset in-flight cap above the engine's hardcoded 16. -Dfastloading.assetcap=off,
 * default ON. It improves BOTH halves of a launch, which parts that merely relocate work do not
 * do.
 *
 * updateAsyncTransactions is the only place a queued task reaches a worker, and it refills
 * in-flight to a literal 16. AssetThrottle grows the pool to 10 threads, but 10 workers share a
 * 16-slot gate, so the pool is mostly decorative: "pending avg 9365 max 10441, in-flight max 16".
 *
 * You do not need to rewrite the constant -- which the advice API genuinely cannot do. Let the
 * engine finish its capped pass, then fill the gate the rest of the way on the way out.
 *
 * THE NON-OBVIOUS HALF: the engine harvests only Math.min(inProgress.size(), 16) entries, so once
 * the list grows past 16 anything finished in the tail is never retired and a top-up ALONE wedges
 * the queue. This sweeps the whole list before refilling.
 *
 * All reflection, so any failure latches `off` and leaves the engine exactly as it was. `pending`
 * and `inProgress` are unguarded -- the engine treats them as single-threaded and so does this,
 * from the same call.
 */
public final class AssetCap {

    public static final String TAG = "[FastLoading/assetcap]";

    // public: this body is inlined into zombie.fileSystem.FileSystemImpl, which then reads these
    // as its own. Anything private throws IllegalAccessError at runtime.
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.assetcap", "on"));

    /** -Dfastloading.assetcapn=N, or null to derive the cap from the live pool. */
    public static final Integer CAP_OVERRIDE = Integer.getInteger("fastloading.assetcapn");

    /**
     * The cap the last top-up applied; see Tuning.assetCap. Re-derived on every top-up from the
     * live pool, because AssetThrottle resizes the pool on the first image task, which can land
     * after the first top-up.
     */
    public static volatile int cap = Tuning.ENGINE_IN_FLIGHT;

    /** The engine's harvest window, and therefore where its blind spot starts. */
    public static final int ENGINE_WINDOW = Tuning.ENGINE_IN_FLIGHT;

    public static volatile boolean off;

    /**
     * Ends the boot scope. Outside boot the raise runs only while GameLoadingState is current:
     * ImagePyramid.destroy() and TilesetImageCreator pump this method in a cancellation spin loop,
     * and a top-up there would lengthen the drain that loop waits on. GameLoadingState.enter runs
     * that drain (WorldMapImages.Reset), which is safe only because GameStateMachine calls
     * enter() before it sets current, so current is still the previous state during it.
     */
    public static volatile boolean bootDone;

    /** -Dfastloading.assetcapload=off: the engine's 16 in flight during the world load. */
    public static final boolean LOAD_SCOPE =
            !"off".equals(System.getProperty("fastloading.assetcapload", "on"));

    /** The world-load window; see Tuning.loadCap. */
    public static final int LOAD_CAP = Tuning.loadCap(Integer.getInteger("fastloading.assetcaploadn"));

    public static int loadSubmitted;
    public static int loadRetired;
    private static boolean loadAnnounced;

    /**
     * BACKSTOP. endBoot() is called from BootProgress's advice on MainScreenState.enter, so the
     * scope depends on a patch landing in ANOTHER class -- the same single-point-of-failure that
     * left the loading screen painting forever and MeshPriority's gate stuck open. If that advice
     * never runs, this bounds the raise anyway. Generous on purpose: a slow boot on a large list
     * is minutes, and closing early only forfeits some of the win, while never closing reaches
     * ImagePyramid.destroy()'s cancellation spin loop.
     */
    public static final long MAX_MS = Long.getLong("fastloading.assetcapms", 600000L);

    public static volatile long firstTopUpAt;
    public static int submitted;
    public static int retiredTail;

    private static Field F_INPROGRESS;
    private static Field F_PENDING;
    private static Field F_EXECUTOR;
    private static Field F_TASK;
    private static Field F_FUTURE;
    private static boolean resolved;

    private AssetCap() {}

    private static void resolve(Object fs) throws Exception {
        Class<?> c = fs.getClass();
        F_INPROGRESS = c.getDeclaredField("inProgress");
        F_PENDING = c.getDeclaredField("pending");
        F_EXECUTOR = c.getDeclaredField("executor");
        F_INPROGRESS.setAccessible(true);
        F_PENDING.setAccessible(true);
        F_EXECUTOR.setAccessible(true);

        Class<?> item = Class.forName("zombie.fileSystem.FileSystemImpl$AsyncItem",
                                      false, c.getClassLoader());
        F_TASK = item.getDeclaredField("task");
        F_FUTURE = item.getDeclaredField("future");
        F_TASK.setAccessible(true);
        F_FUTURE.setAccessible(true);
        resolved = true;
    }

    /** true once the boot scope has run past MAX_MS without the menu ending it. */
    private static boolean bootBackstopFired() {
        long now = System.currentTimeMillis();
        if (firstTopUpAt == 0L) {
            firstTopUpAt = now;
            return false;
        }
        if (MAX_MS <= 0L || now - firstTopUpAt <= MAX_MS) {
            return false;
        }
        // The scope never closed. Something upstream did not run; stop rather than run on.
        bootDone = true;
        DebugLog.log(TAG + " backstop: boot never ended after " + (MAX_MS / 1000L)
                     + "s, cap back to " + ENGINE_WINDOW);
        return true;
    }

    /** After boot: true while a world load is on screen and LOAD_SCOPE is on; logs each edge. */
    private static boolean worldLoadScope() {
        if (!LOAD_SCOPE) {
            return false;
        }
        GameState current = GameWindow.states.current;
        boolean inLoad = current != null
                && "zombie.gameStates.GameLoadingState".equals(current.getClass().getName());
        if (inLoad && !loadAnnounced) {
            loadAnnounced = true;
            loadSubmitted = 0;
            loadRetired = 0;
            DebugLog.log(TAG + " world-load scope armed, cap " + LOAD_CAP);
        } else if (!inLoad && loadAnnounced) {
            loadAnnounced = false;
            DebugLog.log(TAG + " world load ended: " + loadSubmitted + " extra submit(s), "
                         + loadRetired + " retired beyond the engine window; cap back to "
                         + ENGINE_WINDOW);
        }
        return inLoad;
    }

    /**
     * Called on the way out of updateAsyncTransactions, after the engine has done its capped pass.
     */
    @SuppressWarnings("unchecked")
    public static void topUp(Object fs) {
        if (!ON || off || fs == null) {
            return;
        }
        final boolean afterBoot = bootDone;
        if (afterBoot && !worldLoadScope()) {
            return;
        }
        if (!afterBoot && bootBackstopFired()) {
            return;
        }
        try {
            if (!resolved) {
                resolve(fs);
            }
            ArrayList<Object> inProgress = (ArrayList<Object>) F_INPROGRESS.get(fs);
            ArrayList<Object> pending = (ArrayList<Object>) F_PENDING.get(fs);
            ExecutorService executor = (ExecutorService) F_EXECUTOR.get(fs);
            if (inProgress == null || pending == null || executor == null) {
                return;
            }

            // Retire what the engine's 16-entry window could not reach. Scanning the whole list is
            // correct and simplest: anything the engine already retired is no longer in it.
            if (inProgress.size() > ENGINE_WINDOW) {
                for (int i = 0; i < inProgress.size(); i++) {
                    Object item = inProgress.get(i);
                    FutureTask<Object> f = (FutureTask<Object>) F_FUTURE.get(item);
                    if (f == null || !f.isDone()) {
                        continue;
                    }
                    FileTask t = (FileTask) F_TASK.get(item);
                    inProgress.remove(i--);
                    if (!f.isCancelled() && t != null) {
                        Object result = null;
                        try {
                            result = f.get();
                        } catch (Throwable failed) {
                            // As the engine's own harvest does; a failed asset must still be retired.
                            ExceptionLogger.logException(failed, t.getErrorMessage());
                        }
                        t.handleResult(result);
                    }
                    if (t != null) {
                        t.done();
                    }
                    F_TASK.set(item, null);
                    F_FUTURE.set(item, null);
                    if (afterBoot) {
                        loadRetired++;
                    } else {
                        retiredTail++;
                    }
                }
            }

            // Then fill the gate the rest of the way.
            int limit;
            if (afterBoot) {
                limit = LOAD_CAP;
            } else {
                int pool = executor instanceof ThreadPoolExecutor tpe ? tpe.getMaximumPoolSize() : 0;
                limit = Tuning.assetCap(pool, CAP_OVERRIDE);
                // Logged on each change, which is at most twice: the stock pool, then the resized one.
                if (limit != cap) {
                    DebugLog.log(TAG + " in-flight cap " + ENGINE_WINDOW + " -> " + limit
                                 + " (asset pool " + pool + ")");
                }
                cap = limit;
            }
            while (inProgress.size() < limit && !pending.isEmpty()) {
                Object item = pending.remove(0);
                FutureTask<Object> f = (FutureTask<Object>) F_FUTURE.get(item);
                FileTask t = (FileTask) F_TASK.get(item);
                if (f == null) {
                    continue;
                }
                if (f.isCancelled()) {
                    if (t != null) {
                        t.done();
                    }
                    continue;
                }
                inProgress.add(item);
                executor.submit(f);
                if (afterBoot) {
                    loadSubmitted++;
                } else {
                    submitted++;
                }
            }
        } catch (Throwable t) {
            off = true;
            DebugLog.log(TAG + " disabled (" + t + ")");
        }
    }

    /** Ends the raise at the main menu, from Java, alongside the loading screen's retirement. */
    public static void endBoot() {
        if (bootDone) {
            return;
        }
        bootDone = true;
        if (submitted > 0) {
            DebugLog.log(TAG + " boot ended: " + submitted + " extra submit(s), "
                         + retiredTail + " retired beyond the engine window;"
                         + " cap back to " + ENGINE_WINDOW);
        }
    }

    /** Read by the status bridge so a failed install is visible rather than silent. */
    public static String status() {
        if (!ON) return "off";
        if (off) return "DEFECT";
        return "ok, cap " + cap + ", " + submitted + " extra submit(s), "
               + retiredTail + " retired beyond the engine window"
               + (LOAD_SCOPE ? ", world-load cap " + LOAD_CAP : "");
    }
}
