package lugli.fastloading;

import java.util.ArrayList;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.debug.DebugLog;
import zombie.scripting.ScriptManager;
import zombie.scripting.objects.VehicleScript;
import zombie.vehicles.BaseVehicle;

/**
 * Starts the vehicle-texture load at the main menu instead of inside the world-load barrier.
 * -Dfastloading.vehtex=off.
 *
 * Fed in slices, not all at once. A decoded texture holds a direct buffer until the render
 * thread uploads it, and that drains on a 10 ms per frame budget, so loading every script in
 * one call pushes the live set past the gate budget: every asset worker parks, and whatever
 * the player opens next waits behind it. Slicing keeps the live set low enough that the pool
 * never stalls. Total work and wall time are unchanged -- both are bounded by the upload rate
 * either way -- and any script not reached here is loaded by the engine's own world-load call,
 * so the floor is stock behaviour.
 */
public final class VehicleTextureWarm {

    public static final String TAG = "[FastLoading/vehtex]";

    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.vehtex", "on"));

    /**
     * Vehicle scripts fed per slice, and the minimum gap between slices.
     *
     * PACE BY TIME, NOT BY TICK. The first version fed per front-end tick, and the menu runs at
     * the frame cap -- 165 ticks a second -- so eight per tick is 1,320 scripts a second and all
     * 725 were queued inside the first second. It spread nothing while looking like it did; the
     * queue histogram showed the full 3,044 textures already pending at the first sample.
     */
    /**
     * 8 could not finish in a realistic menu: 725 scripts at 8 per 100 ms is 80/s, needing >=9.1 s
     * of GREEN time, and green time is far scarcer than wall time (a completing run logs
     * `725 scripts in 82 ms over 813 backoffs`). 32 finishes in ~2.3 s. Still paced rather than
     * unpaced, but the real protection is the bulk band, not the rate.
     */
    public static final int SLICE = Integer.getInteger("fastloading.vehtexslice", 32);
    public static final long INTERVAL_MS = Long.getLong("fastloading.vehtexinterval", 100L);

    /**
     * 0 = no absolute gate. Shipped at 96 in 1.5.0 and killed the feature on any large mod list,
     * where the backlog runs `pending avg 5148`: the gate never opened and nothing logged that it
     * had not. Belt-and-braces anyway -- the warm marks its window DemandPriority.bulk, so its
     * textures queue below the engine's own band and cannot delay the player. Positive values
     * restore an absolute gate.
     */
    public static final int QUIET_PENDING = Integer.getInteger("fastloading.vehtexquiet", 0);

    /** Leave the opening moment of menu time alone -- what the pending gate really meant. */
    public static final long WARM_DELAY_MS = Long.getLong("fastloading.vehtexdelay", 1500L);

    public static long firstTickAt;
    public static boolean standdownLogged;

    public static long lastSliceAt;

    /**
     * Stand down above this percentage of the buffer budget. Was BUDGET/4, which never opened
     * either: 512 MB of a 2048 MB budget is below where live bytes sit for the whole menu. The
     * guard exists to avoid reaching the budget, where AssetThrottle sleeps workers -- and that
     * is the budget itself, not a quarter of it.
     */
    public static final int HIGH_WATER_PCT = Integer.getInteger("fastloading.vehtexhigh", 75);
    public static final long HIGH_WATER = AssetThrottle.BUDGET / 100L * HIGH_WATER_PCT;

    public static boolean done;
    public static int scripts;
    public static int warmed;
    public static int waits;
    public static long elapsedMs;

    private VehicleTextureWarm() {}

    /**
     * Called from the main menu by FastLoading_VehicleWarm.lua, on the main thread, once per
     * tick until it answers "done". Returns a short status the status panel can show.
     */
    @LuaMethod(name = "FastLoading_WarmVehicleTextures", global = true)
    public static String warm() {
        if (!ON) {
            return "off";
        }
        if (done) {
            return "done";
        }
        try {
            ScriptManager sm = ScriptManager.instance;
            ArrayList<VehicleScript> all = sm == null ? null : sm.getAllVehicleScripts();
            if (all == null || all.isEmpty()) {
                done = true;
                DebugLog.log(TAG + " no vehicle scripts; nothing to warm");
                return "done";
            }
            scripts = all.size();

            // Back off while decoded-but-not-yet-uploaded buffers are already piling up. Uses
            // the gate's cached reading; the underlying call takes a global monitor.
            long now = System.currentTimeMillis();
            if (now - lastSliceAt < INTERVAL_MS) {
                return "pacing";
            }
            if (firstTickAt == 0L) {
                firstTickAt = now;
            }
            int pending = AssetThrottle.pendingCount();
            boolean backpressure = AssetThrottle.liveBytes() > HIGH_WATER;
            boolean demand = DemandPriority.demandPending();
            boolean early = now - firstTickAt < WARM_DELAY_MS;
            boolean tooDeep = QUIET_PENDING > 0 && pending >= 0 && pending > QUIET_PENDING;
            if (backpressure || demand || early || tooDeep) {
                // Stand down on real backpressure, on a live demand request, and for the opening
                // moment of menu time. NOT on raw queue depth by default -- see QUIET_PENDING.
                waits++;
                // Say so, once. A silent stand-down is how this shipped dead in 1.5.0.
                if (!standdownLogged && waits > 50) {
                    standdownLogged = true;
                    DebugLog.log(TAG + " still standing down after " + waits + " ticks"
                                 + " (pending=" + pending + ", backpressure=" + backpressure
                                 + ", demand=" + demand + ", quiet=" + QUIET_PENDING + ")");
                }
                return "waiting";
            }
            lastSliceAt = now;

            long t0 = System.nanoTime();
            int end = Math.min(warmed + SLICE, scripts);
            // Must be the main thread: getSharedTexture mutates s_sharedTextureTable, a plain
            // HashMap the render and game threads also read.
            // Mark the window so DemandPriority queues these below the default band: this is
            // bulk work nobody is waiting for, and it must never delay what the player opened.
            DemandPriority.bulk = true;
            try {
                while (warmed < end) {
                    BaseVehicle.LoadVehicleTextures(all.get(warmed));
                    warmed++;
                }
            } finally {
                DemandPriority.bulk = false;
            }
            elapsedMs += (System.nanoTime() - t0) / 1000000L;

            if (warmed >= scripts) {
                done = true;
                DebugLog.log(TAG + " queued textures for " + scripts + " vehicle scripts in "
                             + elapsedMs + " ms over " + waits
                             + " backoffs; the world-load call will now be cache hits");
                return "done";
            }
            return warmed + "/" + scripts;
        } catch (Throwable t) {
            // Never fatal: without this the engine loads them at world load exactly as before.
            done = true;
            DebugLog.log(TAG + " skipped (" + t + ")");
            return "done";
        }
    }
}
