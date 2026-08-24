-- Starts the vehicle-texture load while the player is on the main menu.
--
-- GameLoadingState:291 calls BaseVehicle.LoadAllVehicleTextures(), which loads every skin of
-- every vehicle script in the whole mod list, and the world-load barrier thirty lines later
-- waits for all of it. Doing the same work here means Texture.getSharedTexture has already
-- cached each one, so the world-load call queues nothing.
--
-- Java side: lugli.fastloading.VehicleTextureWarm, which feeds a few scripts per tick and backs
-- off while decoded textures are waiting on the render thread. Queueing them all in one call
-- parks every asset worker on the buffer budget, which is what made mod thumbnails and the
-- options screen slow to appear. Disabled by -Dfastloading.vehtex=off.
--
-- WHY LUA AND NOT A JAVA PATCH: the first version advised MainScreenState.update and never
-- installed -- ZombieBuddy patched four other classes that run and simply never touched that
-- one. Menu Lua always runs and needs no patch slot.

local DELAY_TICKS = 30      -- let the menu finish building; this call is main-thread work

local ticks = 0
local finished = false
local tick                  -- forward declaration: stop() below refers to it

local function stop()
    finished = true
    Events.OnFETick.Remove(tick)
end

tick = function()
    if finished then return end
    ticks = ticks + 1
    if ticks < DELAY_TICKS then return end

    -- Absent without ZombieBuddy, which is a supported configuration: the Lua half of this mod
    -- works alone and the game loads the textures where it always did.
    if type(FastLoading_WarmVehicleTextures) ~= "function" then
        stop()
        return
    end

    local ok, res = pcall(FastLoading_WarmVehicleTextures)
    if not ok then
        print("[FastLoading/vehtex] call failed: " .. tostring(res))
        stop()
    elseif res == "done" or res == "off" then
        stop()
    end
end

-- OnFETick is the front-end tick (MainScreenState.java:671). OnTickEvenPaused comes from
-- IngameState, which does not exist at the menu, so it would never fire here.
Events.OnFETick.Add(tick)
