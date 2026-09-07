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

    -- Sidebar button visibility toggle.
    pcall(function()
        options:addTickBox("showSidebarButton",
                           getText("UI_LugliAch_opt_showsidebar"),
                           M.isSidebarButtonEnabled(),
                           getText("UI_LugliAch_opt_showsidebar_tip"))
    end)

    M.status(PART, true, "progress scope and sidebar toggle; the unlock sound lives in the window")
end

function M.isSidebarButtonEnabled()
    if PZAPI ~= nil and PZAPI.ModOptions ~= nil then
        local ok, opts = pcall(function() return PZAPI.ModOptions:getOptions(M.OPTIONS_ID) end)
        if ok and opts ~= nil and opts.getOption ~= nil then
            local ok2, opt = pcall(function() return opts:getOption("showSidebarButton") end)
            if ok2 and opt ~= nil and opt.getValue ~= nil then
                local ok3, v = pcall(function() return opt:getValue() end)
                if ok3 and type(v) == "boolean" then return v end
            end
        end
    end
    if type(M.pref) == "function" then
        return M.pref("showSidebar", 1) == 1
    end
    return true
end

function M.setSidebarButtonEnabled(enabled)
    if type(M.setPref) == "function" then
        M.setPref("showSidebar", enabled and 1 or 0)
        M.savePrefs()
    end
    if PZAPI ~= nil and PZAPI.ModOptions ~= nil then
        pcall(function()
            local opts = PZAPI.ModOptions:getOptions(M.OPTIONS_ID)
            if opts and opts.getOption then
                local opt = opts:getOption("showSidebarButton")
                if opt and opt.setValue then opt:setValue(enabled) end
            end
        end)
    end
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
