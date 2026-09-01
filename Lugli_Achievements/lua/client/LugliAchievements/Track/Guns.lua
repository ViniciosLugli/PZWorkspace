require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Firearm tracking"

-- There is no OnShoot event. OnWeaponSwingHitPoint fires for every attack immediately before
-- the engine branches into the firearm path, so filtering on isRanged() is what vanilla does.

-- A molotov is a thrown fire, not a charge. Counting it in both made every molotov run award
-- the explosives achievement as a side effect.
local MOLOTOV = "Base.Molotov"

-- Bookkeeping this tracker keeps for itself: gun_fired is read by the combat tracker to decide
-- whether a kill still counts as a quiet one. No achievement watches it.
local INTERNAL_STATS = {
    "gun_fired",
}

local function onSwing(owner, weapon)
    if M.playerIndex(owner) == nil or weapon == nil then return end
    if weapon.isRanged == nil or not weapon:isRanged() then return end

    M.incStat(owner, "shots_fired", 1)
    -- A latch rather than a check at unlock time: the achievement is about the whole run, and a
    -- counter cannot be un-fired.
    if M.getStat(owner, "gun_fired") == 0 then M.setStat(owner, "gun_fired", 1) end

    if weapon.getFullType ~= nil then
        M.addUnique(owner, "firearms_fired", weapon:getFullType())
    end
end

local function onReload(player)
    if M.playerIndex(player) ~= nil then M.incStat(player, "reloads", 1) end
end

local function onRack(player)
    if M.playerIndex(player) ~= nil then M.incStat(player, "racks", 1) end
end

--- The event carries the trap, not the thrower, so it is credited to the local players. The
--- trap is an IsoTrap and carries no type of its own; getItem() hands back what was thrown.
local function onExplode(trap)
    local full = nil
    if trap ~= nil and trap.getItem ~= nil then
        local ok, item = pcall(function() return trap:getItem() end)
        if ok and item ~= nil then
            local okT, t = pcall(function() return item:getFullType() end)
            if okT then full = t end
        end
    end
    local molotov = (full == MOLOTOV)
    M.forEachLocalPlayer(function(player)
        if molotov then
            M.incStat(player, "molotovs_thrown", 1)
        else
            M.incStat(player, "explosions", 1)
        end
    end)
end

--- A house alarm going off. There is no alarm event, so this reads the music-intensity channel
--- the engine pushes AlarmNearby onto. Keyed by player index, or in split screen one survivor's
--- alarm would suppress the other's.
local seenAlarm = {}
local function onEveryTenMinutes()
    M.forEachLocalPlayer(function(player, idx)
        if player.getMusicIntensityEvents == nil then return end
        local ok, ev = pcall(function()
            return player:getMusicIntensityEvents():findEventById("AlarmNearby")
        end)
        if not ok then return end
        if ev ~= nil and not seenAlarm[idx] then
            seenAlarm[idx] = true
            M.incStat(player, "alarms_survived", 1)
        elseif ev == nil then
            seenAlarm[idx] = false
        end
    end)
end

M.addHandler(PART, "OnWeaponSwingHitPoint", onSwing)
M.addHandler(PART, "OnPressReloadButton", onReload)
M.addHandler(PART, "OnPressRackButton", onRack)
M.addHandler(PART, "OnThrowableExplode", onExplode)
M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.status(PART, true)
