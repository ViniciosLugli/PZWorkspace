--[[
Attachments UI with CleanUI: the weapon workbench looks like CleanUI's windows.

What happens today. Attachments UI draws its workbench, part picker, preset panel and patch editor
in its own flat colours, or in NeatUI's skin when its "NeatUI" option is on. CleanUI restyles the
inventory and loot windows with its own title bar, dark background, thin border and square
buttons, so beside them the workbench looks like it belongs to another game.

What this part changes. While CleanUI's clean inventory mode is on, the three hooks Attachments UI
draws its NeatUI skin through (BA.hasNeat, BA.neatPanel, BA.neatButton) draw CleanUI's pieces
instead, at CleanUI's own tints and at the background opacities the player set in CleanUI's
options, read as they change:

  workbench window   CleanUI's title bar over Attachments UI's 52 px header band, CleanUI's main
                     background below it, the 1 px black separator between them, and CleanUI's
                     border around the body while windowed (none in fullscreen, as Attachments UI)
  picker, presets,   CleanUI's main background and border at its container opacity, with the
  patch editor       separator along the top
  buttons            CleanUI's long button (three-patch) when wider than square, its square button
                     otherwise; Attachments UI's tint, hover, pressed and disabled states kept

Attachments UI's own NeatUI option is never written. With CleanUI's clean mode off, or a CleanUI
texture not loaded yet (a nine-patch answers nil on its first request), Attachments UI draws
exactly as it does without this part. Taking the look skips Attachments UI's window border, which
also skips its resize hint and gamepad resize frame; those two are drawn back after it.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- Attachments UI's header band: `math.min(self.height, 14 + 28 + 10)` in BAWorkbench:prerender.
local HEADER_H = 14 + 28 + 10
-- How long a read of CleanUI's mode and opacities is reused: every panel and button asks per frame.
local REREAD_MS = 100
-- A button wider than this many heights takes CleanUI's long button; narrower ones its square one.
local SQUARE_MAX = 1.25
local DEFAULT_OPACITY, DEFAULT_INNER_OPACITY = 0.65, 0.9

local CUI = "media/ui/CleanUI/"
local NINE_PATHS = {
    title = CUI .. "Panel/CUI_TitleBarBG.png",
    bgL = CUI .. "Panel/MainBackground_L.png",
    bgR = CUI .. "Panel/MainBackground_R.png",
    borderL = CUI .. "Panel/MainBorder_L.png",
    borderR = CUI .. "Panel/MainBorder_R.png",
}
local BUTTON_PATHS = {
    sqBg = CUI .. "Button/SQBackground.png",
    sqBorder = CUI .. "Button/SQBorder.png",
    longBgL = CUI .. "Button/LongBackground_L.png",
    longBgM = CUI .. "Button/LongBackground_M.png",
    longBgR = CUI .. "Button/LongBackground_R.png",
    longBorderL = CUI .. "Button/LongBorder_L.png",
    longBorderM = CUI .. "Button/LongBorder_M.png",
    longBorderR = CUI .. "Button/LongBorder_R.png",
}

local function opacity(v, default)
    v = tonumber(v)
    if v == nil then return default end
    return math.max(0, math.min(1, v))
end

local function check()
    local BA = rawget(_G, "AttachmentsUI")
    local bench = rawget(_G, "BAWorkbench")
    local handleClass = rawget(_G, "BAResizeHandle")
    if type(BA) ~= "table" or type(bench) ~= "table" or type(handleClass) ~= "table" then
        return "Attachments UI's workbench is missing"
    end
    local isClean = rawget(_G, "CleanUI_isCleanInventoryUIEnabled")
    local bgOpacity = rawget(_G, "CleanUI_getBackgroundOpacity")
    local innerOpacity = rawget(_G, "CleanUI_getContainerBackgroundOpacity")
    if type(isClean) ~= "function" or type(bgOpacity) ~= "function" or type(innerOpacity) ~= "function" then
        return "CleanUI has no clean-mode or opacity reader"
    end
    if NinePatchTexture == nil or type(NeatTool) ~= "table" or type(NeatTool.ThreePatch) ~= "table" then
        return "NeatUI Framework's nine- and three-patch drawing is missing"
    end
end

local function install(ctx)
    local BA = rawget(_G, "AttachmentsUI")
    local bench = rawget(_G, "BAWorkbench")
    local handleClass = rawget(_G, "BAResizeHandle")
    local isClean = rawget(_G, "CleanUI_isCleanInventoryUIEnabled")
    local bgOpacity = rawget(_G, "CleanUI_getBackgroundOpacity")
    local innerOpacity = rawget(_G, "CleanUI_getContainerBackgroundOpacity")

    local mode = { at = nil, on = false, opacity = DEFAULT_OPACITY, inner = DEFAULT_INNER_OPACITY }
    local function cleanMode()
        local now = getTimestampMs()
        if mode.at == nil or now < mode.at or now - mode.at >= REREAD_MS then
            mode.at = now
            mode.on = isClean() == true
            if mode.on then
                mode.opacity = opacity(bgOpacity(), DEFAULT_OPACITY)
                mode.inner = opacity(innerOpacity(), DEFAULT_INNER_OPACITY)
            end
        end
        return mode.on
    end

    -- Asked every time and never kept: the engine answers nil on a path's first request and drops
    -- every handle when texture packs change. Every path is asked, so all prime on the same frame.
    local nine = {}
    local function ninePatches()
        local all = true
        for key, path in pairs(NINE_PATHS) do
            local t = NinePatchTexture.getSharedTexture(path)
            nine[key] = t
            if t == nil then all = false end
        end
        return all
    end

    local buttons = nil
    local function buttonTextures()
        if buttons ~= nil then return buttons end
        local found = {}
        for key, path in pairs(BUTTON_PATHS) do
            found[key] = getTexture(path)
            if found[key] == nil then return nil end
        end
        buttons = found
        return buttons
    end

    local function lookActive()
        return cleanMode() and ninePatches()
    end

    -- Attachments UI's own neatPanel and neatButton ask BA.hasNeat; while one of them draws in
    -- our place it must get Attachments UI's answer, not ours.
    local passing = 0
    local function asAttachmentsUI(callOriginal, ...)
        passing = passing + 1
        local ok, res = pcall(callOriginal, ...)
        passing = passing - 1
        if not ok then error(res) end
        return res
    end

    -- MainBackground and MainBorder each round one bottom corner; the two halves round both.
    local function halves(left, right, x, y, w, h, tint, alpha)
        local half = math.floor(w / 2)
        left:render(x, y, half, h, tint, tint, tint, alpha)
        right:render(x + half, y, w - half, h, tint, tint, tint, alpha)
    end

    -- ISInventoryPage:prerender's composition, with Attachments UI's header as the title bar.
    local function drawWindow(ui)
        local x, y, w, h = ui:getAbsoluteX(), ui:getAbsoluteY(), ui.width, ui.height
        local head = math.min(h, HEADER_H)
        nine.title:render(x, y, w, head, 0.6, 0.6, 0.6, 0.95)
        if h > head then
            halves(nine.bgL, nine.bgR, x, y + head, w, h - head, 0.05, mode.opacity)
            if ui.windowed then
                halves(nine.borderL, nine.borderR, x, y + head, w, h - head, 0.8, mode.opacity)
            end
        end
        ui:drawRect(0, head, w, 1, 1, 0, 0, 0)
    end

    local function drawInner(ui)
        local x, y, w, h = ui:getAbsoluteX(), ui:getAbsoluteY(), ui.width, ui.height
        halves(nine.bgL, nine.bgR, x, y, w, h, 0.05, mode.inner)
        halves(nine.borderL, nine.borderR, x, y, w, h, 0.8, mode.inner)
        ui:drawRect(0, 0, w, 1, 1, 0, 0, 0)
    end

    -- CleanUI_LongButton's states: 0.1 resting, 0.2 hovered, 0.05 pressed, a colour lit 1.2x on
    -- hover and dimmed 0.8x pressed, background at 0.8, border 0.4 grey.
    local function drawButton(ui, tex, over, tint, alpha)
        local r, g, b
        if tint ~= nil then
            local k = ui.pressed and 0.8 or over and 1.2 or 1
            r, g, b = math.min(tint.r * k, 1), math.min(tint.g * k, 1), math.min(tint.b * k, 1)
        else
            local v = ui.pressed and 0.05 or over and 0.2 or 0.1
            r, g, b = v, v, v
        end
        alpha = alpha or 1
        local w, h = ui.width, ui.height
        if w > h * SQUARE_MAX then
            local draw = NeatTool.ThreePatch.drawHorizontal
            draw(ui, 0, 0, w, h, tex.longBgL, tex.longBgM, tex.longBgR, 0.8 * alpha, r, g, b)
            draw(ui, 0, 0, w, h, tex.longBorderL, tex.longBorderM, tex.longBorderR, alpha, 0.4, 0.4, 0.4)
        else
            ui:drawTextureScaled(tex.sqBg, 0, 0, w, h, 0.8 * alpha, r, g, b)
            ui:drawTextureScaled(tex.sqBorder, 0, 0, w, h, alpha, 0.4, 0.4, 0.4)
        end
    end

    ctx.wrap(BA, "hasNeat", function(callOriginal)
        return function(...)
            if passing == 0 and lookActive() then return true end
            return callOriginal(...)
        end
    end)

    ctx.wrap(BA, "neatPanel", function(callOriginal)
        return function(ui, name, ...)
            if (name == "MainPanelBG_RoundTop" or name == "InnerPanel_BG") and lookActive() then
                if name == "MainPanelBG_RoundTop" then drawWindow(ui) else drawInner(ui) end
                return true
            end
            return asAttachmentsUI(callOriginal, ui, name, ...)
        end
    end)

    ctx.wrap(BA, "neatButton", function(callOriginal)
        return function(ui, over, tint, alpha, ...)
            local tex = cleanMode() and buttonTextures() or nil
            if tex ~= nil then
                drawButton(ui, tex, over, tint, alpha)
                return true
            end
            return asAttachmentsUI(callOriginal, ui, over, tint, alpha, ...)
        end
    end)

    -- BAWorkbench:render's resize frame and hint, which its early return for a skinned window skips.
    ctx.wrap(bench, "render", function(callOriginal)
        return function(self, ...)
            callOriginal(self, ...)
            if not self.windowed or not lookActive() then return end
            if self.baPadResize then
                for i = 1, 2 do
                    self:drawRectBorder(i, i, self.width - 2 * i, self.height - 2 * i, 1, 1, 1, 1)
                end
            end
            local handle = self.resizeHandle
            if handle and handle:getIsVisible() and (handle:isMouseOver() or handle.resizing) then
                self:drawTextRight(BA.text("ResizeHint"), self.width - handleClass.SIZE - 8,
                    self.height - self.lineH - 10, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end)
end

M.addPart({
    name = "aui-cleanui",
    switch = "AuiCleanUI",
    title = "Attachments UI: CleanUI look",
    tip = "Attachments UI's weapon workbench keeps its own flat look beside CleanUI's windows. This draws the workbench, its part picker, presets and patch editor with CleanUI's title bar, background, border and buttons, at CleanUI's opacity, while CleanUI's clean inventory is on. Only active with both mods.",
    kind = "compat",
    all = { "AttachmentsUI", "CleanUI" },
    side = "client",
    phase = "boot",
    pins = { "aui.neat", "aui.head", "aui.render", "cleanui.frame" },
    check = check,
    install = install,
})
