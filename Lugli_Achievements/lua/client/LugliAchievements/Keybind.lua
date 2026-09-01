require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Keybind"

-- Registered as {value=, key=} objects. The old {name, keycode} array form makes
-- MainOptions.loadKeys call stringStarts(nil) and wipe the main menu.
--
-- No default key: on someone else's mod list any key we picked is already taken. The binding is
-- registered so a player can set one; the way in is the sidebar button.
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
    table.insert(keyBinding, { value = "[Lugli Achievements]" })
    table.insert(keyBinding, { value = "Toggle Achievements", key = 0 })
    M.status(PART, true, "registered, unbound by default")
end

M.addHandler(PART, "OnGameBoot", install)

M.addHandler(PART, "OnKeyPressed", function(key)
    if getCore() == nil then return end
    -- getKey returns 0 when unbound, and every unhandled press arrives here: without the guard
    -- the window would toggle on ANY key.
    local want = getCore():getKey("Toggle Achievements")
    if want ~= nil and want ~= 0 and key == want then M.toggleWindow(0) end
end)
