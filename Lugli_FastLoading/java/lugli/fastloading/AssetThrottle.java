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
     * Milliseconds between budget re-checks while blocked. Vanilla is 20. This was 2, which was
     * a mistake: getBytesAllocated() takes the same global monitor every allocation needs and
     * walks the live-buffer list twice, so a fine poll from ten workers fights the very
     * allocation it is waiting for.
     */
    public static final long POLL_MS = Long.getLong("fastloading.assetpoll", 20L);

    /** How often, and for how long, workers actually slept on the budget. */
    public static long blockedCalls;
    public static long blockedMs;
    public static long totalCalls;

    /**
     * -Dfastloading.assetstats=on logs the counters above while they move, rate-limited, from
     * inside the gate. Reporting them from Lua at OnGameStart is unreliable: a benchmark harness
     * closes the game before that event, and a missing line looks identical to a disabled probe.
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
