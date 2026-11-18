--[[
Badlands Power with Neat Rocco's UI: Badlands generators keep their names, and the battery bank
its charge, batteries and safety line, inside Neat Rocco's generator panel.

What happens today. Badlands Power names each of its generators in the vanilla Generator Info
window and gives its battery bank its own text there: stored charge, the batteries in the rack,
whether it is charging, and that it is safe indoors. Neat Rocco's UI replaces that window with its
own panel, which reads "Gas-powered Generator" in its title and above its Total for every
generator, so the Badlands names are gone. The bank shows a fuel bar and none of its own text.

What this part changes. The panel's title and its base consumption line carry Badlands Power's
name for one of its generators. For the battery bank the panel keeps its own icon and bars, the
first labelled as the bank's stored charge, and below them shows Badlands Power's bank text in the
panel's font: batteries, consumption, charging and safety. The panel prints the base line's name
itself, so that one string is answered with the Badlands name while the panel draws.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local LINE = " <LINE> "

-- Runs fn while getText answers `key` with `value`; every other key is the game's own.
local function withText(key, value, fn, ...)
    local original = getText
    getText = function(k, ...)
        if k == key then return value end
        return original(k, ...)
    end
    local ok, err = pcall(fn, ...)
    getText = original
    if not ok then error(err) end
end

-- "Stored charge:" from "Stored charge: %1%", in any language that puts the number last.
local function chargeLabel()
    local s = getText("IGUI_BLPower_BankCharge", "@@")
    local at = string.find(s, "@@", 1, true)
    if at == nil then return nil end
    local label = string.gsub(string.sub(s, 1, at - 1), "%s+$", "")
    if label == "" then return nil end
    return label
end

-- Badlands Power's bank text without the charge and condition lines the bars already show.
local function bankText(object, barred)
    local text = ISGeneratorInfoWindow.getRichText(object, true) or ""
    if not barred then return text end
    local shown = getText("IGUI_BLPower_BankCharge", math.ceil(object:getFuelPercentage())) .. LINE
        .. getText("IGUI_Generator_Condition", object:getCondition()) .. LINE
    if string.sub(text, 1, #shown) == shown then return string.sub(text, #shown + 1) end
    return text
end

-- The bank as the panel's own body sees it: stopped and outdoors, so the panel draws its icon,
-- charge and condition bars, and no fuel time, gas consumption or fume warning.
local BANK_BODY = {
    isActivated = function() return false end,
    getSquare = function() return nil end,
}

local function bankPanel(self)
    local rt = self.mpfBankText
    if rt == nil then
        rt = ISRichTextPanel:new(0, 0, 10, 10)
        rt:initialise()
        rt.background = false
        rt.blockMouseWheel = true
        rt:setMargins(0, 0, 0, 0)
        self:addChild(rt)
        self.mpfBankText = rt
    end
    return rt
end

local function renderBank(self, object, callOriginal, ...)
    local shown = self.object
    local label = chargeLabel()
    self.object = M.overlay(object, BANK_BODY)
    local ok, err
    if label ~= nil then
        ok, err = pcall(withText, "IGUI_NR_FuelLabel", label, callOriginal, self, ...)
    else
        ok, err = pcall(callOriginal, self, ...)
    end
    self.object = shown
    if not ok then error(err) end

    local rt = bankPanel(self)
    local visible = NR_CollapseUtils.isBodyVisible(self)
    rt:setVisible(visible)
    if not visible then return end
    local pad = NR_Config.padding
    rt:setX(pad)
    rt:setY(NR_Config.headerHeight + pad + NR_Config.lineHeight * 2 + pad)
    local text = bankText(object, label ~= nil)
    local width = self.width - pad * 2
    local font = NR_UIScale.getBodyFont()
    if rt.text ~= text or rt:getWidth() ~= width or rt.defaultFont ~= font then
        rt.defaultFont = font
        rt:setWidth(width)
        rt:setText(text)
        rt:paginate()
    end
    self:setHeight(rt:getY() + rt:getHeight() + pad)
end

local function check()
    local BP = BadlandsPower
    if type(BP) ~= "table" or type(BP.displayName) ~= "function" or type(BP.isBank) ~= "function" then
        return "Badlands Power has no generator names"
    end
    if type(NR_GeneratorPanel) ~= "table" or type(NR_GeneratorPanel.getWindowTitle) ~= "function"
        or type(NR_GeneratorPanel.render) ~= "function" then
        return "Neat Rocco's generator panel is missing"
    end
    if type(NR_Config) ~= "table" or type(NR_UIScale) ~= "table" or type(NR_CollapseUtils) ~= "table" then
        return "Neat Rocco's panel layout is missing"
    end
    if type(ISGeneratorInfoWindow) ~= "table" or type(ISGeneratorInfoWindow.getRichText) ~= "function"
        or type(ISRichTextPanel) ~= "table" then
        return "the Generator Info text is missing"
    end
end

local function install(ctx)
    local BP = BadlandsPower
    ctx.wrap(NR_GeneratorPanel, "getWindowTitle", function(callOriginal)
        return function(self, ...)
            local object = M.realOf(self.object)
            local name = object ~= nil and BP.displayName(object) or nil
            if name ~= nil then return name end
            return callOriginal(self, ...)
        end
    end)

    ctx.wrap(NR_GeneratorPanel, "render", function(callOriginal)
        return function(self, ...)
            local object = M.realOf(self.object)
            if object == nil or object:getObjectIndex() == -1 then return callOriginal(self, ...) end
            if BP.isBank(object) then return renderBank(self, object, callOriginal, ...) end
            if self.mpfBankText ~= nil then self.mpfBankText:setVisible(false) end
            local name = BP.displayName(object)
            if name == nil then return callOriginal(self, ...) end
            withText("IGUI_Generator_TypeGas", name, callOriginal, self, ...)
        end
    end)

    ctx.undo(function()
        for _, panel in pairs(NR_GeneratorPanel.panels or {}) do
            if panel.mpfBankText ~= nil then
                panel:removeChild(panel.mpfBankText)
                panel.mpfBankText = nil
            end
        end
    end)
end

M.addPart({
    name = "bp-neat",
    switch = "BpNeat",
    title = "Badlands Power: generator names and the battery bank in Neat Rocco's generator window",
    tip = "Neat Rocco's generator window calls every generator \"Gas-powered Generator\" and shows the Badlands battery bank as a fuel tank. This keeps the Badlands names in it, and shows the bank's stored charge, batteries, charging and safety the way Badlands Power describes them. Only active with both mods.",
    kind = "compat",
    all = { "BadlandsPower", "Neat_Rocco" },
    side = "client",
    phase = "boot",
    pins = { "bp.name", "bp.bankhead", "nr.render", "nr.size" },
    check = check,
    install = install,
})
