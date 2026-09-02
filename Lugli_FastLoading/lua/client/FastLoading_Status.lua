--[[
    FastLoading status panel.

    A small notice in the top-right of the main menu, shown only when a part could
    not enable itself. When everything is active it stays hidden. Close it with the x
    button; it stays closed for the session.

    Parts record themselves in FastLoading.parts, so this reads real outcomes rather
    than guessing from the mod list. The Java side reports through a global the jar
    registers; a missing global is NOT proof that ZombieBuddy is absent, so ask
    ZombieBuddy itself before blaming it.
]]

FastLoading = FastLoading or {}
FastLoading.parts = FastLoading.parts or {}

local PAD, ROW, W = 16, 20, 400
local TITLE_GAP, NOTE_INDENT = 10, 18
local dismissed = false
local panel = nil

local MOD_ID = "Lugli_FastLoading"

--- ZombieBuddy's own account of this jar, or nil when it will not give one.
-- Fields per ZombieBuddy's LuaAPI: loaded, reason, sha256, decision, persisted.
local function jarStatus()
    if ZombieBuddy == nil then return nil end
    local ok, st = pcall(function() return ZombieBuddy.getJavaModStatus(MOD_ID) end)
    if not ok or type(st) ~= "table" then return nil end
    return st
end

--- Java side.
--
-- Three states have to stay apart, and only the first is a missing dependency:
--   ZombieBuddy absent                  the mod cannot patch anything, and says so
--   present, jar not loaded             report its own reason, verbatim
--   jar loaded, bridge global missing    a defect here; the engine patches are unaffected
--
-- This used to collapse all three onto the first, so a player whose patches were demonstrably
-- running was told to install the ZombieBuddy they already had.
local function javaStatus()
    if type(FastLoading_JavaActive) ~= "function" then
        if ZombieBuddy == nil then
            return { ok = false, kind = "dep", note = "needs ZombieBuddy (Java patches inactive)" }
        end
        local jar = jarStatus()
        if jar and jar.loaded == false then
            local why = type(jar.reason) == "string" and jar.reason or "no reason given"
            return { ok = false, kind = "bug", note = "ZombieBuddy: " .. why }
        end
        -- Loaded, or ZombieBuddy would not say. Either way the patches are not implicated:
        -- the boot screen and the asset work are woven in Java and never read this global.
        return { ok = false, kind = "bug", note = "jar loaded but the Lua bridge is missing" }
    end
    local ok, active = pcall(FastLoading_JavaActive)
    if not ok or not active then
        return { ok = false, kind = "bug", note = "ZombieBuddy is present but the jar did not load" }
    end
    -- A parser defect is a correctness failure, not a missing feature: our replacement for
    -- ScriptParser disagreed with the engine's own and disabled itself. Report it loudly.
    if type(FastLoading_ParseDefect) == "function" then
        local okP, defect = pcall(FastLoading_ParseDefect)
        if okP and defect then
            return { ok = false, kind = "bug",
                     note = "script tokenizer disagreed with the engine and was disabled" }
        end
    end

    local bits = {}
    if type(FastLoading_AssetBudgetMB) == "function" then
        local ok2, mb = pcall(FastLoading_AssetBudgetMB)
        if ok2 then bits[#bits + 1] = tostring(mb) .. " MB buffer budget" end
    end
    if type(FastLoading_LogoSkipped) == "function" then
        local ok3, skipped = pcall(FastLoading_LogoSkipped)
        if ok3 then bits[#bits + 1] = skipped and "intro logos skipped" or "intro logos kept" end
    end
    -- Not a failure, so it never opens the panel on its own. But if the panel is already open
    -- for some other reason, say that hot reload is off: that IS a behaviour change.
    if type(FastLoading_WatcherGateStatus) == "function" then
        local ok4, st = pcall(FastLoading_WatcherGateStatus)
        if ok4 and type(st) == "string" and st:sub(1, 2) == "ok" then
            bits[#bits + 1] = "media hot-reload watch off"
        end
    end
    return { ok = true, note = (#bits > 0) and table.concat(bits, ", ") or nil }
end

local function collect()
    local rows, bad, bugs = {}, 0, 0
    local parts = FastLoading.parts or {}
    local names = {}
    for name in pairs(parts) do names[#names + 1] = name end
    table.sort(names)
    for i = 1, #names do
        local p = parts[names[i]]
        rows[#rows + 1] = { name = names[i], ok = p.ok, note = p.note, kind = p.kind }
        if not p.ok and p.kind ~= "pending" then
            bad = bad + 1
            if p.kind ~= "dep" then bugs = bugs + 1 end
        end
    end
    local j = javaStatus()
    rows[#rows + 1] = { name = "Boot and asset patches", ok = j.ok, note = j.note, kind = j.kind }
    if not j.ok then
        bad = bad + 1
        if j.kind ~= "dep" then bugs = bugs + 1 end
    end
    return rows, bad, bugs
end

local Panel = ISPanel:derive("FastLoadingStatusPanel")

function Panel:createChildren()
    ISPanel.createChildren(self)
    local s = 20
    self.close = ISButton:new(self.width - s - 10, 10, s, s, "x", self, Panel.onClose)
    self.close.backgroundColor            = { r = 1, g = 1, b = 1, a = 0.06 }
    self.close.backgroundColorMouseOver   = { r = 0.87, g = 0.64, b = 0.34, a = 0.30 }
    self.close.borderColor                = { r = 0.55, g = 0.58, b = 0.52, a = 0.7 }
    self.close.textColor                  = { r = 0.85, g = 0.86, b = 0.82, a = 1 }
    self.close:initialise()
    self:addChild(self.close)
end

function Panel:onClose()
    dismissed = true
    self:removeFromUIManager()
    panel = nil
end

function Panel:prerender()
    ISPanel.prerender(self)
    -- accent rule along the top edge
    self:drawRect(0, 0, self.width, 2, 0.9, 0.87, 0.64, 0.34)

    local y = PAD
    self:drawText("FastLoading", PAD, y, 0.95, 0.93, 0.88, 1, UIFont.Small)
    y = y + ROW + TITLE_GAP

    for i = 1, #self.rows do
        local r = self.rows[i]
        if r.ok then
            self:drawText("+", PAD, y, 0.45, 0.78, 0.48, 1, UIFont.Small)
        elseif r.kind == "pending" then
            self:drawText("~", PAD, y, 0.55, 0.58, 0.62, 1, UIFont.Small)
        elseif r.kind == "dep" then
            self:drawText("-", PAD, y, 0.62, 0.65, 0.60, 1, UIFont.Small)
        else
            self:drawText("x", PAD, y, 0.86, 0.42, 0.32, 1, UIFont.Small)
        end
        self:drawText(r.name, PAD + NOTE_INDENT, y, 0.85, 0.86, 0.82, 1, UIFont.Small)
        y = y + ROW
        if r.note then
            self:drawText(r.note, PAD + NOTE_INDENT, y, 0.55, 0.57, 0.53, 1, UIFont.Small)
            y = y + ROW
        end
    end

    if self.bugs > 0 then
        y = y + 6
        self:drawRect(PAD, y, self.width - PAD * 2, 1, 0.35, 0.5, 0.5, 0.45)
        y = y + 8
        self:drawText("An x above is a defect, not a missing dependency.",
                      PAD, y, 0.80, 0.62, 0.34, 1, UIFont.Small)
        y = y + ROW
        self:drawText("Please report it on the Workshop page, with your console.txt.",
                      PAD, y, 0.80, 0.62, 0.34, 1, UIFont.Small)
    end
end

local function height(rows, bugs)
    local h = PAD + ROW + TITLE_GAP
    for i = 1, #rows do
        h = h + ROW
        if rows[i].note then h = h + ROW end
    end
    if bugs > 0 then h = h + 14 + ROW * 2 end
    return h + PAD
end

local function show(force)
    if panel then return end
    if dismissed and not force then return end

    local rows, bad, bugs = collect()
    -- nothing to say when every part is active
    if (bad == 0 and not force and not FastLoading.forceStatusPanel) or #rows == 0 then return end

    -- a defect is worth one line in the log too, so it survives into console.txt
    if bugs > 0 then
        for i = 1, #rows do
            if not rows[i].ok and rows[i].kind ~= "dep" then
                print("[FastLoading/status] DEFECT: " .. rows[i].name .. " - " .. tostring(rows[i].note))
            end
        end
    end

    local h = height(rows, bugs)
    local x = getCore():getScreenWidth() - W - 20
    local y = 20

    panel = Panel:new(x, y, W, h)
    panel.rows = rows
    panel.bugs = bugs
    panel.backgroundColor = { r = 0.07, g = 0.08, b = 0.06, a = 0.90 }
    panel.borderColor = { r = 0.32, g = 0.36, b = 0.28, a = 1 }
    panel:initialise()
    panel:addToUIManager()
end

local function hide()
    if panel then
        panel:removeFromUIManager()
        panel = nil
    end
end

-- Never let a cosmetic panel break the menu: report once and stay gone.
local function guard(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            dismissed = true
            print("[FastLoading/status] panel disabled: " .. tostring(err))
        end
    end
end

--- Summon the panel on demand, even when nothing is wrong. For checking it looks right.
function FastLoading_ShowStatus()
    dismissed = false
    hide()
    local ok, err = pcall(show, true)
    if not ok then print("[FastLoading/status] " .. tostring(err)) end
end

Events.OnMainMenuEnter.Add(guard(function() show(false) end))
Events.OnGameStart.Add(guard(hide))
