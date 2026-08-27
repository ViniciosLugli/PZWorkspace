package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.List;

import zombie.debug.DebugLog;

/**
 * Prices the asset queue's priority merge. -Dfastloading.mergestat=on (default OFF).
 *
 * DIAGNOSTIC ONLY -- it reads and counts, it never mutates. Nothing here changes what the engine
 * does, so an arm running with it on differs from one running without it only by this cost.
 *
 * WHAT IT COUNTS AND WHY THAT SHAPE. FileSystemImpl.updateAsyncTransactions merges `added` into
 * `pending` by linear-scanning `pending` for the first entry of strictly LOWER priority and
 * inserting there. FileTask.priority defaults to 5 and the compare is a strict `>`, so against a
 * uniform-priority queue the condition never holds: the scan runs to completion and the item is
 * appended. The cost is therefore |added| x |pending| compares, with no best case, plus an
 * ArrayList shift whenever a higher-priority task does break early.
 *
 * Counting that by replaying the scan would double the very cost being measured. It does not have
 * to: this insert is the only thing that ever writes `pending`, so `pending` is always in
 * non-increasing priority order, and the break index is a BINARY SEARCH -- ~14 reads at a queue
 * depth of 10,000 instead of 10,000.
 *
 * EXACTNESS. `pending` grows by one per merged item, which the running count folds in. That makes
 * the compare total exact for the uniform-priority case (every item appends, so item i scans
 * |pending| + i) and a close approximation when priorities are mixed, where an already-inserted
 * item can move a later break index by a place or two. `hiPrio` reports how much of the run was
 * mixed at all, so the size of that approximation is visible rather than assumed.
 *
 * THREADING. `pending` is written only from this method, on the game thread, so it is read
 * directly. `added` is appended by runAsync from other threads under the engine's spin lock, so it
 * is snapshotted defensively and a pump whose snapshot fails is counted in `skipped` rather than
 * guessed at. Any reflection failure latches the whole probe off and says so once.
 */
public final class MergeStat {

    public static final String TAG = "[FastLoading/mergestat]";

    // public: called from an advice body inlined into zombie.fileSystem.FileSystemImpl, which
    // reads these as its own. Anything private throws IllegalAccessError at runtime.
    public static final boolean ON =
            "on".equals(System.getProperty("fastloading.mergestat", "off"));

    /** Latched by any reflection failure, so a broken probe reports itself instead of lying. */
    public static volatile boolean off;

    public static volatile long pumps;        // calls to updateAsyncTransactions
    public static volatile long merged;       // items moved from `added` into `pending`
    public static volatile long compares;     // priority compares the engine's scan performs
    public static volatile long shifted;      // elements ArrayList.add(int,E) has to move
    public static volatile long hiPrio;       // merged items whose priority is not the default 5
    public static volatile long skipped;      // pumps whose `added` snapshot lost a race
    public static volatile int maxPending;
    public static volatile int maxAdded;

    /** Boot-phase snapshot, so the world-load half is a subtraction rather than a second run. */
    public static volatile long bootPumps;
    public static volatile long bootCompares;
    public static volatile long bootShifted;
    public static volatile long bootMerged;

    private static volatile boolean announced;
    private static long lastLogNanos;
    private static Field fAdded;
    private static Field fPending;
    private static Field fTask;
    private static Field fPriority;

    private MergeStat() {}

    /**
     * Called from BootProgress.AssetPump's OnEnter, i.e. before the engine's own merge runs, so
     * the sizes read here are the ones that merge will face.
     *
     * It rides the existing advice rather than declaring a second patch class on the same method.
     * Two advices per method stack, but a dev-jar advice added to a method a FastLoading advice
     * already holds has silently failed to run before: the jars register in different
     * phases and by then the class may already be transformed.
     */
    public static void sample(Object fs) {
        if (!ON || off) {
            return;
        }
        // Before every guard below it, so "armed and found nothing" can never read the same as
        // "the call site never ran". Every invisible-closed-guard defect this mod has shipped
        // would have been caught by one line of this shape.
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " armed: counting the priority merge, no behaviour change");
        }
        if (fs == null) {
            off = true;
            DebugLog.log(TAG + " disabled: the advice passed a null FileSystemImpl");
            return;
        }
        try {
            if (fAdded == null) {
                resolve(fs);
                if (fAdded == null) {
                    pumps++;           // both queues empty this pump; retry the lookup on the next
                    return;
                }
            }
            List<?> added = (List<?>) fAdded.get(fs);
            List<?> pending = (List<?>) fPending.get(fs);
            pumps++;
            int p = pending.size();
            if (p > maxPending) {
                maxPending = p;
            }
            heartbeat();
            if (added.isEmpty()) {
                return;
            }

            Object[] items;
            try {
                items = added.toArray();
            } catch (Throwable race) {
                skipped++;                     // a concurrent runAsync won; do not guess the pump
                return;
            }
            if (items.length > maxAdded) {
                maxAdded = items.length;
            }
            for (int i = 0; i < items.length; i++) {
                if (items[i] == null) {
                    continue;                  // same race, one slot rather than the whole array
                }
                int prio = priorityOf(items[i]);
                if (prio == Integer.MIN_VALUE) {
                    continue;
                }
                int depth = p + i;             // the merge has already inserted i items
                int insertAt = breakIndex(pending, prio, p);
                if (insertAt >= p) {
                    compares += depth;         // no strictly-lower entry: the scan runs to the end
                } else {
                    compares += insertAt + 1;  // the compare that broke counts too
                    shifted += depth - insertAt;
                }
                if (prio != 5) {
                    hiPrio++;
                }
                merged++;
            }
        } catch (Throwable t) {
            off = true;
            DebugLog.log(TAG + " disabled after " + pumps + " pump(s): " + t);
        }
    }

    /**
     * A rate-limited line, so the counters survive a harness that kills the game shortly after
     * `game loading took`. An OnGameStart dump does not: the same probe reported through Lua
     * landed in the log in one world-load run out of six, and a missing line reads exactly like a
     * disabled probe.
     *
     * The clock is only read every 64th pump. During a barrier this method is called from a spin
     * loop, so reading it per call would be its own measurable cost.
     *
     * It is called BEFORE the empty-`added` return, not after the merge loop. Gating it on both a
     * pump multiple and a pump that had something to merge is a conjunction, and that conjunction
     * fired zero times across a 788-pump boot -- a rate limiter that can silently never fire is
     * the same defect shape as a stand-down guard that never logs.
     */
    private static void heartbeat() {
        if ((pumps & 63L) != 0L) {
            return;
        }
        long now = System.nanoTime();
        if (now - lastLogNanos < 5_000_000_000L) {
            return;
        }
        lastLogNanos = now;
        DebugLog.log(TAG + " " + status());
    }

    /**
     * First index of `pending` holding a strictly lower priority, or `size` if there is none --
     * the position the engine's scan would break at.
     *
     * The predicate is monotone because `pending` is non-increasing, which is the only reason a
     * search is allowed to stand in for the scan.
     */
    private static int breakIndex(List<?> pending, int prio, int size) {
        int lo = 0;
        int hi = size;
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            Object item = pending.get(mid);
            int q = item == null ? Integer.MIN_VALUE : priorityOf(item);
            if (q == Integer.MIN_VALUE) {
                return size;                   // unreadable entry: charge the full scan, never less
            }
            if (prio > q) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        return lo;
    }

    private static int priorityOf(Object asyncItem) {
        try {
            Object task = fTask.get(asyncItem);
            return task == null ? Integer.MIN_VALUE : fPriority.getInt(task);
        } catch (Throwable t) {
            return Integer.MIN_VALUE;
        }
    }

    /**
     * `added` and `pending` are declared on FileSystemImpl itself; `task` on the private nested
     * AsyncItem; `priority` on the abstract FileTask, so the walk up the hierarchy is required.
     */
    private static void resolve(Object fs) throws Exception {
        Field a = fs.getClass().getDeclaredField("added");
        Field p = fs.getClass().getDeclaredField("pending");
        a.setAccessible(true);
        p.setAccessible(true);
        List<?> added = (List<?>) a.get(fs);
        List<?> pending = (List<?>) p.get(fs);

        Object sample = null;
        if (!added.isEmpty()) {
            sample = added.get(0);
        } else if (!pending.isEmpty()) {
            sample = pending.get(0);
        }
        if (sample == null) {
            return;                            // both queues empty; try again on the next pump
        }
        Field t = sample.getClass().getDeclaredField("task");
        t.setAccessible(true);
        Object task = t.get(sample);
        if (task == null) {
            return;
        }
        Field pr = null;
        for (Class<?> c = task.getClass(); c != null && pr == null; c = c.getSuperclass()) {
            try {
                pr = c.getDeclaredField("priority");
            } catch (NoSuchFieldException ignored) {
                // keep walking: `priority` lives on the abstract FileTask, not on the concrete task
            }
        }
        if (pr == null) {
            throw new NoSuchFieldException("FileTask.priority");
        }
        pr.setAccessible(true);

        fTask = t;
        fPriority = pr;
        fPending = p;
        fAdded = a;                            // assigned last: it is the flag `sample` checks
    }

    /** Called from the same place AssetCap.endBoot() is, so the two halves share one boundary. */
    public static void endBoot() {
        if (!ON || bootPumps != 0) {
            return;
        }
        bootPumps = pumps;
        bootCompares = compares;
        bootShifted = shifted;
        bootMerged = merged;
        DebugLog.log(TAG + " boot: " + status());
    }

    public static String status() {
        if (!ON) return "off";
        if (off) return "DEFECT";
        return "pumps=" + pumps + " merged=" + merged + " compares=" + compares
             + " shifted=" + shifted + " hiPrio=" + hiPrio + " skipped=" + skipped
             + " maxPending=" + maxPending + " maxAdded=" + maxAdded;
    }
}
