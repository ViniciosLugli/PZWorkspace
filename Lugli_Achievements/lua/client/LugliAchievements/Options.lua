require "LugliAchievements/Core"

local M = LugliAchievements
local PART = "Options"

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

    pcall(function()
        options:addTickBox("unlockSound",
                           getText("UI_LugliAch_opt_unlocksound"),
                           true,
                           getText("UI_LugliAch_opt_unlocksound_tip"))
    end)

    M.status(PART, true, "progress scope, per world by default")
end

--- Read live, unlike the scope beside it: this is asked once per unlock, not on a hot path, and
--- someone who just turned it off wants it off now. Defaults ON, matching the tickbox.
function M.unlockSoundEnabled()
    if PZAPI == nil or PZAPI.ModOptions == nil then return true end
    local ok, opts = pcall(function() return PZAPI.ModOptions:getOptions(M.OPTIONS_ID) end)
    if not ok or opts == nil or opts.getOption == nil then return true end
    local ok2, opt = pcall(function() return opts:getOption("unlockSound") end)
    if not ok2 or opt == nil or opt.getValue == nil then return true end
    local ok3, v = pcall(function() return opt:getValue() end)
    if not ok3 then return true end
    return v ~= false
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
