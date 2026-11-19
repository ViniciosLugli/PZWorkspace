--[[
    WorkPanel
    A small panel that shows a route's work while the timed action runs, as a cutaway drawn from
    the art in media/ui/LugliDMS/Work (tools/dms-ui-art.py): the drill's bit going into the lock
    plate and its heat, the claw's nails coming out one by one, a lid lifting on a crowbar, pins
    setting under the pick, a shackle closing between the cutter's jaws or levered by a crowbar,
    the torch's seam glowing down the door's edge, the stethoscope on a turning dial with the
    digits found so far, and wires being made. Under it, what the survivor can do about the work,
    then how far it is. A key, a code, a battery and the smash show none.

    BOUND TO ITS ACTION, NEVER IN CHARGE OF IT. ISLugliDMSRouteAction (Actions.lua) opens it in
    start, ticks it in update and closes it in stop and perform; everything it draws comes from
    the action's own progress over the progress the authority saved on the gate's tag. It takes
    no focus, consumes no key and blocks no movement, so walking off is the action's own stop.
    It closes at once when the survivor is in danger. A client option hides it, and then a
    controller survivor is told the offer over their head instead. It can be dragged, and opens
    where it was last left (Neat.place, kind "work").

    THE ONE CHOICE (Gates.WORK_CHOICES): when the drill is in the red it offers Ease off, and
    when the torch's seam is near the contents it offers Stop. Either pauses the work (the action
    holds its clock) and plays the route's `eased` sound, and the count rides on the submit as
    `choice`, which the authority clamps: it can only spare the drill a wear or lower the burn
    chance. Mouse: the button; controller: LB, read as a press edge since the panel takes no
    focus; no key. An offer left `grace` seconds where it could be taken stops the work (the
    drill overheats, the torch cuts out), its progress kept; with the panel hidden and no
    controller nothing can take it, so the work runs on hot.
]]

require "ISUI/ISPanel"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Neat"
require "LugliDeadMansStash/Actions"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local N = M.neat
    local PART = "WorkPanel"

    -- HOW EACH ROUTE'S WORK IS DRAWN. steps: the visual steps, each playing the route's step sound
    -- (Sounds.lua) as it lands; capped: the route can fail at the authority, so its last step
    -- never shows before the answer does.
    M.WORK_LOOKS = {
        drill = { draw = "drill", steps = 0 },
        claw = { draw = "nails", steps = 4 },
        pry = { draw = "lid", steps = 3 },
        force = { draw = "lid", steps = 3 },
        snap = { draw = "shackle", tool = "Crowbar", steps = 3, capped = true },
        pick = { draw = "pins", steps = 5, capped = true },
        jimmy = { draw = "pins", steps = 3 },
        cut = { draw = "shackle", tool = "Cutter_Jaws", steps = 0 },
        torch = { draw = "seam", steps = 0 },
        manipulate = { draw = "dial", steps = 12 },
        bypass = { draw = "wires", steps = 4, capped = true },
    }

    -- The client options page.
    M.WORK_OPTIONS_ID = "LugliDeadMansStash"
    -- The drill's red zone starts this far along its gauge, where Gauge_Frame paints it.
    local RED_ZONE = 0.75

    -- Where the pieces go, in the art pixels of the 560 x 184 backdrops (tools/dms-ui-art.py's
    -- docstring). The art is twice its size at UI scale 1.
    local SCENE_W, SCENE_H = 560, 184
    local DRILL_PLATE, DRILL_AXIS_Y = { 300, 380 }, 70
    local GAUGE_AT, GAUGE_SLOT = { 20, 144 }, { 4, 4, 512, 24 }
    local SEAM_X, SEAM_Y = 280, { 12, 172 }
    local LID_X, LID_SEAT_Y, LID_BOARD, LID_LIFT = 70, 120, 48, 40
    local CROWBAR_TIP = { 256, 13 }
    local NAIL_X, NAIL_Y, NAIL_OUT_POINT, CLAW_TIP = { 70, 210, 350, 490 }, 112, { 20, 94 }, { 106, 90 }
    local PIN_X, PIN_TOP, SHEAR_Y, PIN_DROP = { 140, 210, 280, 350, 420 }, 10, 96, 10
    local PICK_TIP, TENSION_TIP, LOCK_FACE_X, KEYWAY_FLOOR = { 354, 6 }, { 118, 8 }, 62, 176
    local SHACKLE_AT, SHACKLE_LEG, SHACKLE_CUT_Y, CUTTER_MOUTH, CUTTER_REACH = { 210, 0 }, 119, 70, { 20, 60 }, 60
    local POST_X, WIRE_TOP_Y = { 160, 240, 320, 400 }, 34
    local WIRE_NAMES = { "Red", "Black", "Yellow", "Blue" }

    local function nowMs()
        return getTimestampMs ~= nil and getTimestampMs() or 0
    end

    -- ---- the model: pure, from the action ---------------------------------------------------------

    --- All of the gate's work done: the saved share plus this session's share of what was left.
    function M.workProgress(saved, delta)
        saved = M.clamp(M.finite(saved) or 0, 0, 1)
        return saved + (1 - saved) * M.clamp(M.finite(delta) or 0, 0, 1)
    end

    --- The visual step `progress` has reached; a capped route stops one short of its last.
    function M.workStep(look, progress)
        if look == nil or (look.steps or 0) <= 0 then return 0 end
        local step = math.floor(M.clamp(progress, 0, 1) * look.steps + 0.0001)
        if look.capped then step = math.min(step, look.steps - 1) end
        return step
    end

    local function jobDelta(action)
        local ok, d = pcall(function() return action:getJobDelta() end)
        return ok and M.finite(d) or 0
    end

    --- The action's clock, in action units.
    local function clockOf(action)
        local ok, t = pcall(function() return action.action:getCurrentTime() end)
        return ok and M.finite(t) or nil
    end

    --- 1 at the start of a pause down to 0 at its end; 0 with none running.
    local function pauseLeft(action)
        local c = M.WORK_CHOICES[action.routeId]
        if c == nil or action.workPauseUntil == nil then return 0 end
        return M.clamp((action.workPauseUntil - nowMs()) / (c.pause * 1000), 0, 1)
    end

    --- What the panel shows of an action now, or nil for a route it does not draw.
    function M.workView(action)
        local look = M.WORK_LOOKS[action.routeId]
        if look == nil then return nil end
        local delta = jobDelta(action)
        local progress = M.workProgress(action.workSaved, delta)
        local v = { routeId = action.routeId, look = look, progress = progress, step = M.workStep(look, progress),
                    choices = math.max(0, M.finite(action.choice) or 0), offer = false }
        local left = pauseLeft(action)
        v.pausing = left > 0
        local c = M.WORK_CHOICES[action.routeId]
        if c ~= nil and c.every ~= nil then
            -- Real seconds, as the authority counts the spells: the action's own clock runs up to
            -- 1.2x real time (and faster in single player's fast-forward).
            local work = (M.finite(action.workStart) or 0) + (M.finite(action.workWallMs) or 0) / 1000
            v.red = M.heatSpells(action.routeId, work) > v.choices
            local heat = M.clamp((work - M.heatSpells(action.routeId, work) * c.every) / c.every, 0, 1) * RED_ZONE
            if v.red then heat = 1 end
            v.heat = math.max(heat, left)
            v.offer = v.red and not v.pausing and v.choices < c.max
        elseif c ~= nil and c.from ~= nil then
            v.near = progress >= c.from
            v.cooled = action.workCooled == true
            v.glow = v.pausing and (1 - left) or 1
            v.offer = v.near and not v.cooled and not v.pausing and progress < 1 and v.choices < c.max
        end
        if look.draw == "dial" then
            local md = M.sealedGateOf(action.obj)
            v.revealed = md ~= nil and type(md.revealed) == "string" and md.revealed or "????"
        end
        return v
    end

    --- Play the route's `slot` sound (Sounds.lua) once on the survivor.
    local function cue(action, slot)
        local name = M.routeSound(action.routeId, M.boxKindOf(action.obj), slot)
        if name ~= nil then pcall(function() action.character:playSound(name) end) end
    end

    --- Take the offered choice: one more pause, the clock held where it is. False when nothing is
    --- offered now.
    function M.workChoose(action)
        if action == nil or not action.workOn then return false end
        local v = M.workView(action)
        if v == nil or not v.offer then return false end
        local c = M.WORK_CHOICES[action.routeId]
        action.choice = v.choices + 1
        action.workPauseUntil = nowMs() + c.pause * 1000
        action.workHeld = clockOf(action)
        pcall(function() action:hush() end)
        cue(action, "eased")
        return true
    end

    -- ---- options --------------------------------------------------------------------------------

    local options = nil

    local function optionValue(id, default)
        if options == nil then return default end
        local ok, v = pcall(function() return options:getOption(id):getValue() end)
        if ok and v ~= nil then return v end
        return default
    end

    --- Is the panel shown? A client's own choice, on by default.
    function M.workShown()
        return optionValue("workPanel", true) == true
    end

    local function addOptions()
        if PZAPI == nil or PZAPI.ModOptions == nil then return end
        local ok, err = pcall(function()
            options = PZAPI.ModOptions:create(M.WORK_OPTIONS_ID, M.T("Tooltip_LugliDMS_Work_Options", "Lugli - Dead Man's Stash"))
            options:addTickBox("workPanel", M.T("Tooltip_LugliDMS_Work_OptionShow", "Show the work panel"), true,
                M.T("Tooltip_LugliDMS_Work_OptionShowTip", "A small panel that shows a break-in's work while it runs."))
        end)
        if not ok then
            options = nil
            M.defect(PART, "the options page did not register: " .. tostring(err))
        end
    end

    -- ---- danger, the controller, words ------------------------------------------------------------

    --- Is the survivor in trouble: dead, down, burning or under attack (a zombie or crawler in its
    --- attack or lunge within reach, IsoGameCharacter.getSurroundingAttackingZombies)?
    function M.workDanger(player)
        local ok, yes = pcall(function()
            return player:isDead() or player:isKnockedDown() or player:isOnFire()
                or player:getSurroundingAttackingZombies(true) > 0
        end)
        return ok and yes == true
    end

    local function padOf(player)
        if JoypadState == nil or JoypadState.players == nil then return nil end
        local ok, num = pcall(function() return player:getPlayerNum() end)
        if not ok or type(num) ~= "number" then return nil end
        local pad = JoypadState.players[num + 1]
        if pad == nil or pad.id == nil then return nil end
        return pad
    end

    local function lbDown(pad)
        if pad == nil or isJoypadLBPressed == nil then return false end
        local ok, down = pcall(isJoypadLBPressed, pad.id)
        return ok and down == true
    end

    --- The choice's words, with LB for a controller survivor; a mouse clicks the button they are on.
    function M.workChoiceText(action)
        local label = action.routeId == "torch" and M.T("Tooltip_LugliDMS_Work_Stop", "Stop")
            or M.T("Tooltip_LugliDMS_Work_EaseOff", "Ease off")
        if padOf(action.character) == nil then return label end
        return M.Tf("Tooltip_LugliDMS_Work_Press", "%1 [%2]", label, "LB")
    end

    --- What the survivor can do about the work now: the light choice and its input for a route
    --- that has one, else that it needs nothing and what walking away costs, from its own `fresh`.
    function M.workInstruction(action)
        local c = M.WORK_CHOICES[action.routeId]
        local pad = padOf(action.character) ~= nil
        if c ~= nil and c.every ~= nil then
            if pad then
                return M.Tf("Tooltip_LugliDMS_Work_DoEasePad",
                    "Keep at it. When the heat reaches red, press [%1] to ease off, or the drill overheats and stops.", "LB")
            end
            return M.T("Tooltip_LugliDMS_Work_DoEase",
                "Keep at it. When the heat reaches red, click Ease off, or the drill overheats and stops.")
        elseif c ~= nil and action.workCooled ~= true then
            if pad then
                return M.Tf("Tooltip_LugliDMS_Work_DoStopPad",
                    "Near the end, press [%1] to let the seam cool, or the torch cuts out.", "LB")
            end
            return M.T("Tooltip_LugliDMS_Work_DoStop", "Near the end, click Stop to let the seam cool, or the torch cuts out.")
        end
        local def = M.ROUTES[action.routeId]
        if def ~= nil and def.fresh then
            return M.T("Tooltip_LugliDMS_Work_Fresh", "No input needed. Walk away and this try is lost.")
        end
        return M.T("Tooltip_LugliDMS_Work_Kept", "No input needed. Walk away any time: the work so far is kept.")
    end

    local function percent(p) return math.floor(M.clamp(p, 0, 1) * 100 + 0.5) end

    --- The line under the drawing.
    function M.workStatus(v)
        local d = v.look.draw
        if d == "drill" then
            if v.pausing then return M.T("Tooltip_LugliDMS_Work_Easing", "Easing off, letting the bit cool.") end
            if v.red then return M.T("Tooltip_LugliDMS_Work_Hot", "The drill is running hot.") end
            return M.Tf("Tooltip_LugliDMS_Work_Depth", "Into the lock plate: %1%", percent(v.progress))
        elseif d == "seam" then
            if v.pausing then return M.T("Tooltip_LugliDMS_Work_Cooling", "Letting the seam cool.") end
            if v.near and v.cooled then return M.T("Tooltip_LugliDMS_Work_Cooled", "The seam cooled while you were away.") end
            if v.near then return M.T("Tooltip_LugliDMS_Work_Near", "The seam is close to what is inside.") end
            return M.Tf("Tooltip_LugliDMS_Work_Seam", "Seam cut: %1%", percent(v.progress))
        elseif d == "nails" then
            return M.Tf("Tooltip_LugliDMS_Work_Nails", "Nails out: %1 of %2", v.step, v.look.steps)
        elseif d == "pins" then
            return M.Tf("Tooltip_LugliDMS_Work_Pins", "Pins set: %1 of %2", v.step, v.look.steps)
        elseif d == "wires" then
            return M.Tf("Tooltip_LugliDMS_Work_Wires", "Wires sorted: %1 of %2", v.step, v.look.steps)
        elseif d == "dial" then
            return M.Tf("Tooltip_LugliDMS_Work_Found", "Found so far: %1", v.revealed)
        end
        return M.Tf("Tooltip_LugliDMS_Work_Done", "%1% done", percent(v.progress))
    end

    -- ---- drawing ----------------------------------------------------------------------------------

    local function mix(a, b, t)
        return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
    end

    --- The scene's art pixel ax, ay on the element, rounded as N.piece rounds.
    local function sx(sc, ax) return math.floor(sc.ox + ax * sc.s + 0.5) end
    local function sy(sc, ay) return math.floor(sc.oy + ay * sc.s + 0.5) end

    local function put(sc, key, px, py, a, c)
        return N.piece(sc.el, key, sc.ox, sc.oy, sc.s, px, py, a, c)
    end

    --- Run draw() cropped to the art rectangle x0, y0 .. x1, y1 of the scene.
    local function cropArt(sc, x0, y0, x1, y1, draw)
        local x, y = sx(sc, math.max(0, x0)), sy(sc, math.max(0, y0))
        N.crop(sc.el, x, y, sx(sc, math.min(SCENE_W, x1)) - x, sy(sc, math.min(SCENE_H, y1)) - y, draw)
    end

    --- A piece that reaches past the scene's edge (a long tool, a strand still loose), cut at it.
    local function putIn(sc, key, px, py, a, c)
        cropArt(sc, 0, 0, SCENE_W, SCENE_H, function() put(sc, key, px, py, a, c) end)
    end

    --- 0, 1, 2, 0, ... every `ms` of the clock: a small physical jitter.
    local function beat(ms, n)
        return math.floor(math.max(0, nowMs()) / ms) % n
    end

    local DRAW = {}

    function DRAW.drill(sc, v)
        put(sc, "Work/Drill_Backdrop", 0, 0)
        local p = M.clamp(v.progress, 0, 1)
        if p > 0 then
            local jitter = (p < 1 and not v.pausing) and beat(120, 3) * 2 or 0
            put(sc, "Work/Drill_Chips", DRILL_PLATE[1] - 50, DRILL_AXIS_Y + 8 + jitter)
        end
        local tip = DRILL_PLATE[1] + (DRILL_PLATE[2] - DRILL_PLATE[1]) * p
        local bw, bh = N.size("Work/Drill_Bit")
        put(sc, "Work/Drill_Bit", tip - bw, DRILL_AXIS_Y - bh / 2)
        put(sc, "Work/Gauge_Frame", GAUGE_AT[1], GAUGE_AT[2])
        local heat = M.clamp(M.finite(v.heat) or 0, 0, 1)
        local c = heat < RED_ZONE and mix(N.good, N.accent, heat / RED_ZONE) or N.bad
        local fx, fy = GAUGE_AT[1] + GAUGE_SLOT[1], GAUGE_AT[2] + GAUGE_SLOT[2]
        cropArt(sc, fx, fy, fx + GAUGE_SLOT[3] * heat, fy + GAUGE_SLOT[4], function()
            put(sc, "Work/Gauge_Fill", fx, fy, 1, c)
        end)
    end

    function DRAW.seam(sc, v)
        put(sc, "Work/Seam_Backdrop", 0, 0)
        local p = M.clamp(v.progress, 0, 1)
        local cut = (SEAM_Y[2] - SEAM_Y[1]) * p
        local flicker = 0.85 + 0.15 * math.sin(math.max(0, nowMs()) / 140)
        local alpha = M.clamp(0.35 + 0.65 * (v.glow or 1) * flicker, 0, 1)
        local cw = N.size("Work/Seam_Cut")
        cropArt(sc, SEAM_X - cw / 2, SEAM_Y[1], SEAM_X + cw / 2, SEAM_Y[1] + cut, function()
            put(sc, "Work/Seam_Cut", SEAM_X - cw / 2, SEAM_Y[1], alpha)
        end)
        if v.pausing or p >= 1 then return end
        putIn(sc, "Work/Torch_Tip", SEAM_X - 2, SEAM_Y[1] + cut - 28)
        putIn(sc, "Work/Spark", SEAM_X - 24, SEAM_Y[1] + cut - 23, flicker)
    end

    function DRAW.lid(sc, v)
        put(sc, "Work/Lid_Backdrop", 0, 0)
        local lift = M.clamp(v.progress, 0, 1) * LID_LIFT
        put(sc, "Work/Lid", LID_X, LID_SEAT_Y - LID_BOARD - lift)
        local tipY = LID_SEAT_Y - 6 - lift / 4
        putIn(sc, "Work/Crowbar", LID_X + 150 - CROWBAR_TIP[1], tipY - CROWBAR_TIP[2])
    end

    function DRAW.nails(sc, v)
        put(sc, "Work/Nails_Backdrop", 0, 0)
        local out = math.min(v.step, #NAIL_X)
        for i, nx in ipairs(NAIL_X) do
            if i <= out then
                put(sc, "Work/Nail_Out", nx - NAIL_OUT_POINT[1], NAIL_Y - NAIL_OUT_POINT[2])
            else
                put(sc, "Work/Nail_In", nx - 20, NAIL_Y - 20)
            end
        end
        if out < #NAIL_X then
            putIn(sc, "Work/Hammer_Claw", NAIL_X[out + 1] - 4 - CLAW_TIP[1], NAIL_Y - 5 - CLAW_TIP[2])
        end
    end

    function DRAW.pins(sc, v)
        put(sc, "Work/Pins_Backdrop", 0, 0)
        local set = math.min(v.step, #PIN_X)
        for i, px in ipairs(PIN_X) do
            local drop = i <= set and 0 or PIN_DROP
            local top = SHEAR_Y + drop - 48
            -- Spring is the one piece meant to stretch, from the shaft's top to its driver.
            local x0, y0 = sx(sc, px - 10), sy(sc, PIN_TOP)
            N.draw(sc.el, "Work/Spring", x0, y0, sx(sc, px + 10) - x0, sy(sc, top) - y0)
            put(sc, "Work/Pin_Driver", px - 10, top)
            put(sc, "Work/Pin_Key", px - 10, SHEAR_Y + drop)
        end
        putIn(sc, "Work/Tension", LOCK_FACE_X + 34 - TENSION_TIP[1], KEYWAY_FLOOR - 3 - TENSION_TIP[2])
        local under = PIN_X[math.min(set + 1, #PIN_X)]
        putIn(sc, "Work/Pick", under - PICK_TIP[1], SHEAR_Y + PIN_DROP + 56 - PICK_TIP[2])
    end

    function DRAW.shackle(sc, v)
        put(sc, "Work/Shackle_Backdrop", 0, 0)
        local p = M.clamp(v.progress, 0, 1)
        local cutter = v.look.tool == "Cutter_Jaws"
        put(sc, (cutter and p >= 1) and "Work/Shackle_Cut" or "Work/Shackle_Bar", SHACKLE_AT[1], SHACKLE_AT[2])
        if cutter then
            local reach = (1 - p) * CUTTER_REACH
            putIn(sc, "Work/Cutter_Jaws", SHACKLE_AT[1] + SHACKLE_LEG + reach - CUTTER_MOUTH[1],
                SHACKLE_CUT_Y - CUTTER_MOUTH[2])
        else
            local tipY = 104 - 14 * p
            putIn(sc, "Work/Crowbar", 250 - CROWBAR_TIP[1], tipY - CROWBAR_TIP[2])
        end
    end

    --- Listening at the dial: the face turning under the stethoscope, the digits found beside it.
    function DRAW.dial(sc, v)
        local p = M.clamp(v.progress, 0, 1)
        local frame = math.floor(p * 160) % 40
        local x0, y0 = sx(sc, 40), sy(sc, 8)
        N.draw(sc.el, string.format("Dial/Face_%02d", frame), x0, y0, sx(sc, 208) - x0, sy(sc, 176) - y0)
        put(sc, "Work/Stethoscope", 190, 40)
        local fh = getTextManager():getFontHeight(N.FONT)
        for pos = 1, 4 do
            local wx = 340 + (pos - 1) * 52
            local x, y = sx(sc, wx), sy(sc, 62)
            local w, h = sx(sc, wx + 48) - x, sy(sc, 122) - y
            N.draw(sc.el, "Dial/Window", x, y, w, h)
            local d = string.sub(v.revealed or "????", pos, pos)
            local c = d ~= "?" and N.good or N.textDim
            sc.el:drawTextCentre(d, x + w / 2, y + math.floor((h - fh) / 2), c.r, c.g, c.b, 1, N.FONT)
        end
    end

    function DRAW.wires(sc, v)
        put(sc, "Work/Wires_Backdrop", 0, 0)
        local made = math.min(v.step, #POST_X)
        for i, px in ipairs(POST_X) do
            local key = "Work/Wire_" .. WIRE_NAMES[i]
            if i <= made then
                put(sc, key, px - 12, WIRE_TOP_Y)
            else
                putIn(sc, key, px - 5, WIRE_TOP_Y + 36)
            end
        end
        if made < #POST_X then put(sc, "Work/Clip", POST_X[made + 1] - 24, 44) end
    end

    -- ---- the panel ---------------------------------------------------------------------------------

    LugliDMSWorkPanel = ISPanel:derive("LugliDMSWorkPanel")
    local P = LugliDMSWorkPanel

    function P:new(action)
        local m = N.metrics()
        -- One scale for the scene, from the font: half the art's size at the 19 px Small font.
        local s = m.u(SCENE_H / 2) / SCENE_H
        local inset = m.u(4)
        local sceneW, sceneH = math.floor(SCENE_W * s + 0.5), math.floor(SCENE_H * s + 0.5)
        local bodyW, bodyH = sceneW + inset * 2, sceneH + inset * 2
        local w = bodyW + m.pad * 2
        local lines = #N.wrap(M.workInstruction(action), bodyW, N.FONT)
        local h = m.head + m.gap + bodyH + m.gap + (lines + 1) * m.fh + m.gap + m.btnH + m.pad
        local num = 0
        pcall(function() num = action.character:getPlayerNum() end)
        local sx, sy, sw, sh = 0, 0, w, h
        pcall(function()
            sx, sy = getPlayerScreenLeft(num), getPlayerScreenTop(num)
            sw, sh = getPlayerScreenWidth(num), getPlayerScreenHeight(num)
        end)
        local x = sx + math.floor((sw - w) / 2)
        local y = sy + math.max(0, sh - h - m.u(150))
        local o = ISPanel.new(self, x, y, w, h)
        o.action = action
        o.m = m
        o.bodyH = bodyH
        o.scale, o.inset, o.sceneW, o.sceneH, o.lines = s, inset, sceneW, sceneH, lines
        o.background = false
        o.moveWithMouse = true
        N.place(o, "work", x, y)
        return o
    end
    N.movable(P, "work", ISPanel)

    function P:createChildren()
        ISPanel.createChildren(self)
        local m = self.m
        local bw = self.width - m.pad * 2
        self.choiceBtn = LugliDMSButton:new(m.pad, self.height - m.pad - m.btnH, bw, m.btnH, "", self, P.onChoice)
        self.choiceBtn:initialise()
        self.choiceBtn:setVisible(false)
        self:addChild(self.choiceBtn)
    end

    function P:onChoice()
        M.workChoose(self.action)
    end

    function P:prerender()
        local m = self.m
        local v = M.workView(self.action)
        N.window(self, 0, 0, self.width, self.height, m.head)
        local title = M.T("Tooltip_LugliDMS_Work_" .. tostring(self.action.routeId), tostring(self.action.routeId))
        title = N.fit(title, self.width - m.pad * 2, N.FONT)
        self:drawText(title, m.pad, math.floor((m.head - m.fh) / 2), N.text.r, N.text.g, N.text.b, 1, N.FONT)
        if v == nil then return end
        local bx, by = m.pad, m.head + m.gap
        local bw = self.width - m.pad * 2
        N.inner(self, bx, by, bw, self.bodyH)
        local sc = { el = self, ox = bx + self.inset, oy = by + self.inset, s = self.scale }
        local draw = DRAW[v.look.draw]
        if draw ~= nil then
            draw(sc, v)
        else
            N.progress(self, sc.ox, sc.oy + math.floor((self.sceneH - m.bar) / 2), self.sceneW, m.bar, v.progress)
        end
        local ty = by + self.bodyH + m.gap
        local lines = N.wrap(M.workInstruction(self.action), bw, N.FONT)
        for i = 1, math.min(#lines, self.lines) do
            self:drawText(lines[i], bx, ty, N.textDim.r, N.textDim.g, N.textDim.b, 1, N.FONT)
            ty = ty + m.fh
        end
        ty = by + self.bodyH + m.gap + self.lines * m.fh
        local status = N.fit(M.workStatus(v), bw, N.FONT)
        local c = (v.red or (v.near and not v.pausing)) and N.bad or N.text
        self:drawText(status, bx, ty, c.r, c.g, c.b, 1, N.FONT)
        self.choiceBtn:setVisible(v.offer == true)
        if v.offer then self.choiceBtn:setTitle(N.fit(M.workChoiceText(self.action), bw - m.btnPad, N.FONT)) end
    end

    -- ---- the action's hooks (Actions.lua) -----------------------------------------------------------

    --- The actions whose work is shown now.
    local live = {}

    local function closePanel(action)
        local ui = action.workPanel
        action.workPanel = nil
        if ui ~= nil then pcall(function() ui:removeFromUIManager() end) end
    end

    --- The share of the work the authority saved on the gate before this session: 0 for a try
    --- that starts over.
    local function savedOf(action)
        local def = M.ROUTES[action.routeId]
        if def == nil or def.fresh then return 0 end
        local md = M.sealedGateOf(action.obj)
        local p = md ~= nil and type(md.progress) == "table" and M.finite(md.progress[action.routeId]) or nil
        return M.clamp(p or 0, 0, 1)
    end

    -- What this client last left each box's work as, by box object and route, on the same
    -- contract as the authority's own record (Gates.workResume).
    local leftWork = setmetatable({}, { __mode = "k" })

    function M.workOpen(action)
        local look = M.WORK_LOOKS[action.routeId]
        if look == nil or action.workOn then return end
        local okI, instant = pcall(function() return action.character:isTimedActionInstant() end)
        if okI and instant == true then return end
        action.workOn = true
        action.workSaved = savedOf(action)
        local left = leftWork[action.obj] and leftWork[action.obj][action.routeId] or nil
        local resume = M.workResume(action.routeId, left or { progress = action.workSaved },
            left and left.at or nil, nowMs())
        action.workCooled, action.workStart = resume.cooled, resume.heat
        action.workStep = M.workStep(look, action.workSaved)
        action.workWallMs, action.workLastMs = 0, nowMs()
        live[action] = true
        if not M.workShown() or M.workDanger(action.character) then return end
        local ui = LugliDMSWorkPanel:new(action)
        ui:initialise()
        ui:addToUIManager()
        action.workPanel = ui
    end

    local OVERHEATED = {
        drill = "The drill overheated and stopped.",
        torch = "The torch overheated and cut out.",
    }

    --- The offer was left too long: the work stops as any stop does, its progress kept.
    local function overheat(action)
        cue(action, "overheated")
        action.stoppedBy = "IGUI_LugliDMS_Overheated_" .. action.routeId
        action.stoppedFallback = OVERHEATED[action.routeId]
        action:forceStop()
    end

    function M.workTick(action)
        if not action.workOn then return end
        -- The real time worked since the last tick, a pause left out.
        local t = nowMs()
        local from = action.workLastMs or t
        if action.workPauseUntil ~= nil then from = math.max(from, action.workPauseUntil) end
        if t > from then action.workWallMs = (action.workWallMs or 0) + (t - from) end
        action.workLastMs = t
        if action.workPauseUntil ~= nil then
            if nowMs() < action.workPauseUntil then
                if action.workHeld ~= nil then action:setCurrentTime(action.workHeld) end
            else
                action.workPauseUntil, action.workHeld = nil, nil
                pcall(function() action:resound() end)
            end
        end
        local v = M.workView(action)
        if v == nil then return end
        if v.step > (action.workStep or 0) then
            action.workStep = v.step
            cue(action, "step")
        end
        local pad = padOf(action.character)
        local down = lbDown(pad)
        if down and not action.workPadDown and M.workChoose(action) then v = M.workView(action) end
        action.workPadDown = down
        if action.workPanel ~= nil and M.workDanger(action.character) then closePanel(action) end
        local c = M.WORK_CHOICES[action.routeId]
        if v.offer and c.grace ~= nil and (action.workPanel ~= nil or pad ~= nil) then
            action.workOfferedMs = action.workOfferedMs or t
            if t - action.workOfferedMs >= c.grace * 1000 then
                overheat(action)
                return
            end
        else
            action.workOfferedMs = nil
        end
        -- With the panel hidden or closed, a controller survivor is told the offer once each time.
        if v.offer and action.workPanel == nil and pad ~= nil and not action.workSaid then
            action.workSaid = true
            if HaloTextHelper ~= nil then
                pcall(function() HaloTextHelper.addBadText(action.character, M.workChoiceText(action)) end)
            end
        elseif not v.offer then
            action.workSaid = false
        end
    end

    function M.workClose(action)
        local c = M.WORK_CHOICES[action.routeId]
        if action.workOn and c ~= nil and action.obj ~= nil then
            local progress = M.workProgress(action.workSaved, jobDelta(action))
            leftWork[action.obj] = leftWork[action.obj] or {}
            leftWork[action.obj][action.routeId] = {
                heat = M.heatAfter(action.routeId, action.workStart, (M.finite(action.workWallMs) or 0) / 1000),
                progress = progress, at = nowMs() }
        end
        live[action] = nil
        action.workOn = false
        action.workPauseUntil, action.workHeld, action.workOfferedMs = nil, nil, nil
        closePanel(action)
    end

    M.addTeardown(PART, function()
        local all = {}
        for action in pairs(live) do all[#all + 1] = action end
        for i = 1, #all do M.workClose(all[i]) end
    end)

    addOptions()
    M.status(PART, true)
end
