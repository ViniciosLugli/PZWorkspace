require "LugliAchievements/Core"

local M = LugliAchievements
local PART = "Options"

-- ONE OPTION LIVES HERE, AND ONLY ONE. Progress scope changes what the mod reads at world load,
-- so it belongs on the page you visit between sessions. The unlock sound is a taste decision you
-- want to HEAR while you make it, so it moved into the achievements window, where picking one
-- plays it. See Sound.lua and the settings panel in Window.lua.
--
-- Registration is unconditional: PZAPI.ModOptions save() writes unregistered option lines with
-- no terminator, so consecutive unknown lines fuse and are dropped. Ours is safe while it stays
-- registered.
local function install()
    if PZAPI == nil or PZAPI.ModOptions == nil then
        M.status(PART, false, "the game's mod options API is not present", "dep")
        return
    end

    local ok, options = pcall(function()
        -- Its own key, not the window title: this page sits in a list of every mod's options and
        -- needs the mod's name, while inside the window you already know whose it is.
        return PZAPI.ModOptions:create(M.OPTIONS_ID, getText("UI_LugliAch_opt_title"))
    end)
    if not ok or options == nil then
        M.defect(PART, "could not create the options page: " .. tostring(options))
        return
    end

    -- Default false, which is per world.
    pcall(function()
        options:addTickBox("perCharacter",
                           getText("UI_LugliAch_opt_percharacter"),
                           false,
                           getText("UI_LugliAch_opt_percharacter_tip"))
    end)

    M.status(PART, true, "progress scope; the unlock sound lives in the window")
end

install()

-- Read at world load, not per stat write: a world is the only scope the answer can change
-- between, and the hot path stays free of a menu lookup.
M.addHandler(PART, "OnGameStart", function()
    if type(M.refreshScope) == "function" then
        local per = M.refreshScope()
        M.log(PART, "progress scope: " .. (per and "per character" or "per world"))
    end
end)
