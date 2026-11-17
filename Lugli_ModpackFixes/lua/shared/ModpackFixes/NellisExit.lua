--[[
Nellis Air Force Base: a player inside a vehicle interior always has a way out.

What happens today. Nellis' Enter option records where the player came from in the player's mod
data (AC130_TP_Origem) and moves them to an interior built off the map, near x -19000; Exit reads it
back and returns them 3 squares from that spot. Without the record, Exit only says "Não sei de onde
eu vim..." and the room has no other way out. In multiplayer the record is written on the client
only. The server saves its own copy of the player (ServerPlayerDB.serverUpdateNetworkCharacter
takes the server's IsoPlayer on 42.22.2), no packet carries a client's player mod data to it, and a
joining client gets the server's copy, so a player who relogs or rides out a server restart inside
an interior has lost the record and is shut in.

What this part changes. The client copies each new record to the server, which keeps it on its
copy of the player. A player standing in an interior without a record gets the server's copy back,
and if there is none either, a record that lets Exit land on Nellis' spawn point. Nellis' Enter and
Exit are unchanged. Switched off or failed, the record lives on the client only, as Nellis ships.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes
require "ModpackFixes_Nellis"
local N = M.nellis

local NET = "LugliModpackFixes"
local CMD_KEEP = "nellisKeep"
local CMD_ASK = "nellisAsk"
local CMD_ANSWER = "nellisAnswer"
local COORD_LIMIT = 100000
-- A server without this part never answers; after this long the client uses the spawn record.
local ANSWER_WAIT_MS = 30000

local function record(x, y, z) return { x = x, y = y, z = z } end

local function validRecord(t)
    if type(t) ~= "table" then return nil end
    local x, y, z = tonumber(t.x), tonumber(t.y), tonumber(t.z)
    if x == nil or y == nil or z == nil then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    if math.abs(x) > COORD_LIMIT or math.abs(y) > COORD_LIMIT or z < -32 or z > 31 then return nil end
    return record(x, y, z)
end

local function fallbackRecord()
    return record(N.SPAWN.x - N.EXIT_OFFSET, N.SPAWN.y - N.EXIT_OFFSET, N.SPAWN.z)
end

local function playerInterior(player)
    return N.interiorAt(math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ()))
end

-- Server side: the copy that the server saves and hands back on join.
local function onClientCommand(module, command, player, args)
    if module ~= NET or player == nil then return end
    if command == CMD_KEEP then
        local rec = validRecord(args)
        if rec ~= nil then player:getModData()[N.ORIGIN_KEY] = rec end
    elseif command == CMD_ASK then
        local rec = validRecord(player:getModData()[N.ORIGIN_KEY])
        sendServerCommand(player, NET, CMD_ANSWER, rec or {})
    end
end

-- Client side.
local mirrored = nil
local askedAt = nil

local function mirror(player)
    local rec = player:getModData()[N.ORIGIN_KEY]
    if rec == nil or rec == mirrored then return end
    mirrored = rec
    local valid = validRecord(rec)
    if valid ~= nil then sendClientCommand(player, NET, CMD_KEEP, valid) end
end

local function settle(player, rec, fromServer)
    player:getModData()[N.ORIGIN_KEY] = rec
    if fromServer then mirrored = rec end
end

local function resolve(player)
    if player == nil or player:getModData()[N.ORIGIN_KEY] ~= nil or playerInterior(player) == nil then
        askedAt = nil
        return
    end
    if not M.isMultiplayerClient() then
        settle(player, fallbackRecord(), false)
        return
    end
    local now = getTimestampMs()
    if askedAt == nil then
        askedAt = now
        sendClientCommand(player, NET, CMD_ASK, {})
    elseif now - askedAt >= ANSWER_WAIT_MS then
        askedAt = nil
        settle(player, fallbackRecord(), false)
    end
end

local function onServerCommand(module, command, args)
    if module ~= NET or command ~= CMD_ANSWER then return end
    askedAt = nil
    local player = getPlayer()
    if player == nil or player:getModData()[N.ORIGIN_KEY] ~= nil then return end
    local rec = validRecord(args)
    if rec ~= nil then settle(player, rec, true) else settle(player, fallbackRecord(), false) end
end

local function install(ctx)
    if M.isDedicatedServer() then
        ctx.on("OnClientCommand", onClientCommand)
        return
    end
    if M.isMultiplayerClient() then
        ctx.on("OnPlayerUpdate", function(player)
            if player == getPlayer() then mirror(player) end
        end)
        ctx.on("OnServerCommand", onServerCommand)
    end
    ctx.on("EveryOneMinute", function() resolve(getPlayer()) end)
end

M.addPart({
    name = "nellis-exit",
    switch = "NellisExit",
    title = "Nellis Air Force Base: no one is shut in a vehicle interior",
    tip = "Nellis remembers where you entered an aircraft or vehicle interior only in your own game, so in multiplayer a relog or a server restart inside one leaves Exit with nowhere to go and no way out. The server keeps that spot too and gives it back; with none known, Exit takes you to Nellis' spawn point. Only active with Nellis Air Force Base.",
    kind = "fix",
    all = { "NellisAFB" },
    side = "both",
    phase = "world",
    pins = { "nellis.portals", "nellis.origin", "nellis.enter", "nellis.exit", "nellis.spawn" },
    install = install,
})
