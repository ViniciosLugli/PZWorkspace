package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.concurrent.ThreadPoolExecutor;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.utils.DirectBufferAllocator;
import zombie.debug.DebugLog;

/**
 * Every image task waits here until live direct-buffer bytes fall under a budget.
 * Vanilla's budget is 50 MB polled every 20 ms, which serialises the asset workers.
 */
@Patch(className = "zombie.core.textures.TextureIDAssetManager", methodName = "waitFileTask")
public class AssetThrottle {

    // public: the advice body below is inlined into TextureIDAssetManager, which then
    // accesses these from its own class. Anything private throws IllegalAccessError.
    public static final long BUDGET = Tuning.budgetBytes(Runtime.getRuntime().maxMemory());
    private static volatile boolean poolSized;

    @Patch.OnEnter(skipOn = true)
    public static boolean enter() {
        sizePool();
        while (DirectBufferAllocator.getBytesAllocated() > BUDGET) {
            try {
                Thread.sleep(2L);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        return true;
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
