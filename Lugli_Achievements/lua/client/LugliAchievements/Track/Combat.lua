require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Kill tracking"

-- OnZombieDead fires for EVERY zombie death in the world, which during a horde is effectively
-- per frame. Nothing on this path allocates, and everything expensive waits until the kill is
-- known to be ours.

-- Reached through CATEGORY_STAT, so the gate cannot see these as literals.
local DECLARED_STATS = {
    "kills_axe",
    "kills_blunt",
    "kills_improvised",
    "kills_longblade",
    "kills_smallblade",
    "kills_smallblunt",
    "kills_spear",
}

-- containsWeaponCategory takes the WeaponCategory object, so a string never matches and every
-- category kill went uncounted. The key is the ResourceLocation, which is what saves already hold
-- in weapon_classes_used. Firearms carry no category and are found with isRanged() instead.
local CATEGORIES = {
    { field = "AXE",         key = "base:axe",        stat = "kills_axe" },
    { field = "BLUNT",       key = "base:blunt",      stat = "kills_blunt" },
    { field = "SMALL_BLUNT", key = "base:smallblunt", stat = "kills_smallblunt" },
    { field = "LONG_BLADE",  key = "base:longblade",  stat = "kills_longblade" },
    { field = "SMALL_BLADE", key = "base:smallblade", stat = "kills_smallblade" },
    { field = "SPEAR",       key = "base:spear",      stat = "kills_spear" },
    { field = "UNARMED",     key = "base:unarmed",    stat = "kills_unarmed" },
    { field = "IMPROVISED",  key = "base:improvised", stat = "kills_improvised" },
}

--- Resolved on the first kill, not at load: the class is exposed by then on every build, and a
--- constant this build lacks drops out of the list instead of failing every kill.
local resolved
local function categories()
    if resolved ~= nil then return resolved end
    resolved = {}
    local missing = {}
    for _, c in ipairs(CATEGORIES) do
        local obj = WeaponCategory ~= nil and WeaponCategory[c.field] or nil
        if obj ~= nil then
            resolved[#resolved + 1] = { obj = obj, key = c.key, stat = c.stat }
        else
            missing[#missing + 1] = c.field
        end
    end
    if #missing > 0 then
        M.defect(PART, "WeaponCategory lacks " .. table.concat(missing, " ") .. " on this build")
    end
    return resolved
end

--- Kill() sets attackedBy BEFORE firing the event, so this names the killer. It stays nil for
--- fire and fall deaths, which keeps environmental kills out of the count for free.
local function localKiller(zombie)
    local killer = zombie:getAttackedBy()
    if killer == nil then return nil end
    return (M.playerIndex(killer) ~= nil) and killer or nil
end

local function weaponOf(player)
    local item = player:getPrimaryHandItem()
    if item == nil then return nil end
    if instanceof ~= nil and not instanceof(item, "HandWeapon") then return nil end
    return item
end

local function creditCategories(player, weapon)
    if weapon == nil then
        -- Empty hands still count: unarmed is a real weapon category with exactly one entry.
        M.incStat(player, "kills_unarmed", 1)
        M.addUnique(player, "weapon_classes_used", "base:unarmed")
        return
    end
    if weapon.isRanged ~= nil and weapon:isRanged() then
        M.incStat(player, "kills_firearm", 1)
        return
    end
    local script = weapon:getScriptItem()
    if script == nil or script.containsWeaponCategory == nil then return end
    local cats = categories()
    for i = 1, #cats do
        local c = cats[i]
        -- pcall with arguments, not a closure: a closure here is eight allocations per kill.
        local ok, has = pcall(script.containsWeaponCategory, script, c.obj)
        if ok and has then
            M.incStat(player, c.stat, 1)
            M.addUnique(player, "weapon_classes_used", c.key)
        end
    end
end

local function onZombieDead(zombie)
    if zombie == nil then return end
    local player = localKiller(zombie)
    if player == nil then return end

    M.incStat(player, "kills_total", 1)

    -- "Kills without ever firing a gun" is a mirror counter that the first shot latches off
    -- permanently, rather than a check performed at unlock time.
    local data = M.getCharData(player)
    if data ~= nil and data.stats["gun_fired"] == nil then
        M.incStat(player, "kills_quiet", 1)
    end

    creditCategories(player, weaponOf(player))

    if zombie.isProne ~= nil and zombie:isProne() then
        M.incStat(player, "kills_downed", 1)
    end
    -- getHitTime is melee only: a firearm kill leaves it at zero, so this never fires for one.
    if zombie.getHitTime ~= nil and zombie:getHitTime() == 1 then
        M.incStat(player, "kills_onehit", 1)
    end
    if zombie.getSpeedType ~= nil and zombie:getSpeedType() == 1 then
        M.incStat(player, "killed_sprinter", 1)
    end
    if zombie.wasFakeDead ~= nil and zombie:wasFakeDead() then
        M.incStat(player, "killed_fakedead", 1)
    end
    if player:getWornItems():size() == 0 then
        M.incStat(player, "kills_naked", 1)
    end
end

--- Hits, which are a different thing from kills: where they land and whether they crit.
local function onHitZombie(zombie, wielder, bodyPart)
    if M.playerIndex(wielder) == nil then return end

    if bodyPart ~= nil and BodyPartType ~= nil and bodyPart == BodyPartType.Head then
        M.incStat(wielder, "hits_head", 1)
    end
    if wielder.isCriticalHit ~= nil and wielder:isCriticalHit() then
        M.incStat(wielder, "hits_crit", 1)
    end
end

--- OnCharacterDeath covers animals as well as people, which is the only route to an animal
--- death there is. A player death is handled by the death tracker, so it is excluded here.
--- The event carries no killer, so credit goes to every local player; the detail tracker writes
--- the same normalised species from butchering, so the two routes cannot double-count.
local function onCharacterDeath(character)
    if character == nil then return end
    if instanceof ~= nil and instanceof(character, "IsoPlayer") then return end
    if instanceof ~= nil and not instanceof(character, "IsoAnimal") then return end
    local species = M.animalSpecies(character)
    if species == nil then return end
    M.forEachLocalPlayer(function(player)
        M.addUnique(player, "animal_species", species)
    end)
end

--- A day with no kills, once the survivor is past their first hundred. Counted daily so the
--- comparison is a subtraction rather than a running flag.
local lastDayKills = {}
local function onEveryDays()
    M.forEachStore(function(player, idx)
        local total = M.getStat(player, "kills_total")
        local prev = lastDayKills[idx]
        if prev ~= nil and total == prev and total >= 100 then
            M.incStat(player, "no_kill_days", 1)
        end
        lastDayKills[idx] = total
    end)
end

M.addHandler(PART, "OnZombieDead", onZombieDead)
M.addHandler(PART, "OnHitZombie", onHitZombie)
M.addHandler(PART, "OnCharacterDeath", onCharacterDeath)
M.addHandler(PART, "EveryDays", onEveryDays)
M.status(PART, true)
