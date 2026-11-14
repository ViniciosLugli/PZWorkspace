--[[
Dynamic Backpack Upgrades: an upgraded bag keeps its capacity on the server too.

What happens today. The engine never saves a bag's capacity. InventoryContainer.save writes the
weight reduction and the contents but not the capacity, and every load (a server start, a player
joining, a chunk streaming in) builds the bag from its script first, so it comes back at the
script capacity (InventoryContainer.java:55-77, InventoryItem.java:1898-1903,
Item.java:1519-1521 on 42.22.2). Dynamic Backpack Upgrades records the upgraded value in the
bag's mod data and puts it back with DBU.RestoreBagStats, but only from client Lua (tooltip,
context menu, a per-minute inventory check) and from its Collect Bag action. A dedicated server
never runs client Lua, so after a restart or a rejoin the server's copy of every upgraded bag is
at its script capacity, and the server refuses every transfer past it
(TransactionManager.java:251-258) while the client shows the upgraded number. That is the
"shows 35, stops at 28" report, and why dropping the bag and using Collect Bag, which restores on
the server, is the known workaround.

What this part changes. Once per in-game minute, the side that owns the world puts every upgraded
bag a player carries, bags inside bags included, back to the capacity the mod recorded, through
the mod's own DBU.RestoreBagStats. A bag the engine will not take that value for is tried once,
so the part adds no repeated capacity warnings to the log.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- Item id -> the recorded capacity the engine did not keep, so that bag is not asked again.
local refused = {}

local function restoreIn(container)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= nil and item:IsInventoryContainer() then
            if item:hasModData() then
                local recorded = item:getModData().LComputedCapacity
                if type(recorded) == "number" and refused[item:getID()] ~= recorded then
                    DBU.RestoreBagStats(item)
                    if item:getCapacity() ~= recorded then refused[item:getID()] = recorded end
                end
            end
            restoreIn(item:getInventory())
        end
    end
end

-- getOnlinePlayers() is empty in single player and getNumActivePlayers() is 0 on a server.
local function eachPlayer(fn)
    if M.isDedicatedServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local player = list:get(i)
            if player ~= nil then fn(player) end
        end
        return
    end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then fn(player) end
    end
end

local function install(ctx)
    if type(DBU) ~= "table" or type(DBU.RestoreBagStats) ~= "function" then
        error("DBU.RestoreBagStats is missing")
    end
    ctx.on("EveryOneMinute", function()
        eachPlayer(function(player) restoreIn(player:getInventory()) end)
    end)
end

M.addPart({
    name = "dbu-restore",
    switch = "DbuRestore",
    title = "Dynamic Backpack Upgrades: upgraded capacity holds on the server",
    tip = "The game does not save a bag's capacity, so after a server restart or a rejoin the server treats every upgraded bag as a plain one and refuses items past its old capacity, while the bag still shows the upgraded number. This puts the upgraded capacity back on the server every in-game minute. Only active with Dynamic Backpack Upgrades.",
    kind = "fix",
    all = { "LazoloDynamicBackpackUpgrades" },
    side = "server",
    phase = "world",
    pins = { "dbu.restore" },
    install = install,
})
