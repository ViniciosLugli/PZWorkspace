--[[
Super Gore: a zombie it finishes off counts as the player's kill.

What happens today. Super Gore holds back the damage of a melee or gun hit and settles it on the
next tick (SuperGore.hitCut): a severed neck, a burst head or chest, or the held damage on a
zombie lying down kills the zombie with Kill(). The engine credits a kill only when a hit itself
kills (IsoGameCharacter.hitConsequences); Kill() credits nothing. So every zombie Super Gore
finishes is missing from the player's zombie kill count, and from anything that reads it
(the character screen, Kill Count's total, the death screen).

What this part changes. When that settling kills a zombie that was alive before it, and the
player's count did not move, the count goes up by one. On a server the client is told the same
way the engine tells it (IsoObjectChange.ADD_ZOMBIE_KILL). Deaths Super Gore causes later, by
bleeding out, stay uncounted, as fire deaths are uncounted in vanilla.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local function install(ctx)
    if type(SuperGore) ~= "table" or type(SuperGore.hitCut) ~= "function" then
        error("SuperGore.hitCut is missing")
    end
    if M.isDedicatedServer() and (type(IsoObjectChange) ~= "table" or IsoObjectChange.ADD_ZOMBIE_KILL == nil) then
        error("IsoObjectChange.ADD_ZOMBIE_KILL is missing")
    end
    ctx.wrap(SuperGore, "hitCut", function(callOriginal)
        return function(zombie, ax, ay, gun, sharp, attacker, roll)
            if zombie == nil or not instanceof(attacker, "IsoPlayer") or zombie:isDead() then
                return callOriginal(zombie, ax, ay, gun, sharp, attacker, roll)
            end
            local before = attacker:getZombieKills()
            -- Its only caller, Super Gore's tick queue, runs it under pcall and drops the error.
            if not pcall(callOriginal, zombie, ax, ay, gun, sharp, attacker, roll) then return end
            if not zombie:isDead() or attacker:getZombieKills() ~= before then return end
            attacker:setZombieKills(before + 1)
            if M.isDedicatedServer() then attacker:sendObjectChange(IsoObjectChange.ADD_ZOMBIE_KILL) end
        end
    end)
end

M.addPart({
    name = "sg-kills",
    switch = "SgKills",
    title = "Super Gore: zombies it finishes count as kills",
    tip = "Super Gore settles a hit a moment later, and a zombie it kills that way (a severed head, a burst chest) is not added to your zombie kill count. This adds it, in single player and multiplayer. Only active with Super Gore.",
    kind = "fix",
    all = { "Super_Gore_by_mrdocs" },
    side = "server",
    phase = "world",
    pins = { "sg.gate", "sg.hitcut", "sg.queue" },
    install = install,
})
