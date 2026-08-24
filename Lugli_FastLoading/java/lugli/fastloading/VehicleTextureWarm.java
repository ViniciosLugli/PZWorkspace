package lugli.fastloading;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.debug.DebugLog;
import zombie.scripting.ScriptManager;
import zombie.vehicles.BaseVehicle;

/**
 * Starts the vehicle-texture load at the main menu instead of inside the world-load barrier.
 * -Dfastloading.vehtex=off.
 *
 * The engine loads every vehicle script's textures during world load. Queued at the menu they
 * are normally finished before the player starts a game, so the barrier has nothing left to
 * wait for. Unlike a tile-pack warm the volume is small enough to complete in a short dwell.
 */
public final class VehicleTextureWarm {

    public static final String TAG = "[FastLoading/vehtex]";

    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.vehtex", "on"));

    public static boolean done;
    public static int scripts;
    public static long elapsedMs;

    private VehicleTextureWarm() {}

    /**
     * Called from the main menu by FastLoading_VehicleWarm.lua, on the main thread.
     * Returns a short status the status panel can show. Runs at most once per session.
     */
    @LuaMethod(name = "FastLoading_WarmVehicleTextures", global = true)
    public static String warm() {
        if (!ON) {
            return "off";
        }
        if (done) {
            return "already done";
        }
        done = true;
        try {
            // Must be the main thread: getSharedTexture mutates s_sharedTextureTable, a plain
            // HashMap the render and game threads also read.
            ScriptManager sm = ScriptManager.instance;
            if (sm == null || sm.getAllVehicleScripts() == null
                    || sm.getAllVehicleScripts().isEmpty()) {
                DebugLog.log(TAG + " no vehicle scripts; nothing to warm");
                return "no vehicle scripts";
            }
            scripts = sm.getAllVehicleScripts().size();
            long t0 = System.nanoTime();
            BaseVehicle.LoadAllVehicleTextures();
            elapsedMs = (System.nanoTime() - t0) / 1000000L;
            DebugLog.log(TAG + " queued textures for " + scripts + " vehicle scripts in "
                    + elapsedMs + " ms; the world-load call will now be cache hits");
            return scripts + " scripts in " + elapsedMs + " ms";
        } catch (Throwable t) {
            // Never fatal: without this the engine loads them at world load exactly as before.
            DebugLog.log(TAG + " skipped (" + t + ")");
            return "failed: " + t;
        }
    }
}
