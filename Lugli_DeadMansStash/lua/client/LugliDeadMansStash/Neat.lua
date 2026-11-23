--[[
    Neat
    The mod's windows are drawn from the NeatUI Framework, which mod.info requires: its nine-patch
    panels and title bar, its three-patch button plate, its square button for the title bar's
    close, its tick and cross icons, and its scroll view. This file is the one place that names a
    framework texture; a window asks it for a button or a panel and draws from the palette here.
    The same kit Lugli - Power Grid uses, cut to what this mod draws, so the two look like one
    family. Any texture that is not there draws flat instead.
]]

require "ISUI/ISButton"
require "LugliDeadMansStash/Core"
require "neatui_framework/neattool/neattool_3patch"
require "neatui_framework/neattool/neattool_truncatetext"
require "neatui_framework/scrollview/niscrollbar"
require "neatui_framework/scrollview/niscrollview"
require "neatui_framework/ui/ni_squarebutton"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local N = {}
    local PART = "Neat"
    M.neat = N

    --- The nine-patch panels.
    N.TEX = {
        titleBar   = "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png",
        panelFlat  = "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png",
        innerPanel = "media/ui/NeatUI/DefaultPanel/InnerPanel_BG.png",
    }

    --- The plain textures: the button's three slices, the icons, and the vanilla disc a dial, a
    --- pip and a light are drawn with.
    N.ART = {
        pillLeft  = "media/ui/NeatUI/Button/Button_FULL_L.png",
        pillMid   = "media/ui/NeatUI/Button/Button_FULL_M.png",
        pillRight = "media/ui/NeatUI/Button/Button_FULL_R.png",
        tick      = "media/ui/NeatUI/ICON/Icon_True.png",
        cross     = "media/ui/NeatUI/ICON/Icon_False.png",
        down      = "media/ui/NeatUI/ICON/Icon_DownArrow.png",
        disc      = "media/ui/circle.png",
        keyL      = "media/ui/LugliDMS/Hint/KeyCap_L.png",
        keyM      = "media/ui/LugliDMS/Hint/KeyCap_M.png",
        keyR      = "media/ui/LugliDMS/Hint/KeyCap_R.png",
    }

    --- The Neat family's palette (NeatLockpicking, NeatUI Mechanics): one orange accent, grey
    --- everywhere else. `amber` is the accent's older name, kept for the files that use it.
    N.accent    = { r = 0.95, g = 0.50, b = 0.10 }
    N.amber     = N.accent
    N.text      = { r = 0.92, g = 0.92, b = 0.92 }
    N.textDim   = { r = 0.60, g = 0.60, b = 0.60 }
    N.textFaint = { r = 0.42, g = 0.42, b = 0.42 }
    N.line      = { r = 0.40, g = 0.40, b = 0.40 }
    N.good      = { r = 0.45, g = 0.85, b = 0.40 }
    N.bad       = { r = 0.95, g = 0.42, b = 0.30 }

    N.TITLE_TINT = 0.08
    N.PANEL_TINT = 0.15
    --- Opaque: at 0.9 whatever window is under this one reads through its rows.
    N.PANEL_A    = 1.0
    N.INNER_TINT = 0.11
    --- A button's grey at rest, under the pointer, held, and when it cannot be pressed; and the
    --- dark of a bar's empty track.
    N.BTN_IDLE, N.BTN_HOVER, N.BTN_PRESSED, N.BTN_OFF = 0.20, 0.30, 0.10, 0.12
    N.TRACK = 0.12

    --- `px` at the 19 pixel Small font, scaled to a font `fontH` pixels tall. The game's font size
    --- option takes that font to 26, 33 or 38 pixels, and a gap that stays at its 19 pixel size
    --- beside text twice as tall reads as a mistake.
    function N.scale(px, fontH)
        return math.floor(fontH * px / 19 + 0.5)
    end

    --- THE UI IS AS LARGE AS THE GAME'S FONT SIZE OPTION MAKES IT (Core.getOptionFontSizeReal picks
    --- the Small font, 16 to 38 px). The fonts are swapped only by a Lua reset, which reloads these
    --- files, so a height read when a window opens is the live one.
    N.FONT = UIFont.Small

    --- A title bar's font, a size up from the body's as in every Neat window.
    N.TITLE_FONT = UIFont.Medium or UIFont.Small

    function N.fontH()
        return getTextManager():getFontHeight(N.FONT)
    end

    function N.titleH()
        return getTextManager():getFontHeight(N.TITLE_FONT)
    end

    --- The shared sizes at a font `fontH` pixels tall: `u(px)` scales any other size the same way.
    --- `head` is a title bar, tall enough for the title font; `pad` a window's margin, `gap` the
    --- space between its blocks, `btnH`/`btnPad` a button's height and the room beside its label,
    --- `icon` a tick or cross on a line of text, `scroll` the strip a scroll bar stands in (the
    --- framework's bar is 0.6 of the font height), and `bar` a progress bar's height.
    function N.metrics(fontH)
        local fh = fontH or N.fontH()
        local function u(px) return N.scale(px, fh) end
        local th = N.titleH()
        return { fh = fh, u = u, th = th, head = math.max(u(30), th + u(12)), pad = u(18), gap = u(8),
                 btnH = u(26), btnPad = u(24), icon = u(12), scroll = u(12), bar = u(10) }
    end

    --- A window's title, in the title font, centred in a bar `head` tall.
    function N.title(el, s, x, head)
        el:drawText(s, x, math.floor((head - N.titleH()) / 2), N.text.r, N.text.g, N.text.b, 1, N.TITLE_FONT)
    end

    --- `text` cut to `width` in the title font.
    function N.fitTitle(text, width)
        return N.fit(text, width, N.TITLE_FONT)
    end

    function N.sound(name)
        pcall(function() getSoundManager():playUISound(name) end)
    end

    local textures = {}

    --- A framework texture by its N.ART name. A lookup that comes back empty is asked again on
    --- the next draw, never remembered.
    function N.art(name)
        local t = textures[name]
        if t == nil then
            t = getTexture(N.ART[name])
            textures[name] = t
        end
        return t
    end

    --- The mod's own art, media/ui/LugliDMS/<key>.png with key "Folder/Name" (tools/dms-ui-art.py).
    --- An empty lookup is asked again on the next draw, as N.art's.
    N.UI_ROOT = "media/ui/LugliDMS/"
    local uiTextures = {}
    function N.tex(key)
        local path = N.UI_ROOT .. key .. ".png"
        local t = uiTextures[path]
        if t == nil then
            t = getTexture(path)
            uiTextures[path] = t
        end
        return t
    end

    --- Each piece's size in the art's own pixels, twice its size at UI scale 1. A key stands for
    --- itself and for every "<key>_<suffix>" without an entry of its own (Keypad/Seg for Seg_0
    --- .. Seg_Ghost). tools/dms-ui-art.py --check holds this table to the PNGs.
    N.UI_SIZE = {
        ["Keypad/Faceplate"] = { 300, 400 }, ["Keypad/Key"] = { 72, 56 }, ["Keypad/Lcd_Backlight"] = { 196, 72 },
        ["Keypad/Led"] = { 40, 40 }, ["Keypad/Seg"] = { 32, 56 },
        ["Dial/Plate"] = { 360, 360 }, ["Dial/Face"] = { 256, 256 }, ["Dial/Index"] = { 40, 48 },
        ["Dial/Window"] = { 64, 80 }, ["Dial/Turn"] = { 64, 64 },
        ["Hint/Mouse"] = { 40, 48 },
        ["Work/Drill_Backdrop"] = { 560, 184 }, ["Work/Drill_Bit"] = { 260, 48 }, ["Work/Drill_Chips"] = { 48, 32 },
        ["Work/Gauge_Frame"] = { 520, 32 }, ["Work/Gauge_Fill"] = { 512, 24 },
        ["Work/Seam_Backdrop"] = { 560, 184 }, ["Work/Seam_Cut"] = { 24, 160 }, ["Work/Spark"] = { 48, 48 },
        ["Work/Torch_Tip"] = { 120, 56 },
        ["Work/Lid_Backdrop"] = { 560, 184 }, ["Work/Lid"] = { 420, 56 }, ["Work/Crowbar"] = { 260, 64 },
        ["Work/Nails_Backdrop"] = { 560, 184 }, ["Work/Nail_In"] = { 40, 40 }, ["Work/Nail_Out"] = { 40, 96 },
        ["Work/Hammer_Claw"] = { 160, 96 },
        ["Work/Pins_Backdrop"] = { 560, 184 }, ["Work/Pin_Key"] = { 20, 56 }, ["Work/Pin_Driver"] = { 20, 48 },
        ["Work/Spring"] = { 20, 56 }, ["Work/Pick"] = { 360, 40 }, ["Work/Tension"] = { 120, 40 },
        ["Work/Shackle_Backdrop"] = { 560, 184 }, ["Work/Shackle_Bar"] = { 140, 120 },
        ["Work/Shackle_Cut"] = { 140, 120 }, ["Work/Cutter_Jaws"] = { 220, 120 },
        ["Work/Stethoscope"] = { 120, 120 },
        ["Work/Wires_Backdrop"] = { 560, 184 }, ["Work/Wire"] = { 24, 150 }, ["Work/Clip"] = { 48, 48 },
    }

    --- A piece's native width and height, or nil for one the table does not know.
    function N.size(key)
        local k = key
        while k ~= nil do
            local s = N.UI_SIZE[k]
            if s ~= nil then return s[1], s[2] end
            local cut = string.match(k, "^(.*)_[^_/]+$")
            k = cut
        end
        return nil
    end

    --- One of the mod's textures over x, y, w, h, tinted r, g, b; nothing when it is missing.
    function N.draw(el, key, x, y, w, h, a, r, g, b)
        local t = N.tex(key)
        if t == nil or w <= 0 or h <= 0 then return false end
        el:drawTextureScaled(t, x, y, w, h, a or 1, r or 1, g or 1, b or 1)
        return true
    end

    --- A piece at its native size times `s`, its top left at the art pixel px, py of a backdrop
    --- whose own top left is ox, oy on the element: every anchor in tools/dms-ui-art.py's
    --- docstring goes straight in. `c` tints it, `a` fades it.
    function N.piece(el, key, ox, oy, s, px, py, a, c)
        local w, h = N.size(key)
        if w == nil then return false end
        local x0, y0 = math.floor(ox + px * s + 0.5), math.floor(oy + py * s + 0.5)
        local x1, y1 = math.floor(ox + (px + w) * s + 0.5), math.floor(oy + (py + h) * s + 0.5)
        return N.draw(el, key, x0, y0, x1 - x0, y1 - y0, a, c and c.r, c and c.g, c and c.b)
    end

    --- Run draw() with everything outside x, y, w, h cut away: a piece shown in part (a gauge's
    --- fill, a cut growing down a seam) is drawn whole and cropped, never squashed.
    function N.crop(el, x, y, w, h, draw)
        if w <= 0 or h <= 0 then return end
        el:setStencilRect(x, y, w, h)
        local ok, err = pcall(draw)
        el:clearStencilRect()
        if not ok then error(err) end
    end

    local function ninePatch(path)
        if NinePatchTexture == nil then return nil end
        local ok, np = pcall(NinePatchTexture.getSharedTexture, path)
        if ok then return np end
        return nil
    end

    --- A panel, in the element's own coordinates. getSharedTexture returns nil on the FIRST call
    --- for a path, so every path is asked for once at boot (below), and the flat branch is what
    --- a frame draws if a texture is still not there.
    ---
    --- IT SCROLLS WITH THE ELEMENT ON BOTH BRANCHES. drawRect adds the element's scroll itself
    --- (UIElement.DrawTextureScaledCol); the nine-patch renders at screen coordinates and has to
    --- be told.
    function N.panel(el, path, x, y, w, h, tint, alpha)
        if w <= 0 or h <= 0 then return end
        local np = ninePatch(path)
        if np ~= nil then
            local ok = pcall(function()
                np:render(el:getAbsoluteX() + x + el:getXScroll(), el:getAbsoluteY() + y + el:getYScroll(),
                    w, h, tint, tint, tint, alpha or N.PANEL_A)
            end)
            if ok then return end
        end
        el:drawRect(x, y, w, h, alpha or N.PANEL_A, tint, tint, tint)
        el:drawRectBorder(x, y, w, h, 0.55, N.line.r, N.line.g, N.line.b)
    end

    function N.window(el, x, y, w, h, headerH)
        N.panel(el, N.TEX.titleBar, x, y, w, headerH, N.TITLE_TINT, 1.0)
        N.panel(el, N.TEX.panelFlat, x, y + headerH, w, h - headerH, N.PANEL_TINT, N.PANEL_A)
    end

    function N.inner(el, x, y, w, h, alpha)
        N.panel(el, N.TEX.innerPanel, x, y, w, h, N.INNER_TINT, alpha or 0.7)
    end

    --- One of the framework's icons, `size` square, in colour `c`.
    function N.icon(el, name, x, y, size, c, alpha)
        local t = N.art(name)
        if t == nil then return end
        el:drawTextureScaled(t, x, y, size, size, alpha or 1, c.r, c.g, c.b)
    end

    --- The framework's pill outline over x, y, w, h in grey `r, g, b`. False when its textures are
    --- not there, so the caller draws flat.
    function N.pill(el, x, y, w, h, a, r, g, b)
        local left, mid, right = N.art("pillLeft"), N.art("pillMid"), N.art("pillRight")
        if left == nil or mid == nil or right == nil then return false end
        return NeatTool.ThreePatch.drawHorizontal(el, x, y, w, h, left, mid, right, a, r, g, b) == true
    end

    --- A solid fill in the pill's shape, round ends of radius h / 2: one rect per run of rows with
    --- the same inset. The pill texture is an outline over a faint dark inside, so a filled pill
    --- (an accent button, a bar's fill) needs this under it.
    function N.fillPill(el, x, y, w, h, a, r, g, b)
        if w <= 0 or h <= 0 then return end
        local rad = math.min(h, w) / 2
        local runStart, runInset = nil, nil
        local function flush(upTo)
            if runStart ~= nil then el:drawRect(x + runInset, y + runStart, w - runInset * 2, upTo - runStart, a, r, g, b) end
        end
        for i = 0, h - 1 do
            local dy = math.abs(i + 0.5 - h / 2)
            local inset = 0
            if dy > h / 2 - rad then
                local d = dy - (h / 2 - rad)
                inset = math.floor(rad - math.sqrt(math.max(0, rad * rad - d * d)) + 0.5)
            end
            inset = math.max(0, math.min(inset, math.floor(w / 2) - 1))
            if inset ~= runInset then
                flush(i)
                runStart, runInset = i, inset
            end
        end
        flush(h)
    end

    --- A progress bar: the pill as a dark track, and a solid pill of colour `c` (the accent unless
    --- given) clipped to `frac` of it by a stencil, so the fill keeps its round left end and stops
    --- square where the work did. Without the pill textures it draws flat.
    ---
    --- The stencil is set in the element's unscrolled coordinates (UIElement.setStencilRect adds
    --- the absolute position only) and kept inside the element, so in a scroll view it never opens
    --- a hole outside the view's own clip; once cleared it is painted back to the level it was
    --- (UIElement.repaintStencilRect), or whatever the element drew after it there would vanish.
    function N.progress(el, x, y, w, h, frac, c)
        if w <= 0 or h <= 0 then return end
        c = c or N.accent
        local fw = math.floor(w * M.clamp(M.finite(frac) or 0, 0, 1) + 0.5)
        if not N.pill(el, x, y, w, h, 0.9, N.TRACK, N.TRACK, N.TRACK) then
            el:drawRect(x, y, w, h, 0.9, N.TRACK, N.TRACK, N.TRACK)
            if fw > 0 then el:drawRect(x, y, fw, h, 1, c.r, c.g, c.b) end
            return
        end
        if fw <= 0 then return end
        if fw >= w then
            N.fillPill(el, x, y, w, h, 0.9, c.r, c.g, c.b)
            N.pill(el, x, y, w, h, 1, c.r, c.g, c.b)
            return
        end
        local sx, sy = x + el:getXScroll(), y + el:getYScroll()
        local x0, y0 = math.max(0, sx), math.max(0, sy)
        local x1, y1 = math.min(el:getWidth(), sx + fw), math.min(el:getHeight(), sy + h)
        if x1 <= x0 or y1 <= y0 then return end
        el:setStencilRect(x0, y0, x1 - x0, y1 - y0)
        N.fillPill(el, x, y, w, h, 0.9, c.r, c.g, c.b)
        N.pill(el, x, y, w, h, 1, c.r, c.g, c.b)
        el:clearStencilRect()
        el:repaintStencilRect(x0, y0, x1 - x0, y1 - y0)
    end

    --- One pip of a row: a disc in `c` when `filled`, a dim one when not.
    function N.pip(el, x, y, size, filled, c)
        local t = N.art("disc")
        local col = filled and c or N.line
        local a = filled and 1 or 0.5
        if t ~= nil then
            el:drawTextureScaled(t, x, y, size, size, a, col.r, col.g, col.b)
        else
            el:drawRect(x, y, size, size, a, col.r, col.g, col.b)
        end
    end

    --- The controller's focus: an accent pill around a pill-shaped thing, else an accent frame.
    function N.focusRing(el, x, y, w, h, pill)
        local c = N.accent
        if pill and N.pill(el, x - 2, y - 2, w + 4, h + 4, 1, c.r, c.g, c.b) then return end
        el:drawRectBorder(x - 2, y - 2, w + 4, h + 4, 1, c.r, c.g, c.b)
        el:drawRectBorder(x - 1, y - 1, w + 2, h + 2, 1, c.r, c.g, c.b)
    end

    -- ---- buttons --------------------------------------------------------------------------------

    --- A text button on the framework's three-patch pill, grey as every Neat button is: lighter
    --- under the pointer, darker while held, dim when it cannot be pressed. Only an ACTIVE button
    --- (setActive: the one action that is ready, a key held lit) is filled with the accent. The
    --- controller's focus rings it in the accent.
    LugliDMSButton = ISButton:derive("LugliDMSButton")

    function LugliDMSButton:new(x, y, w, h, title, target, onclick)
        local o = ISButton.new(self, x, y, w, h, title, target, onclick)
        o:setDisplayBackground(false)
        o.active = false
        return o
    end

    function LugliDMSButton:setActive(v)
        self.active = v == true
    end

    --- The grey or accent this button is drawn in now, as r, g, b.
    function LugliDMSButton:tint()
        if not self.enable then return N.BTN_OFF, N.BTN_OFF, N.BTN_OFF end
        if self.active then
            local c, k = N.accent, 1
            if self.pressed then k = 0.8 elseif self:isMouseOver() then k = 1.15 end
            return math.min(1, c.r * k), math.min(1, c.g * k), math.min(1, c.b * k)
        end
        local g = N.BTN_IDLE
        if self.pressed then g = N.BTN_PRESSED elseif self:isMouseOver() then g = N.BTN_HOVER end
        return g, g, g
    end

    function LugliDMSButton:prerender()
        if self.joypadFocused then N.focusRing(self, 0, 0, self.width, self.height, true) end
        local r, g, b = self:tint()
        if self.active and self.enable then N.fillPill(self, 0, 0, self.width, self.height, 0.85, r, g, b) end
        if not N.pill(self, 0, 0, self.width, self.height, 1, r, g, b) then
            self:drawRect(0, 0, self.width, self.height, 0.9, r, g, b)
            self:drawRectBorder(0, 0, self.width, self.height, 1, N.line.r, N.line.g, N.line.b)
        end
        self:updateTooltip()
    end

    function LugliDMSButton:render()
        local tm = getTextManager()
        local c = self.enable and N.text or N.textDim
        local a = self.enable and 1 or 0.6
        self:drawText(self.title, math.floor((self.width - tm:MeasureStringX(self.font, self.title)) / 2),
            math.floor((self.height - tm:getFontHeight(self.font)) / 2), c.r, c.g, c.b, a, self.font)
    end

    --- The close button of a title bar `head` pixels tall on a window `width` wide: the
    --- framework's square button with its cross, inset from the bar's top and right edge.
    function N.closeButton(width, head, target, onclick)
        local inset = math.floor(head * 0.15 + 0.5)
        local size = head - inset * 2
        local btn = NI_SquareButton:new(width - inset - size, inset, size, N.art("cross"), target, onclick)
        btn:setIconSizeRatio(0.5)
        btn:setTooltip(M.T("UI_LugliDMS_Close", "Close"))
        return btn
    end

    --- Put that button back in the corner of a window that is now `width` wide. It is inset from
    --- the right edge by what it is from the top.
    function N.placeClose(btn, width)
        btn:setX(width - btn:getWidth() - btn:getY())
    end

    -- ---- text that has to fit -------------------------------------------------------------------

    --- How many entries of `s` the character at `i` takes. Kahlua hands a string over as
    --- characters, so it is one whatever its code; only a string that did arrive as UTF-8 bytes
    --- has a lead byte FOLLOWED BY its continuation bytes (128 to 191), and only that is kept.
    local function charLen(s, i)
        local b = string.byte(s, i)
        if b < 192 or b > 247 then return 1 end
        local len = (b >= 240) and 4 or (b >= 224) and 3 or 2
        for k = i + 1, i + len - 1 do
            local tail = string.byte(s, k)
            if tail == nil or tail < 128 or tail > 191 then return 1 end
        end
        return len
    end

    local function chars(s)
        local out, i, n = {}, 1, #s
        while i <= n do
            local len = charLen(s, i)
            out[#out + 1] = string.sub(s, i, i + len - 1)
            i = i + len
        end
        return out
    end

    --- A controls bar: each entry a keyboard key's name on a key cap ({ key = "Enter" }) or the
    --- game's own controller glyph ({ pad = "AButton", a Joypad.Texture name }) or a mouse
    --- ({ mouse = "Mouse_Wheel", Hint/Mouse_Left, _Wheel or _Drag }), then its `label`,
    --- left to right from x on a row `h` tall. An entry that would pass `maxW` and every one after it
    --- is left out, never squeezed. Returns the width drawn.
    function N.hints(el, entries, x, y, h, maxW)
        local tm = getTextManager()
        local fh = N.fontH()
        local inner, between = N.scale(5, fh), N.scale(16, fh)
        local ty = y + math.floor((h - fh) / 2)
        local cx = x
        for _, e in ipairs(entries) do
            local glyph = e.pad ~= nil and Joypad ~= nil and Joypad.Texture ~= nil and Joypad.Texture[e.pad] or nil
            local glyphW = h
            if e.mouse ~= nil then
                glyph = N.tex("Hint/" .. e.mouse)
                local mw, mh = N.size("Hint/Mouse")
                glyphW = math.floor(h * mw / mh + 0.5)
            end
            if glyph == nil then glyphW = math.max(h, tm:MeasureStringX(N.FONT, tostring(e.key)) + N.scale(12, fh)) end
            local w = glyphW + inner + tm:MeasureStringX(N.FONT, e.label)
            if cx + w - x > maxW then break end
            if glyph ~= nil then
                el:drawTextureScaled(glyph, cx, y, glyphW, h, 1, 1, 1, 1)
            else
                local l, m, r = N.art("keyL"), N.art("keyM"), N.art("keyR")
                if l == nil or m == nil or r == nil
                    or NeatTool.ThreePatch.drawHorizontal(el, cx, y, glyphW, h, l, m, r, 1, 1, 1, 1) ~= true then
                    el:drawRect(cx, y, glyphW, h, 1, 0.78, 0.78, 0.76)
                end
                local s = tostring(e.key)
                el:drawText(s, cx + math.floor((glyphW - tm:MeasureStringX(N.FONT, s)) / 2), ty - N.scale(1, fh),
                    0.13, 0.13, 0.14, 1, N.FONT)
            end
            el:drawText(e.label, cx + glyphW + inner, ty, N.textDim.r, N.textDim.g, N.textDim.b, 1, N.FONT)
            cx = cx + w + between
        end
        return math.max(0, cx - between - x)
    end

    --- `text` as the lines that fit `width` in `font`. Breaks at spaces, and inside a run with
    --- none: Chinese, Japanese and Korean are written without them. Never returns no lines, so a
    --- caller can count them for its height.
    function N.wrap(text, width, font)
        local tm = getTextManager()
        local function fits(s) return tm:MeasureStringX(font, s) <= width end
        local out, line = {}, ""
        for word in string.gmatch(tostring(text), "%S+") do
            local try = (line == "") and word or (line .. " " .. word)
            if line ~= "" and not fits(try) then
                out[#out + 1] = line
                line = word
            else
                line = try
            end
            if not fits(line) then
                local run = ""
                for _, ch in ipairs(chars(line)) do
                    if run ~= "" and not fits(run .. ch) then
                        out[#out + 1] = run
                        run = ch
                    else
                        run = run .. ch
                    end
                end
                line = run
            end
        end
        if line ~= "" or #out == 0 then out[#out + 1] = line end
        return out
    end

    --- `text` cut to `width` with an ellipsis, for a line that cannot wrap: a title beside its
    --- close button, a button's label.
    function N.fit(text, width, font)
        return NeatTool.truncateText(text, width, font, "...")
    end

    -- WHERE EACH KIND OF WINDOW WAS LAST LEFT (user review 2026-11-19: windows stuck in place). A
    -- window the survivor drags opens there the next time, for any box, this session and the next:
    -- one line `kind x y` each in a file in the profile's Lua folder.
    N.PLACES_FILE = "LugliDeadMansStash_windows.ini"
    local places = nil

    local function loadPlaces()
        if places ~= nil then return places end
        places = {}
        if getFileReader == nil then return places end
        local ok, reader = pcall(getFileReader, N.PLACES_FILE, false)
        if not ok or reader == nil then return places end
        local line = reader:readLine()
        while line ~= nil do
            local kind, x, y = string.match(line, "^(%S+) (%-?%d+) (%-?%d+)$")
            if kind ~= nil then places[kind] = { x = tonumber(x), y = tonumber(y) } end
            line = reader:readLine()
        end
        reader:close()
        return places
    end

    local function savePlaces()
        if getFileWriter == nil then return end
        local ok, writer = pcall(getFileWriter, N.PLACES_FILE, true, false)
        if not ok or writer == nil then return end
        for kind, p in pairs(places) do writer:write(kind .. " " .. p.x .. " " .. p.y .. "\n") end
        writer:close()
    end

    --- Put `el` where its kind of window was last left, else at x, y; on screen either way.
    function N.place(el, kind, x, y)
        local p = loadPlaces()[kind]
        if p ~= nil then x, y = p.x, p.y end
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        el:setX(math.max(0, math.min(math.floor(x), sw - el:getWidth())))
        el:setY(math.max(0, math.min(math.floor(y), sh - el:getHeight())))
    end

    --- Keep where `el` stands now for its kind of window.
    function N.remember(el, kind)
        loadPlaces()[kind] = { x = math.floor(el:getX()), y = math.floor(el:getY()) }
        savePlaces()
    end

    --- Make a window class draggable, remembering where its windows are dropped as `kind`.
    --- `base` is the class it derives from (ISPanel, ISPanelJoypad), whose drag it keeps.
    function N.movable(cls, kind, base)
        local up, upOutside = base.onMouseUp, base.onMouseUpOutside
        function cls:onMouseUp(x, y)
            local was = self.moving
            local r = up(self, x, y)
            if was then N.remember(self, kind) end
            return r
        end
        function cls:onMouseUpOutside(x, y)
            local was = self.moving
            local r = upOutside(self, x, y)
            if was then N.remember(self, kind) end
            return r
        end
    end
    M.addTeardown(PART, function() places = nil end)

    -- PROJECT VIEWPOINT (Workshop 3809306528). Its 3D view holds the mouse for looking and frees it
    -- only for a fixed list of vanilla popups or while a visible window has mouse capture
    -- (UIManager.isModalVisible, read by viewpoint.FP). So a window here takes capture while that
    -- view is on, as vanilla's modal dialogs do, and its buttons can be clicked. The iso view never
    -- captures.
    local viewpointBroken = false
    local function viewOn() return Viewpoint.Loot.viewOn() end

    function N.viewpointView()
        if viewpointBroken or Viewpoint == nil or Viewpoint.Loot == nil or Viewpoint.Loot.viewOn == nil then
            return false
        end
        local ok, on = pcall(viewOn)
        if not ok then
            viewpointBroken = true
            M.defect(PART, "Viewpoint.Loot.viewOn threw, windows no longer free its cursor: " .. tostring(on))
            return false
        end
        return on == true
    end

    --- From a window's prerender: hold mouse capture exactly while the 3D view is on and `wanted`.
    function N.followView(el, wanted)
        local want = wanted ~= false and N.viewpointView()
        if (el.lugliDMSCaptured == true) == want then return end
        el.lugliDMSCaptured = want
        el:setCapture(want)
    end

    --- Ask for every texture once, so the first-call nil of a nine-patch and the load of a plain
    --- texture happen at boot and not on the frame a survivor opens a window.
    local function prime()
        for _, path in pairs(N.TEX) do ninePatch(path) end
        for name in pairs(N.ART) do N.art(name) end
    end

    M.addHandler(PART, "OnGameBoot", prime)
    M.addHandler(PART, "OnGameStart", prime)
    M.status(PART, true)
end
