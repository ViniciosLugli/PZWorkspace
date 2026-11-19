--[[
    NoteWindow
    A clue note's own window, on NeatUI chrome: the note's name as its title and its one page,
    read only. It replaces both of vanilla's ways into a clue note: the inventory's double-click,
    which reads any Literature as a book (ISInventoryPane:doContextualDblClick, ISReadABook), and
    the context menu's Read Note, which opens the writable journal (ISUIWriteJournal). Every other
    item keeps vanilla's double-click and menu. One window per note; asked again it comes to the
    front. Like vanilla's Read Note it needs light and a survivor who can read.
]]

require "ISUI/ISPanelJoypad"
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Codes"
require "LugliDeadMansStash/Neat"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local N = M.neat
    local PART = "NoteWindow"

    local FONT = N.FONT

    LugliDMSNoteWindow = ISPanelJoypad:derive("LugliDMSNoteWindow")
    LugliDMSNoteBody = NIScrollView:derive("LugliDMSNoteBody")
    N.movable(LugliDMSNoteWindow, "note", ISPanelJoypad)

    --- The open windows, by note item.
    local open = {}

    local function measure(s, font)
        local ok, w = pcall(function() return getTextManager():MeasureStringX(font or FONT, s) end)
        if ok and type(w) == "number" then return w end
        return #s * 6
    end

    local function padDrives(playerNum)
        return JoypadState ~= nil and JoypadState.players[playerNum + 1] ~= nil
    end

    local function isEsc(key)
        return Keyboard ~= nil and key == Keyboard.KEY_ESCAPE
    end

    local function playerNumOf(player)
        local ok, n = pcall(function() return player:getPlayerNum() end)
        if ok and type(n) == "number" then return n end
        return 0
    end

    local function isClueNote(item)
        if item == nil then return false end
        local ok, gate = pcall(M.noteGateOf, item)
        return ok and gate ~= nil
    end
    M.isClueNote = isClueNote

    --- Why the survivor cannot read a note now, as vanilla's Read Note words it, or nil when they can.
    function M.noteRefusal(player)
        local okDark, dark = pcall(function() return player:tooDarkToRead() end)
        if okDark and dark == true then return M.T("ContextMenu_TooDark", "Too dark to read.") end
        local okIll, ill = pcall(function() return player:hasTrait(CharacterTrait.ILLITERATE) end)
        if okIll and ill == true then return M.T("ContextMenu_Illiterate", "Don't know how to read.") end
        return nil
    end

    local function noteTitle(item)
        local ok, s = pcall(function() return item:getName() end)
        if ok and type(s) == "string" and s ~= "" then return s end
        return M.T("UI_LugliDMS_Note", "Note")
    end

    local function noteText(item)
        local ok, s = pcall(function() return item:seePage(1) end)
        if ok and type(s) == "string" then return s end
        return ""
    end

    --- The page's text as the lines that fit `width`, its own line breaks kept.
    local function pageLines(text, width)
        local out, pos = {}, 1
        while true do
            local s, e = string.find(text, "\n", pos, true)
            local para = string.sub(text, pos, (s or (#text + 1)) - 1)
            if string.find(para, "%S") == nil then
                out[#out + 1] = ""
            else
                for _, line in ipairs(N.wrap(para, width, FONT)) do out[#out + 1] = line end
            end
            if s == nil then break end
            pos = e + 1
        end
        while #out > 1 and out[#out] == "" do out[#out] = nil end
        if #out == 1 and out[1] == "" then out[1] = M.T("UI_LugliDMS_NoteBlank", "The page is blank.") end
        return out
    end

    -- ---- the layout ---------------------------------------------------------------------------

    local function metrics()
        local k = N.metrics()
        local u = k.u
        return { fh = k.fh, head = k.head, pad = k.pad, inset = u(12), scroll = k.scroll, read = u(380) }
    end

    --- The body's lines at `inner` width, and the height the body takes.
    function LugliDMSNoteWindow:build(inner)
        local m = self.m
        self.lines = pageLines(self.text, inner - m.inset * 2)
        self.box = { x = m.pad, y = m.pad, w = inner, h = m.inset * 2 + #self.lines * m.fh }
        return m.pad + self.box.h + m.pad
    end

    --- A reading width, wider for a title that needs it, never wider or taller than the screen. A
    --- body taller than the room left scrolls in its own strip.
    function LugliDMSNoteWindow:layout()
        local m = self.m
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local want = math.max(m.read, measure(self.title, N.TITLE_FONT) + m.head - m.pad)
        local inner = math.min(want, sw - m.pad * 2)
        local contentH = self:build(inner)
        local scrolls = m.head + contentH > sh
        if scrolls and inner + m.pad * 2 + m.scroll > sw then
            inner = sw - m.pad * 2 - m.scroll
            contentH = self:build(inner)
        end
        self.contentH = contentH
        self.bodyH = scrolls and (sh - m.head) or contentH
        local w = inner + m.pad * 2 + (scrolls and m.scroll or 0)
        self.titleShown = N.fitTitle(self.title, w - m.pad - m.head)
        return w, m.head + self.bodyH
    end

    function LugliDMSNoteWindow:new(player, item)
        local o = ISPanelJoypad:new(0, 0, 1, 1)
        setmetatable(o, self)
        self.__index = self
        o.background = false
        o.moveWithMouse = true
        o.player, o.item = player, item
        o.playerNum = playerNumOf(player)
        o.m = metrics()
        o.title = noteTitle(item)
        o.text = noteText(item)
        local w, h = o:layout()
        o:setWidth(w)
        o:setHeight(h)
        N.place(o, "note", (getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2)
        return o
    end

    function LugliDMSNoteWindow:createChildren()
        ISPanelJoypad.createChildren(self)
        self.body = LugliDMSNoteBody:new(self)
        self.body:initialise()
        self:addChild(self.body)
        self.closeBtn = N.closeButton(self.width, self.m.head, self, self.close)
        self:addChild(self.closeBtn)
        self:setWantKeyEvents(true)
    end

    function LugliDMSNoteWindow:close()
        self:setVisible(false)
        self:removeFromUIManager()
        if padDrives(self.playerNum) then
            pcall(setJoypadFocus, self.playerNum, nil)
        end
        if open[self.item] == self then open[self.item] = nil end
    end

    --- True keeps Esc from opening the pause menu under the window.
    function LugliDMSNoteWindow:isKeyConsumed(key)
        return isEsc(key)
    end

    function LugliDMSNoteWindow:onKeyRelease(key)
        if isEsc(key) and self:isVisible() then self:close() end
    end

    function LugliDMSNoteWindow:onJoypadDown(button)
        if button == Joypad.AButton or button == Joypad.BButton then self:close() end
    end

    function LugliDMSNoteWindow:onJoypadDirUp() self.body:onMouseWheel(-1) end
    function LugliDMSNoteWindow:onJoypadDirDown() self.body:onMouseWheel(1) end

    --- The wheel scrolls a body that scrolls from the title bar too: left to vanilla it zoomed the
    --- map there.
    function LugliDMSNoteWindow:onMouseWheel(del)
        if self.body == nil or self.contentH <= self.bodyH then return false end
        return self.body:onMouseWheel(del)
    end

    function LugliDMSNoteWindow:prerender()
        local p = self.player
        local ok, dead = pcall(function() return p:isDead() end)
        if ok and dead == true then
            self:close()
            return
        end
        local m = self.m
        N.window(self, 0, 0, self.width, self.height, m.head)
        N.title(self, self.titleShown, m.pad, m.head)
    end

    -- ---- the scrolling body -------------------------------------------------------------------

    function LugliDMSNoteBody:new(win)
        local o = NIScrollView.new(self, 0, win.m.head, win.width, win.bodyH)
        o.win = win
        o:setScrollSensitivity(win.m.fh * 2)
        o:setScrollHeight(win.contentH)
        return o
    end

    function LugliDMSNoteBody:prerender()
        NIScrollView.prerender(self)
        local win, m = self.win, self.win.m
        local b = win.box
        N.inner(self, b.x, b.y, b.w, b.h, 0.7)
        for i, line in ipairs(win.lines) do
            self:drawText(line, b.x + m.inset, b.y + m.inset + (i - 1) * m.fh, N.text.r, N.text.g, N.text.b, 1, FONT)
        end
    end

    -- ---- opening it ---------------------------------------------------------------------------

    --- Show `item`'s window. Asked again for the same note it comes to the front. Nil for an item
    --- that is no clue note.
    function M.openNote(player, item)
        if not isClueNote(item) then return nil end
        local num = playerNumOf(player)
        local cur = open[item]
        if cur ~= nil and cur:isVisible() then
            cur:bringToTop()
            if padDrives(num) then pcall(setJoypadFocus, num, cur) end
            return cur
        end
        local win = LugliDMSNoteWindow:new(player, item)
        win:initialise()
        win:instantiate()
        win:addToUIManager()
        win:setVisible(true)
        N.sound("UIActivateTab")
        open[item] = win
        if padDrives(num) then pcall(setJoypadFocus, num, win) end
        return win
    end

    --- Read the note if the survivor can, else say why over their head.
    function M.readNote(player, item)
        local refusal = M.noteRefusal(player)
        if refusal ~= nil then
            pcall(function() HaloTextHelper.addBadText(player, refusal) end)
            return nil
        end
        return M.openNote(player, item)
    end

    -- ---- the double-click ---------------------------------------------------------------------

    -- Only the note test is guarded: whatever it answers, any other item reaches vanilla's own
    -- double-click.
    local wrappedDblClick = nil
    function M.wrapNoteDblClick()
        if ISInventoryPane == nil or type(ISInventoryPane.doContextualDblClick) ~= "function" then
            M.defect(PART, "ISInventoryPane.doContextualDblClick is missing: a clue note reads as a book", true)
            return false
        end
        if ISInventoryPane.doContextualDblClick == wrappedDblClick then return true end
        local original = ISInventoryPane.doContextualDblClick
        wrappedDblClick = function(self, item)
            if isClueNote(item) then
                local player = getSpecificPlayer(self.player)
                if player ~= nil then
                    M.readNote(player, item)
                    return
                end
            end
            return original(self, item)
        end
        ISInventoryPane.doContextualDblClick = wrappedDblClick
        return true
    end
    -- After every other mod has had its turn at the class: CleanUI replaces the whole pane.
    M.addHandler(PART, "OnGameStart", M.wrapNoteDblClick)

    -- ---- the context menu ---------------------------------------------------------------------

    --- Does vanilla's option `opt` read a clue note: Read Note on one, or the book reading of a
    --- selection holding one.
    local function vanillaReadsNote(opt)
        local menu = ISInventoryPaneContextMenu
        if opt == nil or opt.onSelect == nil or menu == nil then return false end
        if opt.onSelect == menu.onWriteSomething then return isClueNote(opt.target) end
        if opt.onSelect == menu.onLiteratureItems and type(opt.target) == "table" then
            for _, it in ipairs(ISInventoryPane.getActualItems(opt.target)) do
                if isClueNote(it) then return true end
            end
        end
        return false
    end

    local function onFillInventoryObjectContextMenu(playerNum, context, items)
        local player = getSpecificPlayer(playerNum)
        if player == nil or type(items) ~= "table" then return end
        local note = nil
        for _, it in ipairs(ISInventoryPane.getActualItems(items)) do
            if isClueNote(it) then
                note = it
                break
            end
        end
        if note == nil then return end

        -- Removed by name, and only when that name is this option's, so a namesake stays.
        for i = #context.options, 1, -1 do
            local opt = context.options[i]
            if vanillaReadsNote(opt) and context:getOptionFromName(opt.name) == opt then
                context:removeOptionByName(opt.name)
            end
        end

        local opt = context:addOptionOnTop(M.T("ContextMenu_LugliDMS_ReadNote", "Read note"), player, M.openNote, note)
        if opt == nil then return end
        opt.itemForTexture = note
        local refusal = M.noteRefusal(player)
        if refusal ~= nil then
            opt.notAvailable = true
            local okTip, tip = pcall(function() return ISInventoryPaneContextMenu.addToolTip() end)
            if okTip and tip ~= nil then
                tip.description = refusal
                opt.toolTip = tip
            end
        end
    end

    M.addTeardown(PART, function()
        for _, win in pairs(open) do win:close() end
    end)
    if M.addHandler(PART, "OnFillInventoryObjectContextMenu", onFillInventoryObjectContextMenu) ~= nil then
        M.status(PART, true)
    end
end
