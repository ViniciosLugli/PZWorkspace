package lugli.fastloading;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.debug.DebugLog;
import zombie.scripting.ScriptManager;
import zombie.vehicles.BaseVehicle;

/**
 * Starts the vehicle-texture load at the main menu instead of inside the world-load barrier.
 * -Dfastloading.vehtex=off
 *
 * `GameLoadingState.java:291` calls `BaseVehicle.LoadAllVehicleTextures()`, which walks EVERY
 * VehicleScript in the merged mod list and loads up to nine textures per skin
 * (`BaseVehicle.java:564-570, 584-607`). It is unconditional: it does not care which vehicles
 * the save actually contains. On a 337-mod list that is ~5,800 PNGs and 948 MB on disk.
 *
 * Those queue at priority 7, and thirty lines later the loader parks on
 * `bWaitForAssetLoadingToFinish2`, which waits for `FileSystemImpl.hasWork()` to go false --
 * i.e. for EVERY queue to empty. Measured here at **38.7 s of a 90 s world load**. The only
 * thing the barrier actually needs is `Bullet.initPhysicsMeshes()` (`GameLoadingState:366`),
 * whose `FileTask_LoadPhysicsShape` tasks are priority 6 and therefore served AFTER all of it.
 *
 * `Texture.getSharedTexture` caches into `s_sharedTextureTable`, so calling the same method
 * earlier means the world-load call finds every entry present and queues nothing. Same
 * textures, same flags, same priority, same code path -- only the start time moves.
 *
 * WHAT THIS IS
 *   A hiding fix, not a deleting fix, and it should be read that way. The decode and upload
 *   still happen; they happen while the player is reading the main menu instead of while the
 *   loading screen is up. A player who clicks Continue two seconds after the menu appears gets
 *   most of the wait back. That is the same trade `MeshPriority` already makes at boot, and
 *   world-load A/B showed that one costs nothing (docs/09-world-load.md).
 *
 * WHY NOT SIMPLY NARROW THE BARRIER
 *   Waiting only on the physics shapes was considered and rejected. `Texture.bind`
 *   (`Texture.java:678-688`) substitutes the red/white error texture whenever `!isReady()`, and
 *   a freshly generated world has parked cars in the first chunks, drawn immediately. That
 *   converts an invisible wait into a visible defect.
 *
 * WHY THE MENU AND NOT EARLIER
 *   It needs `ScriptManager` populated, which happens in `initShared`. Running it during boot
 *   would put the same 948 MB in front of the main menu instead, which is the phase this mod
 *   spent the most effort clearing.
 *
 * WHY LUA CALLS THIS INSTEAD OF A @Patch
 *   The first version advised `MainScreenState.update`. It never installed: ZombieBuddy patched
 *   FileSystemImpl, DebugFileWatcher, TextureIDAssetManager and ScriptParser in the same run and
 *   simply never touched MainScreenState, and with no unconditional counter in the advice the
 *   A/B came back as a clean "no difference" from a patch that had never run. Menu-time Lua is
 *   guaranteed to execute, needs no patch slot, and cannot collide with another advice.
 *
 * COST TO WATCH
 *   ~1.4 GB of VRAM is held from menu time rather than from world-load time. That memory is
 *   already paid today, only later. Menu-time CPU contention is the thing to A/B; the switch
 *   exists so it can be.
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
