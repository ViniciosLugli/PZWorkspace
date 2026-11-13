require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Item tracking"

-- The inventory walk is on the ten-minute tick and nowhere else. The dedup counter is O(1) per
-- insert, where the obvious version is quadratic on a big bag.

-- Every sledgehammer in 42.22 (SledgehammerHead is a crafting part, not one). Finding one is the
-- achievement; which of the three does not matter.
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

--- Forty kilos in both hands at once. Boot.lua asks the same question at load.
function M.checkMacho(player)
    if handWeight(player:getPrimaryHandItem()) + handWeight(player:getSecondaryHandItem()) >= 40 then
        M.setStat(player, "macho", 1)
    end
end

--- What one carried item type earns. Boot.lua walks the bag with this at load.
function M.creditItemType(player, full)
    M.addUnique(player, "item_types", full)
    if TOYS[full] then M.addUnique(player, "toys_found", full) end
    if full == "Base.Spiffo" then M.setStat(player, "saw_spiffo", 1) end
    if full == "Base.SpiffoBig" then M.setStat(player, "saw_bigspiffo", 1) end
    if SLEDGEHAMMERS[full] then M.setStat(player, "saw_sledgehammer", 1) end
end

local function onEveryTenMinutes()
    M.forEachLocalPlayer(function(player, idx)
        local inv = player:getInventory()
        if inv == nil then return end

        -- Counted on the CROSSING, not on every tick spent over the line: the counter is how
        -- many times a survivor overloaded themselves, not how long they stayed that way. The
        -- first look at a survivor only sets the baseline, so loading a world while overloaded
        -- is not a crossing.
        local okW, carried = pcall(function() return inv:getCapacityWeight() end)
        local okC, capacity = pcall(function() return inv:getEffectiveCapacity(player) end)
        local over = okW and okC and type(carried) == "number" and type(capacity) == "number"
            and carried > capacity
        if over and wasOverburdened[idx] == false then
            M.incStat(player, "overburdened", 1)
        end
        wasOverburdened[idx] = over

        M.checkMacho(player)

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
                if okT and type(full) == "string" then M.creditItemType(player, full) end
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

local function creditForage(player)
    if player ~= nil then M.incStat(player, "items_foraged", 1) end
end

--- OnItemFound is raised on the SERVER in multiplayer (sendIconFound becomes a packet), so a
--- client never sees it. spotIcon is where both paths start, and the test is vanilla's own: an
--- icon with an item behind it, spotted for the first time. It is computed before the call,
--- which is what marks the icon. Returns false when the method is gone.
local function hookForaging()
    local cls = rawget(_G, "ISSearchManager")
    if type(cls) ~= "table" or type(cls.spotIcon) ~= "function" then return false end
    if rawget(cls, "_lugliAch_spotIcon") then return true end
    cls._lugliAch_spotIcon = true
    local original = cls.spotIcon
    local live = true
    cls.spotIcon = function(self, icon, ...)
        local fresh = live and type(icon) == "table" and icon.itemDef ~= nil
            and type(self.xpIcons) == "table" and self.xpIcons[icon.iconID] == nil
        local result = original(self, icon, ...)
        if fresh then
            local ok, err = pcall(creditForage, self.character)
            if not ok then
                live = false
                M.defect(PART, "ISSearchManager.spotIcon callback removed after: " .. tostring(err))
            end
        end
        return result
    end
    return true
end

--- A survivor entering the world, a respawn on the same index included, is looked at afresh.
local function onCreatePlayer(playerIndex)
    if playerIndex ~= nil then wasOverburdened[playerIndex] = nil end
end

M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.addHandler(PART, "OnCreatePlayer", onCreatePlayer)
M.addHandler(PART, "OnContainerUpdate", onContainerUpdate)
if hookForaging() then
    M.status(PART, true)
else
    M.status(PART, false, "ISSearchManager.spotIcon is not on this build", "dep")
end
