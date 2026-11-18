--[[
Vanilla tile properties lost under mods that re-declare vanilla tilesets.

What happens today. A mod tile file that names a vanilla tileset replaces each of its sprites with
a new one built only from the mod's copy, so whatever vanilla gave those sprites and the copy does
not repeat is gone in the whole world, not only on the mod's map:
  - More Damaged Objects: three street lights (lighting_outdoor_01_1-3) never light, because the
    StopCar it adds turns them into plain obstacles; the lamp on a pillar (carpentry_02_59-62)
    loses its light and switch, crafted ladders their ladder keys, damaged fences their StopCar,
    pole and chain-link fences their thump sound, three gates get the wrong low-fence type, hedges
    lose pickup and their bush keys, and erosion trees under snow are not trees.
  - Raven Creek: road signs lose scrap materials and animal tying, and the town signs share one
    group with the wrong facings, so none of them can be picked up as a two-tile sign.

What this part changes. When the tile definitions have loaded, every vanilla key such a copy lost
or changed is put back, from data generated out of the vanilla files (ModpackFixes_Tiles.lua), with the sign groups rebuilt the way the engine builds them. A key is
only written while the sprite still holds what the mod gave it, so a mod update, or another mod
that already fixed it, is left alone. What the mod adds (its car damage, its own damaged sprites)
is kept. Wind sway lives in a Java field and cannot be restored from Lua.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Tiles"
local M = LugliModpackFixes

local function tileMods()
    local ids = {}
    for id in pairs(M.tiles or {}) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

local journal = {}

local function restore()
    for i = #journal, 1, -1 do
        journal[i]()
    end
    journal = {}
end

local function apply(manager)
    journal = {}
    local map = manager:getNamedMap()
    local n = { written = 0, same = 0, other = 0, missing = 0, grids = 0 }
    local function find(name)
        local spr = map:get(name)
        if spr == nil then n.missing = n.missing + 1 end
        return spr
    end
    for _, modId in ipairs(tileMods()) do
        local data = M.tiles[modId]
        if M.isModActive(modId) then
            for i = 1, #data.props do
                local row = data.props[i]
                local spr = find(row[1])
                if spr ~= nil then
                    local props, key, want, stale = spr:getProperties(), row[2], row[3], row[4]
                    local cur = props:get(key)
                    if cur == want then
                        n.same = n.same + 1
                    elseif cur == stale then
                        props:set(key, want)
                        props:CreateKeySet()
                        journal[#journal + 1] = function()
                            if stale == nil then props:unset(key) else props:set(key, stale) end
                            props:CreateKeySet()
                        end
                        if props:get(key) ~= want then error(row[1] .. " did not take " .. key .. "=" .. want) end
                        n.written = n.written + 1
                    else
                        n.other = n.other + 1
                    end
                end
            end
            for i = 1, #data.flags do
                local row = data.flags[i]
                local flag = IsoFlagType[row[2]]
                if flag == nil then error("no flag " .. row[2]) end
                local spr = find(row[1])
                if spr ~= nil then
                    local props = spr:getProperties()
                    if props:has(flag) then
                        n.same = n.same + 1
                    else
                        props:set(flag)
                        journal[#journal + 1] = function() props:unset(flag) end
                        if not props:has(flag) then error(row[1] .. " did not take flag " .. row[2]) end
                        n.written = n.written + 1
                    end
                end
            end
            for i = 1, #data.types do
                local row = data.types[i]
                local want, stale = IsoObjectType[row[2]], IsoObjectType[row[3]]
                if want == nil or stale == nil then error("no tile type " .. row[2] .. "/" .. row[3]) end
                local spr = find(row[1])
                if spr ~= nil then
                    local cur = spr:getTileType()
                    if cur == want then
                        n.same = n.same + 1
                    elseif cur == stale then
                        spr:setTileType(want)
                        journal[#journal + 1] = function() spr:setTileType(stale) end
                        if spr:getTileType() ~= want then error(row[1] .. " did not take type " .. row[2]) end
                        n.written = n.written + 1
                    else
                        n.other = n.other + 1
                    end
                end
            end
            for i = 1, #data.grids do
                local row = data.grids[i]
                local members, free = {}, true
                for c = 4, #row do
                    local spr = find(row[c][4])
                    if spr == nil then
                        free = false
                    else
                        members[#members + 1] = spr
                        if spr:getSpriteGrid() ~= nil then free = false end
                    end
                end
                if free then
                    local grid = IsoSpriteGrid.new(row[1], row[2], row[3])
                    for c = 4, #row do
                        grid:setSprite(row[c][1], row[c][2], row[c][3], members[c - 3])
                    end
                    if not grid:validate() then error("sign grid " .. row[4][4] .. " does not validate") end
                    for m = 1, #members do
                        local spr = members[m]
                        spr:setSpriteGrid(grid)
                        journal[#journal + 1] = function() spr:setSpriteGrid(nil) end
                    end
                    n.grids = n.grids + 1
                else
                    n.other = n.other + 1
                end
            end
        end
    end
    M.log(string.format("tile-props: %d vanilla keys restored and %d sprite grids rebuilt; %d already vanilla, %d changed by another mod, %d sprites absent",
        n.written, n.grids, n.same, n.other, n.missing))
end

local function install(ctx)
    if type(M.tiles) ~= "table" then error("ModpackFixes_Tiles.lua did not load") end
    ctx.undo(restore)
    ctx.on("OnLoadedTileDefinitions", apply)
end

M.addPart({
    name = "tile-props",
    switch = "TileProps",
    title = "Vanilla tile properties under tile mods",
    tip = "More Damaged Objects and Raven Creek replace whole vanilla tilesets with older copies, so some street lights stop lighting, hedges cannot be picked up, ladders, fences and signs lose properties, and town signs lose their two-tile pickup. This puts every lost vanilla property back when the tiles load, and keeps what those mods add.",
    kind = "fix",
    any = tileMods(),
    side = "both",
    phase = "boot",
    install = install,
})
