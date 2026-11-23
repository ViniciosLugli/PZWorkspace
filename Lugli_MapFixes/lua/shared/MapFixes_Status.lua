LugliMapFixes = LugliMapFixes or {}
local M = LugliMapFixes

M.TAG = "[Lugli/MapFixes]"
M.parts = M.parts or {}
M.partOrder = M.partOrder or {}
M.defs = M.defs or {}
M.active = M.active or {}

function M.log(msg)
    print(M.TAG .. " " .. tostring(msg))
end

function M.setPart(name, ok, note, kind)
    if M.parts[name] == nil then
        M.partOrder[#M.partOrder + 1] = name
    end
    M.parts[name] = { ok = ok, note = note, kind = kind }
end

-- yieldTo: a mod that does this part's job its own way; while it is active the part stays out.
function M.addPart(name, target, install, yieldTo)
    local def = { name = name, target = target, install = install, yieldTo = yieldTo }
    M.defs[#M.defs + 1] = def
    -- SP loads server/ at world load (GameLoadingState), after OnGameBoot has fired
    if M.booted and M.parts[name] == nil then
        M.installPart(def)
        M.log(M.bootLine())
    end
end

function M.isModActive(id)
    local ok, active = pcall(function() return getActivatedMods():contains(id) end)
    return ok and active == true
end

function M.installPart(def)
    if def.target ~= nil and not M.isModActive(def.target) then
        M.setPart(def.name, false, def.target .. " not active", "dep")
        return
    end
    if def.yieldTo ~= nil and M.isModActive(def.yieldTo) then
        M.setPart(def.name, false, def.yieldTo .. " is active and replaces it", "dep")
        return
    end
    local ok, err = pcall(def.install)
    if ok then
        M.setPart(def.name, true, nil, "ok")
    else
        M.setPart(def.name, false, tostring(err), "bug")
    end
end

function M.partText(p)
    if p.ok == true then return "installed" end
    if p.kind == "dep" then return "skipped: " .. tostring(p.note) end
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
    M.booted = true
    for i = 1, #M.defs do
        M.installPart(M.defs[i])
    end
    M.log(M.bootLine())
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(M.boot)
end
