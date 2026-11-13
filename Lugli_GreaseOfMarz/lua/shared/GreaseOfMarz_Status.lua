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

function M.addPart(name, targets, install)
    M.defs[#M.defs + 1] = { name = name, targets = targets, install = install }
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

function M.installPart(def)
    local missing = M.missingTarget(def)
    if missing ~= nil then
        M.setPart(def.name, false, missing .. " not active", "dep")
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
    for i = 1, #M.defs do
        M.installPart(M.defs[i])
    end
    M.log(M.bootLine())
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(M.boot)
end
