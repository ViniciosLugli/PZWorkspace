--[[
Nick's Generator Manager with Neat Rocco's UI: the generator window lists what this generator pays for.

What happens today. Nick's Generator Manager bills every powered appliance to exactly one generator
and lists those appliances in the vanilla Generator Info window. Neat Rocco's UI replaces that
window with its own panel, which lists the engine's list instead: every appliance in range,
including the ones another generator pays for. With two generators the same fridge shows under
both, and the list no longer adds up to the Total line beneath it, which is Nick's.

What this part changes. While Neat Rocco's panel draws a running generator, the panel reads Nick's
per-generator breakdown as its appliance list, with the numbers printed the way the panel's own
base and Total lines print them. Until Nick's first pass has billed that generator, the engine's
list shows, as it does in Nick's window.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- IsoGenerator's own "#.####" format, as its base and Total lines print it: "0.013", "1.25", "0".
-- Java's DecimalFormat gives "#.####" one integer digit, so the leading zero stays.
function M.fmtLh(v)
    local s = string.format("%.4f", v)
    s = string.gsub(s, "0+$", "")
    s = string.gsub(s, "%.$", "")
    if s == "" then s = "0" end
    return s
end
local fmtLh = M.fmtLh

-- One line per appliance Nick bills to this generator, in the engine's number format; nil when
-- Nick has not billed it yet. The ngm-info part puts the same lines in the Info window text.
function M.ngmLines(object)
    local NGM = NicksGeneratorManager
    local sq = object:getSquare()
    if sq == nil then return nil end
    local cached = NGM.targets[NGM.genKey(sq:getX(), sq:getY(), sq:getZ())]
    if cached == nil or type(cached.items) ~= "table" then return nil end
    local mult = NGM.fuelMult()
    local lines = {}
    for i = 1, #cached.items do
        local it = cached.items[i]
        lines[i] = it.label .. " x" .. it.count .. " (" .. fmtLh(it.draw * mult) .. " L/h)"
    end
    return lines
end

function M.needNgmCache()
    local NGM = NicksGeneratorManager
    if type(NGM) ~= "table" or type(NGM.targets) ~= "table" or type(NGM.genKey) ~= "function"
        or type(NGM.fuelMult) ~= "function" then
        error("Nick's Generator Manager has no billing cache")
    end
end

-- The same lines as the size/get list the panel walks.
local function breakdown(object)
    local lines = M.ngmLines(object)
    if lines == nil then return nil end
    return { size = function() return #lines end, get = function(_, i) return lines[i + 1] end }
end

local function install(ctx)
    M.needNgmCache()
    if type(NR_GeneratorPanel) ~= "table" then error("Neat Rocco's generator panel is missing") end
    ctx.wrap(NR_GeneratorPanel, "render", function(callOriginal)
        return function(self, ...)
            local object = self.object
            local list = object ~= nil and object:getObjectIndex() ~= -1 and object:isActivated()
                and breakdown(object) or nil
            if list == nil then return callOriginal(self, ...) end
            self.object = M.overlay(object, { getItemsPowered = function() return list end })
            local ok, err = pcall(callOriginal, self, ...)
            self.object = object
            if not ok then error(err) end
        end
    end)
end

M.addPart({
    name = "ngm-neat",
    switch = "NgmNeat",
    title = "Nick's Generator Manager: Neat Rocco's generator window lists what each generator pays for",
    tip = "Neat Rocco's generator window lists every appliance in range, also the ones another generator pays for, so the list does not match its Total. This makes it list what Nick's Generator Manager bills to that generator, as Nick's own window does. Only active with both mods.",
    kind = "compat",
    all = { "NicksGeneratorManager", "Neat_Rocco" },
    side = "client",
    phase = "boot",
    pins = { "nr.items", "ngm.targets" },
    install = install,
})
