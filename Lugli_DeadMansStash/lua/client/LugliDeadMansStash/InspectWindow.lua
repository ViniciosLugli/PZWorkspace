--[[
    InspectWindow
    A sealed gate's own window, on NeatUI chrome: how good the haul is likely to be, any work
    already put into it, a safe's power, tries, lockout and digits found, and one row per way of
    opening it with the tool, the time, the noise and a Start button. It describes only; the authority decides (World.lua). Everything is re-read
    twice a second, so a tool picked up or another survivor opening the gate shows here, and the
    window closes when the survivor walks off or dies.
]]

require "ISUI/ISPanelJoypad"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Neat"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local N = M.neat
    local PART = "InspectWindow"

    local FONT = N.FONT

    --- Tiles from the gate's square centre past which the window closes.
    M.INSPECT_REACH = 3
    M.INSPECT_REFRESH_MS = 500

    LugliDMSInspectWindow = ISPanelJoypad:derive("LugliDMSInspectWindow")
    LugliDMSInspectBody = NIScrollView:derive("LugliDMSInspectBody")

    --- The open window of each local player, by player number.
    local open = {}

    local function measure(s, font)
        local ok, w = pcall(function() return getTextManager():MeasureStringX(font or FONT, s) end)
        if ok and type(w) == "number" then return w end
        return #s * 6
    end

    local SAFE_KINDS = { dialsafe = true, keypadsafe = true }

    --- The id the authority keys a gate by ("x,y,z,i"), from Actions.lua's M.gateArgs, read when
    --- asked: that file is the one that knows a gate's index on its square. Nil when it cannot
    --- say. The type checks are not redundant with the pcall: in game a caught error still puts
    --- up the error box, and this runs twice a second.
    function M.gateIdOf(obj)
        if type(M.gateArgs) ~= "function" then return nil end
        local ok, _, id = pcall(M.gateArgs, obj)
        if ok and type(id) == "string" then return id end
        return nil
    end

    --- The clue notes the survivor carries about gate `obj`, as Codes.lua's M.carriedNotes lists
    --- them ({ item, text }), or an empty list when it is not there or fails.
    function M.notesAbout(player, obj)
        if type(M.carriedNotes) ~= "function" then return {} end
        local id = M.gateIdOf(obj)
        if id == nil then return {} end
        local ok, list = pcall(M.carriedNotes, player, id)
        if ok and type(list) == "table" then return list end
        return {}
    end

    local function padDrives(playerNum)
        return JoypadState ~= nil and JoypadState.players[playerNum + 1] ~= nil
    end

    local function isEsc(key)
        return Keyboard ~= nil and key == Keyboard.KEY_ESCAPE
    end

    -- ---- words --------------------------------------------------------------------------------

    --- A lockout's game hours left as the player reads them, rounded up to the minute or the hour.
    --- The code window says the same (Keypad.lua).
    function M.lockoutText(hours)
        local minutes = math.ceil(hours * 60)
        if minutes < 60 then
            if minutes <= 1 then return M.T("UI_LugliDMS_Keypad_LockedMinute", "Locked. Try again in about 1 minute.") end
            return M.Tf("UI_LugliDMS_Keypad_LockedMinutes", "Locked. Try again in about %1 minutes.", minutes)
        end
        local whole = math.ceil(minutes / 60)
        if whole == 1 then return M.T("UI_LugliDMS_Keypad_LockedHour", "Locked. Try again in about 1 hour.") end
        return M.Tf("UI_LugliDMS_Keypad_LockedHours", "Locked. Try again in about %1 hours.", whole)
    end

    --- The mask the authority mirrors ("?4??"), only when it is four digits and "?" with at least
    --- one digit found: object modData is client-writable (docs/31 section 7).
    local function revealedMask(s)
        if type(s) ~= "string" or #s ~= 4 or string.find(s, "^[%d%?]+$") == nil then return nil end
        if string.find(s, "%d") == nil then return nil end
        return s
    end

    --- What a sealed safe shows above its routes, as { s, c }: the keypad's power, the lockout or
    --- the tries left, and the digits already found. Empty for a box, which has none of them.
    local function safeLines(rec, square)
        local out = {}
        if M.KINDS[rec.kind].keypad then
            if M.keypadPowered(rec, square) then
                out[#out + 1] = { s = M.T("UI_LugliDMS_HasPower", "The keypad has power."), c = N.good }
            else
                out[#out + 1] = { s = M.T("UI_LugliDMS_NoPower", "The keypad is dead. It needs power."), c = N.bad }
            end
        end
        local locked = M.lockedFor(rec)
        if locked > 0 then
            out[#out + 1] = { s = M.lockoutText(locked), c = N.bad }
        else
            local tries = M.finite(rec.triesLeft)
            if tries ~= nil then
                tries = math.max(0, math.floor(tries))
                if tries == 1 then
                    out[#out + 1] = { s = M.T("UI_LugliDMS_Keypad_TriesOne", "One try left before it locks."), c = N.textDim }
                else
                    out[#out + 1] = { s = M.Tf("UI_LugliDMS_Keypad_Tries", "Tries left before it locks: %1", tries), c = N.textDim }
                end
            end
        end
        local mask = revealedMask(rec.revealed)
        if mask ~= nil then
            out[#out + 1] = { s = M.Tf("UI_LugliDMS_Found", "Numbers found so far: %1", mask), c = N.text }
        end
        return out
    end

    local function routeName(id)
        return M.T("UI_LugliDMS_Route_" .. tostring(id), tostring(id))
    end

    local function toolName(item)
        -- A route with no item (the code) has no name, and a pcall'd error is still logged.
        if item == nil then return "" end
        local ok, s = pcall(function() return item:getDisplayName() end)
        if ok and type(s) == "string" then return s end
        return "?"
    end

    --- The vanilla item a route's row shows when the survivor holds nothing for it: the tool it
    --- takes, or what it is done with.
    local ROUTE_ITEM = {
        code = "Base.Note", key = "Base.Key1", pry = "Base.Crowbar", force = "Base.Crowbar", snap = "Base.Crowbar",
        claw = "Base.Hammer", smash = "Base.Sledgehammer", pick = "Base.Paperclip", jimmy = "Base.Screwdriver",
        cut = "Base.BoltCutters", manipulate = "Base.Stethoscope", drill = "Base.HandDrill", torch = "Base.BlowTorch",
        bypass = "Base.Screwdriver", battery = "Base.Battery",
    }
    local scriptIcons = {}

    --- A route row's icon: the survivor's own key or tool, else the route's vanilla item, as the
    --- game's crafting window shows its inputs. Nil when there is none to show.
    local function routeIcon(r)
        local item = r.key or r.tool
        if item ~= nil then
            local ok, tex = pcall(function() return item:getTex() end)
            if ok and tex ~= nil then return tex end
        end
        local full = ROUTE_ITEM[r.id]
        if full == nil then return nil end
        -- Only a found icon is kept: one asked for before the scripts load is asked again.
        if scriptIcons[full] == nil then
            local ok, tex = pcall(function() return getScriptManager():FindItem(full):getNormalTexture() end)
            if ok then scriptIcons[full] = tex end
        end
        return scriptIcons[full]
    end
    M.inspectRouteIcon = routeIcon

    --- The lines one route's row says under its name, as { s, c, mark }.
    local function routeLines(r)
        local lines = {}
        if r.ok then
            if r.key ~= nil then
                lines[#lines + 1] = { s = M.T("UI_LugliDMS_Key", "Key") .. ": " .. toolName(r.key), c = N.text, mark = "tick" }
            elseif r.tool ~= nil then
                lines[#lines + 1] = { s = M.T("UI_LugliDMS_Tool", "Tool") .. ": " .. toolName(r.tool), c = N.text, mark = "tick" }
            end
            local f = M.routeFacts(r)
            local function say(s) lines[#lines + 1] = { s = s, c = N.textDim } end
            if f.left then
                say(f.seconds == 1 and M.T("UI_LugliDMS_LeftOne", "About 1 second left")
                    or M.Tf("UI_LugliDMS_Left", "About %1 seconds left", f.seconds))
            else
                say(f.seconds == 1 and M.T("UI_LugliDMS_TakesOne", "Takes about 1 second")
                    or M.Tf("UI_LugliDMS_Takes", "Takes about %1 seconds", f.seconds))
            end
            if f.noise <= 0 then
                say(M.T("UI_LugliDMS_Silent", "Makes no noise"))
            else
                say(M.Tf("UI_LugliDMS_Noise", "Heard up to %1 tiles away", f.noise))
            end
            if f.chance < 100 then say(M.Tf("UI_LugliDMS_Chance", "Chance it gives: %1%", f.chance)) end
            if f.jams then say(M.T("UI_LugliDMS_MayJam", "A failed try can jam the lock.")) end
            if f.spends == "wear" then
                say(M.T("UI_LugliDMS_Wears", "A failed try wears the lockpick down."))
            elseif f.spends == "use" then
                say(M.T("UI_LugliDMS_Spends", "A failed try uses up the tool."))
            end
            if f.wrecks then say(M.T("UI_LugliDMS_Wrecks", "Wrecks the box: it can't be carried away after.")) end
            if f.breaks then say(M.T("UI_LugliDMS_MayBreak", "Fragile things inside may break.")) end
            if f.alarm then say(M.T("UI_LugliDMS_Alarm", "A failed try sets off the alarm and locks it.")) end
            if f.burns then say(M.T("UI_LugliDMS_Burns", "Paper, money and food inside may burn.")) end
            return lines
        end
        if r.reason == M.REASON_NO_TOOL or r.reason == M.REASON_TOOL_BROKEN then
            lines[#lines + 1] = { s = M.T("UI_LugliDMS_Needs", "Needs") .. ": "
                .. M.T("UI_LugliDMS_Need_" .. tostring(r.id), tostring(r.id)), c = N.text, mark = "cross" }
        end
        lines[#lines + 1] = { s = M.T(r.reason, M.T("UI_LugliDMS_CannotNow", "This cannot be done right now.")), c = N.bad }
        return lines
    end

    -- ---- reading the gate ---------------------------------------------------------------------

    local function playerNumOf(player)
        local ok, n = pcall(function() return player:getPlayerNum() end)
        if ok and type(n) == "number" then return n end
        return 0
    end

    --- Is the survivor still at the gate: same floor, within M.INSPECT_REACH of its square centre,
    --- measured the way the authority measures its own reach (World.lua).
    local function inReach(player, obj)
        local ok, near = pcall(function()
            local sq = obj:getSquare()
            if sq == nil then return false end
            if math.floor(player:getZ()) ~= sq:getZ() then return false end
            local dx, dy = player:getX() - (sq:getX() + 0.5), player:getY() - (sq:getY() + 0.5)
            return dx * dx + dy * dy <= M.INSPECT_REACH * M.INSPECT_REACH
        end)
        return ok and near == true
    end
    M.inspectInReach = inReach

    --- Everything the window shows, read fresh. False when the object is no longer a gate.
    function LugliDMSInspectWindow:read()
        self.rec = M.gateRecord(self.obj)
        if self.rec == nil then return false end
        self.sealed = self.rec.state == "sealed"
        local okSq, square = pcall(function() return self.obj:getSquare() end)
        if not okSq then square = nil end
        self.routes = self.sealed and M.routes(self.player, self.rec, square) or {}
        self.safe = self.sealed and safeLines(self.rec, square) or {}
        if self.sealed and SAFE_KINDS[self.rec.kind] then
            local n = #M.notesAbout(self.player, self.obj)
            if n == 1 then
                self.safe[#self.safe + 1] = { s = M.T("UI_LugliDMS_NotesCarriedOne", "You carry a note about this safe."), c = N.text }
            elseif n > 1 then
                self.safe[#self.safe + 1] = { s = M.Tf("UI_LugliDMS_NotesCarried", "You carry %1 notes about this safe.", n), c = N.text }
            end
        end
        self.saved = {}
        if self.sealed and type(self.rec.progress) == "table" then
            for _, id in ipairs(M.KINDS[self.rec.kind].routes) do
                local p = M.finite(self.rec.progress[id])
                if p ~= nil and p > 0 then self.saved[#self.saved + 1] = { id = id, p = M.clamp(p, 0, 1) } end
            end
        end
        return true
    end

    --- A keyed box's word on its key, read from the key row's own answer so the two never disagree.
    --- The client never knows which box a stash key opens, so a carried one is only "may fit"; and
    --- an unfound key may be on a zombie by the building, so it is only "most likely" in it. Never
    --- the id or the place. nil for a box no key opens.
    local function keyHint(routes)
        for _, r in ipairs(routes) do
            if r.id == "key" then
                if r.ok then return M.T("UI_LugliDMS_KeyCarried", "You carry a stash key. It may fit this lock.") end
                return M.T("UI_LugliDMS_KeyNearby", "Its owner kept a key to it, most likely somewhere in this building.")
            end
        end
        return nil
    end

    --- Every line the window draws outside the route rows, in the language and state of now.
    local function texts(self)
        local t = {}
        local kind = tostring(self.rec.kind)
        if self.sealed then
            t.title = M.T("UI_LugliDMS_Gate_" .. kind, kind) .. M.numberSuffix(self.rec.no)
            local tier = M.clamp(M.finite(self.rec.tier) or 1, 1, 3)
            t.tier = M.T("UI_LugliDMS_Tier", "Quality") .. ": " .. M.T("UI_LugliDMS_Tier" .. tier, tostring(tier))
            t.hint = M.T("UI_LugliDMS_Hint_" .. kind .. tier, "")
            t.keyHint = keyHint(self.routes)
        else
            t.title = M.T("UI_LugliDMS_Opened_" .. kind, kind) .. M.numberSuffix(self.rec.no)
            t.tier = M.T("UI_LugliDMS_IsOpen", "It has already been opened.")
        end
        t.saved = M.T("UI_LugliDMS_Saved", "Work already done")
        t.ways = M.T("UI_LugliDMS_Ways", "Ways to open it")
        t.start = M.T("UI_LugliDMS_Start", "Start")
        return t
    end

    -- ---- the layout ---------------------------------------------------------------------------

    --- Every height, gap and inset, from the kit's sizes for the game's font size.
    local function metrics()
        local k = N.metrics()
        local u = k.u
        return { fh = k.fh, row = u(22), head = k.head, pad = k.pad, gap = k.gap, inset = u(8), nudge = u(4),
                 btnH = k.btnH, btnPad = k.btnPad, icon = k.icon, scroll = k.scroll, bar = k.bar,
                 minW = u(420), minText = u(160), tool = u(32) }
    end

    --- The body as draw operations at `inner` width, and the height it takes. The window is sized
    --- from this same list, so the two cannot disagree. Each route row's button is a spot in the
    --- body's unscrolled coordinates.
    function LugliDMSInspectWindow:build(inner)
        local m, t = self.m, self.text
        local ops, spots, y = {}, {}, m.pad
        local function put(s, x, c) ops[#ops + 1] = { s = s, x = m.pad + x, y = y, c = c } end
        local function lines(s, x, width, c, step)
            for _, line in ipairs(N.wrap(s, width, FONT)) do
                put(line, x, c)
                y = y + step
            end
        end

        lines(t.tier, 0, inner, self.sealed and N.text or N.good, m.fh)
        if t.hint ~= nil and t.hint ~= "" then
            y = y + m.nudge
            lines(t.hint, 0, inner, N.textDim, m.fh)
        end
        if t.keyHint ~= nil then
            y = y + m.nudge
            lines(t.keyHint, 0, inner, N.text, m.fh)
        end
        if #self.safe > 0 then
            y = y + m.gap
            for _, line in ipairs(self.safe) do lines(line.s, 0, inner, line.c, m.row) end
        end

        -- WORK ALREADY DONE: a bar a route someone started and put down, filled as far as they got.
        if #self.saved > 0 then
            y = y + m.gap * 2
            lines(t.saved, 0, inner, N.text, m.row)
            for _, s in ipairs(self.saved) do
                lines(routeName(s.id) .. " " .. math.floor(s.p * 100 + 0.5) .. "%", 0, inner, N.textDim, m.fh)
                y = y + m.nudge
                ops[#ops + 1] = { bar = true, x = m.pad, y = y, w = inner, h = m.bar, frac = s.p }
                y = y + m.bar + m.nudge
            end
        end

        if #self.routes > 0 then
            y = y + m.gap * 2
            lines(t.ways, 0, inner, N.text, m.row)
        end
        -- A ROW IS ITS TEXT BESIDE ITS BUTTON while the text keeps room to read; on a screen too
        -- narrow for that the button goes under the text, never over it.
        local btnW = math.min(self.btnW0, inner - m.inset * 2)
        local textW = inner - m.inset * 2 - btnW - m.gap
        local stacked = textW < m.minText
        if stacked then textW = inner - m.inset * 2 end
        self.btnW = btnW
        local markW = m.icon + m.nudge
        local toolW = m.tool + m.gap
        for _, r in ipairs(self.routes) do
            local top = y
            local box = { box = true, x = m.pad, y = top, w = inner }
            ops[#ops + 1] = box
            y = top + m.inset
            local tex = routeIcon(r)
            if tex ~= nil then
                ops[#ops + 1] = { tex = tex, x = m.pad + m.inset, y = y, size = m.tool, a = r.ok and 1 or 0.45 }
            end
            lines(routeName(r.id), m.inset + toolW, textW - toolW, N.text, m.row)
            for _, line in ipairs(routeLines(r)) do
                local x, width = m.inset + toolW, textW - toolW
                if line.mark ~= nil then
                    ops[#ops + 1] = { icon = line.mark, x = m.pad + x, y = y + math.floor((m.fh - m.icon) / 2),
                                      size = m.icon, c = line.mark == "tick" and N.good or N.bad }
                    x, width = x + markW, width - markW
                end
                lines(line.s, x, width, line.c, m.row)
            end
            if tex ~= nil then y = math.max(y, top + m.inset + m.tool) end
            local bx = m.pad + inner - m.inset - btnW
            if stacked then
                spots[#spots + 1] = { id = r.id, ok = r.ok == true, x = bx, y = y, w = btnW, h = m.btnH }
                y = y + m.btnH
            else
                spots[#spots + 1] = { id = r.id, ok = r.ok == true, x = bx, y = top + m.inset, w = btnW, h = m.btnH }
                y = math.max(y, top + m.inset + m.btnH)
            end
            y = y + m.inset
            box.h = y - top
            y = y + m.gap
        end
        self.ops, self.spots = ops, spots
        return y + m.pad
    end

    --- Size the window for what it shows now: as wide as its widest unwrapped line, never wider
    --- or taller than the screen. A body taller than the room left scrolls, and the scroll bar
    --- gets its own strip. The title bar ends in the close button, `head` wide, and the title
    --- leaves it that room.
    function LugliDMSInspectWindow:layout()
        local m = self.m
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local t = texts(self)
        self.text = t
        self.btnW0 = measure(t.start) + m.btnPad

        local want = math.max(m.minW - m.pad * 2, measure(t.title, N.TITLE_FONT) + m.head, measure(t.tier))
        if #self.saved > 0 then want = math.max(want, measure(t.saved)) end
        for _, r in ipairs(self.routes) do
            local w = measure(routeName(r.id))
            for _, line in ipairs(routeLines(r)) do
                w = math.max(w, measure(line.s) + (line.mark ~= nil and (m.icon + m.nudge) or 0))
            end
            want = math.max(want, m.inset * 2 + m.tool + m.gap + w + m.gap + self.btnW0)
        end

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
        self.startShown = N.fit(t.start, self.btnW - m.btnPad, FONT)
        self.titleShown = N.fitTitle(t.title, w - m.pad - m.head)
        return w, m.head + self.bodyH
    end

    --- A signature of everything drawn, so the re-read only lays the window out again when
    --- something moved. Rebuilding the buttons on every re-read would eat a click.
    local function signature(self)
        local parts = { tostring(self.rec.state), tostring(self.rec.tier), tostring(self.rec.kind),
                        tostring(getCore():getScreenWidth()), tostring(getCore():getScreenHeight()) }
        for _, s in ipairs(self.saved) do parts[#parts + 1] = s.id .. math.floor(s.p * 100 + 0.5) end
        -- The safe's lines as drawn: power, tries, the countdown to the minute, the mask.
        for _, line in ipairs(self.safe) do parts[#parts + 1] = line.s end
        -- Each route's row as drawn, so a changed fact lays it out again and nothing else does.
        for _, r in ipairs(self.routes) do
            parts[#parts + 1] = tostring(r.id) .. tostring(r.ok)
            for _, line in ipairs(routeLines(r)) do parts[#parts + 1] = line.s end
        end
        return table.concat(parts, "|")
    end

    --- The routes that can be started now, in row order.
    local function startable(self)
        local out = {}
        for _, s in ipairs(self.spots) do if s.ok then out[#out + 1] = s end end
        return out
    end

    --- Put a button on every route row, labelled Start, lit when the route can be started. The
    --- controller's choice stays on the same route across a re-read while the route is still
    --- listed; a new choice is the first route that can be started, else the first row.
    function LugliDMSInspectWindow:layoutButtons()
        N.placeClose(self.closeBtn, self.width)
        for _, b in ipairs(self.routeBtns or {}) do self.body:removeScrollChild(b) end
        self.routeBtns = {}
        local keep = false
        for _, s in ipairs(self.spots) do if s.id == self.selId then keep = true end end
        if not keep then
            local first = startable(self)[1] or self.spots[1]
            self.selId = first ~= nil and first.id or nil
        end
        local pad = padDrives(self.playerNum)
        for _, s in ipairs(self.spots) do
            local b = LugliDMSButton:new(s.x, s.y, s.w, s.h, self.startShown, self, LugliDMSInspectWindow.onStart)
            b.routeId = s.id
            b:initialise()
            b:setEnable(s.ok)
            b.joypadFocused = pad and s.id == self.selId
            self.body:addScrollChild(b)
            self.routeBtns[#self.routeBtns + 1] = b
        end
    end

    --- Lay out again and move every child to match. setWidth and setHeight keep a top-level
    --- element on screen (ISUIElement.getKeepOnScreen), so a window that grew is pulled back in.
    function LugliDMSInspectWindow:applyLayout()
        local w, h = self:layout()
        self:setWidth(w)
        self:setHeight(h)
        if self.body ~= nil then
            self.body:fit(w, self.bodyH, self.contentH)
            self:layoutButtons()
        end
    end

    function LugliDMSInspectWindow:new(player, obj)
        local o = ISPanelJoypad:new(0, 0, 1, 1)
        setmetatable(o, self)
        self.__index = self
        o.background = false
        o.moveWithMouse = true
        o.player, o.obj = player, obj
        o.playerNum = playerNumOf(player)
        o.m = metrics()
        o:read()
        o.sig = signature(o)
        o:applyLayout()
        N.place(o, "inspect", (getCore():getScreenWidth() - o.width) / 2, (getCore():getScreenHeight() - o.height) / 2)
        return o
    end

    N.movable(LugliDMSInspectWindow, "inspect", ISPanelJoypad)

    function LugliDMSInspectWindow:createChildren()
        ISPanelJoypad.createChildren(self)
        self.body = LugliDMSInspectBody:new(self)
        self.body:initialise()
        self:addChild(self.body)
        self.body:fit(self.width, self.bodyH, self.contentH)
        self.closeBtn = N.closeButton(self.width, self.m.head, self, self.close)
        self:addChild(self.closeBtn)
        self:layoutButtons()
        self:setWantKeyEvents(true)
    end

    --- Re-read the gate. False when the window closed because the gate is gone or the survivor
    --- walked out of reach. It opens only at the gate: M.startInspect walks the survivor there.
    function LugliDMSInspectWindow:refresh()
        if not self:read() or not inReach(self.player, self.obj) then
            self:close()
            return false
        end
        local sig = signature(self)
        if sig ~= self.sig then
            self.sig = sig
            self:applyLayout()
        end
        return true
    end

    --- Start a route. M.startRoute is Actions.lua's, read when pressed: that file loads after this one.
    function LugliDMSInspectWindow:startRoute(id)
        local can = false
        for _, s in ipairs(startable(self)) do if s.id == id then can = true end end
        if not can then return end
        local player, obj = self.player, self.obj
        self:close()
        if type(M.startRoute) ~= "function" then
            M.defect(PART, "M.startRoute is not defined, Actions.lua did not load")
            return
        end
        M.startRoute(player, obj, id)
    end

    function LugliDMSInspectWindow:onStart(button)
        self:startRoute(button.routeId)
    end

    function LugliDMSInspectWindow:close()
        self:setVisible(false)
        self:removeFromUIManager()
        if padDrives(self.playerNum) then
            pcall(setJoypadFocus, self.playerNum, nil)
        end
        if open[self.playerNum] == self then open[self.playerNum] = nil end
    end

    --- Asked by the UI manager for each key this window is handed: true keeps Esc from opening
    --- the pause menu under it.
    function LugliDMSInspectWindow:isKeyConsumed(key)
        return isEsc(key)
    end

    function LugliDMSInspectWindow:onKeyRelease(key)
        if isEsc(key) and self:isVisible() then self:close() end
    end

    --- Bring the chosen route's button into view, through the scroll view's own easing.
    function LugliDMSInspectWindow:showSpot(spot)
        local view = -self.body:getYScroll()
        local target = nil
        if spot.y < view then
            target = -spot.y
        elseif spot.y + spot.h > view + self.bodyH then
            target = -(spot.y + spot.h - self.bodyH)
        end
        if target ~= nil then self.body.smoothScrollTargetY = target end
    end

    --- The d-pad walks every route row, greyed ones too, so a reason below the fold can be read;
    --- A on a greyed one starts nothing. With no rows it scrolls the body.
    function LugliDMSInspectWindow:moveChoice(step)
        local rows = self.spots
        if #rows == 0 then
            self.body:onMouseWheel(step)
            return
        end
        local at = 1
        for i, s in ipairs(rows) do if s.id == self.selId then at = i end end
        at = M.clamp(at + step, 1, #rows)
        self.selId = rows[at].id
        for _, b in ipairs(self.routeBtns) do b.joypadFocused = b.routeId == self.selId end
        self:showSpot(rows[at])
    end

    function LugliDMSInspectWindow:onJoypadDown(button)
        if button == Joypad.AButton then
            if self.selId ~= nil then self:startRoute(self.selId) end
        elseif button == Joypad.BButton then
            self:close()
        end
    end

    function LugliDMSInspectWindow:onJoypadDirUp() self:moveChoice(-1) end
    function LugliDMSInspectWindow:onJoypadDirDown() self:moveChoice(1) end

    --- The wheel scrolls a body that scrolls from the title bar too: left to vanilla it zoomed
    --- the map there. A body that fits leaves the wheel alone.
    function LugliDMSInspectWindow:onMouseWheel(del)
        if self.body == nil or self.contentH <= self.bodyH then return false end
        return self.body:onMouseWheel(del)
    end

    function LugliDMSInspectWindow:prerender()
        N.followView(self)
        local p = self.player
        local ok, dead = pcall(function() return p:isDead() end)
        if ok and dead == true then
            self:close()
            return
        end
        -- Twice a second, not every frame: every route searches the survivor's bags for a tool.
        local now = getTimestampMs ~= nil and getTimestampMs() or 0
        if now >= (self.nextRefresh or 0) then
            self.nextRefresh = now + M.INSPECT_REFRESH_MS
            if not self:refresh() then return end
        end
        local m = self.m
        N.window(self, 0, 0, self.width, self.height, m.head)
        N.title(self, self.titleShown, m.pad, m.head)
    end

    -- ---- the scrolling body -------------------------------------------------------------------
    -- The framework's scroll view, so the title bar stays put while the body scrolls under it:
    -- its wheel, its bar, its clip, and the route buttons as its scroll children.

    function LugliDMSInspectBody:new(win)
        local o = NIScrollView.new(self, 0, win.m.head, win.width, win.bodyH)
        o.win = win
        o:setScrollSensitivity(win.m.row * 2)
        return o
    end

    function LugliDMSInspectBody:fit(w, h, contentH)
        self:setWidth(w)
        self:setHeight(h)
        self:setScrollHeight(contentH)
    end

    function LugliDMSInspectBody:prerender()
        NIScrollView.prerender(self)
        for _, op in ipairs(self.win.ops) do
            if op.box then
                N.inner(self, op.x, op.y, op.w, op.h, 0.7)
            elseif op.bar then
                N.progress(self, op.x, op.y, op.w, op.h, op.frac)
            elseif op.icon ~= nil then
                N.icon(self, op.icon, op.x, op.y, op.size, op.c)
            elseif op.tex ~= nil then
                self:drawTextureScaledAspect(op.tex, op.x, op.y, op.size, op.size, op.a, 1, 1, 1)
            else
                self:drawText(op.s, op.x, op.y, op.c.r, op.c.g, op.c.b, 1, FONT)
            end
        end
    end

    -- ---- opening it ---------------------------------------------------------------------------

    --- Show the window for a gate. One per survivor: asked again for the same gate it comes to
    --- the front, asked for another it replaces the first. Nil for an object that is no gate.
    function M.openInspect(player, obj)
        local num = playerNumOf(player)
        local cur = open[num]
        if cur ~= nil and cur.obj == obj and cur:isVisible() then
            cur:bringToTop()
            if padDrives(num) then pcall(setJoypadFocus, num, cur) end
            return cur
        end
        if cur ~= nil then cur:close() end
        if M.gateRecord(obj) == nil then return nil end
        local win = LugliDMSInspectWindow:new(player, obj)
        win:initialise()
        win:instantiate()
        win:addToUIManager()
        win:setVisible(true)
        pcall(function() getSoundManager():playUISound("UIActivateTab") end)
        open[num] = win
        if padDrives(num) then pcall(setJoypadFocus, num, win) end
        return win
    end

    M.addTeardown(PART, function()
        for _, win in pairs(open) do win:close() end
    end)
    M.status(PART, true)
end
