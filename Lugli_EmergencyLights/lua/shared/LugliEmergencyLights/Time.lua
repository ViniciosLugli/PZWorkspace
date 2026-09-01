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

--- Game seconds to REAL seconds, for the engine machinery that runs on a wall clock.
---
--- Every duration a player sets in this mod is in-game time, like the burn hours above. Some of
--- what consumes it is not: WorldFlares.launchFlare accumulates GameTime.getMultiplier at about 48
--- per REAL second, and getTimestampMs is a wall clock. Converting at the boundary keeps one clock
--- in the options and one in the engine.
---
--- getMinutesPerDay is REAL minutes per game day, so a game day of 86400 s takes that many real
--- minutes: real = game * minutesPerDay / 1440. Falls back to 1:1 rather than to zero, because a
--- flare that never burns is worse than one whose length is off.
function M.realSeconds(gameSeconds)
    if type(gameSeconds) ~= "number" then return 0.0 end
    if type(getGameTime) ~= "function" then return gameSeconds end
    local ok, mpd = pcall(function() return getGameTime():getMinutesPerDay() end)
    if not ok or type(mpd) ~= "number" or mpd <= 0 then return gameSeconds end
    return gameSeconds * mpd / 1440.0
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
function M.fractionLeft(item)
    local left = M.hoursLeft(item)
    if left == nil then return nil end
    local burn = item:getModData()[KEY_BURN]
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
