require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Survival time"

-- getHoursSurvived() is the CHARACTER's clock, not the world's, so it stays correct for a second
-- survivor in the same save. Counters use setStatIfGreater so a reload reporting a slightly
-- lower figure cannot walk them backwards.

-- MoodleType has no values(), so the set is hardcoded. Polled on the ten-minute tick and never
-- per frame: a read is 24 Java calls, and getMoodleLevel(nil) does Map.get(null) and throws
-- inside the engine, so a mistyped name is an error box per moodle rather than a wrong number.
local BAD_MOODLES = {
    "ENDURANCE", "TIRED", "HUNGRY", "PANIC", "SICK", "BORED", "UNHAPPY", "BLEEDING", "WET",
    "HAS_A_COLD", "ANGRY", "STRESS", "THIRST", "INJURED", "PAIN", "HEAVY_LOAD", "DRUNK",
    "HYPERTHERMIA", "HYPOTHERMIA", "WINDCHILL", "CANT_SPRINT", "UNCOMFORTABLE",
    "NOXIOUS_SMELL", "FOOD_EATEN",
}

-- ErosionSeason numbers five seasons for four: SUMMER2 is the back half of summer rather than a
-- season of its own, so it folds into SUMMER and "all four seasons" is reachable.
local SEASON_SUMMER = 2
local SEASON_SUMMER2 = 3
local SEASON_WINTER = 5

local hurtToday = {}

-- Bookkeeping this tracker keeps for itself: the running streak behind clean_days_best.
local INTERNAL_STATS = {
    "clean_streak",
}

local function onEveryHours()
    M.forEachLocalPlayer(function(player)
        local hours = player:getHoursSurvived()
        if type(hours) ~= "number" then return end
        M.setStatIfGreater(player, "days_survived", math.floor(hours / 24))

        -- The character clock minus the hour they woke on, which is the pair vanilla subtracts
        -- itself. getLastHourSleeped() moves only on waking, and is 0 for a survivor who has
        -- never slept, which correctly reads as awake since they spawned.
        local okA, awake = pcall(function()
            return player:getHoursSurvived() - player:getLastHourSleeped()
        end)
        if okA and type(awake) == "number" and awake > 0 then
            M.setStatIfGreater(player, "awake_hours_best", math.floor(awake))
        end
    end)
end

local function onEveryDays()
    M.forEachLocalPlayer(function(player, idx)
        -- A clean day is one where nothing damaged us. Best-of, so breaking the streak does not
        -- take the record with it.
        if hurtToday[idx] then
            hurtToday[idx] = false
            M.setStat(player, "clean_streak", 0)
        else
            local streak = M.getStat(player, "clean_streak") + 1
            M.setStat(player, "clean_streak", streak)
            M.setStatIfGreater(player, "clean_days_best", streak)
        end

        if M.getStat(player, "kills_total") < 10 then
            M.incStat(player, "pacifist_days", 1)
        end

        if getSandboxOptions ~= nil then
            -- A negative electricity modifier is what the instant setting resolves to: the grid
            -- was never on, so there is no day the survivor went off it and the counter would
            -- otherwise run from day zero. The engine guards its own comparison the same way.
            local ok, offGrid = pcall(function()
                local so = getSandboxOptions()
                if so:getElecShutModifier() < 0 then return false end
                return so:doesPowerGridExist() == false
            end)
            if ok and offGrid then M.incStat(player, "off_grid_days", 1) end
            -- There is no water equivalent of doesPowerGridExist, so the engine's own test is
            -- replicated: world age in days plus the apocalypse offset against the modifier.
            local okw, dry = pcall(function()
                local so = getSandboxOptions()
                local shut = so:getWaterShutModifier()
                if shut < 0 then return false end
                local days = getGameTime():getWorldAgeHours() / 24
                    + (so:getTimeSinceApo() - 1) * 30
                return days >= shut
            end)
            if okw and dry then M.incStat(player, "no_water_days", 1) end
        end

        if getClimateManager ~= nil then
            local ok, sid = pcall(function() return getClimateManager():getSeasonId() end)
            if ok and type(sid) == "number" and sid > 0 then
                if sid == SEASON_SUMMER2 then sid = SEASON_SUMMER end
                M.addUnique(player, "seasons_seen", sid)
                if sid == SEASON_WINTER then M.setStat(player, "saw_winter", 1) end
            end
        end

        -- The helicopter is scheduled, not evented. Matching the engine's own condition is the
        -- only pure-Lua way to know the day it flies.
        if getGameTime ~= nil then
            local ok, flying = pcall(function()
                local gt = getGameTime()
                return gt:getNightsSurvived() > gt:getHelicopterDay1()
            end)
            if ok and flying then M.setStat(player, "helicopter_survived", 1) end
        end
    end)
end

local function onEveryTenMinutes()
    M.forEachLocalPlayer(function(player)
        local moodles = player:getMoodles()
        if moodles == nil or MoodleType == nil then return end
        local bad, noxious = 0, 0
        for i = 1, #BAD_MOODLES do
            local mt = MoodleType[BAD_MOODLES[i]]
            if mt ~= nil then
                local ok, lvl = pcall(function() return moodles:getMoodleLevel(mt) end)
                if ok and type(lvl) == "number" and lvl > 0 then
                    bad = bad + 1
                    if BAD_MOODLES[i] == "NOXIOUS_SMELL" then noxious = 1 end
                end
            end
        end
        M.setStatIfGreater(player, "moodles_worst", bad)
        if noxious == 1 then M.setStat(player, "noxious", 1) end
    end)
end

local function onDamage(character)
    -- Fires for zombies too, so the player guard is not optional.
    local i = M.playerIndex(character)
    if i ~= nil then hurtToday[i] = true end
end

local function onWeatherDone(period)
    if period == nil then return end
    local blizzard, tropical = false, false
    pcall(function()
        blizzard = period:isBlizzard() == true
        tropical = period:isTropicalStorm() == true
    end)
    if not blizzard and not tropical then return end
    M.forEachLocalPlayer(function(player)
        if blizzard then
            M.incStat(player, "blizzards", 1)
            if player.isOutside ~= nil and player:isOutside() then
                M.setStat(player, "blizzard_outdoors", 1)
            end
        end
        if tropical then M.incStat(player, "storms", 1) end
    end)
end

--- OnThunderEvent takes five arguments, not one.
local function onThunder(x, y, doStrike)
    if doStrike ~= true then return end
    M.forEachLocalPlayer(function(player)
        if player.isOutside ~= nil and player:isOutside() then
            M.incStat(player, "thunder_heard", 1)
        end
    end)
end

M.addHandler(PART, "EveryHours", onEveryHours)
M.addHandler(PART, "EveryDays", onEveryDays)
M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.addHandler(PART, "OnPlayerGetDamage", onDamage)
M.addHandler(PART, "OnWeatherPeriodComplete", onWeatherDone)
M.addHandler(PART, "OnThunderEvent", onThunder)
M.status(PART, true)
