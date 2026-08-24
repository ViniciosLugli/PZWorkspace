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
    public static final int SLICE = Integer.getInteger("fastloading.vehtexslice", 8);
    public static final long INTERVAL_MS = Long.getLong("fastloading.vehtexinterval", 100L);

    /**
     * Do not start until the loader's own backlog has drained. Warming is background work with
     * no deadline, and the first seconds of menu time are exactly when the boot backlog is still
     * draining and the player is most likely to open something.
     */
    public static final int QUIET_PENDING = Integer.getInteger("fastloading.vehtexquiet", 96);

    public static long lastSliceAt;

    /**
     * Feed only while the live direct-buffer set is below this. A quarter of the gate budget
     * leaves the rest for whatever the player actually asked to see.
     */
    public static final long HIGH_WATER = AssetThrottle.BUDGET / 4L;

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
            int pending = AssetThrottle.pendingCount();
            if (AssetThrottle.liveBytes() > HIGH_WATER
                    || DemandPriority.demandPending()
                    || (pending >= 0 && pending > QUIET_PENDING)) {
                // Stand down while the loader is still busy, and right after the player asked
                // for something: this is bulk work competing for the same sixteen slots.
                waits++;
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
