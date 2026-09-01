require "LugliAchievements/Core"

local M = LugliAchievements
local PART = "Preferences"

-- A cfg file, not ModData: ModData is per save, and where you like the window follows the
-- PLAYER. One key=value per line, since getFileWriter only accepts ini, cfg, txt, log and json.
local FILE = "LugliAchievements.cfg"

-- An unknown key in the file is ignored rather than carried, so removing a setting later cannot
-- leave litter behind forever.
local NUMERIC = { zoom = true, x = true, y = true, w = true, h = true, sort = true }
local TEXT = { filter = true }

local prefs = {}
local loaded = false
local dirty = false

local function load()
    if loaded then return end
    loaded = true
    if getFileReader == nil then return end
    local ok, reader = pcall(getFileReader, FILE, false)
    if not ok or reader == nil then return end
    pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            local k, v = string.match(line, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k ~= nil then
                if NUMERIC[k] then
                    local n = tonumber(v)
                    if n ~= nil then prefs[k] = n end
                elseif TEXT[k] then
                    prefs[k] = v
                end
            end
        end
    end)
    pcall(function() reader:close() end)
end

--- Reads the file on first use rather than at load: client/ runs at boot and the file API is
--- not guaranteed that early.
function M.pref(key, fallback)
    load()
    local v = prefs[key]
    if v == nil then return fallback end
    return v
end

--- Deferred to savePrefs, so dragging a window does not write a file every frame.
function M.setPref(key, value)
    if not (NUMERIC[key] or TEXT[key]) then return end
    load()
    if prefs[key] == value then return end
    prefs[key] = value
    dirty = true
end

function M.savePrefs()
    if not dirty or getFileWriter == nil then return end
    local ok, writer = pcall(getFileWriter, FILE, true, false)
    if not ok or writer == nil then return end
    pcall(function()
        writer:write("# Lugli - Achievements. Window preferences, rewritten by the game.\n")
        for _, k in ipairs({ "zoom", "x", "y", "w", "h", "filter", "sort" }) do
            if prefs[k] ~= nil then
                writer:write(k .. " = " .. tostring(prefs[k]) .. "\n")
            end
        end
    end)
    pcall(function() writer:close() end)
    dirty = false
end

-- Death is the one exit that does not go through the window's own close path. Registered once,
-- at file scope: inside an OnGameStart handler this added a fresh closure per world loaded and
-- never removed one.
M.addHandler(PART, "OnPlayerDeath", M.savePrefs)

M.status(PART, true, "window size, position and last category")
