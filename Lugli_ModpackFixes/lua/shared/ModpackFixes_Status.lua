--[[
Part registry and circuit breaker for Lugli - B42 Modpack Compats & Fixes.

Every part patches another author's mod, so every part must be able to refuse. A part goes
through these checks, in order, and any one of them leaves the game exactly as the other mods
made it:

  side        the part is for this kind of game (client, server, or both)
  activation  the mods it needs are active, and none of the mods that make it pointless
  switch      the player left its sandbox option on (read lazily, cached once a world is up)
  pins        the code it was written against is still the code on disk (ModpackFixes_Pins.lua)
  check       the code it patches, as loaded now, has the shape the part needs (def.check)
  install     each assignment reads back
  runtime     its first error at run time undoes it for the rest of the session

A part that refuses because of another mod or the game, at the pins or the check, stands down
silently, as "tripped"; code that only finds out after install (an event handler) calls
ctx.standDown(why) instead. error() is for this mod's own faults only: Kahlua shows the game's error
box at the throw even inside pcall (KahluaThread.flushErrorMessage), so a part that refused by
raising would look to the player like a crash.

Lua is rebuilt on every exit to the main menu (IngameState.java:972-1072 on 42.22.2), so a part
installs once per Lua state and never has to re-assert.
]]
require "ModpackFixes_Pins"

LugliModpackFixes = LugliModpackFixes or {}
local M = LugliModpackFixes

M.TAG = "[Lugli/ModpackFixes]"
M.SANDBOX_PAGE = "LugliModpackFixes"
M.HASH_MOD = 4294967296
M.parts = M.parts or {}
M.partOrder = M.partOrder or {}
M.defs = M.defs or {}
M.pins = M.pins or {}
M.pinResults = M.pinResults or {}
M.worldReady = false

function M.log(msg)
    print(M.TAG .. " " .. tostring(msg))
end

function M.setPart(name, ok, note, kind)
    if M.parts[name] == nil then
        M.partOrder[#M.partOrder + 1] = name
    end
    M.parts[name] = { ok = ok, note = note, kind = kind }
end

function M.isModActive(id)
    local ok, res = pcall(function() return getActivatedMods():contains(id) end)
    return ok and res == true
end

function M.isDedicatedServer()
    return type(isServer) == "function" and isServer() == true
end

function M.isMultiplayerClient()
    return type(isClient) == "function" and isClient() == true
end

function M.sideSkip(def)
    if def.side == "client" and M.isDedicatedServer() then return "client part on a server" end
    if def.side == "server" and M.isMultiplayerClient() then return "server part on a client" end
    return nil
end

function M.activationSkip(def)
    local all, none, any = def.all or {}, def.none or {}, def.any
    for i = 1, #all do
        if not M.isModActive(all[i]) then return all[i] .. " not active" end
    end
    for i = 1, #none do
        if M.isModActive(none[i]) then return none[i] .. " is active" end
    end
    if any ~= nil then
        for i = 1, #any do
            if M.isModActive(any[i]) then return nil end
        end
        return "none of " .. table.concat(any, ", ") .. " active"
    end
    return nil
end

function M.readSwitch(def)
    local ok, v = pcall(function() return SandboxVars[M.SANDBOX_PAGE][def.switch] end)
    if ok and v == false then return false end
    return true
end

function M.switchOn(def)
    if def.switchCache ~= nil then return def.switchCache end
    local v = M.readSwitch(def)
    if M.worldReady then def.switchCache = v end
    return v
end

function M.partLive(def)
    return def.open ~= true and M.switchOn(def)
end

function M.hashLine(h, line)
    local last = #line
    while last > 0 and string.byte(line, last) <= 32 do
        last = last - 1
    end
    for i = 1, last do
        local c = string.byte(line, i)
        if c < 128 then h = (h * 31 + c) % M.HASH_MOD end
    end
    return (h * 31 + 10) % M.HASH_MOD
end

function M.fingerprint(reader, anchor, count)
    local h, taken, found = 0, 0, false
    while taken < count do
        local line = reader:readLine()
        if line == nil then break end
        if not found and string.find(line, anchor, 1, true) ~= nil then found = true end
        if found then
            h = M.hashLine(h, line)
            taken = taken + 1
        end
    end
    if not found then return nil end
    return h
end

function M.evalPin(name)
    local pin = M.pins[name]
    if pin == nil then return false, "unknown pin " .. tostring(name) end
    local okOpen, reader = pcall(getModFileReader, pin.mod, pin.file, false)
    if not okOpen or reader == nil then return false, pin.mod .. " file missing (" .. name .. ")" end
    local okHash, h = pcall(M.fingerprint, reader, pin.anchor, pin.lines)
    pcall(function() reader:close() end)
    if not okHash then return false, name .. " unreadable: " .. tostring(h) end
    if h == nil then return false, pin.mod .. " changed (" .. name .. ": anchor gone)" end
    for i = 1, #pin.accept do
        if pin.accept[i] == h then return true, nil end
    end
    return false, pin.mod .. " changed (" .. name .. ": got " .. tostring(h) .. ")"
end

function M.checkPin(name)
    local r = M.pinResults[name]
    if r == nil then
        local ok, note = M.evalPin(name)
        r = { ok = ok, note = note }
        M.pinResults[name] = r
    end
    return r.ok, r.note
end

function M.runUndos(def)
    local undos = def.undos or {}
    for i = #undos, 1, -1 do
        pcall(undos[i])
    end
    def.undos = {}
end

function M.trip(def, err)
    if def.open == true then return end
    def.open = true
    M.runUndos(def)
    M.setPart(def.name, false, tostring(err), "open")
    M.log(def.name .. ": circuit open, part undone for this session: " .. tostring(err))
end

-- The silent refusal for code that runs after install: what it needs from another mod or the game
-- is not there. Undone and off for the session like a trip, but recorded as tripped, not as a fault.
function M.standDown(def, why)
    if def.open == true then return end
    def.open = true
    M.runUndos(def)
    M.setPart(def.name, false, tostring(why), "pin")
    M.log(def.name .. ": stood down for this session: " .. tostring(why))
end

local function pack(...)
    return { n = select("#", ...), ... }
end

-- A Java object seen through Lua: every method is the real one bar `overrides` (name -> function
-- of self). `realObject` is the object itself, for a part that is handed another part's overlay.
function M.overlay(object, overrides)
    local methods = {}
    return setmetatable({ realObject = object }, { __index = function(_, key)
        local fn = overrides[key] or methods[key]
        if fn == nil then
            local method = object[key]
            if method == nil then return nil end
            fn = function(_, ...) return method(object, ...) end
            methods[key] = fn
        end
        return fn
    end })
end

function M.realOf(object)
    while type(object) == "table" and object.realObject ~= nil do object = object.realObject end
    return object
end

function M.makeCtx(def)
    local ctx = { def = def }

    function ctx.enabled()
        return M.partLive(def)
    end

    function ctx.standDown(why)
        M.standDown(def, why)
    end

    function ctx.undo(fn)
        def.undos[#def.undos + 1] = fn
    end

    -- build(callOriginal) returns the replacement. An error in it trips the part; if the
    -- original had not run yet in that call it runs then, otherwise its results are returned.
    function ctx.wrap(tbl, key, build)
        if type(tbl) ~= "table" then error("no table to patch for " .. tostring(key)) end
        local original = tbl[key]
        if type(original) ~= "function" then error(tostring(key) .. " is not a function") end
        local state = { calls = 0, last = nil }
        local function callOriginal(...)
            state.calls = state.calls + 1
            state.last = pack(original(...))
            return unpack(state.last, 1, state.last.n)
        end
        local inner = build(callOriginal)
        if type(inner) ~= "function" then error(tostring(key) .. ": the part built no function") end
        local function wrapper(...)
            if not M.partLive(def) then return original(...) end
            local before = state.calls
            local res = pack(pcall(inner, ...))
            if res[1] then return unpack(res, 2, res.n) end
            M.trip(def, res[2])
            if state.calls ~= before then return unpack(state.last, 1, state.last.n) end
            return original(...)
        end
        tbl[key] = wrapper
        if tbl[key] ~= wrapper then error(tostring(key) .. " rejected the assignment") end
        ctx.undo(function()
            if tbl[key] == wrapper then tbl[key] = original end
        end)
        return wrapper
    end

    -- An event handler under the breaker: silent when the part is off, and its first error opens it.
    function ctx.guard(handler)
        return function(...)
            if not M.partLive(def) then return end
            local ok, err = pcall(handler, ...)
            if not ok then M.trip(def, err) end
        end
    end

    function ctx.on(eventName, handler)
        local ev = Events[eventName]
        if ev == nil then error("no event " .. tostring(eventName)) end
        local guarded = ctx.guard(handler)
        ev.Add(guarded)
        ctx.undo(function() ev.Remove(guarded) end)
        return guarded
    end

    -- Runs fn once at a later event, under the same breaker. Used to register a handler after
    -- every other mod has registered its own.
    function ctx.at(eventName, fn)
        local ev = Events[eventName]
        if ev == nil then error("no event " .. tostring(eventName)) end
        local fired = false
        ev.Add(function()
            if fired or def.open == true then return end
            fired = true
            local ok, err = pcall(fn)
            if not ok then M.trip(def, err) end
        end)
    end

    return ctx
end

function M.installPart(def)
    if def.done then return end
    def.done = true
    local why = M.sideSkip(def) or M.activationSkip(def)
    if why == nil and M.worldReady and not M.switchOn(def) then why = "switched off" end
    if why ~= nil then
        M.setPart(def.name, nil, why, "dep")
        return
    end
    -- A pin on a mod that is not active guards code that never runs (an `any` part's other half).
    -- A `vanilla` pin names no active mod, so it is left to the build gate: Lua cannot read game files.
    local pins = def.pins or {}
    for i = 1, #pins do
        local pin = M.pins[pins[i]]
        local ok, note = true, nil
        if pin == nil or M.isModActive(pin.mod) then ok, note = M.checkPin(pins[i]) end
        if not ok then
            M.setPart(def.name, false, note, "pin")
            return
        end
    end
    -- check() returns nil when the part can install, or why it cannot.
    if def.check ~= nil then
        local checked, why = pcall(def.check)
        if not checked then
            M.setPart(def.name, false, tostring(why), "bug")
            return
        end
        if why ~= nil then
            M.setPart(def.name, false, tostring(why), "pin")
            return
        end
    end
    def.undos = {}
    local ok, err = pcall(def.install, M.makeCtx(def))
    if ok then
        -- An install that stood the part down (ctx.standDown) keeps that status.
        if def.open == true then return end
        def.installed = true
        M.setPart(def.name, true, nil, "ok")
    else
        M.runUndos(def)
        M.setPart(def.name, false, tostring(err), "bug")
    end
end

-- phase: "load" installs while this mod's shared Lua loads (before any mod's client Lua),
-- "boot" at OnGameBoot (after every mod's client Lua), "world" when a world starts.
function M.addPart(def)
    if type(def) ~= "table" or type(def.name) ~= "string" or type(def.switch) ~= "string"
        or type(def.install) ~= "function" then
        error("addPart needs name, switch and install")
    end
    def.phase = def.phase or "world"
    def.side = def.side or "client"
    M.defs[#M.defs + 1] = def
    M.setPart(def.name, nil, "waiting for " .. def.phase, "pending")
    if def.phase == "load" then M.installPart(def) end
end

function M.installPhase(phase)
    for i = 1, #M.defs do
        if M.defs[i].phase == phase then M.installPart(M.defs[i]) end
    end
end

function M.partText(p)
    if p.kind == "ok" then return "installed" end
    if p.kind == "dep" then return "skipped: " .. tostring(p.note) end
    if p.kind == "pin" then return "tripped: " .. tostring(p.note) end
    if p.kind == "open" then return "open: " .. tostring(p.note) end
    if p.kind == "pending" then return "pending: " .. tostring(p.note) end
    return "failed: " .. tostring(p.note)
end

function M.statusLine(when)
    local items = {}
    for i = 1, #M.partOrder do
        local name = M.partOrder[i]
        items[i] = name .. ": " .. M.partText(M.parts[name])
    end
    local line = when .. " [build " .. tostring(M.BUILD or "unstamped") .. "], " .. #items .. " part(s)"
    if #items > 0 then
        line = line .. ": " .. table.concat(items, "; ")
    end
    return line
end

function M.boot()
    M.installPhase("boot")
    M.log(M.statusLine("loaded"))
end

-- A part installed before the world existed could not read its switch; say so now.
function M.worldStart()
    if M.worldReady then return end
    M.worldReady = true
    M.installPhase("world")
    for i = 1, #M.defs do
        local def = M.defs[i]
        if def.installed and def.open ~= true and not M.switchOn(def) then
            M.setPart(def.name, nil, "switched off", "dep")
        end
    end
    M.log(M.statusLine("world"))
end

if Events then
    if Events.OnGameBoot then Events.OnGameBoot.Add(M.boot) end
    if Events.OnGameStart then Events.OnGameStart.Add(M.worldStart) end
    if Events.OnServerStarted then Events.OnServerStarted.Add(M.worldStart) end
end
