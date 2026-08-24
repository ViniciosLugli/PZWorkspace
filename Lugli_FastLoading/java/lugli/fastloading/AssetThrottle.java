package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.concurrent.ThreadPoolExecutor;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.utils.DirectBufferAllocator;
import zombie.debug.DebugLog;

/**
 * Every image task waits in waitFileTask until live direct-buffer bytes fall under a budget.
 * Vanilla's is 50 MB polled every 20 ms, which serialises the asset workers: one 2048px RGBA
 * texture is ~22 MB with mipmaps, so four workers exceed it immediately. Budget and pool size
 * scale off heap and core count rather than this machine -- see Tuning.
 *
 * -Dfastloading.assets=off. MIND THE POLARITY: this is OnEnter(skipOn = true), so "off" must
 * return FALSE. Returning true would skip the original and leave NO wait at all, which is not
 * vanilla behaviour but worse than either.
 *
 * docs/18-fastloading-internals.md#assetthrottle
 */
@Patch(className = "zombie.core.textures.TextureIDAssetManager", methodName = "waitFileTask")
public class AssetThrottle {

    // public: the advice body below is inlined into TextureIDAssetManager, which then
    // accesses these from its own class. Anything private throws IllegalAccessError.
    /** -Dfastloading.assetbudget=N megabytes, 0 = derive from the heap. See Tuning. */
    public static final long BUDGET = Tuning.effectiveBudgetBytes(
            Runtime.getRuntime().maxMemory(),
            Long.getLong("fastloading.assetbudget", 0L));
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.assets", "on"));
    private static volatile boolean poolSized;

    /**
     * Milliseconds between budget re-checks while blocked. Vanilla is 20
     * (`TextureIDAssetManager.java:69`); this was 2, which was a mistake.
     *
     * `getBytesAllocated()` is `synchronized` on the SAME global monitor that every buffer
     * allocation takes, and it walks the live-buffer list TWICE per call. Polling at 2 ms from 10
     * workers instead of 20 ms from 4 is a ~50x increase in acquisitions of that lock, all
     * competing with the allocation it is waiting on. At a 768 MB budget the fine poll buys
     * nothing: the budget is only reachable when ~144 decoded images are queued for upload.
     */
    public static final long POLL_MS = Long.getLong("fastloading.assetpoll", 20L);

    /**
     * DIAGNOSTIC, and the decisive one. Buffers are freed only by the render thread
     * (`TextureID.java:465-467`), so the 768 MB budget can only be reached if decoded images are
     * piling up waiting to upload. **If these counters are non-zero, the render thread is the
     * bottleneck** -- which decides whether reducing GL upload work is worth building.
     */
    public static long blockedCalls;
    public static long blockedMs;
    public static long totalCalls;

    /**
     * -Dfastloading.assetstats=on: log the gate counters periodically while they move.
     *
     * WHY PERIODIC AND NOT AT THE END. The counters were only reachable through
     * Dev_AssetStats.lua on OnGameStart, and that lands in the log in about one run out of six:
     * the world-load harness kills the game shortly after "game loading took", which is before
     * OnGameStart. Worse, a missing line is indistinguishable from the probe being off, so five
     * runs of an A/B looked like they had no data rather than like they had a race.
     *
     * Logging from inside the gate itself cannot be raced, and it turns a single end-of-run total
     * into a TIME SERIES across boot and world load -- which is what is actually needed to say
     * where the blocked time falls rather than just how much of it there is.
     *
     * Rate-limited to one line per interval and only emitted while blocking is actually
     * happening, so an unblocked run prints nothing at all.
     */
    public static final boolean STATS =
            "on".equals(System.getProperty("fastloading.assetstats", "off"));
    public static final long STATS_MS = Long.getLong("fastloading.assetstatsms", 5000L);
    public static long lastStatsAt;
    public static long lastStatsBlockedMs;

    @Patch.OnEnter(skipOn = true)
    public static boolean enter() {
        if (!ON) {
            return false;               // run the engine's own 50 MB / 20 ms wait
        }
        sizePool();
        totalCalls++;
        boolean blocked = false;
        long t0 = 0L;
        while (DirectBufferAllocator.getBytesAllocated() > BUDGET) {
            if (!blocked) {
                blocked = true;
                t0 = System.currentTimeMillis();
                blockedCalls++;
            }
            try {
                Thread.sleep(POLL_MS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        if (blocked) {
            blockedMs += System.currentTimeMillis() - t0;
        }
        if (STATS) {
            reportStats();
        }
        return true;
    }

    /** Rate-limited counter dump. Synchronized: this runs on every asset worker. */
    public static synchronized void reportStats() {
        long now = System.currentTimeMillis();
        if (lastStatsAt == 0L) {
            lastStatsAt = now;
            return;
        }
        if (now - lastStatsAt < STATS_MS) {
            return;
        }
        long deltaBlocked = blockedMs - lastStatsBlockedMs;
        lastStatsAt = now;
        lastStatsBlockedMs = blockedMs;
        if (deltaBlocked <= 0L) {
            return;                     // nothing blocked in this window: stay quiet
        }
        DebugLog.log(Tuning.TAG + " gate: calls=" + totalCalls
                     + " blocked=" + blockedCalls
                     + " blockedMs=" + blockedMs
                     + " (+" + deltaBlocked + " in the last " + STATS_MS + " ms)"
                     + " budgetMB=" + (BUDGET >> 20));
    }

    /**
     * FileSystemImpl is built in GameWindow's static initialiser, before mods load, so
     * its constructor cannot be intercepted. newFixedThreadPool returns a
     * ThreadPoolExecutor, which can simply be resized afterwards.
     */
    public static void sizePool() {
        if (poolSized) return;
        poolSized = true;

        int target = Tuning.poolTarget(Runtime.getRuntime().availableProcessors());
        if (target == 0) return;

        try {
            Field f = zombie.fileSystem.FileSystemImpl.class.getDeclaredField("executor");
            f.setAccessible(true);
            Object executor = f.get(zombie.GameWindow.fileSystem);
            if (executor instanceof ThreadPoolExecutor pool && target > pool.getMaximumPoolSize()) {
                pool.setMaximumPoolSize(target);
                pool.setCorePoolSize(target);
                DebugLog.log(Tuning.TAG + " asset pool " + target + " threads, budget "
                             + (BUDGET >> 20) + " MB");
            }
        } catch (Throwable t) {
            DebugLog.log(Tuning.TAG + " pool resize skipped (" + t + ")");
        }
    }
}
