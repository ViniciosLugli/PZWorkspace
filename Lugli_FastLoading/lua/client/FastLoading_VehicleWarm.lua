-- Starts the vehicle-texture load while the player is on the main menu.
--
-- GameLoadingState:291 calls BaseVehicle.LoadAllVehicleTextures(), which loads every skin of
-- every vehicle script in the whole mod list -- ~5,800 PNGs on a 300+ mod list -- and the
-- world-load barrier thirty lines later waits for all of it. Doing the same call here means
-- Texture.getSharedTexture has already cached each one, so the world-load call queues nothing.
--
-- Java side: lugli.fastloading.VehicleTextureWarm. It runs at most once per session and is
-- disabled by -Dfastloading.vehtex=off.
--
-- WHY LUA AND NOT A JAVA PATCH: the first version advised MainScreenState.update and never
-- installed -- ZombieBuddy patched four other classes that run and simply never touched that
-- one. Menu Lua always runs and needs no patch slot.

local DELAY_TICKS = 30      -- let the menu finish building; this call is main-thread work

local ticks = 0
local fired = false

local function tick()
    if fired then return end
    ticks = ticks + 1
    if ticks < DELAY_TICKS then return end
    fired = true
    Events.OnFETick.Remove(tick)

    -- Absent without ZombieBuddy, which is a supported configuration: the Lua half of this mod
    -- works alone and the game simply loads the textures where it always did.
    -- End the boot-only asset priority raise. MeshPriority promotes animation meshes above
    -- textures, which is worth ~12 s at boot (initAnimationMeshes blocks on 79 of them) and
    -- about -24 s at every world load, where nothing blocks that way.
    if type(FastLoading_EndBootPhase) == "function" then
        local okB, resB = pcall(FastLoading_EndBootPhase)
        if okB then print("[FastLoading/meshprio] " .. tostring(resB)) end
    end

    if type(FastLoading_WarmVehicleTextures) == "function" then
        local ok, res = pcall(FastLoading_WarmVehicleTextures)
        if not ok then
            print("[FastLoading/vehtex] call failed: " .. tostring(res))
        end
    end

    -- World tile-pack pages, same idea one level up: GameWindow only MOUNTS those packs, and the
    -- page PNGs are not decoded until LoadTileDefinitions asks for them in the middle of a world
    -- load. Off unless -Dfastloading.packwarm=on.
    if type(FastLoading_WarmPackPages) == "function" then
        local okP, resP = pcall(FastLoading_WarmPackPages)
        if okP then
            if resP ~= "off" then print("[FastLoading/packwarm] " .. tostring(resP)) end
        else
            print("[FastLoading/packwarm] call failed: " .. tostring(resP))
        end
    end
end

-- OnFETick is the front-end tick (MainScreenState.java:671). OnTickEvenPaused comes from
-- IngameState, which does not exist at the menu, so it would never fire here.
Events.OnFETick.Add(tick)
