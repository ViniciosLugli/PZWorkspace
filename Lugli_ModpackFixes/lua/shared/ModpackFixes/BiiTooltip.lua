--[[
Better Item Info and every tooltip mod listed after it, with Guns of Marz active.

Better Item Info draws the item tooltip from its own controller. While Guns of Marz is active it
also puts that controller back in place when a world starts, to keep Guns of Marz from drawing
over it. That reset throws away every tooltip wrapper added by a mod loaded after Better Item
Info: Lazolo's backpack upgrade rows, Seed Season Indicator's season rows, Improvised Silencers'
durability row and any other.

This part keeps the chain as it stood once every mod's Lua had loaded, and puts it back right
after that reset. Every wrapper in it still ends in Better Item Info's controller, so Better Item
Info keeps the layout and Guns of Marz stays under it, as the reset intends.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local BII_RESET_FILE = "BII/Compatibility/GunsOfMarz.lua"

local function fromReset(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, BII_RESET_FILE, 1, true) ~= nil
end

local function install(ctx)
    local tooltip = ISToolTipInv
    if type(tooltip) ~= "table" or type(tooltip.render) ~= "function" then
        error("ISToolTipInv.render is missing")
    end
    if type(EuryTooltipController) ~= "table" or EuryTooltipController.installed ~= true then
        error("Better Item Info's tooltip controller is not installed")
    end
    local chain = tooltip.render
    ctx.on("OnGameStart", function()
        local reset = tooltip.render
        if reset == chain or not fromReset(reset) then return end
        tooltip.render = chain
        if tooltip.render ~= chain then error("ISToolTipInv rejected the chain") end
        ctx.undo(function()
            if tooltip.render == chain then tooltip.render = reset end
        end)
    end)
end

M.addPart({
    name = "bii-tooltip",
    switch = "BiiTooltip",
    title = "Better Item Info: keep other mods' tooltip rows",
    tip = "With Guns of Marz active, Better Item Info resets the item tooltip when a world starts, which hides the rows other mods add, such as backpack upgrades, seed seasons and silencer durability. This keeps them. Only active with Better Item Info and Guns of Marz.",
    kind = "compat",
    all = { "EURY_ITEMINFO", "GunsOfMarz" },
    side = "client",
    phase = "boot",
    pins = { "bii.reset", "bii.install" },
    install = install,
})
