--[[
    Time
]]

require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Time"

--- In-game hours since the world began. nil before a world exists, which is the normal state in the
--- main menu and on a bare test VM.
local seen = nil

--- Forget it. The next world starts its own clock, and carrying a high-water mark across would
--- freeze every burn time in a new game at the old world's age.
function M.resetWorldClock()
    seen = nil
end

function M.worldHours()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gt = pcall(getGameTime)
    if not ok or gt == nil then return nil end
    local ok2, h = pcall(function() return gt:getWorldAgeHours() end)
    if not ok2 or type(h) ~= "number" then return nil end

    -- MONOTONIC BY CONSTRUCTION, because the engine's own value is not -- on a client.
    if seen == nil or h > seen then
        seen = h
    end
    return seen
end

local KEY_EXPIRES = "lugliELExpires"
local KEY_BURN    = "lugliELBurn"
local KEY_ID      = "lugliELId"

M.KEY_EXPIRES = KEY_EXPIRES
M.KEY_BURN    = KEY_BURN
M.KEY_ID      = KEY_ID

--- Stamp an item as burning for burnHours from now.
function M.markCracked(item, burnHours, uniqueId)
    if item == nil or type(burnHours) ~= "number" then return false end
    local md = item:getModData()
    if type(md[KEY_EXPIRES]) == "number" then return false end
    local now = M.worldHours()
    if now == nil then return false end
    md[KEY_BURN] = burnHours
    md[KEY_EXPIRES] = now + burnHours
    if uniqueId ~= nil then md[KEY_ID] = uniqueId end
    return true
end

--- Hours left, or nil when the item was never cracked.
function M.hoursLeft(item)
    if item == nil then return nil end
    local md = item:getModData()
    local expires = md[KEY_EXPIRES]
    if type(expires) ~= "number" then return nil end
    local now = M.worldHours()
    if now == nil then return nil end
    return expires - now
end

--- Fraction of life remaining, 0 to 1. nil when not cracked or the burn time is unknown.
--- Called per lit item per frame, so the ModData is fetched once rather than through hoursLeft.
function M.fractionLeft(item)
    if item == nil then return nil end
    local md = item:getModData()
    local expires = md[KEY_EXPIRES]
    if type(expires) ~= "number" then return nil end
    local now = M.worldHours()
    if now == nil then return nil end
    local left = expires - now
    local burn = md[KEY_BURN]
    if type(burn) ~= "number" or burn <= 0 then return nil end
    if left <= 0 then return 0 end
    if left >= burn then return 1 end
    return left / burn
end

function M.isCracked(item)
    if item == nil then return false end
    return type(item:getModData()[KEY_EXPIRES]) == "number"
end

function M.isExpired(item)
    local left = M.hoursLeft(item)
    return left ~= nil and left <= 0
end

M.status(PART, true)
