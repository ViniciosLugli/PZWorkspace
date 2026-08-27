package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.FutureTask;

import zombie.debug.DebugLog;
import zombie.fileSystem.FileTask;

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

    /** The engine's own value is 16. 48 is what the loose-class version measured at. */
    public static final int CAP = Integer.getInteger("fastloading.assetcapn", 48);

    /** The engine's harvest window, and therefore where its blind spot starts. */
    public static final int ENGINE_WINDOW = 16;

    public static volatile boolean off;
    public static volatile boolean announced;

    /**
     * BOOT ONLY, and this is a safety scope rather than a tuning choice.
     *
     * The entire measured win is in boot (-3.61 s) -- world load did not move -- so ending here
     * costs nothing and removes every risk outside it. Two engine paths pump this method in a
     * CANCELLATION spin loop: ImagePyramid.destroy() (:732) cancels its tasks and then spins on
     * updateAsyncTransactions until they drain, and TilesetImageCreator (:85) does the same shape.
     * A top-up that keeps feeding the gate during one of those would lengthen the very drain the
     * loop is waiting on. Nothing about that is worth a second of boot we already have.
     */
    public static volatile boolean bootDone;

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

    /**
     * Called on the way out of updateAsyncTransactions, after the engine has done its capped pass.
     */
    @SuppressWarnings("unchecked")
    public static void topUp(Object fs) {
        if (!ON || off || bootDone || fs == null) {
            return;
        }
        long now = System.currentTimeMillis();
        if (firstTopUpAt == 0L) {
            firstTopUpAt = now;
        } else if (MAX_MS > 0L && now - firstTopUpAt > MAX_MS) {
            // The scope never closed. Something upstream did not run; stop rather than run on.
            bootDone = true;
            DebugLog.log(TAG + " backstop: boot never ended after " + (MAX_MS / 1000L)
                         + "s, cap back to " + ENGINE_WINDOW);
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
                        } catch (Throwable ignored) {
                            // The engine logs this case; a failed asset must still be retired.
                        }
                        t.handleResult(result);
                    }
                    if (t != null) {
                        t.done();
                    }
                    F_TASK.set(item, null);
                    F_FUTURE.set(item, null);
                    retiredTail++;
                }
            }

            // Then fill the gate the rest of the way.
            while (inProgress.size() < CAP && !pending.isEmpty()) {
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
                submitted++;
            }

            if (!announced) {
                announced = true;
                DebugLog.log(TAG + " in-flight cap raised " + ENGINE_WINDOW + " -> " + CAP);
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
        return "ok, cap " + CAP + ", " + submitted + " extra submit(s), "
               + retiredTail + " retired beyond the engine window";
    }
}
