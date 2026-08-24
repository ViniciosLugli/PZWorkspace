package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * Lets a texture the player just asked for overtake the boot backlog. -Dfastloading.demandprio=off.
 *
 * THE PROBLEM
 *   Every texture in the engine is queued at priority 7 -- TextureIDAssetManager.startLoading
 *   sets it on both branches (:26, :32) -- and FileSystemImpl inserts by a STRICT comparison
 *   (:206-214, `item.task.priority > item1.task.priority`). Equal priorities therefore never
 *   overtake: a new request walks the whole pending list and appends at the tail. On a large mod
 *   list that list peaks near 3,000 entries during menu time, so a checkbox tick or a mod poster
 *   requested when a screen opens waits behind the entire boot backlog before it is even started.
 *   There is no priority band a UI request can use, because everything already occupies the top.
 *
 * THE RULE
 *   While the front end is ticking, a texture being requested NOW is by definition something the
 *   player is looking at, and everything already queued is background. Promote it above the
 *   backlog. Demote the vehicle warm, which is the opposite case: bulk work nobody is waiting for.
 *
 * WHY THIS COSTS NO LOAD TIME
 *   Priority is ordering, not admission -- the same tasks run either way. And the rule is scoped
 *   to the menu, so during boot and world load nothing is promoted and the queue order is exactly
 *   the engine's. A loading barrier waits for the whole queue regardless of order, which is why
 *   reordering can never shorten a load; here it is latency of one request that matters, and that
 *   is precisely what priority controls.
 *
 * ONLY 7 IS TOUCHED, so the mesh (6), physics (6) and animation (4) bands are left alone.
 */
@Patch(className = "zombie.fileSystem.FileTask", methodName = "setPriority")
public final class DemandPriority {

    // public: this body is inlined into zombie.fileSystem.FileTask, which then reads these from
    // its own class. Anything private throws IllegalAccessError at runtime.
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.demandprio", "on"));

    /** The band textures are queued at by the engine. Only this value is rewritten. */
    public static final int TEXTURE_BAND = 7;

    /** Above the band, so it overtakes everything already pending. */
    public static final int DEMAND = Integer.getInteger("fastloading.demandband", 9);

    /** Below the band, so bulk warming never delays anything else. */
    public static final int BULK = Integer.getInteger("fastloading.bulkband", 3);

    /**
     * Set by VehicleTextureWarm around its slice. It runs on the main thread, so a request from
     * another thread inside that window would also be demoted; the window is a handful of
     * scripts and the cost of being wrong is bulk work running slightly later.
     */
    public static volatile boolean bulk;

    /**
     * Promote whatever is requested inside this window, even during boot.
     *
     * Used for the loading screen's own art. Every texture is queued at the same priority, so a
     * request made at the start of boot still waits behind the entire backlog. One promoted
     * texture cannot meaningfully delay thousands, and it is the one the player is looking at.
     */
    public static volatile boolean boost;

    public static long promoted;
    public static long demoted;

    /**
     * When the player last caused a texture to be requested.
     *
     * Promoting a task to the front of `pending` is not enough on its own: it still needs one of
     * the sixteen in-flight slots, and a worker parked in the upload gate HOLDS its slot while
     * making no progress. So for a moment after a demand request the gate and the vehicle warm
     * both stand down, which frees slots and lets the promoted task actually run.
     */
    public static volatile long lastDemandAt;
    public static final long DEMAND_WINDOW_MS =
            Long.getLong("fastloading.demandwindow", 2000L);

    /** True shortly after the player asked for a texture. Public: read from inlined advice. */
    public static boolean demandPending() {
        long t = lastDemandAt;
        return t != 0L && System.currentTimeMillis() - t < DEMAND_WINDOW_MS;
    }

    private DemandPriority() {}

    /**
     * Counters, for proving the advice actually ran. A patched-class line in the log does not
     * mean an advice fired, and an advice firing does not mean its argument write-back reached
     * the callee -- both fail silently, so a counter is the only evidence the rewrite happened.
     */
    @se.krka.kahlua.integration.annotations.LuaMethod(
            name = "FastLoading_DemandStatus", global = true)
    public static String status() {
        if (!ON) {
            return "off";
        }
        return "promoted=" + promoted + " demoted=" + demoted
               + " band=" + DEMAND + "/" + BULK;
    }

    @Patch.OnEnter
    public static void enter(@Patch.Argument(value = 0, readOnly = false) int priority) {
        if (!ON || priority != TEXTURE_BAND) {
            return;
        }
        if (boost) {
            promoted++;
            priority = DEMAND;
            return;
        }
        if (bulk) {
            demoted++;
            priority = BULK;
            return;
        }
        if (AssetThrottle.atMenu()) {
            promoted++;
            lastDemandAt = System.currentTimeMillis();
            priority = DEMAND;
        }
    }
}
