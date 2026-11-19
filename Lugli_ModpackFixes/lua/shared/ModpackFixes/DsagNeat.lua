--[[
Daily Report Journal with Neat Rocco's UI: the journal's window is drawn as a NeatUI window.

What happens today. Daily Report Journal draws its window in the game's vanilla style: a black
frame with a plain title bar, flat grey tab buttons, black panels with thin borders, square buttons
and ISScrollBar arrows. Every other window of the pack is NeatUI's (NeatUI Mechanics and Equipment,
Neat Crafting and Building, and Neat Rocco's UI for the game's own windows): a rounded body, a
header with the title and icon buttons, accent-lined tabs, pill buttons and a slim scroll thumb. The
journal is the one window that looks different.

What this part changes. The window is restyled the way Neat Rocco restyles the game's own
ISCollapsableWindow windows (NR_MediaInfo, NR_RadioWindow: NR_BaseCW), and its header, body, resize
handle and scroll bars are Neat Rocco's own:

  header          NR_Header over the title bar: the title, a collapse button and a close button.
                  The collapse button drives the mod's own pin and collapse, so the saved pinned
                  choice, the roll-up when the mouse leaves and the peek over the header are the
                  mod's. The vanilla title buttons stay hidden.
  body            Neat Rocco's body background, drawn as the window's background. A collapsed window
                  draws its header only.
  resize handle   NR_ResizeWidget, in place of the vanilla corner and bottom handles.
  scroll bars     NR_ScrollingList.applyNeatStyle on each panel's scroll bar: the NeatUI thumb, in
                  place of the ISScrollBar drawing. The bar keeps its place, size and clicks.
  tabs            drawn with NeatUI Framework textures, as NeatUI Mechanics draws its own: a 3-patch
                  tab with an accent line under the open one, a rule under the strip.
  buttons         Neat Rocco's 3-patch pill (NR_RadioSkin.skinButton's shades); the reset button
                  keeps a red pill.
  day list        rows as Neat Rocco's lists draw them: a separator under each, the accent under
                  the selected one, a tint under the mouse; the mod still writes the labels. A
                  rule divides the list from the report text or note editor beside it.
  text, combos    the note and biography editors and the chart's combo boxes take Neat Rocco's
                  own skins (NR_RadioSkin.skinTextEntry, skinComboBox).
  panels          the list and text panels keep their place and scrolling, with their own black
                  background and border made clear so the NeatUI body shows through. The
                  portrait's frame is a separator-coloured line.

The mod's layout, tabs, texts and charts are untouched. The title bar height is Neat Rocco's header
height, which the mod's layout already reads from the window. Undoing the part (a fault, or the
sandbox switch) puts back the vanilla frame, backgrounds, borders, scroll bar drawing and handles,
and takes the header and the handle out of the window.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local TAB = "media/ui/NeatUI/DefaultPanel/CategoryText_"
local FIELD = "media/ui/NeatUI/Button/Button_FULL_"
local ICON_EXPANDED = "media/ui/NeatUI/ICON/Icon_DownArrow.png"
local ICON_COLLAPSED = "media/ui/NeatUI/ICON/Icon_RightArrow.png"
local ACCENT = { r = 0.95, g = 0.55, b = 0.15 }
local ACCENT_SOFT = { r = 0.95, g = 0.70, b = 0.40 }
local TEXT = { r = 0.92, g = 0.92, b = 0.92 }
local TEXT_DIM = { r = 0.60, g = 0.60, b = 0.60 }

-- The mod's own names: an absent one is skipped, a panel it adds later keeps the vanilla look
-- (its scroll bar is still found, by the bar it carries).
local PANELS = { "datas", "rPanel", "medalPanel", "infoPanel", "bodyPanel", "miscPanel", "graphPanel" }
local BUTTONS = { "closeBtn", "noteSaveBtn", "exportBtn", "clearBtn" }
local DANGER_BUTTONS = { clearBtn = true }
local ENTRIES = { "noteBig", "bioBox" }
local COMBOS = { "variableSelect", "rangeSelect", "granularitySelect" }
local VANILLA_TITLE_BUTTONS = { "closeButton", "collapseButton", "pinButton", "infoButton" }

local function check()
    if type(dSAG) ~= "table" or type(dSAG.ReportWindow) ~= "table" then return "Daily Report Journal's window is not loaded" end
    local window = dSAG.ReportWindow
    for _, name in ipairs({ "initialise", "prerender", "layout", "collapse", "pin", "close" }) do
        if type(window[name]) ~= "function" then return "Daily Report Journal's window has no " .. name end
    end
    local need = {
        { "NR_Config", NR_Config, "headerHeight" }, { "NR_BaseCW", NR_BaseCW, "createHeader" },
        { "NR_ScrollingList", NR_ScrollingList, "applyNeatStyle" }, { "NR_ResizeWidget", NR_ResizeWidget, "create" },
        { "NeatTool", NeatTool and NeatTool.ThreePatch, "drawHorizontal" },
        { "NR_Config", NR_Config, "separatorColor" }, { "NR_RadioSkin", NR_RadioSkin, "skinTextEntry" },
        { "NR_RadioSkin", NR_RadioSkin, "skinComboBox" },
    }
    for i = 1, #need do
        local name, module, member = need[i][1], need[i][2], need[i][3]
        if type(module) ~= "table" or module[member] == nil then return "Neat Rocco's UI has no " .. name .. "." .. member end
    end
    for _, member in ipairs({ "initBase", "prerenderBody" }) do
        if type(NR_BaseCW[member]) ~= "function" then return "Neat Rocco's UI has no NR_BaseCW." .. member end
    end
    return nil
end

local sets = {}

local function set3(base)
    local set = sets[base]
    if set == nil then
        local left, middle, right = getTexture(base .. "L.png"), getTexture(base .. "M.png"), getTexture(base .. "R.png")
        if left == nil or middle == nil or right == nil then return nil end
        set = { left = left, middle = middle, right = right }
        sets[base] = set
    end
    return set
end

local function draw3(ui, base, x, y, w, h, alpha, r, g, b)
    if w <= 0 or h <= 0 then return end
    g, b = g or r, b or r
    local set = set3(base)
    if not (set ~= nil and NeatTool.ThreePatch.drawHorizontal(ui, x, y, w, h, set.left, set.middle, set.right, alpha, r, g, b)) then
        ui:drawRect(x, y, w, h, alpha * 0.5, r, g, b)
    end
end

local function drawRule(ui, x, y, w, h)
    local sc = NR_Config.separatorColor
    ui:drawRect(x, y, w, h, sc.a, sc.r, sc.g, sc.b)
end

local function shown(element)
    return type(element) == "table" and element:getIsVisible()
end

-- A 3-patch tab under each tab button (the buttons sit in the tab panel), an accent line under the
-- open one, and the label colours the buttons draw their own text with.
local function drawTabs(window)
    local panel = window.tabPanel
    if not shown(panel) then return end
    drawRule(window, 0, panel:getY() + panel:getHeight() - 1, window:getWidth(), 1)
    for _, id in ipairs(window.tabOrder or {}) do
        local button = window.tabButtons[id]
        if button ~= nil then
            local x, y = panel:getX() + button:getX(), panel:getY() + button:getY()
            local w, h = button:getWidth(), button:getHeight()
            local active, over = window.currentTab == id, button:isMouseOver()
            if active then
                draw3(window, TAB, x, y, w, h, 0.95, 0.26)
                window:drawRect(x + 2, y + h - 2, w - 4, 2, 1, ACCENT.r, ACCENT.g, ACCENT.b)
            elseif over then
                draw3(window, TAB, x, y, w, h, 0.7, 0.18)
            end
            local color = active and ACCENT_SOFT or (over and TEXT or TEXT_DIM)
            button.textColor = { r = color.r, g = color.g, b = color.b, a = 1 }
        end
    end
end

-- A rule between the day list and the column beside it: the report text or the note editor.
local function drawColumnRule(window)
    local list = window.datas
    if not shown(list) then return end
    local beside = shown(window.rPanel) and window.rPanel or window.noteBig
    if not shown(beside) then return end
    drawRule(window, math.floor((list:getX() + list:getWidth() + beside:getX()) / 2), list:getY(), 1, list:getHeight())
end

-- Sets table[key] = value and remembers what to put back.
local function setField(saved, table_, key, value)
    saved[#saved + 1] = { table_, key, rawget(table_, key) }
    table_[key] = value
end

-- Neat Rocco's button (NR_RadioSkin.skinButton): a 3-patch pill whose shade shows hover, press and
-- disabled. The reset button keeps the mod's red, so it still reads as the dangerous one.
local function skinButton(button, saved, danger)
    setField(saved, button, "prerender", function(b)
        local shade = 0.40
        if b.enable == false then
            shade = 0.22
        elseif b.pressed then
            shade = 0.28
        elseif b:isMouseOver() then
            shade = 0.60
        end
        if danger then
            draw3(b, FIELD, 0, 0, b.width, b.height, 1, shade * 1.6, shade * 0.45, shade * 0.45)
        else
            draw3(b, FIELD, 0, 0, b.width, b.height, 1, shade)
        end
        if b.joypadFocused then b:drawRectBorder(0, 0, b.width, b.height, 1, 0.9, 0.9, 0.9) end
    end)
end

-- The day list's rows as Neat Rocco draws list rows (NR_LiteraturePanel): a separator under each
-- row, with the accent for the selected one and a faint tint under the mouse. The mod's own row
-- drawing still writes the label; its per-row box and orange fill are left out.
local function skinRows(list, saved)
    local drawRow = list.doDrawItem
    local labelOnly = setmetatable({ drawRect = function() end, drawRectBorder = function() end }, { __index = list })
    setField(saved, list, "doDrawItem", function(self, y, item, alt)
        local h = self.itemheight
        local top = y + self:getYScroll()
        if top + h >= 0 and top < self.height then
            local w = self:getWidth()
            if self.selected == item.index then
                self:drawRect(0, y, w, h - 1, 0.22, ACCENT.r, ACCENT.g, ACCENT.b)
            elseif self.mouseoverselected == item.index and self:isMouseOver() then
                self:drawRect(0, y, w, h - 1, 0.06, 1, 1, 1)
            end
            drawRule(self, 0, y + h - 1, w, 1)
        end
        return drawRow(labelOnly, y, item, alt)
    end)
end

local function clear(saved, color)
    if type(color) == "table" then setField(saved, color, "a", 0) end
end

local function restyle(window, saved, cleanups)
    setField(saved, window, "drawFrame", window.drawFrame)
    setField(saved, window, "background", window.background)
    NR_BaseCW.initBase(window)
    NR_BaseCW.createHeader(window)
    local header = window.header
    cleanups[#cleanups + 1] = function() window:removeChild(header) end
    window.minimumWidth = math.max(window.minimumWidth or 0, header:getMinimumWidth())

    -- Neat Rocco's own handle in place of the vanilla corner and bottom ones.
    for _, name in ipairs({ "resizeWidget", "resizeWidget2" }) do
        local handle = window[name]
        if type(handle) == "table" then
            handle:setVisible(false)
            cleanups[#cleanups + 1] = function() handle:setVisible(window.resizable == true) end
        end
    end
    window.mpfGrip = NR_ResizeWidget.create(window, function(target, w, h)
        target:setWidth(w)
        target:setHeight(h)
    end)
    local grip = window.mpfGrip
    cleanups[#cleanups + 1] = function() window:removeChild(grip) end

    clear(saved, window.tabPanel.backgroundColor)
    clear(saved, window.tabPanel.borderColor)
    for _, name in ipairs(PANELS) do
        local panel = window[name]
        if type(panel) == "table" then
            clear(saved, panel.backgroundColor)
            clear(saved, panel.borderColor)
            if panel.drawBorder ~= nil then setField(saved, panel, "drawBorder", false) end
        end
    end
    -- switchTab hands each tab button a new background colour, so the background is switched off
    -- rather than made clear; drawTabs draws the tabs.
    for _, button in pairs(window.tabButtons or {}) do setField(saved, button, "displayBackground", false) end
    for _, name in ipairs(BUTTONS) do
        if type(window[name]) == "table" then skinButton(window[name], saved, DANGER_BUTTONS[name] == true) end
    end
    for _, name in ipairs(ENTRIES) do
        local entry = window[name]
        if type(entry) == "table" then
            setField(saved, entry, "backgroundColor", entry.backgroundColor)
            setField(saved, entry, "borderColor", entry.borderColor)
            local font = entry.font
            NR_RadioSkin.skinTextEntry(entry)
            cleanups[#cleanups + 1] = function() entry:setFont(font) end
        end
    end
    for _, name in ipairs(COMBOS) do
        local combo = window[name]
        if type(combo) == "table" then
            setField(saved, combo, "backgroundColor", combo.backgroundColor)
            setField(saved, combo, "borderColor", combo.borderColor)
            NR_RadioSkin.skinComboBox(combo)
        end
    end
    if type(window.datas) == "table" and type(window.datas.doDrawItem) == "function" then skinRows(window.datas, saved) end
    if type(window.avatar) == "table" then
        setField(saved, window.avatar, "render", function(avatar)
            local sc = NR_Config.separatorColor
            avatar:drawRectBorder(0, 0, avatar.width, avatar.height, sc.a, sc.r, sc.g, sc.b)
        end)
    end
    for _, child in pairs(window.children or {}) do
        local bar = type(child) == "table" and child.vscroll or nil
        if type(bar) == "table" then
            setField(saved, bar, "render", rawget(bar, "render"))
            NR_ScrollingList.applyNeatStyle(bar)
        end
    end
end

-- NR_Header's width and the handle's corner follow the window.
local function fit(window)
    local header = window.header
    if header == nil then return end
    header:setWidth(window.width)
    header:calculateLayout(window.width, NR_Config.headerHeight)
    local grip = window.mpfGrip
    if grip ~= nil then
        grip:setX(window.width - NR_Config.resizeSize)
        grip:setY(window.height - NR_Config.resizeSize)
    end
end

-- Vanilla's collapse and pin put their buttons back; the header carries those. The header's collapse
-- button shows whether the window is pinned open, as NR_CollapseUtils draws it for Neat Rocco's own.
local function syncHeader(window)
    for _, name in ipairs(VANILLA_TITLE_BUTTONS) do
        local button = window[name]
        if shown(button) then button:setVisible(false) end
    end
    local button = window.header ~= nil and window.header.collapseButton or nil
    local pinned = window.pin ~= false
    if button ~= nil and window.mpfPinnedShown ~= pinned then
        window.mpfPinnedShown = pinned
        button:setIcon(getTexture(pinned and ICON_EXPANDED or ICON_COLLAPSED))
        button:setActive(pinned)
    end
end

local function install(ctx)
    local Window = dSAG.ReportWindow
    local styled = {}
    local added = { "titleBarHeight", "getWindowTitle", "onClickCollapse", "_onHeaderHover" }

    -- What NR_Header and the mod's layout ask of the window (the NR_BaseCW contract).
    function Window:titleBarHeight() return NR_Config.headerHeight end
    function Window:getWindowTitle() return self.title or "" end
    function Window:onClickCollapse()
        if self.pin == false then Window.pin(self) else Window.collapse(self) end
    end
    function Window:_onHeaderHover() self:uncollapse() end

    ctx.undo(function()
        for i = #styled, 1, -1 do
            local entry = styled[i]
            for j = #entry.cleanups, 1, -1 do pcall(entry.cleanups[j]) end
            for j = #entry.saved, 1, -1 do
                local saved = entry.saved[j]
                saved[1][saved[2]] = saved[3]
            end
            entry.window.header, entry.window.mpfGrip, entry.window.mpfPinnedShown = nil, nil, nil
        end
        styled = {}
        for i = 1, #added do Window[added[i]] = nil end
    end)

    ctx.wrap(Window, "initialise", function(callOriginal)
        return function(self, ...)
            local results = { callOriginal(self, ...) }
            local entry = { window = self, saved = {}, cleanups = {} }
            styled[#styled + 1] = entry
            restyle(self, entry.saved, entry.cleanups)
            fit(self)
            return unpack(results)
        end
    end)
    ctx.wrap(Window, "layout", function(callOriginal)
        return function(self, ...)
            local results = { callOriginal(self, ...) }
            fit(self)
            return unpack(results)
        end
    end)
    ctx.wrap(Window, "prerender", function(callOriginal)
        return function(self, ...)
            local results = { callOriginal(self, ...) }
            syncHeader(self)
            self._bodyShown = not self.isCollapsed
            NR_BaseCW.prerenderBody(self)
            if not self.isCollapsed then
                drawTabs(self)
                drawColumnRule(self)
            end
            return unpack(results)
        end
    end)
end

M.addPart({
    name = "dsag-neat",
    switch = "DsagNeat",
    title = "Daily Report Journal with Neat Rocco's UI",
    tip = "Daily Report Journal is drawn in the game's plain style, the one window in the pack that does not look like the NeatUI ones. With this on its window is drawn as Neat Rocco draws the game's own windows: a NeatUI header with collapse and close buttons, the NeatUI body, resize handle and scroll thumb, accent-lined tabs, pill buttons, Neat list rows with a divider, and Neat Rocco's editors and combo boxes. The journal's own layout, texts and charts are unchanged. Only active with Daily Report Journal, Neat Rocco's UI and the NeatUI Framework.",
    kind = "compat",
    all = { "2858201402/dailystatisticsandgains", "Neat_Rocco", "NeatUI_Framework" },
    side = "client",
    phase = "boot",
    pins = { "dsag.init", "dsag.drawdatas", "nr.radioskin", "nr.basecw", "nr.scroll", "nr.resize", "nr.headercw", "vanilla.collapsewin", "vanilla.collapsepre" },
    check = check,
    install = install,
})
