require "LugliAchievements/Neat"

local M = LugliAchievements
local PART = "Unlock toast"

local W, H = 400, 88
-- 64, not 48: the icon is the thing a player looks at, and paired with the small texture set it
-- is where the art stops being resampled into mush.
local PAD, ICON = 12, 64
local GAP = 8
-- The engine draws its build string bottom-right, where this stack lands; at 16 the lowest toast
-- sat on top of it.
local EDGE_X, EDGE_BOTTOM = 16, 44
-- Rise in and fall out both cross the bottom edge, so only the BOTTOM slot may do either.
-- live[1] is the oldest and already there, so the oldest always leaves, downward, and the rest
-- glide down behind it: nothing ever crosses anything else.
local ENTER_MS, ENTER_RISE = 260, 22
local EXIT_MS = 320
local SLOT_MS = 220             -- how long a panel takes to glide to a new slot
local HOLD_MS = 3200

local queue, live = {}, {}
local Panel = nil

local function now()
    if getTimestampMs ~= nil then
        local ok, t = pcall(getTimestampMs)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

--- Split screen puts player two on the right half, and positioning against the raw screen would
--- drop every toast onto player one.
local function screenBox(playerNum)
    local n = playerNum or 0
    if getPlayerScreenLeft == nil then
        return 0, 0, getCore():getScreenWidth(), getCore():getScreenHeight()
    end
    local ok, x, y, w, h = pcall(function()
        return getPlayerScreenLeft(n), getPlayerScreenTop(n),
               getPlayerScreenWidth(n), getPlayerScreenHeight(n)
    end)
    -- A real box is the screen, a half or a quarter. Anything smaller is the HUD not laid out
    -- yet, and accepting it anchored toasts to the top-left corner.
    local fullW, fullH = getCore():getScreenWidth(), getCore():getScreenHeight()
    if ok and w and h and w >= fullW * 0.24 and h >= fullH * 0.24 then
        return x, y, w, h
    end
    return 0, 0, fullW, fullH
end

local MAX_LIVE_CAP = 5

--- Derived from the room between the watermark and the top of the screen, never zero.
local function maxLive(playerNum)
    local _, _, _, sh = screenBox(playerNum)
    local room = math.floor((sh - EDGE_BOTTOM) / (H + GAP))
    if room < 1 then return 1 end
    if room > MAX_LIVE_CAP then return MAX_LIVE_CAP end
    return room
end

local function easeOut(t) local u = 1 - t return 1 - u * u * u end
local function easeIn(t)  return t * t * t end

local function slotY(sy, sh, slot)
    return sy + sh - EDGE_BOTTOM - H - slot * (H + GAP)
end

--- Slots bottom-up, skipping anything leaving, so the gap closes as the exit starts.
local function reposition()
    local n = 0
    for i = 1, #live do
        local p = live[i]
        if not p.leaving then
            if p.slot ~= n then
                p.slotPrev = p.slot
                p.slotAt = now()
            end
            p.slot = n
            n = n + 1
        end
    end
end

--- A deep queue holds each toast for less, so a burst drains in seconds rather than minutes.
local function holdFor()
    local waiting = #queue
    if waiting > 10 then return 700 end
    if waiting > 3 then return 1200 end
    return HOLD_MS
end

-- ISPanel can be nil at file load after a menu reload, so the class is derived on first use.
local function ensureClass()
    if Panel ~= nil then return true end
    if type(ISPanel) ~= "table" or type(ISPanel.derive) ~= "function" then return false end

    Panel = ISPanel:derive("LugliAchToast")

    function Panel:new(def, playerNum)
        -- Born in place. ISPanel.new puts it at 0,0 and update() only moves it next frame,
        -- which flashed every toast against the top-left corner.
        local sx, sy, sw, sh = screenBox(playerNum or 0)
        local o = ISPanel.new(self, sx + sw - W - EDGE_X,
                              slotY(sy, sh, 0) + ENTER_RISE, W, H)
        o.def = def
        o.playerNum = playerNum or 0
        o.born = now()
        o.slot = 0
        o.slotPrev = nil
        o.exitAt = nil
        o.leaving = false
        -- Captured at birth, so a draining burst does not stretch out mid-flight.
        o.holdMs = holdFor()
        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        o.moveWithMouse = false
        return o
    end

    --- The panel's alpha, and whether it has finished leaving. One number drives every colour.
    function Panel:phase()
        if self.exitAt ~= nil then
            local t = (now() - self.exitAt) / EXIT_MS
            if t >= 1 then return 0, true end
            return 1 - t, false
        end
        local age = now() - self.born
        if age < ENTER_MS then return age / ENTER_MS, false end
        return 1, false
    end

    function Panel:beginExit(slide)
        if self.exitAt ~= nil then return end
        self.exitAt = now()
        self.exitSlides = slide and true or false
        self.leaving = true
        reposition()
    end

    function Panel:update()
        ISPanel.update(self)
        local _, done = self:phase()
        if done then
            for i = 1, #live do
                if live[i] == self then table.remove(live, i) break end
            end
            reposition()
            self:removeFromUIManager()
            M.toastPump()
            return
        end

        local sx, sy, sw, sh = screenBox(self.playerNum)
        self:setX(math.floor(sx + sw - W - EDGE_X))

        -- Where this slot sits, easing across if the slot changed while the panel was alive.
        local y = slotY(sy, sh, self.slot)
        if self.slotPrev ~= nil then
            local t = (now() - (self.slotAt or 0)) / SLOT_MS
            if t >= 1 then
                self.slotPrev = nil
            else
                local from = slotY(sy, sh, self.slotPrev)
                y = from + (y - from) * easeOut(t)
            end
        end

        if self.exitAt ~= nil then
            if self.exitSlides then
                -- Far enough to clear the edge, eased in so it accelerates away.
                local t = math.min(1, (now() - self.exitAt) / EXIT_MS)
                y = y + easeIn(t) * (H + EDGE_BOTTOM + GAP)
            end
        else
            local age = now() - self.born
            if age < ENTER_MS then
                y = y + (1 - easeOut(age / ENTER_MS)) * ENTER_RISE
            elseif not self.leaving and live[1] == self
                   and age >= ENTER_MS + (self.holdMs or HOLD_MS) then
                self:beginExit(true)
            end
        end
        self:setY(math.floor(y))
    end

    --- Click to dismiss early. Only the bottom panel slides out; one from the middle fades where
    --- it stands, or it would travel through the others.
    function Panel:onMouseDown()
        self:beginExit(live[1] == self)
        return true
    end

    function Panel:render()
        local f = self:phase()
        if f <= 0 then return end
        local N = M.neat
        local def = self.def
        local tc = N.tierCol[def.tier] or N.accent
        local tier = { tc.r, tc.g, tc.b }

        N.panel(self, N.TEX.panelFlat, 0, 0, W, H, N.PANEL_TINT, 0.94 * f)
        self:drawRect(0, 0, 3, H, 0.95 * f, tier[1], tier[2], tier[3])

        -- A missing texture is never drawn: the engine would paint its error checkerboard.
        local ix, iy = PAD, math.floor((H - ICON) / 2)
        local tex = N.art(def.icon, ICON)
        if tex ~= nil then
            self:drawTextureScaled(tex, ix, iy, ICON, ICON, f, 1, 1, 1)
        else
            self:drawRect(ix, iy, ICON, ICON, 0.30 * f, tier[1], tier[2], tier[3])
            self:drawRectBorder(ix, iy, ICON, ICON, 0.60 * f, tier[1], tier[2], tier[3])
        end

        local tx = ix + ICON + PAD
        self:drawText(M.text("UI_LugliAch_toast_header", "ACHIEVEMENT UNLOCKED"),
                      tx, 18, tier[1], tier[2], tier[3], 0.95 * f, UIFont.NewSmall)
        local textW = W - tx - PAD
        -- Fitted, not wrapped: WrapText's first line ends wherever the wrap fell, with no
        -- ellipsis. The name is fitted too, since the 24-char gate is an English budget.
        self:drawText(N.fit(M.text(def.name, def.id), textW, UIFont.Medium),
                      tx, 35, 0.96, 0.94, 0.90, f, UIFont.Medium)

        local desc = M.text(def.description, "")
        if desc ~= "" then
            self:drawText(N.fit(desc, textW, UIFont.Small),
                          tx, 58, 0.72, 0.70, 0.66, 0.9 * f, UIFont.Small)
        end
    end
    return true
end

--- Show the next queued unlock, if there is room. Called on unlock and whenever one expires.
function M.toastPump()
    if #queue == 0 then return end
    if #live >= maxLive(queue[1] and queue[1].playerNum or 0) then return end
    if not ensureClass() then return end

    local entry = table.remove(queue, 1)
    local ok, panel = pcall(function() return Panel:new(entry.def, entry.playerNum) end)
    if not ok or panel == nil then
        M.defect(PART, "could not build a toast: " .. tostring(panel))
        return
    end
    panel:initialise()
    panel:addToUIManager()
    live[#live + 1] = panel
    reposition()
end

--- Rides the toastQuiet gate with the toast: the load-time backfill must not arrive as a burst
--- of chimes over a silent screen. The player picks the sound, or none, in the window itself.
local function playUnlockSound()
    -- Through Sound.lua rather than M.neat.sound, because that helper discards the handle and
    -- the handle is the only way to apply the player's chosen volume.
    if type(M.playAtVolume) ~= "function" then return end
    if type(M.unlockSoundName) ~= "function" then return end
    M.playAtVolume(M.unlockSoundName())
end

--- The registry calls this on every unlock. It must not throw: it runs inside the unlock path.
local function onUnlocked(player, def)
    -- Set during the boot backfill: recorded, not announced.
    if M.toastQuiet == true then return end
    playUnlockSound()
    local n = 0
    if player ~= nil and player.getPlayerNum ~= nil then
        local ok, v = pcall(function() return player:getPlayerNum() end)
        if ok and type(v) == "number" then n = v end
    end
    queue[#queue + 1] = { def = def, playerNum = n }
    M.toastPump()
end

M.onUnlocked = onUnlocked
M.status(PART, true)
