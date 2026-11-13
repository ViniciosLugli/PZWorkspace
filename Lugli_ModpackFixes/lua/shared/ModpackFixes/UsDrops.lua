--[[
Undead Survivor: in multiplayer its outfit zombies drop their loot once, from the server.

What happens today. Its drop table is server Lua, which a multiplayer client loads too
(GameLoadingState), and it rolls on OnZombieDead, which fires on the client as well. The engine
fills a dead zombie's inventory only off the client (IsoZombie.onKilled), but this handler adds
its items wherever it runs. So every client gives the corpse its own random extra items the
server never had: they show in the corpse and cannot be taken, until the corpse is moved and the
server's inventory replaces them.

What this part changes. On a multiplayer client that handler is not registered, so a corpse
shows exactly what the server rolled. Single player, a host and a dedicated server keep it.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local US_FILE = "UndeadSurvivor_OnDeathDistribution.lua"
local dropped = nil

local function fromUndeadSurvivor(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, US_FILE, 1, true) ~= nil
end

local function install(ctx)
    ctx.wrap(Events.OnZombieDead, "Add", function(add)
        return function(fn)
            if dropped ~= nil or not M.isMultiplayerClient() or not fromUndeadSurvivor(fn) then return add(fn) end
            dropped = fn
        end
    end)
    ctx.undo(function()
        if dropped == nil then return end
        Events.OnZombieDead.Add(dropped)
        dropped = nil
    end)
end

M.addPart({
    name = "us-drops",
    switch = "UsDrops",
    title = "Undead Survivor: corpse loot in multiplayer is the server's only",
    tip = "In multiplayer, Undead Survivor's outfit zombies get extra random loot on every client, which shows in the corpse but cannot be taken until the corpse is moved. This leaves the loot to the server, so a corpse shows what can really be looted. Only active with Undead Survivor.",
    kind = "fix",
    all = { "UndeadSuvivor" },
    side = "client",
    phase = "boot",
    pins = { "us.drops" },
    install = install,
})
