--[[
    Aim
]]

require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Aim"

--- World point the player is aiming at, clamped to maxRange tiles. Returns x, y, z or nil.
function M.aimPoint(player, maxRange)
    if player == nil then return nil end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local wx, wy = nil, nil

    if screenToIsoX ~= nil and getMouseX ~= nil then
        local ok, ax, ay = pcall(function()
            local n = player:getPlayerNum()
            return screenToIsoX(n, getMouseX(), getMouseY(), pz),
                   screenToIsoY(n, getMouseX(), getMouseY(), pz)
        end)
        if ok and type(ax) == "number" and type(ay) == "number" then
            wx, wy = ax, ay
        end
    end

    -- Joypad: AimingReticle switches to an array Lua cannot read, so the facing direction stands
    -- in. Deterministic rather than approximate.
    if wx == nil then
        local ok, fx, fy = pcall(function()
            return player:getForwardDirection():getX(), player:getForwardDirection():getY()
        end)
        if not ok or type(fx) ~= "number" then return nil end
        wx, wy = px + fx * maxRange, py + fy * maxRange
    end

    local dx, dy = wx - px, wy - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then return px, py, pz end
    if d > maxRange then
        wx = px + dx / d * maxRange
        wy = py + dy / d * maxRange
    end
    return wx, wy, pz
end

--- Can a thrown light land here AND be picked up again afterwards?
local function landable(sq, player)
    if sq == nil then return false end
    local ok, good = pcall(function()
        if not sq:TreatAsSolidFloor() then return false end
        if sq:isSolid() or sq:isSolidTrans() then return false end
        local cur = player:getCurrentSquare()
        if cur ~= nil and sq ~= cur and sq:isWallTo(cur) then return false end
        if AdjacentFreeTileFinder == nil then return true end
        return AdjacentFreeTileFinder.Find(sq, player) ~= nil
    end)
    return ok and good == true
end

M.landable = landable

--- WHERE A ROUND FIRED INTO THE SKY COMES DOWN.
local SKY_SEARCH_RINGS = 3

function M.skySquare(player, maxRange)
    local wx, wy, wz = M.aimPoint(player, maxRange)
    if wx == nil or getCell == nil then return nil end

    local cell = getCell()
    local z = math.floor(wz)
    local ax, ay = math.floor(wx), math.floor(wy)

    local function at(x, y)
        local sq = nil
        local ok = pcall(function() sq = cell:getGridSquare(x, y, z) end)
        if not ok or sq == nil then return nil end
        if not landable(sq, player) then return nil end
        return sq
    end

    local hit = at(ax, ay)
    if hit ~= nil then return hit end

    -- Nearest-first, by ring. Within a ring the order does not matter: every square in it is the
    -- same Chebyshev distance from the aim point, and picking by true distance would be a sort for
    -- a difference of at most half a tile.
    for ring = 1, SKY_SEARCH_RINGS do
        for dx = -ring, ring do
            for dy = -ring, ring do
                -- The ring itself, not the filled square: the interior was covered by the previous
                -- pass and re-testing it would make this O(n^2) in the radius for nothing.
                if dx == -ring or dx == ring or dy == -ring or dy == ring then
                    hit = at(ax + dx, ay + dy)
                    if hit ~= nil then return hit end
                end
            end
        end
    end

    return M.squareAlong(player, wx, wy, wz)
end

--- THE SQUARE AT A WORLD POINT, ignoring everything between here and there. nil if it will not take
--- an item.
function M.directSquare(player, wx, wy, wz)
    if wx == nil or getCell == nil then return nil end
    local ok, sq = pcall(function()
        return getCell():getGridSquare(math.floor(wx), math.floor(wy), math.floor(wz))
    end)
    if not ok or sq == nil then return nil end
    if not landable(sq, player) then return nil end
    return sq
end

--- The square the player is pointing at, clamped to range, ignoring what stands in between.
function M.aimSquareDirect(player, maxRange)
    local wx, wy, wz = M.aimPoint(player, maxRange)
    if wx == nil then return nil end

    local sq = M.directSquare(player, wx, wy, wz)
    if sq ~= nil then return sq end
    return M.squareAlong(player, wx, wy, wz)
end

--- Walk from the player toward a world point, and return the last square that will TAKE an item.
function M.squareAlong(player, wx, wy, wz)
    if player == nil or wx == nil or getCell == nil then return nil end
    local px, py = player:getX(), player:getY()
    local cell = getCell()
    local z = math.floor(wz)

    -- ONE TILE AT A TIME, not a fixed number of lerp samples. Six samples over a long throw skip
    -- whole squares, so the ray could step straight over a wall and land the stick on the far
    -- side of it, which is exactly the case the pickup path refuses.
    local dx, dy = wx - px, wy - py
    local dist = math.sqrt(dx * dx + dy * dy)
    -- CEIL, NOT ROUND, and the honest version of why.
    local steps = math.ceil(dist)
    if steps < 1 then steps = 1 end

    local prev = player:getCurrentSquare()
    local best = nil
    for i = 1, steps do
        local t = i / steps
        local sq = cell:getGridSquare(math.floor(px + dx * t), math.floor(py + dy * t), z)
        if sq == nil then break end
        -- Stop AT the first thing the throw cannot pass, rather than walking back from the far
        -- end: a stick stopped by a wall should land in front of it, not beyond it.
        if prev ~= nil and sq ~= prev then
            -- prev -> sq, the direction of travel.
            local blocked = false
            local ok, v = pcall(function() return prev:isBlockedTo(sq) end)
            if ok then blocked = v == true end
            if blocked then break end
        end
        if landable(sq, player) then best = sq end
        prev = sq
    end

    if best ~= nil then return best end

    -- NOTHING ALONG THE RAY WILL TAKE IT.
    return player:getCurrentSquare()
end

M.status(PART, true)
