--[[
Dynamic Backpack Upgrades: a bag upgraded past the engine's bag limit stops asking for more.

What happens today. A bag's capacity reads back at most 50, and at most 50 less the bag's own
weight, however high it is set (ItemContainer.java:162-172, InventoryContainer.java:80-87 on
42.22.2). Dynamic Backpack Upgrades decides a bag needs fixing by comparing that read with its own
computed value (DBU.GetUpgradedStats). A bag upgraded past the limit never matches, so Fix
Upgrades is always offered for it, and once the player picks Always the mod's per-minute check
calls DBU.UpdateBag on that bag every in-game minute for the rest of the game. Each call logs
"Attempting to set capacity of ... over maximum capacity" (InventoryContainer.java:89-100,
ItemContainer.java:175-184): every 2.5 seconds per bag at the default day length.

What this part changes. When DBU.UpdateBag asks for more than the engine keeps, the part records
what was asked, and DBU.GetUpgradedStats then reports the value the engine kept for as long as the
bag's upgrades ask for that same amount. Below the limit nothing changes, and a new upgrade or a
sandbox change asks the engine again, once.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local ASKED = "LMpfixAskedCapacity"

local function install(ctx)
    if type(DBU) ~= "table" or type(DBU.GetUpgradedStats) ~= "function" or type(DBU.UpdateBag) ~= "function" then
        error("DBU.GetUpgradedStats or DBU.UpdateBag is missing")
    end
    local computed = DBU.GetUpgradedStats
    ctx.wrap(DBU, "GetUpgradedStats", function(callOriginal)
        return function(bag, ...)
            local capacity, reduction = callOriginal(bag, ...)
            local imd = bag:getModData()
            local kept = imd.LComputedCapacity
            if imd[ASKED] == capacity and type(kept) == "number" and kept < capacity then
                return kept, reduction
            end
            return capacity, reduction
        end
    end)
    ctx.wrap(DBU, "UpdateBag", function(callOriginal)
        return function(bag, ...)
            local asked = computed(bag)
            callOriginal(bag, ...)
            local imd = bag:getModData()
            local kept = imd.LComputedCapacity
            if type(asked) == "number" and type(kept) == "number" and kept < asked then
                imd[ASKED] = asked
            else
                imd[ASKED] = nil
            end
        end
    end)
end

M.addPart({
    name = "dbu-ceiling",
    switch = "DbuCeiling",
    title = "Dynamic Backpack Upgrades: no endless fixing past the bag limit",
    tip = "A bag can hold at most 50, however many upgrades it has. Past that limit the mod always offers Fix Upgrades for the bag, and with Fix Always it retries every in-game minute, filling the log with capacity warnings. The bag now counts as fixed at the most the game allows. Only active with Dynamic Backpack Upgrades.",
    kind = "fix",
    all = { "LazoloDynamicBackpackUpgrades" },
    side = "both",
    phase = "boot",
    pins = { "dbu.stats", "dbu.update", "dbu.invcheck" },
    install = install,
})
