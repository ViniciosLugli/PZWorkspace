--[[
Better Pause with SwapIt: hotbar keys work while the game is paused.

What happens today. Better Pause lets you act while paused, and for the hotbar it replaces
ISHotbar:isAllowedToActivateSlot with vanilla's checks minus the pause check. SwapIt defines the
same function again, as vanilla's own copy with the pause check, and loads after it, so with both
mods a hotbar key does nothing while paused.

What this part changes. While the game is paused, a hotbar key is allowed under vanilla's other
checks (not dead, not attacking, no radial menu open, no action queued), as Better Pause intends.
Unpaused, SwapIt's function answers as before.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local SWAPIT_FILE = "SwapIt Main.lua"

local function fromSwapIt(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, SWAPIT_FILE, 1, true) ~= nil
end

local function allowedIgnoringPause(hotbar)
    local player = hotbar.character
    if player:isDead() or player:isAttacking() then return false end
    if getPlayerRadialMenu(hotbar.playerNum):isReallyVisible() then return false end
    local queue = ISTimedActionQueue.queues[player]
    return queue == nil or #queue.queue == 0
end

local function install(ctx)
    if type(ISHotbar) ~= "table" or not fromSwapIt(ISHotbar.isAllowedToActivateSlot) then
        error("ISHotbar.isAllowedToActivateSlot is not SwapIt's")
    end
    ctx.wrap(ISHotbar, "isAllowedToActivateSlot", function(callOriginal)
        return function(self)
            if not isGamePaused() then return callOriginal(self) end
            return allowedIgnoringPause(self)
        end
    end)
end

M.addPart({
    name = "bp-hotbar",
    switch = "BpHotbar",
    title = "Better Pause: hotbar keys while paused, with SwapIt",
    tip = "Better Pause lets the hotbar keys work while the game is paused, but SwapIt puts vanilla's pause check back. This lets them work while paused again. Only active with Better Pause and SwapIt.",
    kind = "compat",
    all = { "SwapIt", "twistbetterpause" },
    side = "client",
    phase = "boot",
    pins = { "swapit.allowed", "bp.allowed" },
    install = install,
})
