LugliHonestWeight = LugliHonestWeight or {}
local M = LugliHonestWeight

M.TAG = "[Lugli/HonestWeight]"
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

function M.addPart(name, install)
    M.defs[#M.defs + 1] = { name = name, install = install }
end

-- install returns nothing when it installed, or a string saying why it chose not to.
function M.installPart(def)
    local ok, err = pcall(def.install)
    if ok and type(err) == "string" then
        M.setPart(def.name, false, err, "dep")
    elseif ok then
        M.setPart(def.name, true, M.parts[def.name] and M.parts[def.name].note or nil, "ok")
    else
        M.setPart(def.name, false, tostring(err), "bug")
    end
end

function M.partText(p)
    if p.ok == true then
        if p.note ~= nil then return "installed (" .. tostring(p.note) .. ")" end
        return "installed"
    end
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
