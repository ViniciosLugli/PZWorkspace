--[[
Hot Brass drops its own casing for rounds Ammo Maker has no calibre for.

Hot Brass turns its casing drops off whenever Ammo Maker is active and hands every spent round to
Ammo Maker instead. Ammo Maker only makes a case for a calibre it knows, and it has no 2 Bore, so
Guns of Marz's Double Deuce, a break-action double barrel firing SWMG.2Bore_Bullet, drops nothing
at all, although Guns of Marz maps that round to Hot Brass's HBVCEF.2Bore_Casing.

For the rounds in ROUNDS this part takes the branch Hot Brass takes with Ammo Maker off: the spent
rounds come out when the gun is opened to reload or unload, through Hot Brass's own
ISReloadWeaponAction.removeRoundFromTube, so the casing, its timing and the server-side drop in
multiplayer are Hot Brass's. Every other round, and these rounds whenever Hot Brass's function or
casing mapping is missing, go to the functions below untouched. A round that any gun mod maps to an
Ammo Maker calibre through the public ammoMakerAddAmmoTypesMap0..9 tables is left to Ammo Maker, so
the part steps aside by itself the day a 2 Bore mapping is published. It reads nothing of Ammo
Maker's own.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

-- Ammo Maker's public calibre list (the one every ammomaker_apiTables.lua repeats) has no 2 Bore.
local ROUNDS = { "SWMG.2Bore_Bullet" }
local API_TABLES = 10

local stats = { state = "not installed", watched = {}, ejections = 0, rounds = 0, failures = 0 }
M.hotBrassCasings = stats

local function apiMapping(round)
    for i = 0, API_TABLES - 1 do
        local map = _G["ammoMakerAddAmmoTypesMap" .. i]
        if type(map) == "table" then
            for _, entry in pairs(map) do
                if type(entry) == "table" and entry.itemType == round and entry.ammoType ~= nil then
                    return "ammoMakerAddAmmoTypesMap" .. i .. " maps it to " .. tostring(entry.ammoType)
                end
            end
        end
    end
    return nil
end

local function install()
    local found, HB = pcall(require, "SpentCasingPhysics/Init")
    if not found or type(HB) ~= "table" then
        error("Hot Brass module SpentCasingPhysics/Init not reachable")
    end
    if type(ISReloadWeaponAction) ~= "table" or type(ISReloadWeaponAction.ejectSpentRounds) ~= "function"
        or type(ISReloadWeaponAction.animEvent) ~= "function" then
        error("ISReloadWeaponAction.ejectSpentRounds or animEvent not found")
    end
    if type(ISRackFirearm) ~= "table" or type(ISRackFirearm.ejectSpentRounds) ~= "function"
        or type(ISRackFirearm.animEvent) ~= "function" then
        error("ISRackFirearm.ejectSpentRounds or animEvent not found")
    end

    local watched, names, aside = {}, {}, {}
    for i = 1, #ROUNDS do
        local mapping = apiMapping(ROUNDS[i])
        if mapping == nil then
            watched[ROUNDS[i]] = true
            names[#names + 1] = ROUNDS[i]
        else
            aside[#aside + 1] = ROUNDS[i] .. " (" .. mapping .. ")"
        end
    end
    stats.watched = watched
    if #names == 0 then
        stats.state = "stepping aside, Ammo Maker takes every round: " .. table.concat(aside, ", ")
        M.log("HotBrassCasings: " .. stats.state)
        return
    end

    -- The round this gun's spent cases are, when Hot Brass can drop its own casing for it right now.
    -- Hot Brass defines removeRoundFromTube at OnInitGlobalModData and Guns of Marz maps its casings
    -- from server Lua, so both are read per call.
    local function ownCasing(action)
        if HB.AMMOMAKER ~= true or type(HB.AMMO_TO_CASING) ~= "table" then return false end
        if type(ISReloadWeaponAction.removeRoundFromTube) ~= "function" then return false end
        local gun = action.gun
        if gun == nil then return false end
        local ammo = gun:getAmmoType()
        local key = ammo and ammo:getItemKey()
        return key ~= nil and watched[key] == true and HB.AMMO_TO_CASING[key] ~= nil
    end

    local function takes(action)
        local ok, result = pcall(ownCasing, action)
        return ok and result == true
    end

    local function noteFailure(err)
        stats.failures = stats.failures + 1
        if stats.failures == 1 then
            M.log("HotBrassCasings: ejection failed, stock path taken: " .. tostring(err))
        end
    end

    -- Hot Brass's spent-round ejection only, also from a rack action: the rack action's own
    -- removeRoundFromTube takes a live round too, which rackBullet still does with Ammo Maker on.
    local function eject(action)
        local spent = action.gun:getSpentRoundCount()
        ISReloadWeaponAction.removeRoundFromTube(action)
        if not isClient() and spent > 0 then
            stats.ejections = stats.ejections + 1
            stats.rounds = stats.rounds + spent
        end
    end

    local function wrap(class)
        local previousEject = class.ejectSpentRounds
        local previousAnim = class.animEvent

        local function ejectSpentRounds(self)
            if not takes(self) then return previousEject(self) end
            -- Hot Brass with Ammo Maker off: the server ejects at start, single player keeps the
            -- count for the openWeapon event, a client leaves it to the server.
            if isServer() then
                local ok, err = pcall(eject, self)
                if not ok then
                    noteFailure(err)
                    return previousEject(self)
                end
            end
        end

        local function animEvent(self, event, parameter)
            if (event == "openWeapon" or event == "changeWeaponSprite") and takes(self) then
                local ok, err = pcall(eject, self)
                if not ok then noteFailure(err) end
            end
            return previousAnim(self, event, parameter)
        end

        local function restore()
            class.ejectSpentRounds = previousEject
            class.animEvent = previousAnim
        end
        class.ejectSpentRounds = ejectSpentRounds
        class.animEvent = animEvent
        if class.ejectSpentRounds ~= ejectSpentRounds or class.animEvent ~= animEvent then
            restore()
            error("assignment to " .. tostring(class.Type) .. " did not take")
        end
        return restore
    end

    local restoreReload = wrap(ISReloadWeaponAction)
    local wrapped, err = pcall(wrap, ISRackFirearm)
    if not wrapped then
        restoreReload()
        error(err, 0)
    end
    stats.state = "Hot Brass drops its own casing for " .. table.concat(names, ", ")
    if #aside > 0 then stats.state = stats.state .. "; Ammo Maker takes " .. table.concat(aside, ", ") end
    M.log("HotBrassCasings: " .. stats.state)
end

M.addPart("HotBrassCasings", { "HBVCEFb42", "ammomaker", "GunsOfMarz" }, install)
