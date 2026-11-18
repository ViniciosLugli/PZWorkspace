--[[
Part registry for Lugli - Grease of Marz.

Every part patches another author's mod, so every part must be able to refuse. A part goes
through these checks, in order, and any one of them leaves the game exactly as the other mods
made it:

  targets     every mod it patches is active
  check       the code it patches, as loaded now, has the shape the part needs (opts.check)
  install     each assignment reads back

A part that refuses because of another mod or the game, at the check, stands down silently, as
"tripped"; code that only finds out after install (an event handler) calls ctx.standDown(why)
instead. error() is for this mod's own faults only: Kahlua shows the game's error box at the throw
even inside pcall (KahluaThread.flushErrorMessage), so a part that refused by raising would look
to the player like a crash.
]]
LugliGreaseOfMarz = LugliGreaseOfMarz or {}
local M = LugliGreaseOfMarz

M.TAG = "[Lugli/GreaseOfMarz]"
M.parts = M.parts or {}
M.partOrder = M.partOrder or {}
M.defs = M.defs or {}

function M.log(msg)
    print(M.TAG .. " " .. tostring(msg))
end

function M.setPart(name, ok, note, kind)
    if M.parts[name] == nil then
        M.partOrder[#M.partOrder + 1] = name
    end
    M.parts[name] = { ok = ok, note = note, kind = kind }
end

-- opts.check, when given, returns nil when the part can install, or why it cannot.
function M.addPart(name, targets, install, opts)
    M.defs[#M.defs + 1] = { name = name, targets = targets, install = install, check = opts and opts.check }
end

function M.isModActive(id)
    local ok, active = pcall(function() return getActivatedMods():contains(id) end)
    return ok and active == true
end

function M.missingTarget(def)
    for i = 1, #def.targets do
        if not M.isModActive(def.targets[i]) then return def.targets[i] end
    end
    return nil
end

-- The silent refusal for code that runs after install: what it needs from another mod or the game
-- is not there. The part leaves stock behaviour in place and is recorded as tripped, not as a fault.
function M.standDown(def, why)
    if def.open == true then return end
    def.open = true
    M.setPart(def.name, false, tostring(why), "pin")
    M.log(def.name .. ": stood down for this session: " .. tostring(why))
end

function M.installPart(def)
    local missing = M.missingTarget(def)
    if missing ~= nil then
        M.setPart(def.name, false, missing .. " not active", "dep")
        return
    end
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
    local ctx = { def = def }
    function ctx.standDown(why)
        M.standDown(def, why)
    end
    local ok, err = pcall(def.install, ctx)
    if def.open == true then return end
    if ok then
        M.setPart(def.name, true, nil, "ok")
    else
        M.setPart(def.name, false, tostring(err), "bug")
    end
end

function M.partText(p)
    if p.ok == true then return "installed" end
    if p.kind == "dep" then return "skipped: " .. tostring(p.note) end
    if p.kind == "pin" then return "tripped: " .. tostring(p.note) end
    return "failed: " .. tostring(p.note)
end

function M.bootLine()
    local items = {}
    for i = 1, #M.partOrder do
        local name = M.partOrder[i]
        items[i] = name .. ": " .. M.partText(M.parts[name])
    end
    local line = "loaded [build " .. tostring(M.BUILD or "unstamped") .. "], " .. #items .. " part(s)"
    if #items > 0 then
        line = line .. ": " .. table.concat(items, "; ")
    end
    return line
end

function M.boot()
    for i = 1, #M.defs do
        M.installPart(M.defs[i])
    end
    M.log(M.bootLine())
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(M.boot)
end
