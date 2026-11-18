--[[
Item Details Panel: its panel replaces the vanilla item tooltip by default.

What happens today. Item Details Panel draws its panel next to the vanilla tooltip, so every item
shows two boxes with much of the same information. Its Hide vanilla tooltip option (a mod option,
off by default) makes the panel take the tooltip's place.

What this part changes. The option's default becomes on. The game reads each player's saved mod
options after every mod has loaded (PZAPI.ModOptions:load, when the main menu or a world's pause
menu is built), so a player who already chose a value keeps it; only a player with no saved value
starts with the panel alone. Item Details Panel's own Reset puts the new default back. The other
Item Details Panel parts of this mod carry the rows other mods draw into the vanilla tooltip over
to the panel, so hiding it loses nothing.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local OPTION = "HideVanillaTooltip"

local function option()
    local options = ItemDetailsPanel.options
    if type(options) ~= "table" or type(options.getOption) ~= "function" then return nil end
    return options:getOption(OPTION)
end

local function check()
    local why = K.check()
    if why ~= nil then return why end
    local o = option()
    if type(o) ~= "table" or o.type ~= "tickbox" then return "Item Details Panel has no " .. OPTION .. " tick box" end
    if type(ItemDetailsPanel.profileDefaults) ~= "table" then return "Item Details Panel has no profile defaults" end
    if type(ItemDetailsPanel.options.modOptionsID) ~= "string" then return "Item Details Panel's options have no id" end
    return nil
end

-- The player's saved line for the option, read the way PZAPI.ModOptions:load reads it.
local function savedByPlayer()
    local prefix = "tickbox|" .. tostring(ItemDetailsPanel.options.modOptionsID) .. "|" .. OPTION .. "|"
    local okOpen, reader = pcall(getFileReader, "ModOptions.ini", false)
    if not okOpen or reader == nil then return false end
    local found = false
    local okRead = pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            if string.sub(line, 1, #prefix) == prefix then
                local v = string.sub(line, #prefix + 1)
                if v == "true" or v == "false" then found = true end
            end
        end
    end)
    pcall(function() reader:close() end)
    return okRead and found
end

local function bump()
    ItemDetailsPanel.configRevision = (ItemDetailsPanel.configRevision or 0) + 1
end

local function install(ctx)
    local o = option()
    local defaults = ItemDetailsPanel.profileDefaults
    local value, default = o.value, defaults[OPTION]
    -- Whether the game has read the saved options yet or not, a saved choice is never touched.
    if not savedByPlayer() then o.value = true end
    defaults[OPTION] = true
    bump()
    local function restore()
        if defaults[OPTION] == true then defaults[OPTION] = default end
        if o.value == true and not savedByPlayer() then o:setValue(value) end
        bump()
    end
    ctx.undo(restore)
    -- A world's sandbox can turn the part off; that is only known once the world starts.
    ctx.at("OnGameStart", function()
        if not ctx.enabled() then restore() end
    end)
end

M.addPart({
    name = "idp-hide",
    switch = "IdpHide",
    title = "Item Details Panel: replace the vanilla tooltip by default",
    tip = "Item Details Panel shows its panel beside the vanilla item tooltip. With this on, its Hide vanilla tooltip option starts on, so the panel takes the tooltip's place. A player who already set that option keeps their choice. Only active with Item Details Panel.",
    kind = "compat",
    all = { "ItemDetailsPanel" },
    side = "client",
    phase = "boot",
    pins = { "idp.hide", "idp.defaults" },
    check = check,
    install = install,
})
