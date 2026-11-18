LugliCrispScreen = LugliCrispScreen or {}
local M = LugliCrispScreen

M.TAG = "[Lugli/CrispScreen]"
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

function M.installPart(def)
    local ok, err = pcall(def.install)
    if ok then
        M.setPart(def.name, true, err, "ok")
    else
        M.setPart(def.name, false, tostring(err), "bug")
    end
end

function M.partText(p)
    if p.ok == true then return p.note ~= nil and tostring(p.note) or "installed" end
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

-- The shader itself is a file override the engine compiles on its own; this part only proves the
-- generated description shipped with it, so a support log names the vanilla file it came from.
M.addPart("Shader", function()
    if M.SHADER_VANILLA_SHA == nil or M.SHADER_SHARPNESS == nil then
        error("CrispScreen_Shader.lua did not load")
    end
    return M.shaderText()
end)

function M.shaderText()
    return "screen.frag from vanilla " .. tostring(M.SHADER_VANILLA_SHA) .. ", sharpness " .. tostring(M.SHADER_SHARPNESS)
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(M.boot)
end
