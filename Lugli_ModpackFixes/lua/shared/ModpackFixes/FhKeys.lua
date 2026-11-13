--[[
Fancy Handwork (B42.19 build, 2.5.1): the swap-hands keys work again and stop throwing.

What happens today. Its key handler walks a list of binds whose first entry is a section header
with no key name, and asks the engine for the key of that entry: core:getKey(nil). On 42.22.2
that call throws, so the handler dies on the first entry for every key press. Measured in a
real session log (2026-11-10): 668 exceptions in 26 s of play, and swap-hands never fires.

What this part changes. The handler and its bind list are locals, so they cannot be repaired.
When Fancy Handwork registers that handler (at OnGameStart) this part registers its own in its
place, which reads the same three key binds and queues the same swap action. If this part is
switched off or fails, Fancy Handwork's own handler is registered, exactly as without this mod.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local FH_FILE = "aFancyHandwork.lua"
local dropped = nil
local swapAction = nil

local function fromFancyHandwork(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, FH_FILE, 1, true) ~= nil
end

local function boundKey(core, name)
    local key = core:getKey(name)
    if type(key) ~= "number" or key <= 0 then return nil end
    return key
end

local function swapOnKey(key)
    local player = getSpecificPlayer(0)
    if player == nil then return end
    local core = getCore()
    local wanted = key == boundKey(core, "FHSwapKey")
    if not wanted and key == boundKey(core, "FHSwapKeyMod") then
        local modifier = boundKey(core, "FHModifier")
        wanted = modifier ~= nil and isKeyDown(modifier)
    end
    if not wanted or isGamePaused() or player:isDead() then return end
    local primary, secondary = player:getPrimaryHandItem(), player:getSecondaryHandItem()
    if (primary ~= nil or secondary ~= nil) and primary ~= secondary then
        ISTimedActionQueue.add(swapAction:new(player, primary, secondary, 10))
    end
end

local function install(ctx)
    local onKey = ctx.guard(swapOnKey)
    ctx.wrap(Events.OnKeyPressed, "Add", function(add)
        return function(fn)
            if dropped ~= nil or not fromFancyHandwork(fn) then return add(fn) end
            if FHSwapHandsAction ~= nil then swapAction = FHSwapHandsAction end
            if type(swapAction) ~= "table" or type(swapAction.new) ~= "function" then
                error("FHSwapHandsAction is missing")
            end
            dropped = fn
            return add(onKey)
        end
    end)
    ctx.undo(function()
        if dropped == nil then return end
        Events.OnKeyPressed.Remove(onKey)
        Events.OnKeyPressed.Add(dropped)
        dropped = nil
    end)
end

M.addPart({
    name = "fh-keys",
    switch = "FhKeys",
    title = "Fancy Handwork: swap-hands keys work and stop throwing errors",
    tip = "On 42.22 the Fancy Handwork B42.19 build throws an error on every key press and its swap-hands keys do nothing. This replaces its key handler with a working one. Only active with that build of Fancy Handwork.",
    kind = "fix",
    all = { "FancyHandworkB42_19" },
    side = "client",
    phase = "boot",
    pins = { "fh.swap", "fh.binds", "fh.handler", "fh.register" },
    install = install,
})
