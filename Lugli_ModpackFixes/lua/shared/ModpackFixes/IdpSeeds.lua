--[[
Item Details Panel and Seed Season Indicator: whether a seed can be sown this month survives a hidden
vanilla tooltip.

What happens today. Seed Season Indicator adds season rows to a seed's vanilla tooltip
(SeedSeasonIndicator.lua): this month's status (best, in season, risky, out of season) and, with its
bad month option on, the bad months, besides water, growing time and the sowing, best and risk
months. Item Details Panel's own gardening rows already show water, growing time and the sowing,
best and risk months, but not this month's status or the bad months. With its Hide vanilla tooltip
option on, those two are gone.

What this part changes. While the vanilla tooltip is hidden, Item Details Panel shows this month's
status and, with that option on, the bad months, for the seeds Seed Season Indicator would show them
for (the player knows the plant), in a Sowing season group of its main panel, right under its own
gardening rows: green for a good month, red for a risky or wrong one.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.SeedSeason"
-- Item Details Panel colours rows by role only, from the player's palette: Seed Season Indicator's
-- green for a good month, red for a risky or wrong one.
local STATUS_ROLE = {
    best = "good",
    inseason = "good",
    risk = "bad",
    outofseason = "bad",
}
local STATUS_KEY = {
    best = "IGUI_SSI_TooltipStatus_Best",
    inseason = "IGUI_SSI_TooltipStatus_InSeason",
    risk = "IGUI_SSI_TooltipStatus_Risk",
    outofseason = "IGUI_SSI_TooltipStatus_OutOfSeason",
}

-- Seed Season Indicator's order: from the first month of a run, so Nov, Dec, Jan reads in that order.
local function monthList(months)
    local inSet = {}
    for _, m in ipairs(months) do inSet[m] = true end
    local start = 1
    for m = 1, 12 do
        local prev = (m == 1) and 12 or (m - 1)
        if inSet[m] and not inSet[prev] then
            start = m
            break
        end
    end
    local parts = {}
    for i = 0, 11 do
        local m = (start - 1 + i) % 12 + 1
        if inSet[m] then parts[#parts + 1] = getText("Farming_Month_" .. m) end
    end
    return table.concat(parts, ", ")
end

-- Seed Season Indicator's module table: local to its file, which returns it.
local ssi

local function seasonData(item, player)
    if not ssi.optTooltip:getValue() or ssi.seedLookup == nil then return nil end
    return ssi.resolveSeasonTooltipData(item, player or getPlayer())
end

local function collect(item, player, context)
    local props, status = seasonData(item, player)
    if props == nil or STATUS_KEY[status] == nil then return nil end
    local enabled = context and context.enabledFields or {}
    local rows = {}
    if enabled.ThisMonth ~= false then
        local month = getGameTime():getMonth() + 1
        rows[#rows + 1] = { id = "ThisMonth",
            label = getText("IGUI_SSI_TooltipThisMonth") .. " (" .. getText("Farming_Month_" .. month) .. ")",
            value = getText(STATUS_KEY[status]), order = 1, role = STATUS_ROLE[status] }
    end
    if enabled.BadMonth ~= false and ssi.optBadMonth:getValue() then
        local bad = props.badMonth
        rows[#rows + 1] = { id = "BadMonth", label = "Bad month",
            value = bad and monthList(bad) or getText("Farming_Tooltip_None"), order = 2,
            role = bad and "bad" or "value" }
    end
    if #rows == 0 then return nil end
    return rows
end

local function check()
    local why = K.check()
    if why ~= nil then return why end
    local ok, lib = pcall(require, "SeedSeasonIndicator")
    if not ok or type(lib) ~= "table" or type(lib.resolveSeasonTooltipData) ~= "function" then
        return "Seed Season Indicator has no resolveSeasonTooltipData"
    end
    if type(lib.optTooltip) ~= "table" or type(lib.optBadMonth) ~= "table" then
        return "Seed Season Indicator's tooltip options are missing"
    end
    ssi = lib
    return nil
end

local function install(ctx)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Seed Season Indicator (Modpack Fixes)",
        description = "Whether a seed can be sown this month and, with Seed Season Indicator's bad month option, its bad months. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "main", order = 85,
        groups = { { id = "Season", labelKey = "IGUI_LugliMPF_IdpSeason", label = "Sowing season", order = 10 } },
        fields = {
            { id = "ThisMonth", label = "This month", groupId = "Season", order = 1 },
            { id = "BadMonth", label = "Bad month", groupId = "Season", order = 2 },
        },
        supports = function(item, player)
            return item ~= nil and K.vanillaHidden() and seasonData(item, player) ~= nil
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-seeds",
    switch = "IdpSeeds",
    title = "Item Details Panel and Seed Season Indicator: this month's status",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, Seed Season Indicator's This month row (best, in season, risky or out of season) and its bad months are gone; Item Details Panel already shows the other season rows. This shows them in Item Details Panel. Only active with both mods.",
    kind = "compat",
    all = { "ItemDetailsPanel", "SeedSeasonIndicator" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.kinds", "ssi.data", "ssi.rows" },
    check = check,
    install = install,
})
