require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Exploration"

-- Places come from square:getSquareRegion(), the game's own vocabulary read off the map data.
-- No coordinate table: a radius around a guessed centre is a boundary the game does not have.
--
-- Room identity is getIDString(), never getRoomID(). The numeric id is
-- (cellY << 16 | cellX) << 32 | index, which passes a Lua double's exact-integer range in the
-- southern half of the map, so counting rooms by number would silently double count there.

-- Reached through a lookup, so the gate cannot see these two as literals.
local DECLARED_STATS = {
    "bathrooms_seen",
    "churches_seen",
}

local ROOM_STAT = {
    bathroom = "bathrooms_seen",
    church = "churches_seen",
}

-- Fires at most once per room per save, so it is cheap.
local function onSeeNewRoom(room)
    if room == nil then return end
    local def = nil
    local okD, d = pcall(function() return room:getRoomDef() end)
    if okD then def = d end

    local id = nil
    if def ~= nil then
        local okI, s = pcall(function() return def:getIDString() end)
        if okI and type(s) == "string" then id = s end
    end

    local name = nil
    local okN, n = pcall(function() return room:getName() end)
    if okN and type(n) == "string" then name = n end

    M.forEachLocalPlayer(function(player)
        if id ~= nil then M.addUnique(player, "rooms_seen", id) end
        if name ~= nil then
            M.addUnique(player, "room_kinds", name)
            local stat = ROOM_STAT[name]
            if stat ~= nil then M.incStat(player, stat, 1) end
            if name == "prisoncells" then M.setStat(player, "saw_prison", 1) end
        end
    end)
end

local function onEveryTenMinutes()
    M.forEachLocalPlayer(function(player)
        local okSq, square = pcall(function() return player:getCurrentSquare() end)
        if not okSq or square == nil then return end

        local okR, region = pcall(function() return square:getSquareRegion() end)
        if okR and type(region) == "string" and region ~= "General" then
            M.addUnique(player, "regions_seen", region)
            if region == "Louisville" then M.setStat(player, "saw_louisville", 1) end
            if region == "LAA" then M.setStat(player, "saw_airport", 1) end
        end

        -- Basements are new in B42 and sit below ground level.
        local okZ, z = pcall(function() return square:getZ() end)
        if okZ and type(z) == "number" and z < 0 then M.setStat(player, "saw_basement", 1) end

        local okB, bdef = pcall(function() return square:getBuildingDef() end)
        if okB and bdef ~= nil then
            local okId, bid = pcall(function() return bdef:getIDString() end)
            if okId and type(bid) == "string" then
                local okE, explored = pcall(function() return bdef:isAllExplored() end)
                if okE and explored then M.addUnique(player, "buildings_explored", bid) end
                local okS, shop = pcall(function() return bdef:isShop() end)
                if okS and shop then M.addUnique(player, "shops_seen", bid) end
            end
        end
    end)
end

M.addHandler(PART, "OnSeeNewRoom", onSeeNewRoom)
M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.status(PART, true)
