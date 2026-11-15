--[[
Vanilla: no error from the reload speed with a fast-reload item worn or equipped.

What happens today. ISReloadWeaponAction.setReloadSpeed (vanilla 42.22) sets the speed of every
reload, rack, magazine insert and eject, bullet load and unload. Once a fast-reload item opens its
check (an ALICE belt or chest rig worn, an ammo case equipped, or an ammo strap worn), it throws in
two places before it sets the speed:
- it reads the worn ammo strap's name without checking that one is worn, so with no strap and
  anything in hand that is neither a shotgun nor fed by a magazine (a revolver, a crossbow, a melee
  weapon) it indexes nil (lines 100 and 102);
- it asks the held item for its magazine type, which only weapons have (HandWeapon.getMagazineType;
  getAmmoType is on every InventoryItem), so filling or emptying a magazine while holding anything
  that is not a weapon (a flashlight, the magazine itself) calls nil (line 95). Filling a magazine
  does not equip it, so whatever the player holds is read.
Reload Those Weapons Again fixes the first by replacing the function, and not the second.

What this part changes. Only in those cases, the whole setReloadSpeed chain is called with a view of
the character: the empty strap slot reads as an item with no name, a held item that is not a weapon
answers nil for its magazine type, and the vehicle names the view as its driver. Vanilla then takes
its "no strap" and "not a magazine gun" branches, the result its checks mean, and every mod that
wraps the function still runs (Ultimate Marksman chains it from its own file before this mod loads,
so replacing the function would drop its bow and crossbow speeds). The view is handed only to code
this part knows: vanilla's function, Reload Those Weapons Again's copy of it, and Ultimate
Marksman's two wrappers.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- Basename of the file that made each closure the chain may hold. The bow wrapper keeps the one
-- under it in a field; the others end the walk.
local LAST_FILES = { ["ISReloadWeaponAction.lua"] = true, ["ISReloadWeaponFix.lua"] = true, ["UMReloadSpeed.lua"] = true }
local UM_BOW_FILE = "UMArcheryReloadAnimation.lua"

local NO_STRAP = setmetatable({}, { __index = function() return function() return nil end end })

local function sourceOf(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    if not ok or type(name) ~= "string" then return nil end
    return string.match(name, "([^/\\]+)$")
end

-- Ultimate Marksman's crossbow wrapper keeps the function under it in a local, so the walk ends
-- there; its pinned body only calls that function and reads the character back.
local function checkChain(fn)
    for _ = 1, 4 do
        local file = sourceOf(fn)
        if LAST_FILES[file] then return end
        if file ~= UM_BOW_FILE then
            error("setReloadSpeed comes from " .. tostring(file) .. ", which this part does not know")
        end
        fn = ISReloadWeaponAction.UMArcherySetReloadSpeed
    end
    error("setReloadSpeed chain is longer than this part knows")
end

local function fastTag(character, tag)
    return character:hasEquippedTag(tag) or character:hasWornTag(tag)
end

-- Vanilla's branches, in vanilla's order. Returns whether they would read the name of a strap that
-- is not worn, and whether the held item lacks a method they call.
local function hazards(character)
    local gun = character:getPrimaryHandItem()
    if not gun then return false, false end
    local strap = character:getWornItem(ItemBodyLocation.AMMO_STRAP)
    local reloadFast = character:hasEquippedTag(ItemTag.RELOAD_FAST_SHELLS)
        or character:hasEquippedTag(ItemTag.RELOAD_FAST_BULLETS)
        or character:hasEquippedTag(ItemTag.RELOAD_FAST_MAGAZINES)
    if not (reloadFast or character:hasWornTag(ItemTag.RELOAD_FAST_MAGAZINES) or (strap and strap:getClothingItem())) then
        return false, false
    end
    local shell = gun:getAmmoType() == AmmoType.SHOTGUN_SHELLS
    local untyped = not shell and gun.getMagazineType == nil
    if strap or (not shell and not untyped and gun:getMagazineType()) then return false, untyped end
    return not fastTag(character, shell and ItemTag.RELOAD_FAST_SHELLS or ItemTag.RELOAD_FAST_BULLETS), untyped
end

local function untypedView(item)
    return M.overlay(item, { getMagazineType = function() return nil end })
end

-- The vehicle is seen through the view too: vanilla compares its driver with the character.
local function characterView(character, missingStrap, untyped)
    local view
    local overrides = {
        getVehicle = function()
            local vehicle = character:getVehicle()
            if vehicle == nil then return nil end
            return M.overlay(vehicle, {
                getDriver = function()
                    local driver = vehicle:getDriver()
                    if driver == character then return view end
                    return driver
                end,
            })
        end,
    }
    if missingStrap then
        overrides.getWornItem = function(_, location)
            local item = character:getWornItem(location)
            if item == nil and location == ItemBodyLocation.AMMO_STRAP then return NO_STRAP end
            return item
        end
    end
    if untyped then
        overrides.getPrimaryHandItem = function() return untypedView(character:getPrimaryHandItem()) end
    end
    view = M.overlay(character, overrides)
    return view
end

local function install(ctx)
    if type(ISReloadWeaponAction) ~= "table" or type(ISReloadWeaponAction.setReloadSpeed) ~= "function" then
        error("ISReloadWeaponAction.setReloadSpeed is missing")
    end
    checkChain(ISReloadWeaponAction.setReloadSpeed)
    ctx.wrap(ISReloadWeaponAction, "setReloadSpeed", function(callOriginal)
        return function(character, rack)
            local missingStrap, untyped = hazards(character)
            if missingStrap or untyped then
                return callOriginal(characterView(character, missingStrap, untyped), rack)
            end
            return callOriginal(character, rack)
        end
    end)
end

M.addPart({
    name = "reload-strap",
    switch = "ReloadStrap",
    title = "Vanilla: no reload or magazine error with a fast-reload item",
    tip = "With an ALICE belt or chest rig worn (or an ammo case equipped), reloading a shotgun or revolver without an ammo strap, or filling or emptying a magazine while holding anything that is not a weapon, throws an error and skips the reload speed. They work as vanilla means them to. Works beside Reload Those Weapons Again, which fixes only the first. Off while Reload Strap Fix is active.",
    kind = "fix",
    none = { "ReloadStrapFix" },
    side = "both",
    phase = "boot",
    pins = { "vanilla.reloadspeed", "um.bowspeed", "um.crossbowspeed", "rba.reloadspeed" },
    install = install,
})
