--[[
Picking Meister's Grab and Unpack Contents menu with Better Item Transfer.

Picking Meister puts its "Grab Contents" / "Unpack Contents" entry in front of the vanilla
"Place Item" entry, which it finds by that label, and in front of "More" when "Place Item" is
missing; with neither it adds nothing. Better Item Transfer renames "Place Item" to "Place" before
any mod sees the menu, so the entry lands in front of "More" or is not offered at all.

This part points Picking Meister at the label Better Item Transfer gives the entry. Picking
Meister reads that label from its own global table on every menu, so nothing is wrapped.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local function install(ctx)
    local p4 = P4PickingMeister
    if type(p4) ~= "table" or type(p4.OnFillInventoryObjectContextMenu_Grab) ~= "function" then
        error("Picking Meister's menu handler is missing")
    end
    local stock, renamed = getText("ContextMenu_PlaceItemOnGround"), getText("IGUI_Place")
    if p4.Menu_Vanilla_Place ~= stock then
        error("Picking Meister no longer anchors on the Place Item label")
    end
    p4.Menu_Vanilla_Place = renamed
    if p4.Menu_Vanilla_Place ~= renamed then error("Picking Meister's table rejected the change") end
    ctx.undo(function()
        if p4.Menu_Vanilla_Place == renamed then p4.Menu_Vanilla_Place = stock end
    end)
end

M.addPart({
    name = "p4-place",
    switch = "P4Place",
    title = "Picking Meister: Grab Contents next to Place",
    tip = "Better Item Transfer renames Place Item to Place, so Picking Meister's Grab and Unpack Contents entry moves to the bottom of the menu or is not offered. This puts it back beside Drop and Place. Only active with both mods.",
    kind = "compat",
    all = { "BetterItemTransfer", "P4PickingMeister" },
    side = "client",
    phase = "world",
    pins = { "p4.label", "p4.anchor", "bit.place" },
    install = install,
})
