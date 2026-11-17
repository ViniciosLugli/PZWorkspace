--[[
Nellis Air Force Base: the server keeps its vehicle interiors powered.

What happens today. Each of Nellis' 11 vehicle interiors holds one generator from the map (vanilla's
MOGenerator.lua turns the tile into a real generator), and Nellis' client script tops up to full
fuel and switches on every generator inside an interior, every in-game minute. In multiplayer that
runs on every client that has an interior loaded: each sends all of them to the server every
minute, since setFuel syncs on every call (IsoGenerator.java:513-522 on 42.22.2), and the server
takes any client's generator state as it comes (GameServer.receiveSyncIsoObject). The power holds
only while some client happens to run the script. And since any generator counts, a player can
carry an empty one in, wait a minute and take it out full, as often as they like.

What this part changes. Nellis' client keep-alive stands down once the world is up, and the side
that owns the world (the server, or the game in single player) keeps only each interior's own
generator full and on, writing only what changed. The interior's own generator is the one standing
in it when its chunk first loads with this part: MapObjects.loadGridSquare runs after MOGenerator
has made the map's generator, in the same main-thread call that makes the chunk's squares
reachable (ServerMap.ServerCell.Load2, IsoChunkMap.processAllLoadGridSquare), so no player and no
minute tick acts first. It is tagged with its interior in its object modData, and the world's
global ModData records the interior as "own"; an interior seen fully loaded with none is "none".
The moment the own generator leaves its square by any path (taking it, a moveables pickup, which
copies object modData into the item), OnObjectAboutToBeRemoved turns the record to "none", so a
copied tag is worthless: a generator placed there later, the map's own put back included, is never
filled. Switched off or failed, Nellis' own keep-alive runs as it ships.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes
require "ModpackFixes_Nellis"
local N = M.nellis

local WORLD_KEY, TAG = "LugliModpackFixes_Nellis", "LugliNellisOwn"
-- MapObjects keeps one callback per sprite and priority, so this priority must stay unused for these sprites.
local LOAD_PRIORITY = 3
local SPRITE_PREFIX, SPRITE_COUNT = "appliances_misc_01_", 16

local captured = {}

local function interiorKey(r) return r.x1 .. "," .. r.y1 .. "," .. r.z end

local function generatorInterior(obj)
    if not instanceof(obj, "IsoGenerator") then return nil end
    local sq = obj:getSquare()
    local r = sq ~= nil and N.interiorAt(sq:getX(), sq:getY(), sq:getZ()) or nil
    return r ~= nil and interiorKey(r) or nil
end

local function adoptAtLoad(obj)
    local key = generatorInterior(obj)
    if key == nil then return end
    local record = ModData.getOrCreate(WORLD_KEY)
    if record[key] ~= nil then return end
    obj:getModData()[TAG] = key
    record[key] = "own"
end

local function revokeOnRemove(obj)
    local key = generatorInterior(obj)
    if key == nil or obj:getModData()[TAG] ~= key then return end
    local record = ModData.getOrCreate(WORLD_KEY)
    if record[key] == "own" then record[key] = "none" end
end

local function keepPowered()
    local record = ModData.getOrCreate(WORLD_KEY)
    for i = 1, #N.INTERIORS do
        local r = N.INTERIORS[i]
        local key = interiorKey(r)
        local own = record[key] == "own"
        local loaded = true
        for x = r.x1, r.x2 do
            for y = r.y1, r.y2 do
                local sq = getSquare(x, y, r.z)
                if sq == nil then
                    loaded = false
                elseif own then
                    local gen = sq:getGenerator()
                    if gen ~= nil and gen:getModData()[TAG] == key then
                        if gen:getFuel() < N.MAX_FUEL then gen:setFuel(N.MAX_FUEL) end
                        if not gen:isActivated() then gen:setActivated(true) end
                    end
                end
            end
        end
        if loaded and record[key] == nil then record[key] = "none" end
    end
end

local function captureFrom(ctx, eventName)
    local ev = Events[eventName]
    ctx.wrap(ev, "Add", function(add)
        return function(fn)
            if N.fromNellis(fn) then captured[#captured + 1] = { ev = ev, fn = fn } end
            return add(fn)
        end
    end)
end

local function standDownNellis(ctx)
    if not ctx.enabled() then return end
    for i = 1, #captured do
        local c = captured[i]
        c.ev.Remove(c.fn)
        ctx.undo(function() c.ev.Add(c.fn) end)
    end
end

local function install(ctx)
    captured = {}
    if not M.isDedicatedServer() then
        captureFrom(ctx, "EveryOneMinute")
        captureFrom(ctx, "OnInitWorld")
        ctx.at("OnGameStart", function() standDownNellis(ctx) end)
    end
    if not M.isMultiplayerClient() then
        -- MapObjects has no remove: the guard leaves it inert once the part is off or undone.
        local adopt = ctx.guard(adoptAtLoad)
        for i = 0, SPRITE_COUNT - 1 do
            MapObjects.OnLoadWithSprite(SPRITE_PREFIX .. i, adopt, LOAD_PRIORITY)
        end
        ctx.on("OnObjectAboutToBeRemoved", revokeOnRemove)
        ctx.on("EveryOneMinute", keepPowered)
    end
end

M.addPart({
    name = "nellis-power",
    switch = "NellisPower",
    title = "Nellis Air Force Base: the server powers the vehicle interiors",
    tip = "Nellis keeps every generator inside its aircraft and vehicle interiors fueled and running from every player's game, so in multiplayer each client keeps sending them to the server, and any generator carried in comes out full. The server does it instead, only for the generator each interior came with, and only when something changed. Only active with Nellis Air Force Base.",
    kind = "fix",
    all = { "NellisAFB" },
    side = "both",
    phase = "load",
    pins = { "nellis.portals", "nellis.power", "nellis.powerreg" },
    install = install,
})
