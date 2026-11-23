--[[
Guns found loaded show their magazine, and drop it into the hand on eject.

Guns of Marz rolls a gun's magazine when the gun is created: on a hit the magazine goes on the gun
as its Clip part and its type is saved in the gun's mod data; on a miss the gun is left empty. The
engine then loads guns found as loot, carried by zombies or placed in a scene
(HandWeapon.randomizeFirearmAsLoot / randomizeBullets: setContainsClip(true) when the gun has a
magazine type), so a gun that missed the roll is loaded with no Clip part and no saved type. It
looks empty while loaded, and Gunworks, which takes the off-hand magazine from the Clip part or the
saved type, has nothing to put in the hand when it is ejected.

For a Gunworks gun in that state this part saves the gun's own magazine type and puts the Clip part
on, the way Gunworks' own insert leaves it: when it is equipped (in single player as the player
equips it; in multiplayer on the server, which owns the gun, as the equip action completes, and
sent to the owner from there), and when a magazine eject starts (client and server).
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local function gunworks()
    local foundAnim, ReloadAnim = pcall(require, "WeaponSystems/Utils/ReloadAnim")
    local foundMag, Magazine = pcall(require, "WeaponSystems/Utils/Magazine")
    if not foundAnim or not foundMag or type(ReloadAnim) ~= "table" or type(Magazine) ~= "table" then return nil, nil end
    return ReloadAnim, Magazine
end

local function check()
    local ReloadAnim, Magazine = gunworks()
    if ReloadAnim == nil or type(ReloadAnim.GetHandlerForGun) ~= "function" then
        return "Gunworks ReloadAnim.GetHandlerForGun not found"
    end
    if type(Magazine.attachMagazineVisual) ~= "function" or type(Magazine.SaveMagazineType) ~= "function" then
        return "Gunworks Magazine.attachMagazineVisual or SaveMagazineType not found"
    end
    if type(ISEjectMagazine) ~= "table" or type(ISEjectMagazine.start) ~= "function" then
        return "ISEjectMagazine.start not found"
    end
    if type(ISEquipWeaponAction) ~= "table" or type(ISEquipWeaponAction.complete) ~= "function" then
        return "ISEquipWeaponAction.complete not found"
    end
    return nil
end

local function install(ctx)
    local ReloadAnim, Magazine = gunworks()
    local stats = { equipped = 0, ejected = 0 }
    M.loadedLoot = stats

    -- true when the gun was loaded without its magazine part and now has it
    local function restore(gun)
        if gun == nil or not instanceof(gun, "HandWeapon") or not gun:isContainsClip() then return false end
        if gun:getWeaponPart("Clip") ~= nil or gun:getWeaponPart("Magazine") ~= nil then return false end
        local magType = gun:getMagazineType()
        if magType == nil or magType == "" then return false end
        local saved = gun:getModData().MagazineType
        if saved ~= nil and saved ~= "" then return false end
        if ReloadAnim.GetHandlerForGun(gun) == nil then return false end
        Magazine.SaveMagazineType(gun, magType)
        Magazine.attachMagazineVisual(gun, magType)
        return gun:getWeaponPart("Clip") ~= nil or gun:getWeaponPart("Magazine") ~= nil
    end

    local previousStart = ISEjectMagazine.start
    function ISEjectMagazine:start()
        if restore(self.gun) then stats.ejected = stats.ejected + 1 end
        return previousStart(self)
    end
    if ISEjectMagazine.start == previousStart then
        ctx.standDown("ISEjectMagazine.start did not take the wrap")
        return
    end

    -- Multiplayer: the server owns the gun, so it restores it as the equip completes, before
    -- sendEquip shows it to others, and sends the owner the gun's parts and mod data.
    if isServer() then
        local previousComplete = ISEquipWeaponAction.complete
        function ISEquipWeaponAction:complete()
            if self.primary and restore(self.item) then
                stats.equipped = stats.equipped + 1
                if type(syncHandWeaponFields) == "function" then syncHandWeaponFields(self.character, self.item) end
            end
            return previousComplete(self)
        end
    elseif not isClient() and Events.OnEquipPrimary then
        Events.OnEquipPrimary.Add(function(character, item)
            -- NPC mods such as Living World equip guns on IsoZombie bodies, which have no isLocalPlayer
            if not instanceof(character, "IsoPlayer") or not character:isLocalPlayer() then return end
            if not restore(item) then return end
            stats.equipped = stats.equipped + 1
            character:resetEquippedHandsModels()
        end)
    end
end

M.addPart("LoadedLoot", { "SWMG" }, install, { check = check })
