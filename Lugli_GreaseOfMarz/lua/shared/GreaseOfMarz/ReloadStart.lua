--[[
Ultimate Marksman beside Gunworks: the reload-start step comes back.

Gunworks wraps ISReloadWeaponAction.start so that a registered gun's handler runs onReloadStart,
which puts the reload prop (shell holder, speedloader, stripper clip) in the off hand. Ultimate
Marksman loads later and redefines start without calling the function it replaces, so that step
never runs for any gun that reloads without a magazine.

This part wraps whatever start is final once every file has loaded. Each call notes whether the
chain below it reached the handler's onReloadStart, and runs that step itself only when it did
not. It never runs the step twice, and it goes idle on its own if Ultimate Marksman starts
calling the previous start.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local function install()
    local found, ReloadAnim = pcall(require, "WeaponSystems/Utils/ReloadAnim")
    if not found or type(ReloadAnim) ~= "table" or type(ReloadAnim.getHandlerForAction) ~= "function" then
        error("Gunworks ReloadAnim module not reachable")
    end
    if type(ISReloadWeaponAction) ~= "table" or type(ISReloadWeaponAction.start) ~= "function" then
        error("ISReloadWeaponAction.start not found")
    end

    local previous = ISReloadWeaponAction.start
    local stats = { repaired = 0 }
    M.reloadStart = stats

    function ISReloadWeaponAction:start()
        local handler = ReloadAnim.getHandlerForAction(self)
        local step = handler and handler.onReloadStart
        if type(step) ~= "function" then
            return previous(self)
        end
        local reached = false
        handler.onReloadStart = function(action)
            reached = true
            return step(action)
        end
        local ok, err = pcall(previous, self)
        handler.onReloadStart = step
        if not ok then error(err, 0) end
        if not reached then
            stats.repaired = stats.repaired + 1
            step(self)
        end
    end
end

M.addPart("ReloadStart", { "SWMG", "UltimateMarksman" }, install)
