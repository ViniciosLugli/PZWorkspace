--[[
Item Details Panel and Improvised Silencers: suppressor noise reduction and condition survive a
hidden vanilla tooltip.

What happens today. Improvised Silencers draws the tooltip itself for its suppressors and for a gun
that has one fitted (ISIL_DurabilityTooltip.lua): it swaps in its own description while the vanilla
rows draw, then adds a Noise Reduction row and, for suppressors that wear out, a Suppressor
Condition bar. With Item Details Panel's Hide vanilla tooltip option on, none of it shows.

What this part changes. While the vanilla tooltip is hidden, Item Details Panel shows the
suppressor's name, its noise reduction and its condition bar, read from Improvised Silencers' own
functions and coloured as it colours them, and the description block shows Improvised Silencers'
text for its suppressors.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.Suppressor"
local DESCRIPTION_KEY = "Tooltip_ISIL_DynamicSuppressor"
local WHITE = { 1, 1, 1, 1 }

local function suppressorOf(item)
    if instanceof(item, "WeaponPart") and ISILSilencerStats.isOurSuppressor(item) then return item end
    if instanceof(item, "HandWeapon") then
        local part = item:getWeaponPart("Canon")
        if part ~= nil and ISILSilencerStats.isOurSuppressor(part) then return part end
    end
    return nil
end

-- Improvised Silencers' bar colours: highlight green over half, amber over a quarter, red below.
local function barColor(fraction)
    if fraction > 0.50 then
        local hc = getCore():getGoodHighlitedColor()
        return { hc:getR(), hc:getG(), hc:getB(), 1 }
    end
    if fraction > 0.25 then return { 0.95, 0.75, 0.10, 1 } end
    return { 0.90, 0.15, 0.10, 1 }
end

local function label(key)
    return (string.gsub(getText(key), "%s*:%s*$", ""))
end

local function collect(item, player, context)
    local suppressor = suppressorOf(item)
    if suppressor == nil then return nil end
    local reduction = ISILSilencerStats.getNoiseReduction(suppressor:getFullType())
    if reduction == nil then return nil end
    local enabled = context and context.enabledFields or {}
    local rows = {}
    if enabled.Heading ~= false then
        local name = suppressor:getDisplayName()
        rows[#rows + 1] = { id = "Heading", label = name, value = name, order = 0,
            presentation = { kind = "header" } }
    end
    if enabled.NoiseReduction ~= false then
        rows[#rows + 1] = { id = "NoiseReduction", label = label("Tooltip_ISIL_NoiseReduction"),
            value = tostring(reduction) .. "%", order = 1,
            presentation = { kind = "keyvalue", labelColor = WHITE, valueColor = WHITE } }
    end
    if enabled.Condition ~= false and ISILSilencerStats.isDurabilityTracked(suppressor) then
        local remaining, maximum = ISILSilencerDurability.peek(suppressor)
        if type(remaining) == "number" and type(maximum) == "number" and maximum > 0 then
            local fraction = math.max(0, math.min(1, remaining / maximum))
            rows[#rows + 1] = { id = "Condition", label = label("Tooltip_SuppressorCondition"),
                value = tostring(math.floor(remaining + 0.5)) .. " / " .. tostring(math.floor(maximum + 0.5)),
                progress = fraction, order = 2,
                presentation = { kind = "progress", labelColor = WHITE, barColor = barColor(fraction) } }
        end
    end
    return rows
end

local function check()
    local why = K.check()
    if why ~= nil then return why end
    if type(ISILSilencerStats) ~= "table" or type(ISILSilencerStats.isOurSuppressor) ~= "function"
        or type(ISILSilencerStats.getNoiseReduction) ~= "function"
        or type(ISILSilencerStats.isDurabilityTracked) ~= "function" then
        return "Improvised Silencers' stats functions are missing"
    end
    if type(ISILSilencerDurability) ~= "table" or type(ISILSilencerDurability.peek) ~= "function" then
        return "Improvised Silencers' durability functions are missing"
    end
    return nil
end

local function install(ctx)
    K.addTooltipKeyHook(ctx, function(item)
        if instanceof(item, "WeaponPart") and ISILSilencerStats.isOurSuppressor(item) then return DESCRIPTION_KEY end
        return nil
    end)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Improvised Silencers suppressor (Modpack Fixes)",
        description = "Improvised Silencers' noise reduction and condition bar, for a suppressor or a gun with one fitted. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "independent", order = 70,
        fields = {
            { id = "Heading", label = "Suppressor name", order = 0 },
            { id = "NoiseReduction", label = "Noise reduction", order = 1 },
            { id = "Condition", label = "Suppressor condition", order = 2 },
        },
        supports = function(item)
            return item ~= nil and K.vanillaHidden() and suppressorOf(item) ~= nil
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-silencer",
    switch = "IdpSilencer",
    title = "Item Details Panel and Improvised Silencers: suppressor stats",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, Improvised Silencers' noise reduction, suppressor condition bar and suppressor description are gone, for the suppressor and for a gun with one fitted. This shows them in Item Details Panel. Only active with both mods.",
    kind = "compat",
    all = { "ItemDetailsPanel", "ImprovisedSilencers" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.kinds", "isil.tooltip" },
    check = check,
    install = install,
})
