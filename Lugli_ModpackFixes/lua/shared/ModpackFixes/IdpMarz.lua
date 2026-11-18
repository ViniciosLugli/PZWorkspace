--[[
Item Details Panel and Guns of Marz: a gun's Information lines survive a hidden vanilla tooltip.

What happens today. Guns of Marz draws a red "Information" block under the tooltip of every gun in
its per-gun table (ammo, rail slots, muzzle device, bayonet: CustomItemTooltips.lua, data in
MarzWeapons/ItemTooltipsTable). Guns of Tien rewrites a gun's entry for what is fitted on it
(deployed or sawn-off stocks, selectors, bipods) right before each tooltip draws. Item Details
Panel's Guns of Marz bridge leaves descriptive text out on purpose, so with its Hide vanilla
tooltip option on the whole block is gone.

What this part changes. While the vanilla tooltip is hidden, Item Details Panel shows the same
lines under the same Information heading, read from the same table at the moment Guns of Tien has
fitted them to this gun.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.MarzInformation"
local MAX_LINES = 16
local LINE_COLOR = { 1, 1, 1, 1 }
local HEADING_COLOR = { 1, 0.02, 0.02, 1 }

local tooltips

local function linesOf(item)
    local entry = tooltips and tooltips.tooltipsPergun and tooltips.tooltipsPergun[item:getFullType()]
    if type(entry) == "string" then return K.splitLines(entry, MAX_LINES) end
    if type(entry) ~= "table" then return nil end
    local lines = {}
    for i = 1, #entry do
        local line = entry[i]
        if type(line) == "string" and line ~= "" then
            lines[#lines + 1] = line
            if #lines >= MAX_LINES then break end
        end
    end
    if #lines == 0 then return nil end
    return lines
end

local function check()
    local why = K.check()
    if why ~= nil then return why end
    local ok, table_ = pcall(require, "MarzWeapons/ItemTooltipsTable")
    if not ok or type(table_) ~= "table" or type(table_.tooltipsPergun) ~= "table" then
        return "Guns of Marz's tooltip table is not loaded"
    end
    tooltips = table_
    return nil
end

local function install(ctx)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Guns of Marz information (Modpack Fixes)",
        description = "Guns of Marz's per-gun lines (ammo, rail slots, muzzle device, bayonet), with Guns of Tien's fitted state. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "independent", order = 80,
        fields = K.lineFields(MAX_LINES),
        supports = function(item)
            return item ~= nil and K.vanillaHidden() and linesOf(item) ~= nil
        end,
        collect = function(item, player, context)
            local lines = linesOf(item)
            if lines == nil then return nil end
            return K.textRows("Information", HEADING_COLOR, lines, context, LINE_COLOR)
        end,
    })
end

M.addPart({
    name = "idp-marz",
    switch = "IdpMarz",
    title = "Item Details Panel and Guns of Marz: gun information",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, the red Information block Guns of Marz adds to a gun's tooltip (ammo, rail slots, muzzle device, bayonet, and Guns of Tien's fitted parts) is gone. This shows it in Item Details Panel. Only active with both mods.",
    kind = "compat",
    all = { "ItemDetailsPanel", "GunsOfMarz" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.kinds", "marz.tooltip" },
    check = check,
    install = install,
})
