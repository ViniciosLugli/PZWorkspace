require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Item tracking"

-- The inventory walk is on the ten-minute tick and nowhere else. The dedup counter is O(1) per
-- insert, where the obvious version is quadratic on a big bag.

-- Every sledgehammer in 42.20. Finding one is the achievement; which of the three does not
-- matter.
local SLEDGEHAMMERS = {
    ["Base.Sledgehammer"] = true,
    ["Base.Sledgehammer2"] = true,
    ["Base.SledgehammerForged"] = true,
}

-- Matched by exact type because B42 has no toy tag or category: nothing in the data marks these.
local TOYS = {
    ["Base.BorisBadger"] = true, ["Base.EyeOfCthulhu"] = true, ["Base.FluffyfootBunny"] = true,
    ["Base.FreddyFox"] = true, ["Base.FurbertSquirrel"] = true, ["Base.JacquesBeaver"] = true,
    ["Base.MoleyMole"] = true, ["Base.PancakeHedgehog"] = true, ["Base.PanchoDog"] = true,
    ["Base.Plushabug"] = true, ["Base.Spiffo"] = true, ["Base.SpiffoBig"] = true,
    ["Base.TrashGoblin"] = true, ["Base.ToyBear"] = true,
    ["Base.ToyBear_Crafted_Cotton"] = true, ["Base.ToyBear_Crafted_Burlap"] = true,
    ["Base.Bricktoys"] = true, ["Base.Crayons"] = true, ["Base.Cube"] = true,
    ["Base.Doll"] = true, ["Base.Rubberducky"] = true, ["Base.RubberSpider"] = true,
    ["Base.ToyBadge"] = true, ["Base.ToyCar"] = true, ["Base.ToyPlane"] = true,
    ["Base.Yoyo"] = true,
}

local lastCount = {}
local wasOverburdened = {}

local function handWeight(item)
    if item == nil then return 0 end
    local ok, w = pcall(function() return item:getActualWeight() end)
    return (ok and type(w) == "number") and w or 0
end

local function onEveryTenMinutes()
    M.forEachLocalPlayer(function(player, idx)
        local inv = player:getInventory()
        if inv == nil then return end

        -- Counted on the CROSSING, not on every tick spent over the line: the counter is how
        -- many times a survivor overloaded themselves, not how long they stayed that way.
        local okW, carried = pcall(function() return inv:getCapacityWeight() end)
        local okC, capacity = pcall(function() return inv:getEffectiveCapacity(player) end)
        local over = okW and okC and type(carried) == "number" and type(capacity) == "number"
            and carried > capacity
        if over and not wasOverburdened[idx] then
            M.incStat(player, "overburdened", 1)
        end
        wasOverburdened[idx] = over

        -- Forty kilos in both hands at once.
        if handWeight(player:getPrimaryHandItem()) + handWeight(player:getSecondaryHandItem()) >= 40 then
            M.setStat(player, "macho", 1)
        end

        local items = inv:getItems()
        if items == nil then return end
        local n = items:size()

        -- A delta, not the size, so putting things down does not subtract from a lifetime total.
        local prev = lastCount[idx]
        if prev ~= nil and n > prev then M.incStat(player, "items_acquired", n - prev) end
        lastCount[idx] = n

        for i = 0, n - 1 do
            local item = items:get(i)
            if item ~= nil then
                local okT, full = pcall(function() return item:getFullType() end)
                if okT and type(full) == "string" then
                    M.addUnique(player, "item_types", full)
                    if TOYS[full] then M.addUnique(player, "toys_found", full) end
                    if full == "Base.Spiffo" then M.setStat(player, "saw_spiffo", 1) end
                    if full == "Base.SpiffoBig" then M.setStat(player, "saw_bigspiffo", 1) end
                    if SLEDGEHAMMERS[full] then M.setStat(player, "saw_sledgehammer", 1) end
                end
            end
        end
    end)
end

--- OnContainerUpdate names no container: the engine fires it bare from a dozen places and,
--- where it passes anything, it passes the item that changed rather than what holds it. So this
--- reads the one container within reach, the player's own inventory.
local function onContainerUpdate()
    M.forEachLocalPlayer(function(player)
        local inv = player:getInventory()
        if inv == nil then return end
        local ok, w = pcall(function() return inv:getContentsWeight() end)
        if ok and type(w) == "number" then
            M.setStatIfGreater(player, "heaviest_container", math.floor(w))
        end
    end)
end

local function onItemFound(player)
    if player == nil then return end
    M.incStat(player, "items_foraged", 1)
end

M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.addHandler(PART, "OnContainerUpdate", onContainerUpdate)
M.addHandler(PART, "OnItemFound", onItemFound)
M.status(PART, true)
