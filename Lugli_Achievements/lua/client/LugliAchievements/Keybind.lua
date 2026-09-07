require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Keybind"

-- Registered as {value=, key=} with default F7.
local function install()
    if type(keyBinding) ~= "table" or Keyboard == nil then
        M.status(PART, false, "keyBinding is not available", "dep")
        return
    end
    for i = 1, #keyBinding do
        if keyBinding[i] ~= nil and keyBinding[i].value == "Toggle Achievements" then
            M.status(PART, true, "already registered")
            return
        end
    end
    local defaultKey = (Keyboard and Keyboard.KEY_F7) or 65
    table.insert(keyBinding, { value = "[Lugli Achievements]" })
    table.insert(keyBinding, { value = "Toggle Achievements", key = defaultKey })
    M.status(PART, true, "registered, default F7")
end

function M.getHotkeyString()
    if getCore == nil or type(getKeyName) ~= "function" then return nil end
    local ok, want = pcall(function() return getCore():getKey("Toggle Achievements") end)
    if not ok or want == nil or want == 0 then return nil end
    local okName, name = pcall(getKeyName, want)
    if okName and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

M.addHandler(PART, "OnGameBoot", install)
install()

local lastKeyToggleMs = 0

if not M.keybindHandlerInstalled then
    M.keybindHandlerInstalled = true
    M.addHandler(PART, "OnKeyPressed", function(key)
        if getCore() == nil then return end
        local okMatch, match = pcall(function() return getCore():isKey("Toggle Achievements", key) end)
        if not okMatch or not match then return end
        if getSpecificPlayer == nil or getSpecificPlayer(0) == nil then return end
        local now = (type(getTimestampMs) == "function") and getTimestampMs() or 0
        if now - lastKeyToggleMs < 250 then return end
        lastKeyToggleMs = now
        M.toggleWindow(0)
    end)
end
