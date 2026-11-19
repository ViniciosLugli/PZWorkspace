--[[
Daily Report Journal: the journal stays closed for a new character.

What happens today. Daily Report Journal builds its window when a world starts and opens it unless
the character has a saved choice (dSAG_Window.lua, the OnGameStart handler: "a save without a stored
preference (brand-new game) starts open so first-time users see the mod"). So every new character
spawns with a report window over the screen and nothing to report: day one has no finished day yet.
A respawn after a death does the same, the window left open from the death screen.

What this part changes. After the mod's own handlers, a character with no saved choice
(modData.dSAG_winVisible unset) gets the journal closed, and that closed state is saved for the
character the way the mod saves a close. The player opens it with the mod's key (J by default) and
that choice is kept as before. The mod's auto-show after a night's sleep and its show on death are
untouched: they need a finished day or a death, and the journal opens for those as ever.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local function check()
    if type(dSAG) ~= "table" then return "Daily Report Journal's dSAG is not loaded" end
    if type(dSAG.ReportWindow) ~= "table" or type(dSAG.ReportWindow.setWindowVisible) ~= "function" then
        return "Daily Report Journal's window has no setWindowVisible"
    end
    return nil
end

local function closeForNewCharacter()
    local win = dSAG.ReportWindow.instance
    local player = getSpecificPlayer(0)
    if win == nil or player == nil then return end
    if player:getModData().dSAG_winVisible ~= nil then return end
    win:setWindowVisible(false)
end

local function install(ctx)
    ctx.on("OnGameStart", closeForNewCharacter)
    ctx.on("OnCreatePlayer", function(playerIndex)
        if playerIndex == 0 then closeForNewCharacter() end
    end)
end

M.addPart({
    name = "dsag-quiet",
    switch = "DsagQuiet",
    title = "Daily Report Journal: closed for a new character",
    tip = "Daily Report Journal opens its window on every new character, on a first day with nothing to report. With this on the journal starts closed for a character who has not opened or closed it yet, and stays as the player leaves it after that. Its key still opens it, and its auto-show after sleep and on death are unchanged. Only active with Daily Report Journal.",
    kind = "compat",
    all = { "2858201402/dailystatisticsandgains" },
    side = "client",
    phase = "boot",
    pins = { "dsag.start", "dsag.visible" },
    check = check,
    install = install,
})
