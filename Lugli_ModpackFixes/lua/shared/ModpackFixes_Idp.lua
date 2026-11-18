--[[
Shared helpers for the parts that bring other mods' tooltip information into Item Details Panel.

Item Details Panel (ItemDetailsPanel) draws its own panel beside the item tooltip and, with its
Hide vanilla tooltip option on, instead of it. Hidden means the vanilla ISToolTipInv.render chain
never runs, so every row another mod draws into that tooltip is gone. These parts hand the same
information to Item Details Panel through its public provider API (ItemDetailsPanel.API, v1), and
only while the vanilla tooltip is hidden, so nothing shows twice.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local K = M.idp or {}
M.idp = K

-- A callback under the part's breaker: silent while the part is off, and its first error opens it.
local function guarded(ctx, fn)
    return function(...)
        if not ctx.enabled() then return nil end
        local ok, res = pcall(fn, ...)
        if ok then return res end
        M.trip(ctx.def, res)
        return nil
    end
end

-- Functions of an item that name the translation key the vanilla tooltip would show for it instead
-- of its own (Improvised Silencers swaps one in while it draws); the first non-nil answer wins.
K.tooltipKeyHooks = K.tooltipKeyHooks or {}

-- Adds a hook for the life of the part.
function K.addTooltipKeyHook(ctx, fn)
    local hooks = K.tooltipKeyHooks
    local hook = guarded(ctx, fn)
    hooks[#hooks + 1] = hook
    ctx.undo(function()
        for i = #hooks, 1, -1 do
            if hooks[i] == hook then table.remove(hooks, i) end
        end
    end)
end

function K.api()
    local idp = ItemDetailsPanel
    return type(idp) == "table" and idp.API or nil
end

-- nil when Item Details Panel's API can take a provider, or why it cannot.
function K.check()
    local api = K.api()
    if type(api) ~= "table" or api.ready ~= true or api.VERSION ~= 1 then
        return "Item Details Panel's API (v1) is not ready"
    end
    if type(api.registerProvider) ~= "function" or type(api.unregisterProvider) ~= "function"
        or type(api.hasCapability) ~= "function" then
        return "Item Details Panel's API has no provider registration"
    end
    if type(ItemDetailsPanel.option) ~= "function" then
        return "Item Details Panel has no option reader"
    end
    return nil
end

-- The vanilla tooltip is hidden right now, by Item Details Panel's own rule (ISToolTipInv.render in
-- UI/DetailsPanel.lua): the panel on, Hide vanilla tooltip on, and the display active, which its
-- show-vanilla key turns off while held (UI/DisplayActivation.lua).
function K.vanillaHidden()
    local idp = ItemDetailsPanel
    local okEnabled, enabled = pcall(idp.option, "Enabled")
    if not okEnabled or not enabled then return false end
    local ok, on = pcall(idp.option, "HideVanillaTooltip")
    if not ok or on ~= true then return false end
    if type(idp.displayActivated) == "function" then
        local okActive, active = pcall(idp.displayActivated)
        if okActive and active == false then return false end
    end
    return true
end

-- Registers a provider and takes it back when the part is undone. A refusal stands the part down.
function K.register(ctx, def)
    local api = K.api()
    def.supports = guarded(ctx, def.supports)
    def.collect = guarded(ctx, def.collect)
    local ok, why = api.registerProvider(def)
    if not ok then
        ctx.standDown("Item Details Panel refused provider " .. tostring(def.id) .. ": " .. tostring(why))
        return false
    end
    ctx.undo(function() api.unregisterProvider(def.id) end)
    return true
end

-- Declares a heading and Line1..LineN as the rows of an independent provider.
function K.lineFields(count)
    local fields = { { id = "Heading", label = "Heading", order = 0 } }
    for i = 1, count do
        fields[#fields + 1] = { id = "Line" .. i, label = "Line " .. i, order = i }
    end
    return fields
end

-- Text lines under a heading, as the independent panel draws them. Item Details Panel draws every
-- independent provider in one panel and heads only the first with its provider name, so each block
-- carries its own heading row; a heading equal to the provider name would be dropped.
function K.textRows(heading, headingColor, lines, context, color)
    local rows = {}
    local enabled = context and context.enabledFields or {}
    if heading ~= nil and enabled.Heading ~= false then
        rows[1] = { id = "Heading", label = heading, value = heading, order = 0,
            presentation = { kind = "header", labelColor = headingColor } }
    end
    for i = 1, #lines do
        local id = "Line" .. i
        if enabled[id] ~= false then
            local presentation = { kind = "label" }
            if color ~= nil then presentation.labelColor = color end
            rows[#rows + 1] = { id = id, label = lines[i], value = lines[i], presentation = presentation, order = i }
        end
    end
    return rows
end

-- Splits text on line breaks, dropping blank lines; nil when nothing is left.
function K.splitLines(text, limit)
    if type(text) ~= "string" then return nil end
    local lines = {}
    for line in string.gmatch(text, "[^\r\n]+") do
        line = string.gsub(line, "^%s+", "")
        line = string.gsub(line, "%s+$", "")
        if line ~= "" then
            lines[#lines + 1] = line
            if #lines >= limit then break end
        end
    end
    if #lines == 0 then return nil end
    return lines
end
