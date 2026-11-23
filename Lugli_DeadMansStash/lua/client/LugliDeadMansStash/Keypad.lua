--[[
    Keypad
    A safe's code window, on the same NeatUI chrome as the inspect window, with one face per
    lock, painted by tools/dms-ui-art.py (media/ui/LugliDMS/Keypad and Dial). A keypad safe has a
    segment display and a 3x4 pad: digits type left to right, C clears, OK enters, a light answers
    red or green. A dial safe has a combination dial: turned right, left, right, left, each change
    of direction sets the number under the index, and the last is set the same way or tried where
    it stands; a turn left before the first right is refused. The dial eases through its baked
    frames the way it was turned. Above the lock, one line says what to do
    now; under everything, the controls of the keyboard or the controller driving it. Beside the
    lock: the tries left as pips, the notes the survivor carries about this safe, and the codes
    already tried on it this session.

    It never knows the code. Submitting hands the four digits to the caller's onSubmit and does
    nothing else; the authority's verdict comes back through M.keypadResult. It closes when the
    survivor walks off or dies.
]]

require "ISUI/ISPanelJoypad"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Neat"
require "LugliDeadMansStash/InspectWindow"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local N = M.neat
    local PART = "Keypad"

    local FONT = N.FONT

    M.KEYPAD_DIGITS = 4
    M.KEYPAD_KINDS = { dialsafe = true, keypadsafe = true }
    --- How long a wrong code shakes the lock, how long the light stays lit, and how long the
    --- green light shows before the window gives way to the open safe.
    M.KEYPAD_SHAKE_MS, M.KEYPAD_LIGHT_MS, M.KEYPAD_OPEN_MS = 450, 900, 600
    --- The notes are re-read this often; the most shown, and the tried codes kept, per safe.
    M.KEYPAD_NOTES_MS, M.KEYPAD_NOTES_SHOWN, M.KEYPAD_TRIED_KEPT = 500, 4, 8
    --- After a reply, how long the safe's tag is left unread, so a late tag cannot undo it.
    M.KEYPAD_QUIET_MS = 1000

    --- How long a key typed from the keyboard shows pressed, and how long the dial takes to turn
    --- one number (four of its 40 frames) when it is not already behind.
    M.KEYPAD_KEY_FLASH_MS, M.KEYPAD_DIAL_STEP_MS = 120, 90
    M.DIAL_FRAMES = 40
    --- How long the line on top says why a turn left before the first right did nothing.
    M.DIAL_REFUSED_MS = 1500

    --- The dial's two ways: right is clockwise, which brings the lower numbers to the mark.
    local RIGHT, LEFT = 1, -1

    --- The display's segment colour (tools/dms-ui-art.py KEYPAD_LCD).
    local LCD_GREEN = { r = 128 / 255, g = 232 / 255, b = 150 / 255 }
    local KEY_INK = { r = 22 / 255, g = 22 / 255, b = 24 / 255 }

    -- Where the pieces sit on their backdrops, in the art's own pixels (the art tool's docstring).
    local FACEPLATE_W, FACEPLATE_H = 300, 400
    local LCD_GLASS = { x = 40, y = 36, w = 196, h = 72 }
    local LED_SOCKET = { x = 242, y = 52, w = 40, h = 40 }
    local KEY_ORIGIN_X, KEY_ORIGIN_Y, KEY_STEP_X, KEY_STEP_Y, KEY_W, KEY_H = 34, 136, 80, 64, 72, 56
    local SEG_PITCH, SEG_COLON_PITCH, SEG_W = 40, 24, 32
    local PLATE, FACE, FACE_AT = 360, 256, 52
    local INDEX = { x = 160, y = 8, w = 40, h = 48 }
    local WINDOW_W, WINDOW_H, WINDOW_X, WINDOW_STEP, WINDOW_GAP = 64, 80, 37, 74, 12
    local TURN = 64

    --- The keypad's keys in reading order: three rows of digits, then clear, 0 and enter.
    local PAD = { 1, 2, 3, 4, 5, 6, 7, 8, 9, "clear", 0, "enter" }

    --- Keyboard field name to the digit it types: the top row and the numpad, whose codes are
    --- not contiguous.
    local DIGIT_KEYS = {
        KEY_0 = 0, KEY_1 = 1, KEY_2 = 2, KEY_3 = 3, KEY_4 = 4, KEY_5 = 5, KEY_6 = 6, KEY_7 = 7, KEY_8 = 8, KEY_9 = 9,
        KEY_NUMPAD0 = 0, KEY_NUMPAD1 = 1, KEY_NUMPAD2 = 2, KEY_NUMPAD3 = 3, KEY_NUMPAD4 = 4,
        KEY_NUMPAD5 = 5, KEY_NUMPAD6 = 6, KEY_NUMPAD7 = 7, KEY_NUMPAD8 = 8, KEY_NUMPAD9 = 9,
    }
    local BOTH_KEYS = { "KEY_ESCAPE", "KEY_RETURN", "KEY_NUMPADENTER", "KEY_BACK" }
    local DIAL_KEYS = { "KEY_LEFT", "KEY_RIGHT", "KEY_A", "KEY_D" }

    LugliDMSKeypadWindow = ISPanelJoypad:derive("LugliDMSKeypadWindow")
    local W = LugliDMSKeypadWindow

    --- The open window of each local player, by player number.
    local open = {}
    --- The codes tried and refused, by safe (its gate id, else the object), newest first.
    local tried = {}

    local function isKey(key, name)
        return Keyboard ~= nil and Keyboard[name] ~= nil and key == Keyboard[name]
    end

    local function keyDigit(key)
        for name, d in pairs(DIGIT_KEYS) do
            if isKey(key, name) then return d end
        end
        return nil
    end

    local function anyKey(key, names)
        for _, name in ipairs(names) do
            if isKey(key, name) then return true end
        end
        return false
    end

    local function measure(s, font)
        local ok, w = pcall(function() return getTextManager():MeasureStringX(font or FONT, s) end)
        if ok and type(w) == "number" then return w end
        return #s * 6
    end

    local function fontHeight(font)
        local ok, h = pcall(function() return getTextManager():getFontHeight(font) end)
        if ok and type(h) == "number" then return h end
        return N.fontH()
    end

    local function digitFont()
        return UIFont.Large or FONT
    end

    --- The pad's labels: a size up from the body, as printed keys are.
    local KEY_FONT = UIFont.Medium or FONT

    local function playerNumOf(player)
        local ok, n = pcall(function() return player:getPlayerNum() end)
        if ok and type(n) == "number" then return n end
        return 0
    end

    local function padDrives(playerNum)
        return JoypadState ~= nil and JoypadState.players[playerNum + 1] ~= nil
    end

    local function nowMs()
        return getTimestampMs ~= nil and getTimestampMs() or 0
    end

    local function worldHours()
        local ok, h = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and type(h) == "number" then return h end
        return 0
    end

    --- 0 to n - 1 whatever `v` is: Kahlua's % keeps the dividend's sign (Java's remainder).
    local function wrap(v, n)
        local r = v % n
        if r < 0 then r = r + n end
        return r
    end

    local function wrap10(v)
        return wrap(v, 10)
    end

    --- The sandbox's tries a safe starts with, when the client can read it.
    local function triesCap()
        if type(M.cfg) ~= "function" then return nil end
        local ok, v = pcall(M.cfg, "SafeTries")
        if ok then return M.finite(v) end
        return nil
    end

    -- ---- what it knows ------------------------------------------------------------------------

    --- Take the view's fields. `revealed` is read only when it is exactly four characters of
    --- digits and "?" with a digit found: object modData is client-writable (docs/31 section 7).
    function W:setView(view)
        self.kind = view.kind
        local tries = M.finite(view.triesLeft)
        self.triesLeft = tries ~= nil and math.max(0, math.floor(tries)) or nil
        self.triesMax = math.max(self.triesMax or 0, self.triesLeft or 0, math.floor(triesCap() or 0))
        self.lockedFor = math.max(0, M.finite(view.lockedFor) or 0)
        self.lockAt = worldHours()
        self.powered = view.powered
        local s = view.revealed
        self.mask = nil
        if type(s) == "string" and #s == M.KEYPAD_DIGITS and string.find(s, "^[%d%?]+$") ~= nil
            and string.find(s, "%d") ~= nil then
            self.mask = s
        end
    end

    function W:isDial()
        return self.kind == "dialsafe"
    end

    --- The window's sound for `slot` (key, tick, submit) on this kind of safe (Sounds.lua).
    function W:sound(slot)
        local own = M.CODE_WINDOW_SOUNDS[self.kind]
        local name = own ~= nil and own[slot] or nil
        if type(name) == "string" then N.sound(name) end
    end

    --- False for a keypad without power: nothing can be entered.
    function W:entryOn()
        return not (self.kind == "keypadsafe" and self.powered == false)
    end

    --- Game hours left of a lockout, counted down from when it was learnt.
    function W:lockedLeft()
        return math.max(0, self.lockedFor - (worldHours() - self.lockAt))
    end

    --- Can the lock be worked now: power, no lockout, and not already opening.
    function W:live()
        return self:entryOn() and self:lockedLeft() <= 0 and self.openedAt == nil
    end

    --- The four digits as they stand, or nil while the lock does not hold four.
    function W:code()
        if self:isDial() then
            if self:dialFull() then return table.concat(self.set) end
            if #self.set ~= M.KEYPAD_DIGITS - 1 or self.dir ~= LEFT then return nil end
            return table.concat(self.set) .. tostring(self.pos)
        end
        if #self.typed ~= M.KEYPAD_DIGITS then return nil end
        return self.typed
    end

    function W:canSubmit()
        return self:live() and self:code() ~= nil
    end

    --- The safe this window remembers its tries under.
    function W:triedKey()
        return M.gateIdOf(self.obj) or self.obj
    end

    function W:triedList()
        return tried[self:triedKey()] or {}
    end

    local function remember(key, code)
        local list = tried[key] or {}
        for i = #list, 1, -1 do
            if list[i] == code then table.remove(list, i) end
        end
        table.insert(list, 1, code)
        while #list > M.KEYPAD_TRIED_KEPT do table.remove(list) end
        tried[key] = list
    end

    --- The clue texts carried about this safe, as Codes.lua lists them (InspectWindow.lua reads it).
    function W:readNotes()
        local out = {}
        for _, n in ipairs(M.notesAbout(self.player, self.obj)) do
            if type(n) == "table" and type(n.text) == "string" and n.text ~= "" then out[#out + 1] = n.text end
        end
        self.notes = out
    end

    -- ---- the keypad ---------------------------------------------------------------------------

    function W:edited()
        self.wrong = false
    end

    --- Show key `i` (PAD's order) pressed for a moment, as a key typed from the keyboard is.
    function W:flashKey(i)
        self.flashIndex, self.flashAt = i, nowMs()
    end

    function W:keyFlashing(i)
        return self.flashIndex == i and self.flashAt ~= nil and nowMs() - self.flashAt < M.KEYPAD_KEY_FLASH_MS
    end

    --- A digit typed goes on the end; a fifth is not taken.
    function W:typeDigit(d)
        if self:isDial() or not self:live() then return end
        if #self.typed >= M.KEYPAD_DIGITS then return end
        self.typed = self.typed .. tostring(d)
        self:flashKey(d == 0 and 11 or d)
        self:sound("key")
        self:edited()
    end

    --- Backspace: the last digit typed. On the dial, the dial starts over.
    function W:erase()
        if self:isDial() then
            self:resetDial()
            return
        end
        if not self:live() or self.typed == "" then return end
        self.typed = string.sub(self.typed, 1, #self.typed - 1)
        self:sound("key")
        self:edited()
    end

    function W:clearTyped()
        if self:isDial() or not self:live() then return end
        self.typed = ""
        self:flashKey(10)
        self:sound("key")
        self:edited()
    end

    --- Key `i` of the pad (PAD's order) pressed.
    function W:pressKey(i)
        local k = PAD[i]
        if k == "clear" then
            self:clearTyped()
        elseif k == "enter" then
            self:submit()
        elseif k ~= nil then
            self:typeDigit(k)
        end
    end

    -- ---- the dial -----------------------------------------------------------------------------

    --- True once all four numbers are set: the dial holds them until they are tried or reset.
    function W:dialFull()
        return #self.set >= M.KEYPAD_DIGITS
    end

    --- One step of the dial `way` (RIGHT or LEFT). The first number is reached turning right, so a
    --- turn left before it is refused, and the line on top says why. Each change of direction
    --- after that sets the number at the mark, the fourth too, which leaves the dial where it is:
    --- a survivor turning back to lock in the last number, as every other one is, must not lose
    --- the three before it.
    function W:turnDial(way)
        if not self:isDial() or self.openedAt ~= nil or self:dialFull() then return end
        if self.dir == nil and way ~= RIGHT then
            self.refusedAt = nowMs()
            return
        end
        self.refusedAt = nil
        if self.dir == nil then
            self.dir = RIGHT
        elseif way ~= self.dir then
            self.set[#self.set + 1] = self.pos
            self.dir = way
            if self:dialFull() then
                self:sound("tick")
                self:edited()
                return
            end
        end
        self.pos = wrap10(self.pos - way)
        self.frameTarget = self.frameTarget - 4 * way
        self:sound("tick")
        self:edited()
    end

    --- The way the next number is set: right for the first and third, left for the second and
    --- the last.
    function W:wayNow()
        return self:spin() % 2 == 1 and RIGHT or LEFT
    end

    --- Bring the frame shown toward the dial's, the way it turned (a turn right from 0 runs 0, 39,
    --- 38 ...), at a number per KEYPAD_DIAL_STEP_MS and faster the further it is behind, so a
    --- held key or a fast drag never leaves it lagging.
    function W:easeDial(now)
        local dt = math.max(0, now - (self.frameAt or now))
        self.frameAt = now
        local diff = self.frameTarget - self.frameShown
        if diff == 0 then return end
        local stepF = dt * 4 / M.KEYPAD_DIAL_STEP_MS * math.max(1, math.abs(diff) / 4)
        if stepF >= math.abs(diff) then
            self.frameShown = self.frameTarget
        else
            self.frameShown = self.frameShown + (diff > 0 and stepF or -stepF)
        end
        -- Kept near zero: only the difference and the frame mod 40 mean anything.
        local whole = M.DIAL_FRAMES * math.floor(self.frameTarget / M.DIAL_FRAMES)
        self.frameTarget, self.frameShown = self.frameTarget - whole, self.frameShown - whole
    end

    --- The baked frame shown now: Dial/Face_<frame>, which has number frame / 4 at the index.
    function W:dialFrame()
        return wrap(math.floor(self.frameShown + 0.5), M.DIAL_FRAMES)
    end

    function W:resetDial()
        if not self:isDial() or self.openedAt ~= nil then return end
        self.set, self.dir, self.refusedAt = {}, nil, nil
        self:edited()
    end

    --- Which number the survivor is on: 1 to 4, the slot the mark is filling.
    function W:spin()
        if self.dir == nil then return 1 end
        return #self.set + 1
    end

    local function angleOf(dx, dy)
        return math.atan2(dy, dx)
    end

    function W:onDial(x, y)
        local d = self.dial
        if d == nil then return false end
        local dx, dy = x - d.cx, y - d.cy
        return dx * dx + dy * dy <= d.r * d.r
    end

    --- The pointer at x, y while dragging: every tenth of a turn round the centre is a step, the
    --- way it went. Close to the centre the angle means nothing and is skipped.
    function W:dragTo(x, y)
        local d = self.dial
        local dx, dy = x - d.cx, y - d.cy
        if dx * dx + dy * dy < self.m.dead * self.m.dead then return end
        local a = angleOf(dx, dy)
        local delta = a - self.dragAngle
        while delta > math.pi do delta = delta - 2 * math.pi end
        while delta <= -math.pi do delta = delta + 2 * math.pi end
        self.dragAngle = a
        self.dragAcc = self.dragAcc + delta
        local step = 2 * math.pi / 10
        while self.dragAcc >= step do
            self.dragAcc = self.dragAcc - step
            self:turnDial(RIGHT)
        end
        while self.dragAcc <= -step do
            self.dragAcc = self.dragAcc + step
            self:turnDial(LEFT)
        end
    end

    -- ---- the reply ----------------------------------------------------------------------------

    --- Hand the code to the caller. True when the caller took it (onSubmit returned true): only
    --- then is it the code a reply answers, so a refused second Enter never replaces the first.
    function W:submit()
        if not self:canSubmit() then return false end
        local code = self:code()
        local ok, taken = pcall(self.onSubmit, code)
        if not ok then
            M.defect(PART, "onSubmit failed: " .. tostring(taken))
            return false
        end
        if taken ~= true then return false end
        self.pending = code
        if not self:isDial() then self:flashKey(12) end
        self:sound("submit")
        return true
    end

    --- Take the safe as its tag reads now: tries, power, lockout and digits found change between
    --- replies, by another survivor or the clock. Closed once it is no longer sealed, unless it
    --- is this window's own opening, whose green light closes it. A reply's tag can land after
    --- the reply itself (docs/31 section 7), so the tag is not read again for a moment after one.
    function W:reread(now)
        if self.viewOf == nil or self.openedAt ~= nil or now < (self.quietUntil or 0) then return end
        local ok, view = pcall(self.viewOf)
        if not ok then
            M.defect(PART, "viewOf failed: " .. tostring(view))
            self.viewOf = nil
            return
        end
        if view == nil then
            self:close()
            return
        end
        if type(view) == "table" then self:setView(view) end
    end

    function W:light(c)
        self.lightC, self.lightAt = c, nowMs()
    end

    --- The authority's reply. Right lights green and closes the window a moment later; wrong and
    --- lockout light red, shake it, remember the code as tried, clear the lock for another go,
    --- and take the tries left and the lockout the reply carries.
    function W:result(outcome, args)
        if outcome == "right" or outcome == "opened" then
            self:light(N.good)
            self.openedAt = nowMs()
            return true
        end
        if outcome ~= "wrong" and outcome ~= "lockout" then return false end
        self.quietUntil = nowMs() + M.KEYPAD_QUIET_MS
        local tries = M.finite(args.triesLeft)
        if tries ~= nil then
            self.triesLeft = math.max(0, math.floor(tries))
            self.triesMax = math.max(self.triesMax, self.triesLeft)
        end
        local hours = M.finite(args.lockedFor)
        if outcome == "lockout" and hours ~= nil then
            self.lockedFor = math.max(0, hours)
            self.lockAt = worldHours()
        end
        if self.pending ~= nil then
            remember(self:triedKey(), self.pending)
            self.pending = nil
        end
        self.typed = ""
        self.set, self.dir = {}, nil
        self.wrong = true
        self.shakeAt = nowMs()
        self:light(N.bad)
        return true
    end

    -- ---- words --------------------------------------------------------------------------------

    --- What to do now, as { s, c }: the one line above the lock. Dark, locked out, or the step.
    local function instruction(self)
        if not self:entryOn() then
            return { s = M.T("UI_LugliDMS_Keypad_NoPower", "No power. A battery in its compartment would wake it."), c = N.bad }
        end
        local left = self:lockedLeft()
        if left > 0 then return { s = M.lockoutText(left), c = N.bad } end
        if self:isDial() then
            if self.refusedAt ~= nil and nowMs() - self.refusedAt < M.DIAL_REFUSED_MS then
                return { s = M.T("UI_LugliDMS_Dial_RightFirst", "The first number is dialed turning right."), c = N.bad }
            end
            if self:dialFull() then
                return { s = M.T("UI_LugliDMS_Dial_Ready", "All four numbers are set. Try the combination, or reset to start over."),
                         c = N.accent }
            end
            return { s = M.T("UI_LugliDMS_Dial_Turn" .. self:spin(), ""), c = N.accent }
        end
        return { s = M.T("UI_LugliDMS_Keypad_Prompt_keypadsafe", "Type the four-digit code, then press OK."), c = N.text }
    end

    --- The lines over the tries, as { s, c }: what the last try did and the last try's warning.
    local function statusLines(self)
        local out = {}
        if not self:entryOn() or self:lockedLeft() > 0 then return out end
        if self.wrong then
            out[#out + 1] = { s = M.T("UI_LugliDMS_Keypad_Wrong", "That is not the code."), c = N.bad }
        end
        if self.triesLeft == 1 then
            out[#out + 1] = { s = M.T("UI_LugliDMS_Keypad_TriesOne", "One try left before it locks."), c = N.accent }
        end
        return out
    end

    --- The controls bar's entries for the keyboard or, when one drives the window, the controller.
    local function controls(self)
        local function cap(k, fallback) return M.T("UI_LugliDMS_Cap_" .. k, fallback) end
        local function word(k, fallback) return M.T("UI_LugliDMS_Hint_" .. k, fallback) end
        if padDrives(self.playerNum) then
            -- key: the name on a plain cap, for a controller the game has no glyph for.
            if self:isDial() then
                return { { pad = "DPad", key = "D-pad", label = word("Turn", "Turn") },
                         { pad = "AButton", key = "A", label = word("Try", "Try") },
                         { pad = "XButton", key = "X", label = word("Reset", "Reset") },
                         { pad = "BButton", key = "B", label = word("Close", "Close") } }
            end
            return { { pad = "DPad", key = "D-pad", label = word("Move", "Move") },
                     { pad = "AButton", key = "A", label = word("Press", "Press") },
                     { pad = "YButton", key = "Y", label = word("Try", "Try") },
                     { pad = "BButton", key = "B", label = word("Close", "Close") } }
        end
        if self:isDial() then
            return { { key = "A / D", label = word("Turn", "Turn") }, { key = cap("Enter", "Enter"), label = word("Try", "Try") },
                     { key = cap("Backspace", "Backspace"), label = word("Reset", "Reset") },
                     { mouse = "Mouse_Drag", label = word("Turn", "Turn") } }
        end
        return { { key = "0-9", label = word("Type", "Type") }, { key = cap("Backspace", "Backspace"), label = word("Erase", "Erase") },
                 { key = cap("Enter", "Enter"), label = word("Try", "Try") }, { key = cap("Esc", "Esc"), label = word("Close", "Close") } }
    end

    local function texts(self)
        local kind = tostring(self.kind)
        local t = {
            title = M.T("UI_LugliDMS_Keypad_Title_" .. kind, kind),
            instruction = instruction(self),
            controls = controls(self),
            submit = M.T("UI_LugliDMS_Keypad_Submit_" .. kind, "Enter"),
            status = statusLines(self),
            tries = M.T("UI_LugliDMS_Keypad_TriesLabel", "Tries left"),
            notes = M.T("UI_LugliDMS_Keypad_Notes", "Your notes"),
            noNotes = M.T("UI_LugliDMS_Keypad_NoNotes", "You carry no notes about this safe."),
            tried = M.T("UI_LugliDMS_Keypad_Tried", "Tried"),
            noneTried = M.T("UI_LugliDMS_Keypad_NoneTried", "Nothing tried yet."),
            clear = M.T("UI_LugliDMS_Keypad_KeyClear", "C"),
            enter = M.T("UI_LugliDMS_Keypad_KeyEnter", "OK"),
            reset = M.T("UI_LugliDMS_Dial_Reset", "Reset"),
        }
        if self.mask ~= nil then t.found = M.Tf("UI_LugliDMS_Found", "Numbers found so far: %1", self.mask) end
        return t
    end

    -- ---- the layout ---------------------------------------------------------------------------

    local function metrics()
        local k = N.metrics()
        local u = k.u
        -- plate: the keypad's faceplate width, dial: the dial's face diameter, each shrinking to
        -- its floor to keep the window on the screen.
        return { fh = k.fh, u = u, head = k.head, pad = k.pad, gap = k.gap, nudge = u(4), btnH = k.btnH,
                 btnPad = k.btnPad, plate = u(240), plateMin = u(150), dial = u(180), dialMin = u(110),
                 turnMin = u(22), dead = u(6), colGap = u(18), sideW = u(220), sideMax = u(320), pip = u(10),
                 pipGap = u(5), shake = u(7), rule = u(2), indent = u(10), hintH = u(22), noteLines = 3,
                 minW = u(320) }
    end

    --- The side column at x, y, `width` wide, as draw operations added to `ops`: the status, the
    --- tries as pips, the digits found, the notes and the codes tried. As many
    --- notes are listed as fit above `limit` with the tried codes under them, up to
    --- M.KEYPAD_NOTES_SHOWN, and the rest counted. Returns its bottom.
    function W:side(ops, t, x, y, width, limit)
        local m = self.m
        local function lines(s, c, dx, maxLines)
            local wrapped = N.wrap(s, width - (dx or 0), FONT)
            for i, line in ipairs(wrapped) do
                if maxLines ~= nil and i == maxLines and #wrapped > maxLines then
                    line = N.fit(line .. " " .. wrapped[i + 1], width - (dx or 0), FONT)
                end
                ops[#ops + 1] = { s = line, x = x + (dx or 0), y = y, c = c }
                y = y + m.fh
                if maxLines ~= nil and i >= maxLines then break end
            end
        end
        for _, line in ipairs(t.status) do lines(line.s, line.c) end
        -- THE TRIES: the label and its pips on one line when they fit, the pips under it when not.
        if self.triesLeft ~= nil and self:entryOn() and self:lockedLeft() <= 0 then
            local total = math.min(20, math.max(self.triesMax, self.triesLeft))
            local labelW = measure(t.tries)
            local inline = labelW + m.gap + total * (m.pip + m.pipGap) <= width
            local px, rowH = x, m.fh
            if inline then
                ops[#ops + 1] = { s = t.tries, x = x, y = y, c = N.textDim }
                px = x + labelW + m.gap
            else
                lines(t.tries, N.textDim)
                y = y + m.nudge
                rowH = m.pip
            end
            local py = y + math.floor((rowH - m.pip) / 2)
            for i = 1, total do
                if px + m.pip > x + width then
                    px = x
                    py = py + m.pip + m.pipGap
                end
                ops[#ops + 1] = { pip = true, x = px, y = py, size = m.pip, filled = i <= self.triesLeft,
                                  c = self.triesLeft == 1 and N.bad or N.accent }
                px = px + m.pip + m.pipGap
            end
            y = math.max(y + rowH, py + m.pip) + m.gap
        end
        if t.found ~= nil then lines(t.found, N.accent) end
        y = y + m.gap

        local list = self:triedList()
        local triedText = #list == 0 and t.noneTried or table.concat(list, " / ")
        local reserve = m.gap + m.fh + m.nudge + #N.wrap(triedText, width, FONT) * m.fh
        if #self.notes > 0 then reserve = reserve + m.fh end

        lines(t.notes, N.text)
        y = y + m.nudge
        if #self.notes == 0 then
            lines(t.noNotes, N.textFaint)
        end
        local shown = 0
        for i = 1, math.min(#self.notes, M.KEYPAD_NOTES_SHOWN) do
            local n = math.min(#N.wrap(self.notes[i], width - m.indent, FONT), m.noteLines)
            if y + n * m.fh + m.nudge + reserve > limit then break end
            local top = y
            lines(self.notes[i], N.textDim, m.indent, m.noteLines)
            ops[#ops + 1] = { rule = true, x = x, y = top, w = m.rule, h = y - top, c = N.accent }
            y = y + m.nudge
            shown = i
        end
        if #self.notes > shown then
            lines(M.Tf("UI_LugliDMS_Keypad_MoreNotes", "and %1 more", #self.notes - shown), N.textFaint, m.indent)
        end
        y = y + m.gap

        lines(t.tried, N.text)
        y = y + m.nudge
        lines(triedText, #list == 0 and N.textFaint or N.textDim)
        return y
    end

    --- A rect of the art's pixels on a backdrop at ox, oy drawn `s` screen pixels a pixel.
    local function artRect(ox, oy, s, r)
        local x0, y0 = math.floor(ox + r.x * s + 0.5), math.floor(oy + r.y * s + 0.5)
        return { x = x0, y = y0, w = math.floor(ox + (r.x + r.w) * s + 0.5) - x0,
                 h = math.floor(oy + (r.y + r.h) * s + 0.5) - y0 }
    end

    --- The keypad's faceplate at x, y drawn `s` screen pixels an art pixel, its display, light and
    --- key cells on it. Returns its width and height.
    function W:layoutKeypad(x, y, s)
        self.plate = { x = x, y = y, s = s, w = math.floor(FACEPLATE_W * s + 0.5), h = math.floor(FACEPLATE_H * s + 0.5) }
        self.lcd = artRect(x, y, s, LCD_GLASS)
        self.led = artRect(x, y, s, LED_SOCKET)
        self.keyRects = {}
        for i = 1, #PAD do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            self.keyRects[i] = artRect(x, y, s, { x = KEY_ORIGIN_X + col * KEY_STEP_X, y = KEY_ORIGIN_Y + row * KEY_STEP_Y,
                                                  w = KEY_W, h = KEY_H })
        end
        return self.plate.w, self.plate.h
    end

    --- The dial's device width at scale `s`: its plate between its two turn arrows.
    local function dialWidth(m, s)
        local turn = math.max(m.turnMin, math.floor(TURN * s + 0.5))
        return math.floor(PLATE * s + 0.5) + 2 * (turn + m.gap), turn
    end

    --- The dial at x, y, drawn `s` screen pixels an art pixel: its plate with the face and the
    --- index, a turn arrow each side, the four number windows under it, then Reset and the try
    --- button. Returns its width and height.
    function W:layoutDial(x, y, s)
        local m = self.m
        local w, turn = dialWidth(m, s)
        local px = x + turn + m.gap
        self.plate = { x = px, y = y, s = s, w = math.floor(PLATE * s + 0.5), h = math.floor(PLATE * s + 0.5) }
        self.dial = { cx = math.floor(px + (FACE_AT + FACE / 2) * s + 0.5), cy = math.floor(y + (FACE_AT + FACE / 2) * s + 0.5),
                      r = math.floor(FACE / 2 * s) }
        self.markRect = artRect(px, y, s, INDEX)
        local ty = y + math.floor((self.plate.h - turn) / 2)
        self.turnRects = { left = { x = x, y = ty, w = turn, h = turn }, right = { x = x + w - turn, y = ty, w = turn, h = turn } }
        self.slots = {}
        for i = 1, M.KEYPAD_DIGITS do
            self.slots[i] = artRect(px, y, s, { x = WINDOW_X + (i - 1) * WINDOW_STEP, y = PLATE + WINDOW_GAP, w = WINDOW_W, h = WINDOW_H })
        end
        -- The buttons span the device, arrows included; a try label too long for the row beside
        -- Reset (a large font, a long language) takes a row of its own under it, unless the screen
        -- is too short for one (W:layout sets tryRow false), where the label is cut instead.
        local iy = self.slots[1].y + self.slots[1].h + m.gap
        local resetW = math.min(math.floor(w / 3), measure(self.text.reset) + m.btnPad * 2)
        local tryW = math.max(measure(self.text.submit), measure(M.Tf("UI_LugliDMS_Dial_TryCode", "Try %1", "0000")))
            + m.btnPad * 2
        self.turnRects.reset = { x = x, y = iy, w = resetW, h = m.btnH }
        if w - resetW - m.gap >= tryW or self.tryRow == false then
            self.submitRect = { x = x + resetW + m.gap, y = iy, w = w - resetW - m.gap, h = m.btnH }
        else
            self.turnRects.reset.w = w
            iy = iy + m.btnH + m.gap
            self.submitRect = { x = x, y = iy, w = w, h = m.btnH }
        end
        return w, iy + m.btnH - y
    end

    --- The device's scale, its full size, and its floor: the dial's face, else the faceplate.
    local function scales(self)
        local m = self.m
        if self:isDial() then return m.dial / FACE, m.dialMin / FACE end
        return m.plate / FACEPLATE_W, m.plateMin / FACEPLATE_W
    end

    --- The device's width and height at scale `s`, laid out at x, y.
    function W:layoutDevice(x, y, s)
        if self:isDial() then return self:layoutDial(x, y, s) end
        return self:layoutKeypad(x, y, s)
    end

    --- Size the window and place everything on it, in the window's own coordinates: what to do
    --- now on top, the lock under it, and the controls at the bottom. The lock stands left and the
    --- side column right when the screen is wide enough, else the column goes under the lock. The
    --- lock shrinks, never below its floor, to keep the window on the screen.
    function W:layout()
        local m = self.m
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local t = texts(self)
        self.text = t
        self.tryRow = nil
        local full, floor = scales(self)
        local devW = self:layoutDevice(0, 0, full)
        local sideW = math.min(m.sideMax, math.max(m.sideW, measure(t.notes), measure(t.tried), measure(t.tries)))
        local titleW = measure(t.title, N.TITLE_FONT) + m.head
        local room = sw - m.pad * 2 - devW - m.colGap
        local twoCol = sideW <= room
        local inner
        if twoCol then
            sideW = math.min(m.sideMax, room)
            inner = math.max(devW + m.colGap + sideW, titleW, m.minW - m.pad * 2)
            sideW = inner - devW - m.colGap
        else
            inner = math.min(math.max(devW, titleW, m.minW - m.pad * 2, sideW), sw - m.pad * 2)
            sideW = inner
        end

        local ops, y = {}, m.head + m.pad
        local say = t.instruction
        if say.s ~= "" then
            for _, line in ipairs(N.wrap(say.s, inner, FONT)) do
                ops[#ops + 1] = { s = line, x = m.pad, y = y, c = say.c }
                y = y + m.fh
            end
            y = y + m.gap
        end

        -- The scale: full size, less if the screen is short (beside the column) or narrow
        -- (over it), never under the floor.
        local s = full
        if twoCol then
            local _, fullH = self:layoutDevice(0, 0, full)
            local room = sh - y - m.gap - m.hintH - m.pad * 2
            if fullH > room then s = math.max(floor, full * room / fullH) end
        else
            -- The width is not quite proportional (the gaps and the arrows' floor are fixed),
            -- so a few passes close in on it.
            local w = devW
            for _ = 1, 4 do
                if w <= inner or s <= floor then break end
                s = math.max(floor, s * inner / w)
                w = self:layoutDevice(0, 0, s)
            end
        end
        devW = self:layoutDevice(0, 0, s)
        local devX = twoCol and m.pad or (m.pad + math.floor((inner - devW) / 2))
        local _, devH = self:layoutDevice(devX, y, s)
        if y + devH > sh - m.gap - m.hintH - m.pad * 2 then
            self.tryRow = false
            _, devH = self:layoutDevice(devX, y, s)
        end
        self.device = { x = devX, y = y, w = devW, h = devH }

        local sideX, sideY = devX + devW + m.colGap, y
        if not twoCol then sideX, sideY = m.pad, y + devH + m.gap * 2 end
        local bottom = self:side(ops, t, sideX, sideY, sideW, sh - m.pad * 2 - m.gap - m.hintH)
        bottom = math.max(bottom, y + devH)

        self.hintRect = { x = m.pad, y = bottom + m.gap, w = inner, h = m.hintH }
        local w = inner + m.pad * 2
        self.ops = ops
        self.titleShown = N.fitTitle(t.title, w - m.pad - m.head)
        return w, self.hintRect.y + m.hintH + m.pad
    end

    --- Everything the layout depends on, so it runs again only when one of them moved.
    local function signature(self)
        local parts = { tostring(self.kind), tostring(getCore():getScreenWidth()), tostring(getCore():getScreenHeight()),
                        tostring(self.mask), tostring(self.triesLeft), tostring(self.triesMax), tostring(self:spin()),
                        tostring(padDrives(self.playerNum)), instruction(self).s }
        for _, line in ipairs(statusLines(self)) do parts[#parts + 1] = line.s end
        for _, n in ipairs(self.notes) do parts[#parts + 1] = n end
        parts[#parts + 1] = table.concat(self:triedList(), ",")
        return table.concat(parts, "|")
    end

    local function place(b, r)
        b:setX(r.x)
        b:setY(r.y)
        b:setWidth(r.w)
        b:setHeight(r.h)
    end

    --- A button's label cut to fit; the whole one is kept as `label`.
    local function label(b, s, r, m)
        b.label = s
        b:setTitle(N.fit(s, r.w - math.floor(m.btnPad / 2), FONT))
    end

    --- The dial's try button names the code it would try, the number at the mark included, so
    --- the last number plainly needs no turn back before it is tried.
    function W:submitLabel()
        local code = self:canSubmit() and self:code() or nil
        if self:isDial() and code ~= nil then return M.Tf("UI_LugliDMS_Dial_TryCode", "Try %1", code) end
        return self.text.submit
    end

    function W:placeButtons()
        local t, m = self.text, self.m
        N.placeClose(self.closeBtn, self.width)
        if self:isDial() then
            place(self.leftBtn, self.turnRects.left)
            place(self.resetBtn, self.turnRects.reset)
            label(self.resetBtn, t.reset, self.turnRects.reset, m)
            place(self.rightBtn, self.turnRects.right)
            place(self.submitBtn, self.submitRect)
            label(self.submitBtn, self:submitLabel(), self.submitRect, m)
        else
            for i, b in ipairs(self.keyBtns) do
                place(b, self.keyRects[i])
                local k = PAD[i]
                b.label = k == "clear" and t.clear or k == "enter" and t.enter or tostring(k)
                b:setTitle(N.fit(b.label, self.keyRects[i].w - math.floor(m.btnPad / 2), KEY_FONT))
            end
        end
    end

    --- Light what can be pressed now, the ready action in the accent, and ring the controller's
    --- choice.
    function W:syncButtons()
        local pad = padDrives(self.playerNum)
        local can = self:canSubmit()
        if self:isDial() then
            local turns = self.openedAt == nil and not self:dialFull()
            self.leftBtn:setEnable(turns and self.dir ~= nil)
            self.rightBtn:setEnable(turns)
            self.resetBtn:setEnable(self.openedAt == nil)
            local s = self:submitLabel()
            if self.submitBtn.label ~= s then label(self.submitBtn, s, self.submitRect, self.m) end
            self.submitBtn:setEnable(can)
            self.submitBtn:setActive(can)
            self.submitBtn.joypadFocused = pad and can
        else
            local live = self:live()
            for i, b in ipairs(self.keyBtns) do
                b:setEnable(live)
                b:setActive(PAD[i] == "enter" and can)
                b.joypadFocused = pad and live and i == self.focusKey
            end
        end
    end

    --- Lay out again and move every child to match. setWidth and setHeight keep a top-level
    --- element on screen.
    function W:applyLayout()
        local w, h = self:layout()
        self:setWidth(w)
        self:setHeight(h)
        if self.closeBtn ~= nil then
            self:placeButtons()
            self:syncButtons()
        end
    end

    function W:new(player, obj, view, onSubmit, viewOf)
        local o = ISPanelJoypad:new(0, 0, 1, 1)
        setmetatable(o, self)
        self.__index = self
        o.background = false
        o.moveWithMouse = true
        o.player, o.obj, o.onSubmit, o.viewOf = player, obj, onSubmit, viewOf
        o.playerNum = playerNumOf(player)
        o.m = metrics()
        o.typed, o.focusKey = "", 5
        o.pos, o.set, o.dir = 0, {}, nil
        o.dragAcc = 0
        o.frameTarget, o.frameShown = 0, 0
        o:setView(view)
        o:readNotes()
        o.nextNotes = nowMs() + M.KEYPAD_NOTES_MS
        o.sig = signature(o)
        o:applyLayout()
        N.place(o, "code", math.floor((getCore():getScreenWidth() - o.width) / 2),
            math.floor((getCore():getScreenHeight() - o.height) / 2))
        return o
    end

    --- A key of the pad: the faceplate's own key, up or pressed (held by the pointer, or typed
    --- from the keyboard a moment ago), its label printed in ink, a shade lighter while the window
    --- cannot take it. OK's label lights once a whole code waits on it. It shakes with the lock.
    LugliDMSKeypadKey = LugliDMSButton:derive("LugliDMSKeypadKey")
    local Key = LugliDMSKeypadKey

    function Key:down()
        return self.pressed == true or self.window:keyFlashing(self.keyIndex)
    end

    function Key:prerender()
        local k = PAD[self.keyIndex]
        local skin = k == "clear" and "Keypad/Key_Clear" or k == "enter" and "Keypad/Key_Ok" or "Keypad/Key"
        local dx = self.window:shakeOffset()
        if not N.draw(self, skin .. (self:down() and "_Down" or "_Up"), dx, 0, self.width, self.height, self.enable and 1 or 0.6) then
            LugliDMSButton.prerender(self)
            return
        end
        if self.joypadFocused then N.focusRing(self, dx, 0, self.width, self.height, false) end
        self:updateTooltip()
    end

    function Key:render()
        local s = self.window.plate.s
        local dy = self:down() and math.floor(2 * s + 0.5) or 0
        local c = (self.active and self.enable) and N.text or KEY_INK
        local x = self.window:shakeOffset() + math.floor((self.width - measure(self.title, KEY_FONT)) / 2)
        local y = math.floor((self.height - fontHeight(KEY_FONT)) / 2) - math.floor(2 * s + 0.5) + dy
        self:drawText(self.title, x, y, c.r, c.g, c.b, self.enable and 0.85 or 0.45, KEY_FONT)
    end

    --- A turn arrow beside the dial: the way the next number is set in the accent, the other grey;
    --- lighter under the pointer.
    LugliDMSDialTurn = LugliDMSButton:derive("LugliDMSDialTurn")
    local Turn = LugliDMSDialTurn

    function Turn:prerender()
        local win = self.window
        local c = (self.enable and win:wayNow() == self.way) and N.accent or N.textFaint
        local k = self.pressed and 0.8 or (self:isMouseOver() and 1.2 or 1)
        local name = self.way == RIGHT and "Dial/Turn_Right" or "Dial/Turn_Left"
        if not N.draw(self, name, 0, 0, self.width, self.height, self.enable and 1 or 0.5,
            math.min(1, c.r * k), math.min(1, c.g * k), math.min(1, c.b * k)) then
            LugliDMSButton.prerender(self)
            LugliDMSButton.render(self)
        end
        if self.joypadFocused then N.focusRing(self, 0, 0, self.width, self.height, false) end
        self:updateTooltip()
    end

    function Turn:render() end

    local function button(self, title, fn, class)
        local b = (class or LugliDMSButton):new(0, 0, 1, 1, title, self, fn)
        b.window = self
        b:initialise()
        self:addChild(b)
        return b
    end

    function W:createChildren()
        ISPanelJoypad.createChildren(self)
        self.closeBtn = N.closeButton(self.width, self.m.head, self, self.close)
        self:addChild(self.closeBtn)
        if self:isDial() then
            self.leftBtn = button(self, "<", W.onTurnButton, Turn)
            self.leftBtn.way, self.leftBtn.icon = LEFT, true
            self.resetBtn = button(self, "", W.onResetButton)
            self.rightBtn = button(self, ">", W.onTurnButton, Turn)
            self.rightBtn.way, self.rightBtn.icon = RIGHT, true
            self.submitBtn = button(self, "", W.onSubmitButton)
        else
            self.keyBtns = {}
            for i = 1, #PAD do
                local b = button(self, "", W.onKeyButton, Key)
                b.keyIndex = i
                b.font = KEY_FONT
                self.keyBtns[i] = b
            end
        end
        self:placeButtons()
        self:syncButtons()
        self:setWantKeyEvents(true)
    end

    function W:onKeyButton(b)
        self.focusKey = b.keyIndex
        self:pressKey(b.keyIndex)
    end

    function W:onTurnButton(b)
        self:turnDial(b.way)
    end

    function W:onResetButton()
        self:resetDial()
    end

    function W:onSubmitButton()
        self:submit()
    end

    function W:close()
        self:setVisible(false)
        self:removeFromUIManager()
        if padDrives(self.playerNum) then
            pcall(setJoypadFocus, self.playerNum, nil)
        end
        if open[self.playerNum] == self then open[self.playerNum] = nil end
    end

    -- ---- input --------------------------------------------------------------------------------

    --- Asked by the UI manager for each key this window is handed: true keeps a digit off the
    --- hotbar, Esc from opening the pause menu under it, and the dial's turning keys from walking
    --- the survivor.
    function W:isKeyConsumed(key)
        if keyDigit(key) ~= nil or anyKey(key, BOTH_KEYS) then return true end
        return self:isDial() and anyKey(key, DIAL_KEYS)
    end

    function W:onKeyPress(key)
        if not self:isVisible() then return end
        local d = keyDigit(key)
        if isKey(key, "KEY_RETURN") or isKey(key, "KEY_NUMPADENTER") then
            self:submit()
        elseif isKey(key, "KEY_BACK") then
            self:erase()
        elseif self:isDial() then
            if isKey(key, "KEY_LEFT") or isKey(key, "KEY_A") then
                self:turnDial(LEFT)
            elseif isKey(key, "KEY_RIGHT") or isKey(key, "KEY_D") then
                self:turnDial(RIGHT)
            end
        elseif d ~= nil then
            self:typeDigit(d)
        end
    end

    --- A held turning key or Backspace repeats; a held digit or Enter does not.
    function W:onKeyRepeat(key)
        if keyDigit(key) ~= nil or isKey(key, "KEY_RETURN") or isKey(key, "KEY_NUMPADENTER") then return end
        self:onKeyPress(key)
    end

    function W:onKeyRelease(key)
        if isKey(key, "KEY_ESCAPE") and self:isVisible() then self:close() end
    end

    function W:onJoypadDown(button)
        if button == Joypad.AButton then
            if self:isDial() then self:submit() else self:pressKey(self.focusKey) end
        elseif button == Joypad.BButton then
            self:close()
        elseif button == Joypad.XButton then
            self:erase()
        elseif button == Joypad.YButton then
            self:submit()
        end
    end

    --- The d-pad walks the pad's keys, stopping at its edges; on the dial, left and right turn it.
    function W:moveFocus(dc, dr)
        local i = self.focusKey - 1
        local col, row = M.clamp(i % 3 + dc, 0, 2), M.clamp(math.floor(i / 3) + dr, 0, 3)
        self.focusKey = row * 3 + col + 1
    end

    function W:onJoypadDirLeft()
        if self:isDial() then self:turnDial(LEFT) else self:moveFocus(-1, 0) end
    end

    function W:onJoypadDirRight()
        if self:isDial() then self:turnDial(RIGHT) else self:moveFocus(1, 0) end
    end

    function W:onJoypadDirUp()
        if not self:isDial() then self:moveFocus(0, -1) end
    end

    function W:onJoypadDirDown()
        if not self:isDial() then self:moveFocus(0, 1) end
    end

    -- One place for both faces: the next safe's code window opens where the last one was left.
    -- The releases below end the dial's grip first and hand anything else to the remembering ones.
    N.movable(W, "code", ISPanelJoypad)
    local moveUp, moveUpOutside = W.onMouseUp, W.onMouseUpOutside

    --- A press on the dial grips it; anywhere else drags the window.
    function W:onMouseDown(x, y)
        if self:isDial() and self:onDial(x, y) then
            self.dragging = true
            self.dragAngle = angleOf(x - self.dial.cx, y - self.dial.cy)
            self.dragAcc = 0
            return true
        end
        return ISPanelJoypad.onMouseDown(self, x, y)
    end

    function W:onMouseMove(dx, dy)
        if self.dragging then
            self:dragTo(self:getMouseX(), self:getMouseY())
            return true
        end
        return ISPanelJoypad.onMouseMove(self, dx, dy)
    end

    function W:onMouseMoveOutside(dx, dy)
        if self.dragging then
            self:dragTo(self:getMouseX(), self:getMouseY())
            return true
        end
        return ISPanelJoypad.onMouseMoveOutside(self, dx, dy)
    end

    function W:onMouseUp(x, y)
        if self.dragging then
            self.dragging = false
            return true
        end
        return moveUp(self, x, y)
    end

    function W:onMouseUpOutside(x, y)
        if self.dragging then
            self.dragging = false
            return true
        end
        return moveUpOutside(self, x, y)
    end

    --- The wheel turns the dial, up to the left (the numbers at the mark count up). Kept from the
    --- map on both faces, which would zoom under the window.
    function W:onMouseWheel(del)
        if self:isDial() then self:turnDial(del < 0 and LEFT or RIGHT) end
        return true
    end

    -- ---- drawing ------------------------------------------------------------------------------

    --- The sideways offset of a shake after a wrong code: a decaying wobble, 0 once it is over.
    function W:shakeOffset()
        if self.shakeAt == nil then return 0 end
        local t = nowMs() - self.shakeAt
        if t < 0 or t >= M.KEYPAD_SHAKE_MS then return 0 end
        local f = t / M.KEYPAD_SHAKE_MS
        return math.floor(self.m.shake * math.sin(f * math.pi * 6) * (1 - f) + 0.5)
    end

    --- The light's colour now, or nil while it is dark.
    function W:lit()
        if self.lightAt == nil or nowMs() - self.lightAt >= M.KEYPAD_LIGHT_MS then return nil end
        return self.lightC
    end

    --- The keypad's light in its socket: red for a wrong code, green for the right one, else off.
    function W:drawLed(dx)
        local r = self.led
        local c = self:entryOn() and self:lit() or nil
        local name = c == N.good and "Green" or c ~= nil and "Red" or "Off"
        N.draw(self, "Keypad/Led_" .. name, r.x + dx, r.y, r.w, r.h, 1)
    end

    local function centred(self, s, r, dx, c, a, font)
        local fh = fontHeight(font)
        self:drawText(s, r.x + dx + math.floor((r.w - measure(s, font)) / 2), r.y + math.floor((r.h - fh) / 2),
            c.r, c.g, c.b, a, font)
    end

    --- The keypad's display, lit from behind: the digits typed in four segment cells over the
    --- unlit segments, a dash for each one still to come, the lockout counting down in red, or
    --- dark glass without power.
    function W:drawLcd(dx)
        if not self:entryOn() then return end
        local p = self.plate
        local ox, oy, s = p.x + dx, p.y, p.s
        N.piece(self, "Keypad/Lcd_Backlight", ox, oy, s, LCD_GLASS.x, LCD_GLASS.y, 0.30, LCD_GREEN)
        local glyphs, c = {}, nil
        local left = self:lockedLeft()
        if left > 0 then
            local minutes = math.ceil(left * 60)
            local text = string.format("%d:%02d", math.floor(minutes / 60), minutes % 60)
            for i = 1, #text do
                local ch = string.sub(text, i, i)
                glyphs[i] = ch == ":" and "Colon" or ch
            end
            c = N.bad
        else
            for i = 1, M.KEYPAD_DIGITS do
                local ch = string.sub(self.typed, i, i)
                glyphs[i] = ch ~= "" and ch or "Dash"
            end
            c = self:lit() or LCD_GREEN
        end
        local total = -(SEG_PITCH - SEG_W)
        for _, g in ipairs(glyphs) do total = total + (g == "Colon" and SEG_COLON_PITCH or SEG_PITCH) end
        local px = LCD_GLASS.x + (LCD_GLASS.w - total) / 2
        local py = LCD_GLASS.y + (LCD_GLASS.h - 56) / 2
        for _, g in ipairs(glyphs) do
            if g == "Colon" then
                local centre = px + (SEG_COLON_PITCH - (SEG_PITCH - SEG_W)) / 2
                N.piece(self, "Keypad/Seg_Colon", ox, oy, s, centre - SEG_W / 2, py, 1, c)
                px = px + SEG_COLON_PITCH
            else
                N.piece(self, "Keypad/Seg_Ghost", ox, oy, s, px, py, 0.08, LCD_GREEN)
                N.piece(self, "Keypad/Seg_" .. g, ox, oy, s, px, py, g == "Dash" and 0.35 or 1, c)
                px = px + SEG_PITCH
            end
        end
    end

    --- The dial's four number windows: those set, the one at the mark in the window being filled,
    --- "-" for the rest.
    function W:drawSlots(dx)
        local font = digitFont()
        local spin = self:spin()
        for i, r in ipairs(self.slots) do
            if not N.draw(self, "Dial/Window", r.x + dx, r.y, r.w, r.h, 1) then N.inner(self, r.x + dx, r.y, r.w, r.h, 0.9) end
            if self.set[i] ~= nil then
                centred(self, tostring(self.set[i]), r, dx, self:lit() or N.text, 1, font)
            elseif i == spin and self.dir ~= nil then
                centred(self, tostring(self.pos), r, dx, N.accent, 1, font)
                self:drawRect(r.x + dx + self.m.nudge, r.y + r.h - self.m.rule - 1, r.w - self.m.nudge * 2, self.m.rule,
                    1, N.accent.r, N.accent.g, N.accent.b)
            else
                centred(self, "-", r, dx, N.textFaint, 1, font)
            end
        end
    end

    --- The dial: its plate, the face at the frame it has eased to, and the index over the rim.
    function W:drawDial(dx)
        local p = self.plate
        local ox, oy, s = p.x + dx, p.y, p.s
        N.piece(self, "Dial/Plate", ox, oy, s, 0, 0, 1)
        N.piece(self, string.format("Dial/Face_%02d", self:dialFrame()), ox, oy, s, FACE_AT, FACE_AT, 1)
        N.piece(self, "Dial/Index", ox, oy, s, INDEX.x, INDEX.y, 1)
    end

    function W:prerender()
        N.followView(self)
        local p = self.player
        local ok, dead = pcall(function() return p:isDead() end)
        if (ok and dead == true) or not M.inspectInReach(p, self.obj) then
            self:close()
            return
        end
        local now = nowMs()
        if self.openedAt ~= nil and now - self.openedAt >= M.KEYPAD_OPEN_MS then
            self:close()
            return
        end
        if now >= self.nextNotes then
            self.nextNotes = now + M.KEYPAD_NOTES_MS
            self:readNotes()
            self:reread(now)
            if not self:isVisible() then return end
        end
        local sig = signature(self)
        if sig ~= self.sig then
            self.sig = sig
            self:applyLayout()
        end
        self:syncButtons()
        local m = self.m
        N.window(self, 0, 0, self.width, self.height, m.head)
        N.title(self, self.titleShown, m.pad, m.head)
        local dx = self:shakeOffset()
        if self:isDial() then
            self:easeDial(now)
            self:drawDial(dx)
            self:drawSlots(dx)
        else
            local p = self.plate
            if not N.piece(self, "Keypad/Faceplate", p.x + dx, p.y, p.s, 0, 0, 1) then
                N.inner(self, p.x + dx, p.y, p.w, p.h, 0.8)
            end
            self:drawLcd(dx)
            self:drawLed(dx)
        end
        local h = self.hintRect
        N.hints(self, self.text.controls, h.x, h.y, h.h, h.w)
        for _, op in ipairs(self.ops) do
            if op.pip then
                N.pip(self, op.x, op.y, op.size, op.filled, op.c)
            elseif op.rule then
                self:drawRect(op.x, op.y, op.w, op.h, 0.8, op.c.r, op.c.g, op.c.b)
            else
                self:drawText(op.s, op.x, op.y, op.c.r, op.c.g, op.c.b, 1, FONT)
            end
        end
    end

    -- ---- opening it ---------------------------------------------------------------------------

    --- Show the code window for a safe. `view` carries kind ("dialsafe" or "keypadsafe"),
    --- revealed ("?4??" or nil), triesLeft, lockedFor (game hours, 0 when free) and powered;
    --- onSubmit(code) gets a four-digit string and returns true when it took the try. viewOf(),
    --- optional, returns the view as the safe reads now, nil once it is no longer sealed. One per
    --- survivor: asked again for the same safe it takes the new view and comes to the front, asked
    --- for another it replaces the first. Nil for a view that is no safe's or without an onSubmit.
    function M.openKeypad(player, obj, view, onSubmit, viewOf)
        if type(view) ~= "table" or M.KEYPAD_KINDS[view.kind] == nil or type(onSubmit) ~= "function" then
            return nil
        end
        if type(viewOf) ~= "function" then viewOf = nil end
        local num = playerNumOf(player)
        local cur = open[num]
        if cur ~= nil and cur.obj == obj and cur:isVisible() and cur.kind == view.kind then
            cur.onSubmit, cur.viewOf = onSubmit, viewOf
            cur:setView(view)
            cur:bringToTop()
            if padDrives(num) then pcall(setJoypadFocus, num, cur) end
            return cur
        end
        if cur ~= nil then cur:close() end
        local win = W:new(player, obj, view, onSubmit, viewOf)
        win:initialise()
        win:instantiate()
        win:addToUIManager()
        win:setVisible(true)
        N.sound("UIActivateTab")
        open[num] = win
        if padDrives(num) then pcall(setJoypadFocus, num, win) end
        return win
    end

    --- The authority's reply to a submitted code: outcome "right" (or "opened") lights green and
    --- closes the window, "wrong" lights red and takes args.triesLeft, "lockout" also takes
    --- args.lockedFor. The window is args.player's, else the open one on args.obj, else the only
    --- open one. True when a window took the reply.
    function M.keypadResult(outcome, args)
        if type(args) ~= "table" then args = {} end
        local win = nil
        if args.player ~= nil then
            win = open[playerNumOf(args.player)]
        else
            local count = 0
            for _, w in pairs(open) do
                if args.obj == nil or w.obj == args.obj then
                    win = w
                    count = count + 1
                end
            end
            if count ~= 1 then win = nil end
        end
        if win == nil or not win:isVisible() then return false end
        if args.obj ~= nil and win.obj ~= args.obj then return false end
        return win:result(outcome, args)
    end

    M.addTeardown(PART, function()
        for _, win in pairs(open) do win:close() end
        tried = {}
    end)
    M.status(PART, true)
end
