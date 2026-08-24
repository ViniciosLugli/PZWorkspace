package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.List;
import java.util.concurrent.ThreadPoolExecutor;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.utils.DirectBufferAllocator;
import zombie.debug.DebugLog;

/**
 * Sizes the direct-buffer gate every image task waits on, and the asset thread pool.
 * -Dfastloading.assets=off restores the engine's 50 MB budget and 4 threads.
 *
 * MIND THE POLARITY: this is OnEnter(skipOn = true), so "off" must return FALSE. Returning true
 * would skip the engine's wait entirely, which is not vanilla behaviour and worse than either.
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

    /**
     * Cached live-buffer reading. getBytesAllocated() takes the allocator's global monitor and
     * walks the live list twice, and the main thread takes that same monitor to upload a
     * texture -- so calling it once per image task makes the UI wait on the asset pool. Under
     * budget, which is the normal case, a reading this recent is good enough to admit a task.
     * Over budget the caller is already sleeping, so the exact reading costs nothing there.
     */
    public static final long CACHE_NS =
            Long.getLong("fastloading.assetcache", 20L) * 1000000L;
    public static volatile long cachedBytes;
    public static volatile long cachedAt;

    /** Live direct-buffer bytes, no more than CACHE_NS stale. Public: the advice inlines it. */
    public static long liveBytes() {
        long now = System.nanoTime();
        long at = cachedAt;
        if (at != 0L && now - at < CACHE_NS) {
            return cachedBytes;
        }
        long b = DirectBufferAllocator.getBytesAllocated();
        cachedBytes = b;
        cachedAt = now;
        return b;
    }

    /**
     * Upload backlog the render thread is allowed to fall behind by, in queued items.
     *
     * THIS IS THE ONE THAT MATTERS FOR MENU LATENCY. Every retired texture queues a createTexture
     * onto RenderThread's invoke queue (TextureID.java:327), up to 16 a frame, and the render
     * thread drains that queue under a 10 ms budget per loop (RenderThread.java:303). Production
     * beats consumption, so the queue grows without bound.
     *
     * Anything that calls invokeOnRenderContext -- Keyboard.initKeyNames when the options screen
     * opens, Core.setDisplayMode when it is applied -- then BLOCKS behind the whole backlog:
     * flushInvokeQueue rescues a waiting item, but only after running every item ahead of it, and
     * that rescue loop has no budget (:308-316), so on a large mod list the main thread can sit
     * in RenderContextQueueItem.waitUntilFinished for seconds.
     *
     * Parking a decode worker while the render thread is this far behind costs no throughput --
     * the work would only have queued, and its buffer could not be freed until it uploaded.
     * -Dfastloading.uploadcap=0 disables the check.
     */
    public static final int UPLOAD_CAP = Integer.getInteger("fastloading.uploadcap", 0);

    // DEFAULT OFF, and measured rather than cautious. Capping the backlog does shorten the
    // blocking wait, but a worker parked in this gate still holds one of the sixteen in-flight
    // slots, so it starves the request the player is waiting for. The queue has two consumers
    // and throttling only moves the cost between them; removing the blocking calls fixes both.

    /**
     * The cap applies ONLY while the front end is ticking, and that is deliberate.
     *
     * A deep upload queue costs nothing during boot or a world load: nothing is waiting on the
     * render thread for a UI response, and the loading barrier waits for the whole queue anyway,
     * so parking a worker there would be pure loss. It costs everything at the menu, where a
     * click blocks behind the backlog. Scoping it this way makes the fix load-neutral by
     * construction rather than by measurement.
     *
     * Driven by a heartbeat from menu Lua rather than a state check: OnFETick fires only at the
     * front end, so the flag clears itself the moment a world starts loading. OnGameStart would
     * be far too late -- it fires after the load this must not affect.
     */
    public static volatile long lastMenuBeat;
    public static final long MENU_STALE_MS = 1000L;

    @se.krka.kahlua.integration.annotations.LuaMethod(
            name = "FastLoading_MenuBeat", global = true)
    public static String menuBeat() {
        lastMenuBeat = System.currentTimeMillis();
        // The front end ticking IS the definition of boot being over, so retire the loading
        // screen here rather than waiting for its idle timer. Otherwise it can repaint over a
        // menu that is already drawing itself.
        BootProgress.off = true;
        return "ok";
    }

    public static boolean atMenu() {
        long t = lastMenuBeat;
        return t != 0L && System.currentTimeMillis() - t < MENU_STALE_MS;
    }

    private static volatile boolean queueFieldsTried;
    private static Field F_QUEUE;
    private static Field F_INVOKING;

    /** Depth of the render thread's invoke queue, or 0 if it cannot be read. */
    public static int uploadBacklog() {
        if (UPLOAD_CAP <= 0 || !atMenu()) {
            return 0;               // loading phases run uncapped
        }
        if (DemandPriority.demandPending()) {
            // A parked worker still holds one of the sixteen in-flight slots, so capping here
            // would block the very request the player is waiting for. Let the pool run.
            return 0;
        }
        try {
            if (!queueFieldsTried) {
                initQueueFields();
            }
            if (F_QUEUE == null) {
                return 0;
            }
            Object inbox = F_QUEUE.get(null);
            int n;
            // The engine locks the inbox itself; the invoking list is render-thread local, so
            // reading its size is a benign race and only ever makes us a frame stale.
            synchronized (inbox) {
                n = ((List<?>) inbox).size();
            }
            if (F_INVOKING != null) {
                n += ((List<?>) F_INVOKING.get(null)).size();
            }
            return n;
        } catch (Throwable t) {
            F_QUEUE = null;             // read it once, never again
            return 0;
        }
    }

    private static volatile boolean pendingFieldTried;
    private static Field F_PENDING;

    /**
     * Depth of the asset system's pending queue, or -1 if it cannot be read. Used to tell "the
     * loader is still busy" from "the machine is idle", which is the difference between bulk
     * warming being free and it being the reason a menu feels slow.
     */
    public static int pendingCount() {
        try {
            if (!pendingFieldTried) {
                pendingFieldTried = true;
                Object fs = zombie.GameWindow.fileSystem;
                if (fs != null) {
                    F_PENDING = fs.getClass().getDeclaredField("pending");
                    F_PENDING.setAccessible(true);
                }
            }
            if (F_PENDING == null) {
                return -1;
            }
            Object v = F_PENDING.get(zombie.GameWindow.fileSystem);
            return (v instanceof List) ? ((List<?>) v).size() : -1;
        } catch (Throwable t) {
            F_PENDING = null;
            return -1;
        }
    }

    private static synchronized void initQueueFields() {
        if (queueFieldsTried) {
            return;
        }
        queueFieldsTried = true;
        try {
            Class<?> rt = Class.forName("zombie.core.opengl.RenderThread");
            F_QUEUE = rt.getDeclaredField("invokeOnRenderQueue");
            F_QUEUE.setAccessible(true);
            F_INVOKING = rt.getDeclaredField("invokeOnRenderQueue_Invoking");
            F_INVOKING.setAccessible(true);
        } catch (Throwable t) {
            F_QUEUE = null;
            DebugLog.log(Tuning.TAG + " upload backlog unreadable (" + t + ")");
        }
    }

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

    /**
     * Asset workers run below the game thread. Ten decode threads on a six-core part outbid the
     * front end, and the menu drops frames -- which is what a player feels as a slow options
     * screen. Priority costs no throughput: while the game thread is idle, as it is through a
     * loading screen, the workers still get every spare core.
     * -Dfastloading.assetprio=N, 1..10, 0 leaves the default.
     */
    public static final int WORKER_PRIORITY =
            Integer.getInteger("fastloading.assetprio", 0);

    @Patch.OnEnter(skipOn = true)
    public static boolean enter() {
        if (!ON) {
            return false;               // run the engine's own 50 MB / 20 ms wait
        }
        sizePool();
        // Every image task starts here, so each worker demotes itself on its first one. No
        // thread factory needed, and it reaches the pool's original threads too.
        if (WORKER_PRIORITY > 0) {
            Thread self = Thread.currentThread();
            if (self.getPriority() != WORKER_PRIORITY) {
                try {
                    self.setPriority(WORKER_PRIORITY);
                } catch (Throwable ignored) {
                }
            }
        }
        totalCalls++;
        boolean blocked = false;
        long t0 = 0L;
        while (liveBytes() > BUDGET || uploadBacklog() > UPLOAD_CAP) {
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

    /**
     * One line describing the whole pipeline, for a per-second trace.
     *
     * The three numbers are the three places a texture can be stuck, and they need different
     * fixes: waiting to start (pending), decoded but waiting for the render thread (upload),
     * or held back by the buffer budget (live/blocked). Without all three side by side, a slow
     * texture is indistinguishable from a slow machine -- which is how three wrong causes got
     * chased before this existed.
     */
    @se.krka.kahlua.integration.annotations.LuaMethod(
            name = "FastLoading_PipelineStatus", global = true)
    public static String pipelineStatus() {
        int pend = pendingCount();
        int up;
        try {
            Object inbox = F_QUEUE == null ? null : F_QUEUE.get(null);
            if (inbox == null) {
                initQueueFields();
                inbox = F_QUEUE == null ? null : F_QUEUE.get(null);
            }
            if (inbox == null) {
                up = -1;
            } else {
                synchronized (inbox) {
                    up = ((List<?>) inbox).size();
                }
                if (F_INVOKING != null) {
                    up += ((List<?>) F_INVOKING.get(null)).size();
                }
            }
        } catch (Throwable t) {
            up = -1;
        }
        return "pending=" + pend
               + " upload=" + up
               + " liveMB=" + (liveBytes() >> 20)
               + " blocked=" + blockedCalls
               + " blockedMs=" + blockedMs;
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
