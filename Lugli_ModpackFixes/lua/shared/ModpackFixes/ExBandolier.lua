--[[
Explosives: a full grenade bandolier holds its grenades on a dedicated server too.

What happens today. Explosives spawns its full grenade bandolier (Explosives.GrenadeBandolierFull)
on zombies in its two grenadier army outfits and in its loot tables, and turns each one into an
empty bandolier plus three M67 grenades and up to two random others from an OnFillContainer handler
in client Lua (42/media/lua/client/InventorySwap.lua). Containers are filled, and that event fired,
only where the game is not a multiplayer client (ItemPickerJava.java:559-653 on 42.22.2), which in
multiplayer is the dedicated server, and a dedicated server never loads client Lua. So on a server
every one of those zombies and containers keeps the full bandolier with no grenades: its weight and
name say full, and the grenades never exist.

What this part changes. On the side that fills containers, the same swap runs from shared Lua:
each full bandolier in a container being filled becomes the empty bandolier, three M67 grenades and
the same two 50% rolls as the mod's own handler, and on a server the removal is sent to the clients,
which already show the worn bandolier on the corpse. In single player the mod's handler and this one
both run, and whichever runs first leaves no full bandolier for the other.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local FULL = "GrenadeBandolierFull"

local function onFill(roomName, containerType, container)
    if not container then return end
    if tostring(container):find("ItemPickerContainer") then return end
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if item:getType() == FULL then
            container:Remove(item)
            -- The fill is answered with the container's items as additions only
            -- (RequestItemsForContainerPacket, AddInventoryItemToContainerPacket), so a client that
            -- already shows the worn bandolier keeps it unless the removal is sent.
            if M.isDedicatedServer() then sendRemoveItemFromContainer(container, item) end
            container:AddItem("Explosives.GrenadeBandolier")
            container:AddItem("Explosives.M67Grenade")
            container:AddItem("Explosives.M67Grenade")
            container:AddItem("Explosives.M67Grenade")
            for extra = 1, 2 do
                if ZombRand(100) < 50 then
                    local roll = ZombRand(100)
                    if roll < 50 then
                        container:AddItem("Explosives.M26Grenade")
                    elseif roll < 80 then
                        container:AddItem("Explosives.Mk2Grenade")
                    else
                        container:AddItem("Explosives.M14TH3Grenade")
                    end
                end
            end
        end
    end
end

local function install(ctx)
    ctx.on("OnFillContainer", onFill)
end

M.addPart({
    name = "ex-bandolier",
    switch = "ExBandolier",
    title = "Explosives: grenade bandoliers hold their grenades in multiplayer",
    tip = "Explosives turns a full grenade bandolier into an empty one plus its grenades only in client code, and on a dedicated server containers and zombies are filled by the server, so in multiplayer the bandolier says full and holds nothing. This does the same swap on the server. Only active with Explosives.",
    kind = "fix",
    all = { "Explosives" },
    side = "server",
    phase = "boot",
    pins = { "ex.swap" },
    install = install,
})
