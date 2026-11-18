--[[
Undead Survivor's Headhunter rifles take the rounds and magazine Guns of Marz hands out instead.

Both rifles take vanilla .308 rounds, the vanilla M14 magazine and the vanilla .308 box. Guns of
Marz turns each of those into its own item the moment one is created, and leaves the rifles
alone, so a Headhunter never finds anything it can load.

This part gives both rifles the round, magazine and box of Guns of Marz's own M14, which has the
same 20 rounds and bolt action. It decides per world, after the save's sandbox settings are
loaded and before any item is: only when Guns of Marz converts the .308 round or the M14 magazine
in this save, because with both conversions off the vanilla items stay and the rifles work as
they are. A gun reads these from its script when it is created or loaded (the save holds neither),
so rifles already in a save change too.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local RIFLES = { "Base.HeadhunterRifle", "Base.DeadlyHeadhunterRifle" }
local DONOR = "MarzGuns.M14"
local ROUND = "SWMG.762x51_Bullet"
local MAGAZINE = "MarzGuns.762x51Magazine20_M14"
local BOX = "MarzGuns.762x51_Box"

M.headhunter = { state = "waiting for a world" }

local function itemKeyOf(script)
    local ammo = script:getAmmoType()
    return ammo and ammo:getItemKey()
end

local function scriptOf(manager, fullType)
    local script = manager:getItem(fullType)
    if script == nil then return nil, fullType .. " not defined" end
    return script, nil
end

-- Reads everything before the first write; returns why the rifles cannot be retargeted, or nil.
local function retarget()
    local manager = ScriptManager.instance
    local donor, why = scriptOf(manager, DONOR)
    if why ~= nil then return why end
    if itemKeyOf(donor) ~= ROUND then return DONOR .. " no longer takes " .. ROUND end
    local magazine
    magazine, why = scriptOf(manager, MAGAZINE)
    if why ~= nil then return why end
    if itemKeyOf(magazine) ~= ROUND then return MAGAZINE .. " no longer takes " .. ROUND end
    why = select(2, scriptOf(manager, BOX))
    if why ~= nil then return why end
    local rifles = {}
    for i = 1, #RIFLES do
        rifles[i], why = scriptOf(manager, RIFLES[i])
        if why ~= nil then return why end
    end

    local ammo = donor:getAmmoType()
    for i = 1, #rifles do
        rifles[i]:setAmmoType(ammo)
        rifles[i]:DoParam("MagazineType = " .. MAGAZINE)
        rifles[i]:DoParam("AmmoBox = " .. BOX)
    end
    return nil
end

-- Returns the state, or nil and why the part stands down.
local function decide()
    local replacement = MarzGuns_OnCreate.ComputeVanillaReplacementType
    if replacement("Base.308Bullets") == nil and replacement("Base.M14Clip") == nil then
        return "stock: Guns of Marz converts neither .308 rounds nor M14 magazines in this world"
    end
    local why = retarget()
    if why ~= nil then return nil, why end
    return "retargeted " .. #RIFLES .. " rifles to " .. ROUND .. ", " .. MAGAZINE .. ", " .. BOX
end

local function onWorldItemsReady(ctx)
    local ok, result, why = pcall(decide)
    if ok and why ~= nil then
        M.headhunter.state = "stood down: " .. why
        ctx.standDown(why)
        return
    end
    M.headhunter.state = ok and result or ("failed: " .. tostring(result))
    M.log("Headhunter: " .. M.headhunter.state)
end

local function check()
    if type(MarzGuns_OnCreate) ~= "table" or type(MarzGuns_OnCreate.ComputeVanillaReplacementType) ~= "function" then
        return "Guns of Marz replacer MarzGuns_OnCreate.ComputeVanillaReplacementType not found"
    end
    return nil
end

local function install(ctx)
    Events.OnLoadedTileDefinitions.Add(function() onWorldItemsReady(ctx) end)
end

M.addPart("Headhunter", { "GunsOfMarz", "UndeadSuvivor" }, install, { check = check })
