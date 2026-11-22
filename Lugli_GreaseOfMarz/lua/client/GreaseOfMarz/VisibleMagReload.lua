--[[
Visible Magazine Reloads stays off guns Gunworks reloads.

Visible Magazine Reloads (PZMagReload) means to leave guns with their own reload system alone, and
does so on most Gunworks guns because Gunworks sets WeaponReloadType to its own reload profile when
the action starts. Two of its paths still reach Gunworks guns from ISInsertMagazine:start and
ISEjectMagazine:start:
- its table for other packs' models (PZMagReload.MODELL) is keyed by the model name without the
  module, and is checked before the reload type. Complete Vanilla Firearms Expansion's FAL, CAR15,
  M14, MP5 and MP5SD share those names with Guns of Marz's, so with that pack active Marz's guns
  play its reload with the other pack's models;
- Gunworks' profile for Guns of Tien's SV98 and SV99 is named "boltaction", the one reload type its
  rifle path accepts.

For a gun Gunworks has a reload handler for, this part hides that model table and marks every
magazine part as one it cannot show (PZMagReload.LEER) for the length of the start call, so both
paths return before anything is changed and Gunworks runs its reload alone. Every other gun is left
to it exactly as before. Client only: Visible Magazine Reloads' reload hooks are client Lua.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local NO_MODELS = {}
local NO_PARTS = setmetatable({}, { __index = function() return true end })

local function reloadAnim()
    local found, ReloadAnim = pcall(require, "WeaponSystems/Utils/ReloadAnim")
    if found and type(ReloadAnim) == "table" then return ReloadAnim end
    return nil
end

local function check()
    local ReloadAnim = reloadAnim()
    if ReloadAnim == nil or type(ReloadAnim.GetHandlerForGun) ~= "function" then
        return "Gunworks ReloadAnim.GetHandlerForGun not found"
    end
    if type(PZMagReload) ~= "table" or type(PZMagReload.MODELL) ~= "table" then
        return "PZMagReload.MODELL not found"
    end
    if PZMagReload.LEER ~= nil and type(PZMagReload.LEER) ~= "table" then
        return "PZMagReload.LEER is not a table"
    end
    if type(ISInsertMagazine) ~= "table" or type(ISInsertMagazine.start) ~= "function"
        or type(ISEjectMagazine) ~= "table" or type(ISEjectMagazine.start) ~= "function" then
        return "ISInsertMagazine.start or ISEjectMagazine.start not found"
    end
    return nil
end

local function install(ctx)
    local ReloadAnim = reloadAnim()
    local stats = { kept = 0 }
    M.visibleMagReload = stats
    -- What a start call hid, put back by the next call if that start raised before it returned.
    local hidden = nil

    local function reveal()
        if hidden == nil then return end
        PZMagReload.MODELL, PZMagReload.LEER = hidden.models, hidden.parts
        hidden = nil
    end

    local function gunworksGun(action)
        local gun = action and action.gun
        return gun ~= nil and instanceof(gun, "HandWeapon") and ReloadAnim.GetHandlerForGun(gun) ~= nil
    end

    local function keepOff(previous)
        return function(self)
            reveal()
            if not gunworksGun(self) then return previous(self) end
            hidden = { models = PZMagReload.MODELL, parts = PZMagReload.LEER }
            PZMagReload.MODELL, PZMagReload.LEER = NO_MODELS, NO_PARTS
            stats.kept = stats.kept + 1
            local result = previous(self)
            reveal()
            return result
        end
    end

    local insertStart, ejectStart = ISInsertMagazine.start, ISEjectMagazine.start
    ISInsertMagazine.start = keepOff(insertStart)
    ISEjectMagazine.start = keepOff(ejectStart)
    if ISInsertMagazine.start == insertStart or ISEjectMagazine.start == ejectStart then
        ISInsertMagazine.start, ISEjectMagazine.start = insertStart, ejectStart
        M.visibleMagReload = nil
        return ctx.standDown("the magazine actions rejected the assignment")
    end
    stats.stock = { insert = insertStart, eject = ejectStart }
end

M.addPart("VisibleMagReload", { "SWMG", "PZMagReload" }, install, { check = check })
