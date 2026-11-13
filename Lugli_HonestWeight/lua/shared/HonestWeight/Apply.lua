--[[
Honest Weight: writes generated per-item weights into the script items.

What the engine does: Item.InstanceItem copies the script item's weight into every new
InventoryItem (Item.java:1838), and a save stores an item's weight only when it is a custom
weight (flag 128, InventoryItem.java:1744). A script weight set before the world loads
therefore reaches every non-custom item in an existing save on its next load, and removing
this mod reverts them the same way.

When: OnGameBoot runs after every script (re)load: SP menu, MP client after ResetLua, and the
dedicated server (GameServer.java:1539). It snapshots the pristine weights and writes the
default presets, so items are right even where SandboxVars are not real yet.
OnLoadedTileDefinitions (IsoWorld.java:2004) runs once the save's or the server's sandbox is
loaded, before any player (:2119) or cell (:2211), and rewrites every row with the presets.

Every write is absolute and computed from the snapshot, so nothing compounds. A row whose
pristine weight differs from the one the data was generated against is skipped as stale (the
mod changed it, or another mod wrote it first). A value changed by another mod after our boot
write is left alone as yielded. The data rows are generated; never edit them by hand.
]]
require "HonestWeight_Status"

local M = LugliHonestWeight

M.PART = "Weights"
-- Row: fullType, fingerprint, fixed, mass, volume, emptyFingerprint, emptyFixed, emptyMass, flags,
-- partModifier. partModifier >= 0 is the pristine WeightModifier of a weapon part: installed, a
-- part adds that to its gun instead of its weight (HandWeapon.getActualWeight), so it is written
-- as the part's own new weight. The script Item has no getter for it, and WeaponPart does not
-- save it (Item.java:1515 copies it into each new instance), so it is written blind.
M.STRIDE = 10
-- Flags are a sum: 1 melee (stamina follows weight), 2 an installed vehicle part, whose weight
-- is also its vehicle's physics mass in kilograms (BaseVehicle.java:9202), so Scale skips it.
M.FLAG_MELEE = 1
M.FLAG_PHYSICS = 2
M.data = M.data or {}
M.pristine = M.pristine or {}
M.pristineEmpty = M.pristineEmpty or {}
M.pristineMod = M.pristineMod or {}
M.written = M.written or {}
M.writtenEmpty = M.writtenEmpty or {}
M.writtenMod = M.writtenMod or {}
M.writtenPart = M.writtenPart or {}

-- Script weights are float32; data is decimal with at most 4 places.
local EPS = 0.0005
-- BulkFloor option 1..4: Off, Light, Normal, Strict, in kg per packed litre.
local BULK_K = { 0, 0.05, 0.10, 0.15 }
local BULK_NAME = { "off", "light", "normal", "strict" }
-- Scale: game weight units per real kilogram. Vanilla weighs everyday goods about 1.5x their
-- real mass for its carry capacity; 1.5 keeps the balance loadouts at 0.87 of vanilla.
local SCALE_MIN, SCALE_MAX = 1.0, 2.5
local DEFAULTS = { realism = 100, bulk = 3, scale = 1.5, vanillaStamina = false }
local INCOMPATIBLE = "TrueWeight"
local HASH_MOD = 2147483647

local function near(a, b)
    local d = a - b
    return d < EPS and d > -EPS
end

local function activeMods()
    local set = {}
    local list = getActivatedMods and getActivatedMods() or nil
    if list == nil then return set end
    for i = 0, list:size() - 1 do
        local id = tostring(list:get(i))
        if string.sub(id, 1, 1) == "\\" then id = string.sub(id, 2) end
        set[id] = true
    end
    return set
end

function M.presets()
    local p = { realism = DEFAULTS.realism, bulk = DEFAULTS.bulk, scale = DEFAULTS.scale,
        vanillaStamina = DEFAULTS.vanillaStamina }
    local sv = SandboxVars and SandboxVars.LugliHW
    if type(sv) == "table" then
        local r, b, s = tonumber(sv.Realism), tonumber(sv.BulkFloor), tonumber(sv.Scale)
        if r ~= nil and r >= 0 and r <= 100 then p.realism = r end
        if b ~= nil and BULK_K[b] ~= nil then p.bulk = b end
        if s ~= nil and s >= SCALE_MIN and s <= SCALE_MAX then p.scale = s end
        if type(sv.VanillaStamina) == "boolean" then p.vanillaStamina = sv.VanillaStamina end
    end
    return p
end

-- The player's main inventory and a floor square each hold 50 (ItemContainer.capacity,
-- ItemContainer.hasRoomFor): a heavier item could be neither picked up, uninstalled nor dropped.
-- Above CARRY_KNEE a weight eases toward CARRY_CEILING, so heavier stays heavier and every
-- item stays carryable.
local CARRY_KNEE, CARRY_CEILING = 25, 45
function M.carry(w)
    if w <= CARRY_KNEE then return w end
    local span = CARRY_CEILING - CARRY_KNEE
    return CARRY_KNEE + span * (1 - math.exp(-(w - CARRY_KNEE) / span))
end

-- honest = carry(scale * max(mass, volume * k)); final = fixed + realism * (honest - fixed)
function M.target(fixed, mass, vol, r, k, s)
    local honest = mass
    local floor = vol * k
    if floor > honest then honest = floor end
    return fixed + r * (M.carry(s * honest) - fixed)
end

local function newCounts()
    return { applied = 0, stale = 0, missing = 0, yielded = 0, clamped = 0, hash = 0, sources = 0, leftovers = 0 }
end

-- The generator puts every item in exactly one source, so their order cannot matter.
-- A data file from an older release that Steam left on disk carries another version: ignored.
local function activeSources(active, c)
    local list = {}
    for i = 1, #M.data do
        local s = M.data[i]
        if s.version ~= M.DATA_VERSION then
            c.leftovers = c.leftovers + 1
        elseif s.mod == nil or active[s.mod] then
            list[#list + 1] = s
        end
    end
    return list
end

local function mix(h, v)
    return (h * 31 + math.floor(v * 10000 + 0.5)) % HASH_MOD
end

-- Melee stamina per swing and per chop is weight x EnduranceMod (CombatManager.java:1314,
-- :3985, ISChopTreeAction.lua:100), and HandWeapon reads the script weight live. Real mass
-- therefore changes stamina; with VanillaStamina the mod is rescaled so the product stays.
local function applyStamina(item, ft, stage, w, vanillaStamina, c)
    local cur = item:getEnduranceMod()
    local mine = M.writtenMod[ft]
    if stage == "boot" then
        if mine ~= nil and near(cur, mine) then cur = M.pristineMod[ft] end
        M.pristineMod[ft] = cur
    elseif mine ~= nil and not near(cur, mine) and not near(cur, M.pristineMod[ft]) then
        M.writtenMod[ft] = nil
        return
    end
    local mod = M.pristineMod[ft]
    local p = M.pristine[ft]
    if vanillaStamina and w > 0 and p > 0 then mod = mod * p / w end
    item:setEnduranceMod(mod)
    mod = item:getEnduranceMod()
    M.writtenMod[ft] = mod
    c.hash = mix(c.hash, mod)
end

local function setPartModifier(item, v)
    item:DoParam("WeightModifier = " .. tostring(v))
end

-- Puts a part's pristine modifier back once its weight is no longer ours.
local function releasePart(item, ft)
    local pristine = M.writtenPart[ft]
    if pristine == nil then return end
    setPartModifier(item, pristine)
    M.writtenPart[ft] = nil
end

-- stage "boot": take the snapshot, check fingerprints, write.
-- stage "sandbox": rewrite what boot wrote, leaving anything another mod changed since.
local function applyRow(sm, rows, i, stage, r, k, s, vanillaStamina, c)
    local ft = rows[i]
    local item = sm:getItem(ft)
    if item == nil then
        c.missing = c.missing + 1
        return
    end
    local cur = item:getActualWeight()
    local hasEmpty = rows[i + 5] >= 0
    local curEmpty = hasEmpty and item:getWeightEmpty() or 0
    local mine = M.written[ft]
    if stage == "sandbox" then
        if mine == nil then return end
        if not near(cur, mine) and not near(cur, M.pristine[ft]) then
            M.written[ft] = nil
            releasePart(item, ft)
            c.yielded = c.yielded + 1
            return
        end
    else
        -- Our own earlier write stays recorded until it is overwritten, so revert() still
        -- finds it if this pass fails before reaching the row again.
        local ours = mine ~= nil and near(cur, mine)
        if ours then
            cur = M.pristine[ft]
            curEmpty = M.pristineEmpty[ft] or curEmpty
        else
            M.written[ft] = nil
            M.writtenEmpty[ft] = nil
        end
        M.pristine[ft] = cur
        M.pristineEmpty[ft] = curEmpty
        if not near(cur, rows[i + 1]) or (hasEmpty and not near(curEmpty, rows[i + 5])) then
            if ours then
                item:setActualWeight(cur)
                if hasEmpty then item:setWeightEmpty(curEmpty) end
                M.written[ft] = nil
                M.writtenEmpty[ft] = nil
                releasePart(item, ft)
            end
            c.stale = c.stale + 1
            return
        end
    end
    local flags = rows[i + 8]
    if math.floor(flags / M.FLAG_PHYSICS) % 2 == 1 then s = 1 end
    local w = M.target(rows[i + 2], rows[i + 3], rows[i + 4], r, k, s)
    item:setActualWeight(w)
    w = item:getActualWeight()
    M.written[ft] = w
    c.hash = mix(c.hash, w)
    local partModifier = rows[i + 9]
    if partModifier >= 0 then
        setPartModifier(item, w)
        M.writtenPart[ft] = partModifier
        c.hash = mix(c.hash, partModifier)
    end
    if hasEmpty then
        local e = rows[i + 6] + r * (M.carry(s * rows[i + 7]) - rows[i + 6])
        if e > w then
            e = w
            c.clamped = c.clamped + 1
        end
        item:setWeightEmpty(e)
        e = item:getWeightEmpty()
        M.writtenEmpty[ft] = e
        c.hash = mix(c.hash, e)
    end
    if flags % 2 == M.FLAG_MELEE then applyStamina(item, ft, stage, w, vanillaStamina, c) end
    c.applied = c.applied + 1
end

function M.applyAll(stage)
    local p = DEFAULTS
    if stage == "sandbox" then p = M.presets() end
    local r, k = p.realism / 100, BULK_K[p.bulk]
    local c = newCounts()
    local sm = ScriptManager.instance
    local sources = activeSources(M.active or {}, c)
    for s = 1, #sources do
        local rows = sources[s].rows
        c.sources = c.sources + 1
        for i = 1, #rows, M.STRIDE do
            applyRow(sm, rows, i, stage, r, k, p.scale, p.vanillaStamina, c)
        end
    end
    c.realism, c.bulk, c.scale = p.realism, BULK_NAME[p.bulk], p.scale
    c.stamina = p.vanillaStamina and "vanilla" or "weight"
    M.counts = c
    return c
end

function M.countsText(c)
    local text = "data " .. tostring(M.DATA_VERSION) .. ", " .. c.sources .. " source(s), applied "
        .. c.applied .. ", stale " .. c.stale .. ", missing " .. c.missing .. ", yielded "
        .. c.yielded .. ", clamped " .. c.clamped .. ", realism " .. tostring(c.realism)
        .. " bulk " .. tostring(c.bulk) .. " scale " .. tostring(c.scale) .. " stamina " .. tostring(c.stamina)
        .. ", hash " .. tostring(c.hash)
    if c.leftovers > 0 then text = text .. ", " .. c.leftovers .. " leftover data file(s) ignored" end
    return text
end

-- Puts back every pristine value this mod overwrote, so a failed pass leaves the game stock.
function M.revert()
    local sm = ScriptManager.instance
    for ft in pairs(M.written) do
        pcall(function()
            local item = sm:getItem(ft)
            if item == nil then return end
            item:setActualWeight(M.pristine[ft])
            if M.writtenEmpty[ft] ~= nil then item:setWeightEmpty(M.pristineEmpty[ft]) end
            if M.writtenMod[ft] ~= nil then item:setEnduranceMod(M.pristineMod[ft]) end
        end)
    end
    for ft in pairs(M.writtenPart) do
        pcall(function()
            local item = sm:getItem(ft)
            if item ~= nil then setPartModifier(item, M.writtenPart[ft]) end
        end)
    end
    M.written, M.writtenEmpty, M.writtenMod, M.writtenPart = {}, {}, {}, {}
end

local function installWeights()
    M.enabled = false
    M.active = activeMods()
    if M.active[INCOMPATIBLE] then
        return INCOMPATIBLE .. " is active; disable it to use Honest Weight"
    end
    local ok, res = pcall(M.applyAll, "boot")
    if not ok then
        pcall(M.revert)
        error(res)
    end
    M.enabled = true
    M.setPart(M.PART, true, M.countsText(res), "ok")
end

function M.onTileDefinitions()
    if not M.enabled then return end
    local ok, res = pcall(M.applyAll, "sandbox")
    if ok then
        M.log("presets applied: " .. M.countsText(res))
    else
        M.enabled = false
        pcall(M.revert)
        M.setPart(M.PART, false, "sandbox pass: " .. tostring(res), "bug")
        M.log(M.PART .. ": failed: sandbox pass: " .. tostring(res))
    end
end

M.addPart(M.PART, installWeights)

if Events and Events.OnLoadedTileDefinitions then
    Events.OnLoadedTileDefinitions.Add(M.onTileDefinitions)
end
