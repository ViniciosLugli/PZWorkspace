require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Death tracking"

-- OnPlayerDeath carries no cause, so the cause is LATCHED as it happens and read back at death.
-- A latch with no time limit would credit a fire death to someone singed an hour earlier.

-- Reached through CAUSE_STAT, so the gate cannot see these as literals.
local DECLARED_STATS = {
    "died_bleeding",
    "died_crash",
    "died_fall",
    "died_fire",
    "died_hunger",
    "died_infection",
    "died_poison",
    "died_thirst",
}

-- Bookkeeping this tracker keeps for itself: a saved stat rather than a table, because the
-- drink and the death are usually hours and sometimes a whole save apart.
local INTERNAL_STATS = {
    "drank_bleach",
}

-- Damage type -> the achievement it can explain. The engine passes these as plain strings.
local CAUSE_STAT = {
    FIRE           = "died_fire",
    FALLDOWN       = "died_fall",
    THIRST         = "died_thirst",
    HUNGRY         = "died_hunger",
    POISON         = "died_poison",
    INFECTION      = "died_infection",
    BLEEDING       = "died_bleeding",
    CARCRASHDAMAGE = "died_crash",
    CARHITDAMAGE   = "died_crash",
}

-- How recent a hit has to be to count as the cause of death, in in-game hours.
local CAUSE_WINDOW_HOURS = 0.5

local lastCause, lastCauseAt = {}, {}

local function onDamage(character, damageType)
    if type(damageType) ~= "string" then return end
    local i = M.playerIndex(character)
    if i == nil then return end
    lastCause[i] = damageType
    lastCauseAt[i] = M.worldHours()
end

--- IsInfected() reads the real infection field; IsFakeInfected() is the separate one, so a
--- hypochondriac does not qualify. Asked directly rather than off the cause latch, which only
--- knows about infection once it is doing damage: a survivor bitten an hour ago and then pulled
--- down by the horde turns without ever taking a point of INFECTION damage.
local function isKnoxInfected(player, idx)
    local ok, infected = pcall(function()
        return player:getBodyDamage():IsInfected()
    end)
    if ok and type(infected) == "boolean" then return infected end
    return idx ~= nil and lastCause[idx] == "INFECTION"
end

-- Bleach is a FLUID, not a Food, so the only action that pours it into a survivor is
-- ISDrinkFluidAction. Its type is read TWICE because either read alone is blind half the time:
-- at start the container still holds the bleach but the survivor may yet cancel, and at perform
-- the drink definitely happened but "drink all" leaves the container empty, where
-- getPrimaryFluid() returns null. So start records the answer and perform writes the latch.
local BLEACH_FLAG = "_lugliAchBleach"

local function isBleach(action)
    if action == nil or action.fluidContainer == nil then return false end
    if FluidType == nil or FluidType.Bleach == nil then return false end
    local ok, bleach = pcall(function()
        local fluid = action.fluidContainer:getPrimaryFluid()
        if fluid == nil then return false end
        return fluid:getFluidType() == FluidType.Bleach
    end)
    return ok and bleach == true
end

local function onDrinkStart(action)
    if isBleach(action) then action[BLEACH_FLAG] = true end
end

local function onDrinkDone(action)
    if action == nil or action.character == nil then return end
    if action[BLEACH_FLAG] ~= true and not isBleach(action) then return end
    M.setStat(action.character, "drank_bleach", 1)
end

local function onDeath(player)
    if player == nil then return end
    M.incStat(player, "deaths", 1)

    local hours = 0
    local okH, h = pcall(function() return player:getHoursSurvived() end)
    if okH and type(h) == "number" then hours = h end

    if hours < 24 then M.setStat(player, "died_day_one", 1) end
    if hours >= 8760 then M.setStat(player, "died_veteran", 1) end

    -- Where.
    local okSq, square = pcall(function() return player:getCurrentSquare() end)
    if okSq and square ~= nil then
        local okR, room = pcall(function() return square:getRoom() end)
        if okR and room ~= nil then
            local okN, name = pcall(function() return room:getName() end)
            if okN and name == "bathroom" then M.setStat(player, "died_bathroom", 1) end
        end
        local okReg, region = pcall(function() return square:getSquareRegion() end)
        if okReg and region == "General" then M.setStat(player, "died_wilderness", 1) end
    end

    -- Why, from the latch, and only if it was recent enough to be the cause.
    local idx = M.playerIndex(player)
    if idx ~= nil and lastCause[idx] ~= nil then
        if (M.worldHours() - (lastCauseAt[idx] or 0)) <= CAUSE_WINDOW_HOURS then
            local stat = CAUSE_STAT[lastCause[idx]]
            if stat ~= nil then M.setStat(player, stat, 1) end
        end
    end

    -- shouldBecomeZombieAfterDeath() alone is not the question it looks like: under Transmission
    -- 3, "everyone infected", it answers true for every death there is, which would hand this to
    -- a survivor who starved in a bunker.
    local okZ, willTurn = pcall(function() return player:shouldBecomeZombieAfterDeath() end)
    if okZ and willTurn == true and isKnoxInfected(player, idx) then
        M.setStat(player, "died_zombified", 1)
    end

    -- No time window on bleach: the drink is the cause of death however long it took, which is
    -- the whole reason it is not on the cause latch.
    if M.getStat(player, "drank_bleach") > 0 then
        M.setStat(player, "died_bleach", 1)
    end

    -- Hypothermia is a moodle at maximum rather than a damage type.
    local okM, cold = pcall(function()
        return player:getMoodles():getMoodleLevel(MoodleType.HYPOTHERMIA)
    end)
    if okM and type(cold) == "number" and cold >= 4 then M.setStat(player, "died_cold", 1) end

    -- There is no animal damage type, so this is the honest approximation: an animal is nearby
    -- and the last damage was a weapon hit.
    if idx ~= nil and lastCause[idx] == "WEAPONHIT" and player.getCell ~= nil then
        local okA, near = pcall(function()
            local list = player:getCell():getObjectList()
            if list == nil then return false end
            for i = 0, list:size() - 1 do
                local o = list:get(i)
                if o ~= nil and instanceof ~= nil and instanceof(o, "IsoAnimal") then
                    if math.abs(o:getX() - player:getX()) < 3
                        and math.abs(o:getY() - player:getY()) < 3 then return true end
                end
            end
            return false
        end)
        if okA and near then M.setStat(player, "died_animal", 1) end
    end
end

M.addHandler(PART, "OnPlayerGetDamage", onDamage)
M.addHandler(PART, "OnPlayerDeath", onDeath)

-- Wrapped at OnGameStart so the copy chained is whatever is current after every mod has had its
-- turn at the class. Two methods on one class, and the gear tracker counts perform on it too:
-- onAction is built to let all three ride one wrapper per method.
local h = M.addHandler(PART, "OnGameStart", function()
    local started = M.onAction(PART, "ISDrinkFluidAction", onDrinkStart, "start")
    local done = M.onAction(PART, "ISDrinkFluidAction", onDrinkDone)
    if started and done then
        M.status(PART, true)
    end
end)

if h ~= nil then M.status(PART, nil, "checked when you load a world", "pending") end
