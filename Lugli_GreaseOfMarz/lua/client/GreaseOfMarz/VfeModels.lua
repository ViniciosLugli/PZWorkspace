--[[
Complete Vanilla Firearms Expansion leaves the model of a Gunworks gun alone.

Complete Vanilla Firearms Expansion (ExtendedVanillaWeapons) watches the gun in the hand every player
update and, whenever its magazine state or parts change, calls VFESetWeaponModel. For a gun in its
model table that picks the pack's variant; for every other gun it falls back to the gun's script
model. Gunworks sets the model of its guns itself, from their parts (ConditionalModel and the
attachment layers of StatsFactory): Guns of Tien's MP7, SCAR, Vector and HK416 fold their iron
sights under an optic as their own `_RD`/`_FD` models. So with the pack active every magazine
eject, insert or part change put the plain model back, and where Gunworks did not reapply its
model after that (the Vectors and the MP7 after a reload) the gun kept it, sights up through the
optic, until the next change.

For a gun Gunworks has a reload handler for and the pack has no model of its own for, this part
skips that fallback, so the model stays the one Gunworks gave it. Guns in the pack's table and
every other gun are left to it exactly as before. Client only, like the pack's model code.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

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
    if type(VFESetWeaponModel) ~= "function" then return "VFESetWeaponModel not found" end
    if type(VFEWeaponModelTable) ~= "table" then return "VFEWeaponModelTable not found" end
    return nil
end

local function install(ctx)
    local ReloadAnim = reloadAnim()
    local stats = { kept = 0 }
    M.vfeModels = stats

    local function packModel(fullType)
        for _, entry in ipairs(VFEWeaponModelTable) do
            if type(entry) == "table" and entry.Name == fullType then return true end
        end
        return false
    end

    local previous = VFESetWeaponModel
    VFESetWeaponModel = function(weapon, open)
        if weapon ~= nil and instanceof(weapon, "HandWeapon") and not packModel(weapon:getFullType())
            and ReloadAnim.GetHandlerForGun(weapon) ~= nil then
            stats.kept = stats.kept + 1
            return
        end
        return previous(weapon, open)
    end
    stats.stock = previous
end

M.addPart("VfeModels", { "SWMG", "ExtendedVanillaWeapons" }, install, { check = check })
