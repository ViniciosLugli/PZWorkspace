--[[
    CarrySound
]]

require "LugliEmergencyLights/Core"
require "LugliEmergencyLights/Items"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Carry sound"

local carried = {}      -- playerIndex -> { emitter, key }
local remote = {}       -- username    -> { emitter }

--- The BAG answer, cached, and the timestamp it expires at. playerIndex -> boolean / ms.
local bagLit = {}
local bagAt = {}
local remoteAt = 0

local function nowMs()
    return getTimestampMs ~= nil and getTimestampMs() or 0
end

--- Is a rate-limited job due, and if so book the next one.
local function due(at)
    local now = nowMs()
    if now < at then return false, at end
    local every = M.scanInterval()
    if type(every) ~= "number" or every < 0 then every = 1.0 end
    return true, now + every * 1000
end

local function burning(item)
    return item ~= nil and M.litInfo(item) ~= nil and not M.isExpired(item)
end

--- True when this character holds something whose family makes a burn sound.
local function holdingBurner(character)
    local item = character:getPrimaryHandItem()
    if not burning(item) then item = character:getSecondaryHandItem() end
    return burning(item) and M.burnSoundFor(M.litInfo(item).family) ~= nil
end

--- MOVE the emitter, never rebuild it.
local function follow(rec, name, x, y, z, square)
    pcall(function() rec.emitter:setPos(x, y, z) end)
    -- Polled rather than handle-cached, as IsoGenerator does it: self-healing across a reload.
    if square ~= nil and not rec.emitter:isPlaying(name) then
        M.loopOn(rec.emitter, name, square)
    end
end

local function start(name, x, y, z, square)
    if square == nil then return nil end
    local emitter = M.emitterAt(math.floor(x), math.floor(y), math.floor(z))
    if emitter == nil then return nil end
    -- emitterAt places at the TILE CENTRE (it adds 0.5); follow() moves to the carrier's exact
    -- position. Creating at one and moving to the other left the source half a tile to one side,
    -- which is audible as a permanent lean to one ear. Snap it before the first frame.
    pcall(function() emitter:setPos(x, y, z) end)
    M.loopOn(emitter, name, square)
    return { emitter = emitter, key = name }
end

local function dropOwn(idx)
    local rec = carried[idx]
    if rec == nil then return end
    carried[idx] = nil
    M.stopEmitter(rec.emitter)
end

local function dropRemote(who)
    local rec = remote[who]
    if rec == nil then return end
    remote[who] = nil
    M.stopEmitter(rec.emitter)
end

--- Is a lit flare somewhere in this player's bags? The expensive question, asked on the interval.
local function carryingBurner(player, idx)
    local run, next_ = due(bagAt[idx] or 0)
    if not run then return bagLit[idx] == true end
    bagAt[idx] = next_

    local found = false
    local ok, items = pcall(function() return M.allCarried(player) end)
    if ok and items ~= nil then
        for i = 1, #items do
            local item = items[i]
            if item ~= nil and burning(item) and M.burnSoundFor(M.litInfo(item).family) ~= nil then
                found = true
                break
            end
        end
    end
    bagLit[idx] = found
    return found
end

--- Which of the two mono entries the local player's own flare wants, or nil.
local function ownSound(player, idx)
    if holdingBurner(player) then return M.SND_FLARE_BURN_HELD end
    if not M.cfg("CarriedFlareSound") then return nil end
    if carryingBurner(player, idx) then return M.SND_FLARE_BURN_CARRIED end
    return nil
end

local function updateOwn(player, idx)
    local name = ownSound(player, idx)
    if name == nil then
        dropOwn(idx)
        return
    end

    local x, y, z = player:getX(), player:getY(), player:getZ()
    local rec = carried[idx]
    if rec ~= nil and rec.key == name then
        follow(rec, name, x, y, z, player:getCurrentSquare())
        return
    end

    dropOwn(idx)
    carried[idx] = start(name, x, y, z, player:getCurrentSquare())
end

local function updateRemote()
    if getOnlinePlayers == nil then return end
    local players = getOnlinePlayers()
    if players == nil then return end

    local seen = {}
    for i = 0, players:size() - 1 do
        local other = players:get(i)
        if other ~= nil and not other:isLocalPlayer() and holdingBurner(other) then
            local who = tostring(other:getUsername())
            seen[who] = true
            local x, y, z = other:getX(), other:getY(), other:getZ()
            if remote[who] ~= nil then
                follow(remote[who], M.SND_FLARE_BURN_REMOTE, x, y, z, other:getCurrentSquare())
            else
                remote[who] = start(M.SND_FLARE_BURN_REMOTE, x, y, z, other:getCurrentSquare())
            end
        end
    end

    local stale = {}
    for who, _ in pairs(remote) do
        if not seen[who] then stale[#stale + 1] = who end
    end
    for i = 1, #stale do dropRemote(stale[i]) end
end

local function tick()
    -- Rate-limited on its own clock: it walks every online player, which is the same order of
    -- cost as the bag walk and none of it can change faster than someone can light a flare.
    if M.isMultiplayer() then
        local run, next_ = due(remoteAt)
        if run then
            remoteAt = next_
            pcall(updateRemote)
        end
    end
    M.forEachLocalPlayer(function(player, idx)
        -- Caught per player so a throw cannot strand a looping emitter, which IsoWorld would
        -- then tick forever at a fixed point. Reported once, not every pass.
        local ok, err = pcall(updateOwn, player, idx)
        if not ok then
            dropOwn(idx)
            M.defect(PART, tostring(err))
        end
    end)
end

function M.dropCarrySounds()
    for idx, _ in pairs(carried) do dropOwn(idx) end
    for who, _ in pairs(remote) do dropRemote(who) end
    carried, remote = {}, {}
    -- The caches go with them. A stale "yes" across a world change would start a hiss for a flare
    -- in the previous world's bag.
    bagLit, bagAt, remoteAt = {}, {}, 0
end

-- EVERY TICK, with the two expensive questions rate-limited inside.
local h = M.addTicker(PART, 0, tick)
M.addTeardown(PART, function() M.dropCarrySounds() end)

if h ~= nil then M.status(PART, true) end
