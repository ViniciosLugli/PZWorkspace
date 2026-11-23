--[[
Better Push: the domino chain falls the way the shove went, once per shove, for every player.

What happens today (Better Push 1.4 on 42.22.2). The client handler rolls on every
OnWeaponHitCharacter whose weapon is BareHands, and the engine passes BareHands for every shove,
stomp and grapple (IsoLivingCharacter.getAttackingWeapon), so stomping a downed zombie rolls too.
The event also fires on the server and on every nearby client for a remote attacker
(Hit.java:163), and the handler never asks whose shove it was, so each nearby client rolls and
sends its own chain. The chain takes the nearest zombie to the last link in any direction, back
toward the player included: the push direction and the "Domino Link Width" option are computed and
never used. Each link is knocked down through five setters that disagree (setHitReaction("Shove"),
knockDown(true), setKnockedDown, setStaggerBack, setFallOnFront(true)), so a zombie facing the
player falls the wrong way. The delay is 20 OnTicks, so it depends on the frame rate. In
multiplayer the server calls getZombieByOnlineID, which exists nowhere, so every chain throws
there; and a knockdown set only on the server could not show anyway: the owner client simulates a
zombie (NetworkZombieManager.updateAuth), ZombiePacket carries no knockedDown, and a remote copy
starts its fall only from a local bKnockedDown, which is why vanilla relays a shove to the server
and to every nearby client (PlayerHitPacket.java:233-236).

What this part changes. Better Push's own handlers stand down once the world is up. The attacking
client alone rolls, once per shove (never a stomp, a grapple or a seated player), with Better
Push's own sandbox values. The chain runs ahead of the shove: each link within Link Distance of the
one before, within Link Width of the push line, on the same floor, standing. Each zombie falls
from the side the push came from: knockDown(true) from behind, knockDown(false) then FRONT from the
front (a bare knockDown(false) leaves the attack position null, which no staggerback node matches,
and the zombie freezes in its pose). Links fall 0.35 s apart by the clock. In multiplayer the
server checks the chain (alive, within reach of the shover, no longer than the shover's strength
allows, one chain per half second) and sends it to every client, and each knocks its own copy
down at the same pace, as a vanilla shove is applied on every machine. Switched off or failed,
Better Push runs as it ships.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local B = {}
M.betterPush = B
B.FILES = { "BetterPush_Client.lua", "BetterPush_Server.lua" }
B.EVENTS = { "OnWeaponHitCharacter", "OnTick", "OnClientCommand" }
B.NET = "LugliBetterPush"
B.LINK_MS = 350
-- One shove can hit several zombies; their hits arrive within the same swing.
B.SWING_MS = 400
B.SERVER_GAP_MS = 500
B.REACH_SLACK = 2.5
-- A link that walked or was pushed further than this from where the chain found it is skipped.
B.DRIFT = 1.0
B.DEFAULTS = {
    MinStrengthLevel = 5, MaxStrengthLevel = 10, MinChance = 5, MaxChance = 30,
    BetterPushMinZombies = 1, BetterPushMaxZombies = 4,
    BetterPushLineDistance = 0.8, BetterPushLineWidth = 0.8,
}

local captured = {}
local queue = {}
local queued = {}
local lastSwing = {}
local lastChain = {}

local function option(key)
    local page = SandboxVars and SandboxVars.BetterPush
    local v = page and page[key]
    if type(v) ~= "number" then return B.DEFAULTS[key] end
    return v
end

local function ordered(a, b)
    if a > b then return b, a end
    return a, b
end

function B.settings()
    local s = {}
    s.minStr, s.maxStr = ordered(option("MinStrengthLevel"), option("MaxStrengthLevel"))
    s.minChance, s.maxChance = ordered(option("MinChance"), option("MaxChance"))
    s.minCount, s.maxCount = ordered(math.max(1, math.floor(option("BetterPushMinZombies"))),
        math.max(1, math.floor(option("BetterPushMaxZombies"))))
    s.dist = math.max(0.1, option("BetterPushLineDistance"))
    s.width = math.max(0.1, option("BetterPushLineWidth"))
    return s
end

local function scaled(s, str, lo, hi)
    if str >= s.maxStr or s.minStr == s.maxStr then return hi end
    local t = (str - s.minStr) / (s.maxStr - s.minStr)
    return math.floor(lo + t * (hi - lo) + 0.5)
end

function B.chance(s, str)
    if str < s.minStr then return 0 end
    return scaled(s, str, s.minChance, s.maxChance)
end

function B.count(s, str)
    if str < s.minStr then return s.minCount end
    return scaled(s, str, s.minCount, s.maxCount)
end

function B.standing(z)
    if z == nil or z:isDead() or z:getHealth() <= 0 then return false end
    if z:isOnFloor() or z:isKnockedDown() or z:isCrawling() then return false end
    local reaction = z:getHitReaction()
    return reaction == nil or reaction == ""
end

-- Pushed the way it faces means pushed from behind.
function B.fromBehind(z, ux, uy)
    local f = z:getForwardDirection()
    return f:getX() * ux + f:getY() * uy > 0
end

function B.chain(player, shoved, count, s)
    local sx, sy = shoved:getX(), shoved:getY()
    local dx, dy = sx - player:getX(), sy - player:getY()
    local len = math.sqrt(dx * dx + dy * dy)
    local out = {}
    if len < 0.1 then return out, 0, 0 end
    local ux, uy = dx / len, dy / len
    local level = math.floor(shoved:getZ())
    local list = shoved:getCell():getZombieList()
    local used = { [shoved] = true }
    local cx, cy = sx, sy
    for _ = 1, count do
        local best, bestDist = nil, s.dist
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if not used[z] then
                local zx, zy = z:getX() - cx, z:getY() - cy
                if math.abs(zx) < bestDist and math.abs(zy) < bestDist and zx * ux + zy * uy > 0
                    and math.floor(z:getZ()) == level then
                    local d = math.sqrt(zx * zx + zy * zy)
                    local lateral = math.abs((z:getX() - sx) * uy - (z:getY() - sy) * ux)
                    if d < bestDist and lateral <= s.width and B.standing(z) then
                        best, bestDist = z, d
                    end
                end
            end
        end
        if best == nil then break end
        out[#out + 1] = best
        used[best] = true
        cx, cy = best:getX(), best:getY()
    end
    return out, ux, uy
end

function B.knock(z, fromBehind)
    if not B.standing(z) then return false end
    if fromBehind then
        z:knockDown(true)
    else
        z:knockDown(false)
        z:setPlayerAttackPosition("FRONT")
    end
    return true
end

-- links[i] = { zombie, behind, step }: step is its place in the chain, so a link a client does not
-- have keeps the pace of the rest.
function B.schedule(links, now)
    for i = 1, #links do
        local l = links[i]
        local z = l.zombie
        if not queued[z] then
            queued[z] = true
            queue[#queue + 1] = { zombie = z, behind = l.behind, at = now + l.step * B.LINK_MS,
                x = z:getX(), y = z:getY() }
        end
    end
end

function B.pending()
    return #queue
end

local function tick()
    if #queue == 0 then return end
    local now = getTimestampMs()
    local i = 1
    while i <= #queue do
        local e = queue[i]
        if now >= e.at then
            table.remove(queue, i)
            queued[e.zombie] = nil
            local z = e.zombie
            local mx, my = z:getX() - e.x, z:getY() - e.y
            if mx * mx + my * my <= B.DRIFT * B.DRIFT then B.knock(z, e.behind) end
        else
            i = i + 1
        end
    end
end

local function zombiesById(ids)
    local want, found = {}, {}
    for i = 1, #ids do want[ids[i]] = true end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local id = z:getOnlineID()
        if want[id] then found[id] = z end
    end
    return found
end

local function onHit(attacker, target, weapon)
    if not instanceof(attacker, "IsoPlayer") or not instanceof(target, "IsoZombie") then return end
    if not attacker:isLocalPlayer() or not attacker:isShoving() or attacker:getVehicle() ~= nil then return end
    -- Buttstroke fires this event again with the gun; the shove's own hit carries BareHands.
    if weapon == nil or weapon:getType() ~= "BareHands" or target:isDead() then return end
    local now = getTimestampMs()
    local last = lastSwing[attacker]
    if last ~= nil and now - last < B.SWING_MS then return end
    lastSwing[attacker] = now
    local s = B.settings()
    local str = attacker:getPerkLevel(Perks.Strength)
    local chance = B.chance(s, str)
    if chance <= 0 or ZombRand(100) >= chance then return end
    local chain, ux, uy = B.chain(attacker, target, B.count(s, str), s)
    if #chain == 0 then return end
    if M.isMultiplayerClient() then
        local ids, behind = {}, {}
        for i = 1, #chain do
            ids[i] = chain[i]:getOnlineID()
            behind[i] = B.fromBehind(chain[i], ux, uy)
        end
        sendClientCommand(attacker, B.NET, "chain", { ids = ids, behind = behind })
        return
    end
    local links = {}
    for i = 1, #chain do
        links[i] = { zombie = chain[i], behind = B.fromBehind(chain[i], ux, uy), step = i }
    end
    B.schedule(links, now)
end

function B.serverChain(player, args)
    if player == nil or player:isDead() or type(args) ~= "table" or type(args.ids) ~= "table" then return nil end
    local behind = type(args.behind) == "table" and args.behind or {}
    local now = getTimestampMs()
    -- Keyed by online id, so a player who left holds nothing alive.
    local last = lastChain[player:getOnlineID()]
    if last ~= nil and now - last < B.SERVER_GAP_MS then return nil end
    local s = B.settings()
    local count = B.count(s, player:getPerkLevel(Perks.Strength))
    if #args.ids == 0 or #args.ids > count then return nil end
    local reach = count * s.dist + B.REACH_SLACK
    local found = zombiesById(args.ids)
    local px, py = player:getX(), player:getY()
    local out = { ids = {}, behind = {}, steps = {} }
    for i = 1, #args.ids do
        local z = found[args.ids[i]]
        if z ~= nil and not z:isDead() then
            local dx, dy = z:getX() - px, z:getY() - py
            if dx * dx + dy * dy <= reach * reach then
                local n = #out.ids + 1
                out.ids[n], out.behind[n], out.steps[n] = args.ids[i], behind[i] == true, i
            end
        end
    end
    if #out.ids == 0 then return nil end
    lastChain[player:getOnlineID()] = now
    return out
end

local function onClientCommand(module, command, player, args)
    if module ~= B.NET or command ~= "chain" then return end
    local out = B.serverChain(player, args)
    if out ~= nil then sendServerCommand(B.NET, "chain", out) end
end

function B.clientChain(args)
    if type(args) ~= "table" or type(args.ids) ~= "table" then return end
    local found = zombiesById(args.ids)
    local links = {}
    for i = 1, #args.ids do
        local z = found[args.ids[i]]
        if z ~= nil then
            local step = type(args.steps) == "table" and tonumber(args.steps[i]) or i
            links[#links + 1] = { zombie = z, behind = type(args.behind) == "table" and args.behind[i] == true, step = step }
        end
    end
    B.schedule(links, getTimestampMs())
end

local function onServerCommand(module, command, args)
    if module ~= B.NET or command ~= "chain" then return end
    B.clientChain(args)
end

local function fromBetterPush(fn)
    for i = 1, #B.FILES do
        if M.closureFrom(fn, B.FILES[i]) then return true end
    end
    return false
end

local function capture(ctx, eventName)
    local ev = Events[eventName]
    ctx.wrap(ev, "Add", function(add)
        return function(fn)
            if fromBetterPush(fn) then captured[#captured + 1] = { ev = ev, fn = fn } end
            return add(fn)
        end
    end)
end

local function standDownStock(ctx)
    if not ctx.enabled() then return end
    while #captured > 0 do
        local c = table.remove(captured)
        c.ev.Remove(c.fn)
        ctx.undo(function() c.ev.Add(c.fn) end)
    end
end

local function install(ctx)
    captured, queue, queued, lastSwing, lastChain = {}, {}, {}, {}, {}
    for i = 1, #B.EVENTS do capture(ctx, B.EVENTS[i]) end
    local standDown = function() standDownStock(ctx) end
    ctx.at("OnGameStart", standDown)
    ctx.at("OnServerStarted", standDown)
    if not M.isDedicatedServer() then
        ctx.on("OnWeaponHitCharacter", onHit)
        ctx.on("OnTick", tick)
        if M.isMultiplayerClient() then ctx.on("OnServerCommand", onServerCommand) end
    end
    if M.isDedicatedServer() then ctx.on("OnClientCommand", onClientCommand) end
end

M.addPart({
    name = "better-push",
    switch = "BetterPush",
    title = "Better Push: the domino falls the way you pushed, in multiplayer too",
    tip = "Better Push's chain rolls on stomps and grapples, picks zombies in any direction, ignores its Link Width option, drops zombies facing you the wrong way, rolls once on every nearby player's game, and never happens in multiplayer (its server code calls a function the game does not have). With this on, only your own shove rolls, the chain runs ahead of the push within Link Distance and Link Width, each zombie falls from the side it was pushed, 0.35 s apart, and in multiplayer the server checks the chain and every player sees it fall. Better Push's own sandbox settings still apply. Only active with Better Push.",
    kind = "fix",
    all = { "BetterPush" },
    side = "both",
    phase = "load",
    pins = { "bpush.hit", "bpush.hitreg", "bpush.tickreg", "bpush.server", "bpush.servertick", "bpush.options" },
    install = install,
})
