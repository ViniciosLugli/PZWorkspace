require "LugliAchievements/Neat"

local M = LugliAchievements
local PART = "Achievements window"

-- Measured once. Every dimension below is a multiple of one of these.
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)

local MIN_ZOOM, MAX_ZOOM = 1, 4

-- The INDEX is what gets saved: append freely, never reorder.
local SORTS = { "default", "name", "progress", "done", "tier" }

--- What a player who has never touched the dropdown sees. By NAME, so reordering SORTS above
--- cannot silently change the default.
local DEFAULT_SORT = 1
for i = 1, #SORTS do
    if SORTS[i] == "done" then DEFAULT_SORT = i end
end

-- The font already grows with the zoom and the art is measured in font heights, so this scales
-- something that has already grown: hence the gentle steps. 3 and 4 share the Large font, so
-- their step is the only thing separating them.
local ART_BASE = 2.6
local ART_SCALE = { 1.0, 1.1, 1.25, 1.5 }

-- PZ's font ladder stops at Large, so past 2x only the geometry keeps growing.
local FONTS = {
    [1] = { body = UIFont.Small,  head = UIFont.Medium, bodyH = FONT_HGT_SMALL,  headH = FONT_HGT_MEDIUM },
    [2] = { body = UIFont.Medium, head = UIFont.Large,  bodyH = FONT_HGT_MEDIUM, headH = FONT_HGT_LARGE },
    [3] = { body = UIFont.Large,  head = UIFont.Large,  bodyH = FONT_HGT_LARGE,  headH = FONT_HGT_LARGE },
    [4] = { body = UIFont.Large,  head = UIFont.Large,  bodyH = FONT_HGT_LARGE,  headH = FONT_HGT_LARGE },
}

local Window = nil
local instance = nil

-- Preferences live in Prefs, a file: ModData is per save, and where you like this window is a
-- property of you rather than of the save.
function M.getUIZoom()
    local z = M.pref("zoom", 1)
    if type(z) ~= "number" then return 1 end
    if z < MIN_ZOOM then return MIN_ZOOM end
    if z > MAX_ZOOM then return MAX_ZOOM end
    return math.floor(z)
end

function M.setUIZoom(z)
    if type(z) ~= "number" then return end
    if z < MIN_ZOOM then z = MIN_ZOOM end
    if z > MAX_ZOOM then z = MAX_ZOOM end
    M.setPref("zoom", math.floor(z))
end

function M.rememberWindow(win)
    if win == nil then return end
    M.setPref("x", math.floor(win:getX()))
    M.setPref("y", math.floor(win:getY()))
    M.setPref("w", math.floor(win:getWidth()))
    M.setPref("h", math.floor(win:getHeight()))
    M.savePrefs()
end

local function ensureClass()
    if Window ~= nil then return true end
    if type(ISCollapsableWindow) ~= "table" or type(ISCollapsableWindow.derive) ~= "function" then
        return false
    end
    local N = M.neat
    Window = ISCollapsableWindow:derive("LugliAchWindow")

    --- The sidebar list, built once per window: categories are registered at load and never
    --- change while one is open, and metrics() alone would otherwise rebuild thirteen tables
    --- several times a frame.
    function Window:categories()
        if self.cats == nil then
            local out = { { id = "", label = M.text("UI_LugliAch_filter_all", "All") } }
            local order = M.getCategoryOrder()
            for i = 1, #order do
                local cat = M.getCategory(order[i])
                out[#out + 1] = { id = order[i], label = M.text(cat and cat.name or order[i], order[i]) }
            end
            self.cats = out
        end
        return self.cats
    end

    --- Every size the window uses, derived from the measured font and the zoom, in one place so
    --- nothing downstream can invent a number of its own.
    function Window:metrics()
        local z = M.getUIZoom()
        local f = FONTS[z] or FONTS[1]
        local pad = math.floor(f.bodyH * 0.5)

        local m = {
            z = z, font = f, bodyH = f.bodyH, headH = f.headH,
            pad = pad,
            title = math.floor(f.headH * 1.6),
            -- Sidebar rows track the SMALL font, not the zoomed one: the list is navigation
            -- rather than content, and scaling it like the grid put rows past the bottom edge.
            row = math.floor(FONT_HGT_SMALL * 1.7 + (f.bodyH - FONT_HGT_SMALL) * 0.4),
            -- The art is sized FIRST and the cell holds it. Sizing art from what the label left
            -- over gives a one-line name a bigger icon than its two-line neighbour.
            art = math.floor(f.bodyH * ART_BASE * ART_SCALE[z]),
            bar = math.max(3, math.floor(f.bodyH * 0.3)),
            scroll = math.max(4, math.floor(f.bodyH * 0.45)),
            search = math.floor(f.bodyH * 11),
            btn = math.floor(f.headH * 1.15),
        }
        -- Two label lines always, so every icon in the grid is the same size.
        m.cell = m.art + m.bodyH * 2 + pad * 2 + math.floor(f.bodyH * 0.4)

        -- As wide as its widest label needs, never a guessed constant, plus a fixed column for
        -- the count measured from the widest number the registry can actually produce.
        local cats = self:categories()
        local widest = 0
        for i = 1, #cats do
            local w = N.width(cats[i].label, f.body)
            if w > widest then widest = w end
        end
        local n = tostring(#M.getAllDefinitions())
        m.count = N.width(n .. "/" .. n, f.body) + pad
        m.sym = math.floor(f.bodyH * 1.15)
        m.sidebar = m.sym + pad + widest + m.count + pad * 3

        m.header = f.bodyH + f.headH + m.bar + pad * 3
        -- detailBase is what the pane's text needs; m.detail is that plus the grid's leftover.
        -- Only detailBase may size the WINDOW -- see applyZoom.
        m.detailBase = f.headH + f.bodyH * 2 + pad * 3
        m.detail = m.detailBase
        m.gridX = m.sidebar + pad
        m.gridY = m.title + m.header
        m.gridW = self.width - m.gridX - pad - m.scroll - pad
        m.gridH = self.height - m.gridY - m.detail - pad
        if m.gridH < m.cell then m.gridH = m.cell end

        -- Justified columns: fit as many as the width allows, then give the leftover back to the
        -- gaps so the grid meets both edges instead of leaving a ragged margin.
        local cols = math.max(1, math.floor((m.gridW + pad) / (m.cell + pad)))
        local used = cols * m.cell
        local slack = m.gridW - used
        m.cols = cols
        m.gap = (cols > 1) and math.floor(slack / (cols - 1)) or 0
        if m.gap < pad then m.gap = pad end
        m.step = m.cell + m.gap

        -- Whole tiles only, vertically too. Whatever height is left after the last full row goes
        -- to the detail pane, so the remainder becomes reading room rather than a sliced tile.
        local rowsFit = math.max(1, math.floor((m.gridH + m.gap) / m.step))
        local snapped = rowsFit * m.step - m.gap
        m.detail = m.detail + (m.gridH - snapped)
        m.gridH = snapped
        m.rowsFit = rowsFit
        return m
    end

    function Window:new(x, y, w, h, playerNum)
        local o = ISCollapsableWindow.new(self, x, y, w, h)
        o.playerNum = playerNum or 0
        o.title = ""
        o.resizable = true
        o.drawFrame = false
        o.scroll = 0
        o.sideScroll = 0
        o.filter = ""
        o.search = ""
        o.selected = nil
        o.rows = {}
        return o
    end

    function Window:rebuild()
        local out = {}
        local defs = M.getAllDefinitions()
        local q = string.lower(self.search or "")
        for i = 1, #defs do
            local d = defs[i]
            local keep = (self.filter == "" or d.category == self.filter)
            if keep and q ~= "" then
                local hay = string.lower(M.text(d.name, d.id) .. " "
                                         .. M.text(d.description, "") .. " " .. d.id)
                keep = string.find(hay, q, 1, true) ~= nil
            end
            if keep then out[#out + 1] = d end
        end
        self:applySort(out, getSpecificPlayer and getSpecificPlayer(self.playerNum) or nil)
        self.rows = out
        self.scroll = 0
    end

    --- Every mode falls back to the registry order for ties: a sort that is not total is a list
    --- that moves under the cursor when nothing changed.
    local TIER_RANK = { gold = 1, silver = 2, bronze = 3 }

    --- Sort the visible rows in place.
    ---
    --- Every key is computed once, before the sort, never inside the comparator. Looking them up
    --- in the callback meant ~2,600 comparisons each reaching pcall(ModData.getOrCreate): about
    --- ten thousand store walks to open the window, and again on every search keystroke, because
    --- rebuild() re-sorts. That was the freeze. Decorated first it is 283 lookups.
    function Window:applySort(rows, player)
        local mode = SORTS[self.sortMode or 1] or "default"
        if mode == "default" then return end

        -- Registry order, the tie-break that keeps the sort total. Without it rows with equal
        -- keys can compare inconsistently, which is how table.sort is made to overflow its stack.
        local home, rank, frac, name = {}, {}, {}, {}
        for i = 1, #rows do
            local d = rows[i]
            home[d.id] = i
            if mode == "progress" or mode == "done" then
                rank[d.id] = M.isUnlockedAnywhere(player, d.id) and 1 or 0
            end
            if mode == "progress" then
                local ok, f = pcall(M.getProgressFraction, player, d)
                frac[d.id] = (ok and type(f) == "number") and f or 0
            elseif mode == "name" then
                name[d.id] = string.lower(M.text(d.name, d.id))
            end
        end

        table.sort(rows, function(a, b)
            local ia, ib = a.id, b.id
            if mode == "progress" then
                -- Earned rows last: a finished row is not an answer to "what am I nearly at".
                if rank[ia] ~= rank[ib] then return rank[ib] == 1 end
                if frac[ia] ~= frac[ib] then return frac[ia] > frac[ib] end
            elseif mode == "done" then
                if rank[ia] ~= rank[ib] then return rank[ia] == 1 end
            elseif mode == "name" then
                if name[ia] ~= name[ib] then return name[ia] < name[ib] end
            else
                local ka = TIER_RANK[a.tier] or 4
                local kb = TIER_RANK[b.tier] or 4
                if ka ~= kb then return ka < kb end
            end
            return (home[ia] or 0) < (home[ib] or 0)
        end)
    end

    function Window:createChildren()
        ISCollapsableWindow.createChildren(self)

        -- Positioned against the width the window was CONSTRUCTED with, so a resize strands them
        -- mid-title-bar. Neither does anything useful on a browsable list.
        for _, name in ipairs({ "pinButton", "collapseButton" }) do
            local b = self[name]
            if b ~= nil then
                b:setVisible(false)
                b:setEnabled(false)
            end
        end

        self.zoomBox = ISComboBox:new(0, 0, 10, 10, self, function(_, box)
            local pick = box.options[box.selected]
            if pick ~= nil then
                self:applyZoom(tonumber(string.sub(pick, 1, 1)) or 1)
                M.neat.sound(M.neat.SOUND.option)
            end
        end)
        self.zoomBox:initialise()
        self.zoomBox:instantiate()
        for i = MIN_ZOOM, MAX_ZOOM do self.zoomBox:addOption(i .. "x") end
        self.zoomBox.selected = M.getUIZoom()
        self:addChild(self.zoomBox)

        self.sortBox = ISComboBox:new(0, 0, 10, 10, self, function(_, box)
            self.sortMode = box.selected or 1
            M.setPref("sort", self.sortMode)
            self:rebuild()
            M.neat.sound(M.neat.SOUND.option)
        end)
        self.sortBox:initialise()
        self.sortBox:instantiate()
        for _, key in ipairs(SORTS) do
            self.sortBox:addOption(M.text("UI_LugliAch_sort_" .. key, key))
        end
        self.sortMode = M.pref("sort", DEFAULT_SORT)
        if type(self.sortMode) ~= "number" or self.sortMode < 1 or self.sortMode > #SORTS then
            self.sortMode = DEFAULT_SORT
        end
        self.sortBox.selected = self.sortMode
        self:addChild(self.sortBox)

        self.searchBox = ISTextEntryBox:new("", 0, 0, 10, 10)
        self.searchBox:initialise()
        self.searchBox:instantiate()
        self.searchBox.onTextChange = function()
            self.search = self.searchBox:getInternalText() or ""
            self:rebuild()
        end
        self:addChild(self.searchBox)

        self:buildSoundPanel()
        self:reflow()
        self:rebuild()
    end

    -- The unlock sound lives here, not on the mod options page, because that page cannot play
    -- anything and this is a choice you can only make by hearing it.
    --
    -- A popup rather than another header row: m.gridY is m.title + m.header, so widening the
    -- header would push through gridH, rowsFit, m.detail, minimumHeight and applyZoom's wantH.
    function Window:buildSoundPanel()
        if ISPanel == nil or ISComboBox == nil or ISVolumeControl == nil then
            M.log(PART, "no sound panel: the game's UI classes are not all present")
            return
        end

        self.soundBtn = ISButton:new(0, 0, 10, 10,
                                     M.text("UI_LugliAch_window_sound", "Sound"), self,
                                     function() self:toggleSoundPanel() end)
        self.soundBtn:initialise()
        self.soundBtn:instantiate()
        self.soundBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.4 }
        self:addChild(self.soundBtn)

        local panel = ISPanel:new(0, 0, 10, 10)
        panel:initialise()
        panel:instantiate()
        panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        panel:setVisible(false)
        panel.owner = self
        -- Drawn by hand so it matches the rest of the window rather than the vanilla panel chrome.
        function panel:prerender()
            local m = self.owner:metrics()
            N.panel(self, N.TEX.panelRound, 0, 0, self.width, self.height, N.PANEL_TINT, 0.97)
            local pad = m.pad
            self:drawText(M.text("UI_LugliAch_window_sound", "Sound"),
                          pad, pad, N.text.r, N.text.g, N.text.b, 1, m.font.body)
            self:drawText(M.text("UI_LugliAch_window_volume", "Volume"),
                          pad, self.volumeCtl:getY() - m.bodyH - math.floor(pad / 2),
                          N.text.r, N.text.g, N.text.b, 1, m.font.body)
        end
        -- Swallow clicks so picking a sound does not fall through to the grid behind it.
        function panel:onMouseDown() return true end
        self.soundPanel = panel
        self:addChild(panel)

        local combo = ISComboBox:new(0, 0, 10, 10, self, function(_, box)
            M.setSoundIndex(box.selected or 1)
            -- The point of moving this out of the options page: you hear what you picked.
            M.previewSound()
        end)
        combo:initialise()
        combo:instantiate()
        for _, key in ipairs(M.SOUND_LABELS or {}) do
            combo:addOption(M.text(key, key))
        end
        combo.selected = M.soundIndex()
        panel.soundCombo = combo
        panel:addChild(combo)

        local vol = ISVolumeControl:new(0, 0, 10, 10, self, function(_, _, v)
            M.setSoundNotch(v)
            -- Only on a real change, which setVolume already guarantees: it returns early when
            -- the notch is unchanged, so dragging across one notch does not stutter the clip.
            M.previewSound()
        end)
        vol:initialise()
        vol:instantiate()
        vol.volume = M.soundNotch()
        panel.volumeCtl = vol
        panel:addChild(vol)
    end

    function Window:toggleSoundPanel()
        if self.soundPanel == nil then return end
        local show = not self.soundPanel:isVisible()
        if show then
            -- Re-read rather than trust the widgets: the cfg is shared with any other window
            -- this player has open, and the file is the truth.
            self.soundPanel.soundCombo.selected = M.soundIndex()
            self.soundPanel.volumeCtl.volume = M.soundNotch()
        end
        self.soundPanel:setVisible(show)
        M.neat.sound(M.neat.SOUND.option)
    end

    function Window:reflow()
        local m = self:metrics()
        if self.searchBox ~= nil then
            -- FONT FIRST: setFont forwards to the java UITextBox2, assigning .font does not, so
            -- the box measured with UIFont.Small and the text sat high in it.
            self.searchBox:setFont(m.font.body)
            self.searchBox:setWidth(m.search)
            self.searchBox:setHeight(m.bodyH + 6)
            self.searchBox:setX(self.width - m.pad - m.search)
            self.searchLabelX = self.width - m.pad - m.search
                - N.width(M.text("UI_LugliAch_window_search", "Search"), m.font.body) - m.pad
            self.searchBox:setY(m.title + m.pad)
        end
        if self.sortBox ~= nil then
            local sh = m.bodyH + 6
            self.sortBox:setWidth(m.search)
            self.sortBox:setHeight(sh)
            self.sortBox.baseHeight = sh
            self.sortBox.itemheight = sh
            self.sortBox.font = m.font.body
            self.sortBox.fontHgt = m.bodyH
            self.sortBox:setX(self.width - m.pad - m.search)
            self.sortBox:setY(m.title + m.pad + sh + math.floor(m.pad / 2))
            self.sortBox.selected = self.sortMode or 1
        end
        if self.zoomBox ~= nil then
            local w = m.btn * 2 + m.pad
            self.zoomBox:setWidth(w)
            self.zoomBox:setHeight(m.btn)
            -- ISComboBox centres its arrow on baseHeight, set once from the constructor and
            -- never touched by setHeight.
            self.zoomBox.baseHeight = m.btn
            self.zoomBox.itemheight = m.btn
            self.zoomBox.font = m.font.body
            self.zoomBox.fontHgt = m.bodyH
            self.zoomBox:setX(self.width - m.pad - w)
            self.zoomBox:setY(math.floor((m.title - m.btn) / 2))
            self.zoomBox.selected = m.z
        end
        if self.soundBtn ~= nil then
            local w = N.width(M.text("UI_LugliAch_window_sound", "Sound"), m.font.body) + m.pad * 2
            self.soundBtn:setWidth(w)
            self.soundBtn:setHeight(m.btn)
            self.soundBtn.font = m.font.body
            -- Left of the zoom combo, both pinned to the right edge, so neither strands on a
            -- resize the way the vanilla pin and collapse buttons do.
            self.soundBtn:setX(self.width - m.pad - (m.btn * 2 + m.pad) - m.pad - w)
            self.soundBtn:setY(math.floor((m.title - m.btn) / 2))
        end
        if self.soundPanel ~= nil then
            local sh = m.bodyH + 6
            local inner = math.max(m.search, m.cell * 2)
            local pw = inner + m.pad * 2
            local ph = m.pad + m.bodyH + math.floor(m.pad / 2) + sh
                       + m.pad + m.bodyH + math.floor(m.pad / 2) + m.btn + m.pad
            self.soundPanel:setWidth(pw)
            self.soundPanel:setHeight(ph)
            -- Hangs below the button, held inside the window so it cannot spill off the frame.
            local px = math.min(self.soundBtn ~= nil and self.soundBtn:getX() or 0,
                                self.width - pw - m.pad)
            self.soundPanel:setX(math.max(m.pad, px))
            self.soundPanel:setY(m.title)

            local combo = self.soundPanel.soundCombo
            combo:setWidth(inner)
            combo:setHeight(sh)
            combo.baseHeight = sh
            combo.itemheight = sh
            combo.font = m.font.body
            combo.fontHgt = m.bodyH
            combo:setX(m.pad)
            combo:setY(m.pad + m.bodyH + math.floor(m.pad / 2))

            local vol = self.soundPanel.volumeCtl
            vol:setWidth(inner)
            vol:setHeight(m.btn)
            vol:setX(m.pad)
            vol:setY(combo:getY() + sh + m.pad + m.bodyH + math.floor(m.pad / 2))
        end
        self.minimumWidth = m.sidebar + m.cell * 3 + m.pad * 5
        self.minimumHeight = m.title + m.header + m.cell + m.detailBase + m.pad * 2
    end

    --- Size the window for a zoom level and centre it, never letting it exceed the screen.
    function Window:applyZoom(z)
        M.setUIZoom(z)
        local m = self:metrics()
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local wantW = m.sidebar + (m.cell + m.pad) * 6 + m.pad * 3 + m.scroll
        -- detailBase, NOT m.detail: m.detail has absorbed leftover computed from self.height, so
        -- sizing from it feeds the window's height back into the height it asks for.
        local wantH = m.title + m.header + (m.cell + m.pad) * 3 + m.detailBase + m.pad * 2
        -- Never shorter than the sidebar needs: the category list is the one part of this window
        -- whose height is content rather than layout, and rows fell off the bottom silently.
        local sideH = m.title + m.pad * 2 + #self:categories() * m.row
        if sideH > wantH then wantH = sideH end
        self:setWidth(math.max(m.sidebar + m.cell * 3 + m.pad * 5,
                               math.min(wantW, math.floor(sw * 0.94))))
        self:setHeight(math.min(wantH, math.floor(sh * 0.94)))
        self:setX(math.max(0, math.floor((sw - self.width) / 2)))
        self:setY(math.max(0, math.floor((sh - self.height) / 2)))
        self.scroll = 0
        self:reflow()
    end

    function Window:onMouseWheel(del)
        local m = self:metrics()
        -- Over the sidebar the wheel scrolls the sidebar. The window is sized to fit the whole
        -- list, so this only matters on a screen too short to allow that.
        if self.mouseOverSidebar then
            local listH = #self:categories() * m.row
            local visible = self.height - m.title - m.pad * 2
            local maxSide = math.max(0, listH - visible)
            self.sideScroll = self.sideScroll + del * m.row
            if self.sideScroll < 0 then self.sideScroll = 0 end
            if self.sideScroll > maxSide then self.sideScroll = maxSide end
            return true
        end
        local maxScroll = math.max(0, math.ceil(#self.rows / m.cols) * m.step - m.gridH)
        self.scroll = self.scroll + del * math.floor(m.cell / 2)
        if self.scroll < 0 then self.scroll = 0 end
        if self.scroll > maxScroll then self.scroll = maxScroll end
        return true
    end

    --- What the cursor is over, resolved once per move rather than per tile per frame. The hit
    --- tests are the same arithmetic onMouseDown uses: two readings of one grid is how a highlight
    --- ends up a cell off from what it selects.
    function Window:trackHover(mx, my)
        local m = self:metrics()
        self.mouseOverSidebar = (mx < m.sidebar) and (my > m.title)
        self.hoverCat, self.hoverRow = nil, nil

        if self.mouseOverSidebar then
            local cats = self:categories()
            for i = 1, #cats do
                local ry = m.title + m.pad + (i - 1) * m.row - self.sideScroll
                if my >= ry and my < ry + m.row then self.hoverCat = cats[i].id break end
            end
            return
        end

        if mx >= m.gridX and my >= m.gridY and my <= m.gridY + m.gridH then
            local col = math.floor((mx - m.gridX) / m.step)
            local row = math.floor((my - m.gridY + self.scroll) / m.step)
            if col >= 0 and col < m.cols then
                self.hoverRow = self.rows[row * m.cols + col + 1]
            end
        end
    end

    function Window:onMouseMove(dx, dy)
        ISCollapsableWindow.onMouseMove(self, dx, dy)
        self:trackHover(self:getMouseX(), self:getMouseY())
    end

    --- Or the last tile the pointer crossed stays lit for as long as the window is open.
    function Window:onMouseMoveOutside(dx, dy)
        ISCollapsableWindow.onMouseMoveOutside(self, dx, dy)
        self.mouseOverSidebar = false
        self.hoverCat, self.hoverRow = nil, nil
    end

    function Window:onMouseDown(x, y)
        local m = self:metrics()

        if x < m.sidebar and y >= m.title then
            local cats = self:categories()
            for i = 1, #cats do
                local ry = m.title + m.pad + (i - 1) * m.row - self.sideScroll
                if y >= ry and y < ry + m.row then
                    -- rebuild() ends with scroll = 0, so re-clicking the current category used
                    -- to throw away how far you had scrolled through it.
                    if self.filter ~= cats[i].id then
                        self.filter = cats[i].id
                        M.setPref("filter", self.filter)
                        self:rebuild()
                        M.neat.sound(M.neat.SOUND.tab)
                    end
                    return true
                end
            end
        end

        if x >= m.gridX and y >= m.gridY and y <= m.gridY + m.gridH then
            local col = math.floor((x - m.gridX) / m.step)
            local row = math.floor((y - m.gridY + self.scroll) / m.step)
            if col >= 0 and col < m.cols then
                local d = self.rows[row * m.cols + col + 1]
                -- Only on a real change: holding the mouse down must not machine-gun the sound.
                if d ~= nil and d ~= self.selected then
                    self.selected = d
                    M.neat.sound(M.neat.SOUND.pick)
                end
            end
            return true
        end
        return ISCollapsableWindow.onMouseDown(self, x, y)
    end

    --- Two lines, split on a word boundary and measured. A 2-to-4 word name never fits one line
    --- in a tile, so a single line turns every tile into an ellipsis.
    local function twoLines(text, avail, font)
        if N.width(text, font) <= avail then return text, nil end
        local best = nil
        for pos in string.gmatch(text, "()%s") do
            if N.width(string.sub(text, 1, pos - 1), font) <= avail then best = pos end
        end
        if best == nil then return N.fit(text, avail, font), nil end
        return string.sub(text, 1, best - 1), N.fit(string.sub(text, best + 1), avail, font)
    end

    function Window:drawTile(m, d, x, y, player)
        local unlocked = M.isUnlockedAnywhere(player, d.id)
        local hidden = (d.hidden == true) and not unlocked
        local tier = N.tierCol[d.tier] or N.accent
        local dim = unlocked and 1 or 0.38
        local cell, pad = m.cell, m.pad

        local hot = (self.hoverRow == d)

        N.inner(self, x, y, cell, cell, unlocked and 0.72 or 0.42)
        -- The tile's own colour, not a grey wash: a locked bronze and a locked gold light
        -- differently, which is the only worth cue a dimmed tile has.
        if hot then
            self:drawRect(x, y, cell, cell, 0.14, tier.r, tier.g, tier.b)
        end
        self:drawRectBorder(x, y, cell, cell, hot and 0.9 or (unlocked and 0.65 or 0.28),
                            tier.r * dim, tier.g * dim, tier.b * dim)
        self:drawRect(x, y, cell, math.max(2, math.floor(m.bodyH * 0.16)),
                      unlocked and 0.95 or 0.35, tier.r * dim, tier.g * dim, tier.b * dim)

        local name = hidden and M.text(d.hiddenText, "???") or M.text(d.name, d.id)
        local l1, l2 = twoLines(name, cell - pad, m.font.body)
        local nameH = m.bodyH * 2
        local artH = m.art
        local artY = y + pad
        local artX = x + math.floor((cell - artH) / 2)

        local tex = (not hidden) and N.art(d.icon, artH) or nil
        if tex ~= nil then
            self:drawTextureScaled(tex, artX, artY, artH, artH, 1, dim, dim, dim)
        else
            self:drawRect(artX, artY, artH, artH, unlocked and 0.34 or 0.16,
                          tier.r * dim, tier.g * dim, tier.b * dim)
            local glyph = hidden and "?" or string.upper(string.sub(name, 1, 1))
            self:drawText(glyph, artX + artH / 2 - N.width(glyph, m.font.head) / 2,
                          artY + artH / 2 - m.headH / 2,
                          tier.r * dim + 0.2, tier.g * dim + 0.2, tier.b * dim + 0.2,
                          0.95, m.font.head)
        end

        local tr, tg, tb = N.text.r * dim + 0.12, N.text.g * dim + 0.12, N.text.b * dim + 0.12
        local ny = y + cell - pad - nameH
        -- A single line centres in the two-line block, so names share an optical centre.
        if l2 == nil then ny = ny + math.floor(m.bodyH / 2) end
        self:drawText(l1, x + math.floor((cell - N.width(l1, m.font.body)) / 2), ny,
                      tr, tg, tb, 1, m.font.body)
        if l2 ~= nil then
            self:drawText(l2, x + math.floor((cell - N.width(l2, m.font.body)) / 2),
                          ny + m.bodyH, tr, tg, tb, 1, m.font.body)
        end

        if not unlocked and not hidden and d.target and d.target > 1 then
            local f = M.getProgressFraction(player, d)
            local bh = math.max(2, math.floor(m.bodyH * 0.2))
            local by = y + cell - bh - 2
            local bx, bw = x + pad, cell - pad * 2
            self:drawRect(bx, by, bw, bh, 0.40, 0.18, 0.18, 0.18)
            if f > 0 then
                self:drawRect(bx, by, math.floor(bw * f), bh, 0.95, tier.r, tier.g, tier.b)
            end
        end
        if self.selected == d then
            self:drawRectBorder(x - 2, y - 2, cell + 4, cell + 4, 1,
                                N.accent.r, N.accent.g, N.accent.b)
        end
    end

    function Window:prerender()
        local m = self:metrics()
        local player = getSpecificPlayer and getSpecificPlayer(self.playerNum) or nil

        N.window(self, 0, 0, self.width, self.height, m.title)

        self:drawText(M.text("UI_LugliAch_window_title", "Achievements"),
                      m.title, math.floor((m.title - m.headH) / 2),
                      N.accent.r, N.accent.g, N.accent.b, 1, m.font.head)

        local s = M.getSummary(player)

        N.inner(self, 0, m.title, m.sidebar, self.height - m.title, 0.5)
        local cats = self:categories()
        for i = 1, #cats do
            local c = cats[i]
            local on = (c.id == self.filter)
            local ry = m.title + m.pad + (i - 1) * m.row - self.sideScroll
            if ry + m.row > m.title and ry < self.height then
                -- Under the selection, never over it.
                if not on and self.hoverCat == c.id then
                    self:drawRect(0, ry, m.sidebar, m.row, 0.14, N.accent.r, N.accent.g, N.accent.b)
                end
                if on then
                    self:drawRect(0, ry, m.sidebar, m.row, 0.32, N.accent.r, N.accent.g, N.accent.b)
                    self:drawRect(0, ry, math.max(2, math.floor(m.bodyH * 0.16)), m.row, 1,
                                  N.accent.r, N.accent.g, N.accent.b)
                end
                local col = (on or self.hoverCat == c.id) and N.text or N.textDim
                local ty = ry + math.floor((m.row - m.bodyH) / 2)
                -- A white silhouette, so it takes the row's own colour like the label does.
                local sym = N.tex("media/ui/achievements/cat/" ..
                                  (c.id == "" and "all" or c.id) .. ".png")
                local tx = m.pad
                if sym ~= nil then
                    local sy = ry + math.floor((m.row - m.sym) / 2)
                    self:drawTextureScaled(sym, m.pad, sy, m.sym, m.sym,
                                           on and 1 or 0.72, col.r, col.g, col.b)
                    tx = m.pad + m.sym + m.pad
                end
                self:drawText(N.fit(c.label, m.sidebar - m.count - tx - m.pad, m.font.body),
                              tx, ty, col.r, col.g, col.b, 1, m.font.body)
                -- How much of this category is done, so the sidebar is a progress report and not
                -- just a filter. Complete categories take the accent.
                local cs = (c.id == "") and { inSave = s.inSave, total = s.total }
                                        or s.byCategory[c.id]
                if cs ~= nil and cs.total > 0 then
                    local txt = cs.inSave .. "/" .. cs.total
                    local full = (cs.inSave >= cs.total)
                    local cc = full and N.accent or col
                    self:drawText(txt, m.sidebar - m.pad - N.width(txt, m.font.body), ty,
                                  cc.r, cc.g, cc.b, full and 1 or 0.8, m.font.body)
                end
            end
        end

        if self.searchLabelX ~= nil then
            self:drawText(M.text("UI_LugliAch_window_search", "Search"), self.searchLabelX,
                          m.title + m.pad + math.floor(m.pad / 2),
                          N.textDim.r, N.textDim.g, N.textDim.b, 1, m.font.body)
        end

        local hx = m.gridX
        -- Say which scope the figure below is counting: under the default, progress belongs to
        -- the world, and labelling it "this survivor" would be a lie the player only discovers
        -- when a death does not reset it.
        local scopeLabel = (type(M.isPerCharacter) == "function" and M.isPerCharacter())
                           and M.text("UI_LugliAch_window_survivor", "This survivor")
                           or M.text("UI_LugliAch_window_world", "This world")
        self:drawText(scopeLabel, hx, m.title + m.pad,
                      N.textDim.r, N.textDim.g, N.textDim.b, 1, m.font.body)
        local head = s.unlocked .. " / " .. s.total .. " " .. s.percent .. "%"
        self:drawText(head, hx, m.title + m.pad + m.bodyH,
                      N.text.r, N.text.g, N.text.b, 1, m.font.head)
        -- What earlier survivors in this save earned and this one has not. The achievements
        -- earned by dying can only appear here for most saves.
        if s.inSave > s.unlocked then
            local extra = "+" .. (s.inSave - s.unlocked) .. " "
                .. M.text("UI_LugliAch_window_earlier", "earned by earlier survivors")
            self:drawText(extra, hx + N.width(head, m.font.head) + m.pad,
                          m.title + m.pad + m.bodyH + math.floor((m.headH - m.bodyH) / 2),
                          N.textDim.r, N.textDim.g, N.textDim.b, 1, m.font.body)
        end

        local barY = m.gridY - m.bar - m.pad
        local barW = self.width - hx - m.pad
        self:drawRect(hx, barY, barW, m.bar, 0.45, 0.16, 0.16, 0.17)
        if s.total > 0 and s.inSave > 0 then
            self:drawRect(hx, barY, math.floor(barW * (s.inSave / s.total)), m.bar,
                          0.45, N.accent.r, N.accent.g, N.accent.b)
        end
        if s.total > 0 and s.unlocked > 0 then
            local pc = N.progressCol(s.unlocked / s.total)
            self:drawRect(hx, barY, math.floor(barW * (s.unlocked / s.total)), m.bar,
                          1, pc.r, pc.g, pc.b)
        end

        N.inner(self, m.gridX - 2, m.gridY, m.gridW + 4, m.gridH, 0.45)
        local first = math.max(0, math.floor(self.scroll / m.step))
        local last = first + math.ceil(m.gridH / m.step)

        self:setStencilRect(m.gridX - 2, m.gridY, m.gridW + 4, m.gridH)
        for r = first, last do
            for c = 0, m.cols - 1 do
                local d = self.rows[r * m.cols + c + 1]
                if d ~= nil then
                    self:drawTile(m, d, m.gridX + c * m.step,
                                  m.gridY + r * m.step - self.scroll, player)
                end
            end
        end
        self:clearStencilRect()

        local contentH = math.ceil(#self.rows / m.cols) * m.step
        if contentH > m.gridH then
            local tx = self.width - m.pad - m.scroll
            self:drawRect(tx, m.gridY, m.scroll, m.gridH, 0.35, 0.12, 0.12, 0.13)
            local thumbH = math.max(m.row, math.floor(m.gridH * (m.gridH / contentH)))
            local maxScroll = contentH - m.gridH
            local t = (maxScroll > 0) and (self.scroll / maxScroll) or 0
            self:drawRect(tx, math.floor(m.gridY + (m.gridH - thumbH) * t), m.scroll, thumbH,
                          0.9, N.accent.r, N.accent.g, N.accent.b)
        end

        if #self.rows == 0 then
            self:drawText(M.text("UI_LugliAch_window_empty", "Nothing matches that."),
                          m.gridX + m.pad, m.gridY + m.pad,
                          N.textDim.r, N.textDim.g, N.textDim.b, 1, m.font.body)
        end

        -- The pane takes whatever height the snapped grid did not need, so its content is
        -- centred in it rather than pinned to the top: at 4x that difference is most of the pane.
        local dy = self.height - m.detail
        local paneH = m.detail - m.pad
        N.inner(self, m.gridX - 2, dy, m.gridW + 4, paneH, 0.55)
        local d = self.selected
        local tx2 = m.gridX + m.pad
        local blockH = m.headH + m.bodyH * 2 + m.bar + m.pad
        local top = dy + math.max(m.pad, math.floor((paneH - blockH) / 2))
        if d ~= nil and player ~= nil then
            -- Anywhere in the save, matching the grid: a row earned by a survivor who has since
            -- died is still shown as earned, and mine below is what separates the two.
            local unlocked = M.isUnlockedAnywhere(player, d.id)
            local mine = M.isUnlocked(player, d.id)
            local hidden = (d.hidden == true) and not unlocked
            local tier = N.tierCol[d.tier] or N.accent
            -- Hidden achievements keep their secret: no icon, same as no name.
            local box = math.min(paneH - m.pad * 2, math.floor(m.cell * 0.9))
            local art = (not hidden) and N.art(d.icon, box) or nil
            if art ~= nil and box > m.headH then
                self:drawTextureScaled(art, tx2, dy + math.floor((paneH - box) / 2),
                                       box, box, 1, 1, 1, 1)
                tx2 = tx2 + box + m.pad * 2
            end
            self:drawText(hidden and M.text(d.hiddenText, "???") or M.text(d.name, d.id),
                          tx2, top, tier.r, tier.g, tier.b, 1, m.font.head)
            -- Which category it belongs to, right-aligned on the same line: with a search across
            -- every category, the selected tile otherwise gives no clue where it lives.
            local cat = M.getCategory(d.category)
            local cname = M.text(cat and cat.name or d.category, d.category)
            self:drawText(cname,
                          m.gridX + m.gridW - m.pad - N.width(cname, m.font.body),
                          top + math.floor((m.headH - m.bodyH) / 2),
                          N.textDim.r, N.textDim.g, N.textDim.b, 1, m.font.body)
            if not hidden then
                self:drawText(N.fit(M.text(d.description, ""),
                                    m.gridX + m.gridW - m.pad * 2 - tx2, m.font.body),
                              tx2, top + m.headH, N.text.r, N.text.g, N.text.b,
                              1, m.font.body)
            end
            local line
            if unlocked and not mine then
                local who = M.getSaveUnlockOwner(d.id)
                line = (who ~= "")
                    and (M.text("UI_LugliAch_unlocked_by", "earned by") .. " " .. who)
                    or M.text("UI_LugliAch_window_earlier", "earned by earlier survivors")
            elseif unlocked then
                -- Just that it is done. The stored value is world age in hours: meaningful to
                -- the ledger, meaningless to a player.
                line = M.text("UI_LugliAch_unlocked", "Unlocked")
            elseif not hidden then
                line = M.getProgressText(player, d)
            end
            if line ~= nil and line ~= "" then
                self:drawText(line, tx2, top + m.headH + m.bodyH,
                              N.accent.r, N.accent.g, N.accent.b, 1, m.font.body)
            end
            -- Only where there is a fraction to show: a one-shot achievement has no meaningful
            -- partial state, and a hidden one must not leak that it is close.
            if not hidden and not unlocked and d.target and d.target > 1 then
                local by = top + m.headH + m.bodyH * 2 + math.floor(m.pad / 2)
                local bw = m.gridX + m.gridW - m.pad - tx2
                self:drawRect(tx2, by, bw, m.bar, 0.5, 0.16, 0.16, 0.17)
                local f = M.getProgressFraction(player, d)
                if f > 0 then
                    self:drawRect(tx2, by, math.floor(bw * f), m.bar, 1, tier.r, tier.g, tier.b)
                end
            end
        else
            self:drawText(M.text("UI_LugliAch_window_pick", "Select an achievement to see its detail."),
                          tx2, top + m.headH,
                          N.textDim.r, N.textDim.g, N.textDim.b, 1, m.font.body)
        end
    end

    function Window:render() end

    function Window:onResize()
        ISCollapsableWindow.onResize(self)
        self:reflow()
    end

    --- ISCollapsableWindow:close is only setVisible(false) (:134-136): it leaves the window in the
    --- UI manager and cannot clear `instance`, so the X left the sidebar icon lit and cost the
    --- next click on it closing something already shut.
    function Window:close()
        ISCollapsableWindow.close(self)
        M.forgetWindow(self)
    end
    return true
end

--- Tear down for good, however it was dismissed. Idempotent.
function M.forgetWindow(win)
    if instance == nil then return end
    if win ~= nil and win ~= instance then return end
    M.rememberWindow(instance)
    pcall(function() instance:removeFromUIManager() end)
    instance = nil
    -- Every dismissal funnels through here, so it is the one place worth voicing.
    M.neat.sound(M.neat.SOUND.close)
end

function M.toggleWindow(playerNum)
    if not ensureClass() then
        M.defect(PART, "ISCollapsableWindow is not available")
        return
    end
    if M.isWindowOpen() then
        M.forgetWindow(instance)
        return
    end
    -- Reaching here holding a husk means isWindowOpen missed it. Drop it rather than leak.
    M.forgetWindow(instance)
    local okNew, win = pcall(function()
        return Window:new(0, 0, 800, 600, playerNum or 0)
    end)
    if not okNew or win == nil then
        M.defect(PART, "could not build the window: " .. tostring(win))
        return
    end
    win:initialise()
    win:instantiate()
    win:addToUIManager()
    -- Sizes and centres for the remembered zoom, so opening it always fits the screen.
    win:applyZoom(M.getUIZoom())

    -- Size before position, so the clamp knows how big the thing being placed is.
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local pw, ph = M.pref("w", nil), M.pref("h", nil)
    if type(pw) == "number" and type(ph) == "number" then
        win:setWidth(math.max(win.minimumWidth or 0, math.min(pw, sw)))
        win:setHeight(math.max(win.minimumHeight or 0, math.min(ph, sh)))
        win:reflow()
    end
    local px, py = M.pref("x", nil), M.pref("y", nil)
    if type(px) == "number" and type(py) == "number" then
        win:setX(math.max(0, math.min(px, sw - win:getWidth())))
        win:setY(math.max(0, math.min(py, sh - win:getHeight())))
    end

    -- And the category it was left on, if it still exists.
    local want = M.pref("filter", "")
    if type(want) == "string" and want ~= "" and M.getCategory(want) ~= nil then
        win.filter = want
    end
    instance = win
    M.neat.sound(M.neat.SOUND.open)
end

--- Open means ON SCREEN, not "a table still exists". The sidebar icon reads this every prerender,
--- and setVisible is public, so this asks the widget and repairs itself when the two disagree.
function M.isWindowOpen()
    if instance == nil then return false end
    local ok, visible = pcall(function() return instance:isVisible() end)
    if not ok or visible == false then
        M.forgetWindow(instance)
        return false
    end
    return true
end

M.status(PART, true)
