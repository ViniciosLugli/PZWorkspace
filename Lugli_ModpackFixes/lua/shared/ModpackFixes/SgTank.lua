--[[
Super Gore against the Special Zombies Tank.

What happens today. Both mods hold back the damage of a weapon hit and settle it on the next tick.
The Tank adds a buffer to its health and remembers it; Super Gore then adds 1000 on top and
remembers the buffered value. The Tank settles first (Special Zombies loads before Super Gore,
and both settle on OnTick): it sees its health above what it buffered, takes that as no damage
and puts its health back. Super Gore then reads 1000 plus the buffer as the damage dealt. A hit
that cuts nothing kills the Tank outright; a hit that cuts a limb leaves it with the buffer as
extra health. Either way the Tank's scaling, health pool and rage phase are skipped.

What this part changes. Super Gore leaves Tanks alone: no gore and no held damage on a Tank, so
the Tank takes every hit the way its own mod scales it. Every other zombie is Super Gore's as before.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local function isTank(target)
    return instanceof(target, "IsoZombie") and target:getModData().SZType == "Tank"
end

local function install(ctx)
    if type(SuperGore) ~= "table" or type(SuperGore.onWeaponHit) ~= "function" then
        error("SuperGore.onWeaponHit is missing")
    end
    ctx.wrap(SuperGore, "onWeaponHit", function(callOriginal)
        return function(attacker, target, weapon, damage)
            if isTank(target) then return end
            return callOriginal(attacker, target, weapon, damage)
        end
    end)
end

M.addPart({
    name = "sg-tank",
    switch = "SgTank",
    title = "Super Gore: the Tank takes hits by its own rules",
    tip = "Super Gore and the Special Zombies Tank both hold back a hit's damage, and together a Tank dies to almost any weapon hit, or gains health when a limb is cut. This leaves Tanks to their own mod, without Super Gore's gore. Other zombies are unchanged. Only active with both mods.",
    kind = "compat",
    all = { "Super_Gore_by_mrdocs", "SpecialZombiesTankB42" },
    side = "server",
    phase = "world",
    pins = { "sg.gate", "sg.weaponhit", "sg.hitreg", "szt.settle", "szt.buffer" },
    install = install,
})
