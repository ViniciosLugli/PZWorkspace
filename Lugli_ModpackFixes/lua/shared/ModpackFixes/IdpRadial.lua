--[[
Item Details Panel and Smart Radial Menu: a radial slice's extra lines survive a hidden vanilla
tooltip.

What happens today. While a Smart Radial Menu slice is highlighted, the item tooltip it opens ends
with the slice's own coloured lines (SRMOverlay.lua: what the slice will do, and its key hints),
drawn into the vanilla tooltip. With Item Details Panel's Hide vanilla tooltip option on, the
panel shows instead and those lines are gone.

What this part changes. While the vanilla tooltip is hidden, Item Details Panel shows the same
lines, in the same colours, for as long as Smart Radial Menu has them set for that player.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.RadialMenu"
local MAX_LINES = 8
local DEFAULT_COLOR = { r = 1, g = 0.65, b = 0, a = 1 }

-- Smart Radial Menu's overlay class: local to SRMOverlay.lua, which returns it.
local overlay

local function extraLines(player)
    player = player or getPlayer()
    if player == nil then return nil end
    local extra = overlay.playerExtraTooltipText[player:getPlayerNum()]
    if type(extra) ~= "table" or extra.text == nil or type(extra.coloredLines) ~= "table" then return nil end
    if #extra.coloredLines == 0 then return nil end
    return extra.coloredLines
end

local function collect(item, player, context)
    local lines = extraLines(player)
    if lines == nil then return nil end
    local enabled = context and context.enabledFields or {}
    local rows = {}
    if enabled.Heading ~= false then
        local heading = getText("IGUI_LugliMPF_IdpRadial")
        rows[#rows + 1] = { id = "Heading", label = heading, value = heading, order = 0,
            presentation = { kind = "header" } }
    end
    for i = 1, math.min(#lines, MAX_LINES) do
        local line, id = lines[i], "Line" .. i
        if enabled[id] ~= false and type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
            local c = type(line.color) == "table" and line.color or DEFAULT_COLOR
            rows[#rows + 1] = { id = id, label = line.text, value = line.text, order = i,
                presentation = { kind = "label", labelColor = { c.r or 1, c.g or 1, c.b or 1, c.a or 1 } } }
        end
    end
    if #rows <= 1 then return nil end
    return rows
end

local function check()
    local why = K.check()
    if why ~= nil then return why end
    local ok, lib = pcall(require, "SRMOverlay")
    if not ok or type(lib) ~= "table" or type(lib.playerExtraTooltipText) ~= "table" then
        return "Smart Radial Menu's tooltip text table is missing"
    end
    overlay = lib
    return nil
end

local function install(ctx)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Smart Radial Menu (Modpack Fixes)",
        description = "The extra lines a highlighted Smart Radial Menu slice adds to its item tooltip. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "independent", order = 60,
        fields = K.lineFields(MAX_LINES),
        supports = function(item, player)
            return item ~= nil and K.vanillaHidden() and extraLines(player) ~= nil
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-radial",
    switch = "IdpRadial",
    title = "Item Details Panel and Smart Radial Menu: slice hints",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, the coloured lines a Smart Radial Menu slice adds to its item tooltip are gone. This shows them in Item Details Panel. Only active with both mods.",
    kind = "compat",
    all = { "ItemDetailsPanel", "SmartRadialMenu" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.kinds", "srm.extra" },
    check = check,
    install = install,
})
