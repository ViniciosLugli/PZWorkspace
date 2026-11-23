--[[
Buttstroke: an aimed gun-stock hit deals its damage once, wears the gun once, tires only you.

What happens today (Buttstroke / Gun Stock Attack on 42.22.2). Its one handler, on OnHitZombie,
lives in media/lua/server, which multiplayer clients load too (GameLoadingState.java:148), and
OnHitZombie fires on the attacker, on the server and on every nearby client for the same shove
(Hit.java:163, PlayerHitPacket.java:234). The handler asks nothing about which machine it is on,
so each one rolls the gun's condition with its own ZombRand, unsynced, and each judges the shove
by the shover's aim as that machine sees it. A zombie's health in multiplayer is the copy of the
client that runs it (NetworkZombieAI.set, NetworkZombiePacker:243, NetworkZombieSimulator:188),
and the server ends a zombie a hit leaves at 0 (IsoGameCharacter:6279-6288), so the stroke lands
only where those two copies happen to judge it a stroke. It then fires OnWeaponHitCharacter again with
the gun as the weapon, so every hit listener sees a ranged weapon hit during a melee shove:
Ultimate Marksman's special arrows can go off from a crossbow's stock
(UMArcherySpecialArrowEffects.lua), and Shoot Through Barricades can mark the zombie as avoiding
damage, cancelling the real shove through a barricaded window (OnHitZombie fires before the hit,
IsoZombie.java:1379). It never checks for a vehicle; a player reports the game crashing on a
buttstroke from a car seat.

What this part changes. Buttstroke's handler stands down once the world is up. Only the shover's
game judges the stroke, as Buttstroke does (same sandbox values and formulas), and plays the sound
and drains the endurance. Alone, it also takes the health and rolls the wear. In multiplayer it
takes the health off its own copy only when it runs that zombie, and tells the server, which checks
the hit (the shover holds a ranged weapon, the zombie is within reach, the damage is no more than
the setting allows, one stroke per zombie per swing), takes the same health off its own copy, rolls
the wear on its copy of the gun, synced back to its owner, and passes the stroke on: the client that
runs the zombie, when it is not the shover, takes the health off there. No machine fires a second
OnWeaponHitCharacter: the shove already fired its own. Nothing runs for a seated player. Switched
off or failed, Buttstroke runs as it ships.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local S = {}
M.buttstroke = S
S.FILE = "Buttstroke_Lua/Script.lua"
S.NET = "LugliButtstroke"
S.REACH = 3.0
S.SWING_MS = 300
S.DEFAULTS = { Damage = 5.0, EnduranceLost = 0.005, WeaponConditionLost = 1 }

local captured = {}
local lastStroke = {}

function S.option(key)
    local page = SandboxVars and SandboxVars.ButtstrokeOption
    local v = page and page[key]
    if type(v) ~= "number" then return S.DEFAULTS[key] end
    return v
end

local function isGun(item)
    return item ~= nil and instanceof(item, "HandWeapon") and item:isRanged()
end

-- Buttstroke's own test (Script.lua:22-38), plus the vehicle seat.
function S.isStroke(player)
    if not instanceof(player, "IsoPlayer") or player:getVehicle() ~= nil then return false end
    if player:getVariableBoolean("Bob_BayonetAttack") or player:getVariableBoolean("StompAnim") then return false end
    if not (player:isDoShove() and player:isAiming() and player:getVariableBoolean("bShoveAiming")) then return false end
    return isGun(player:getPrimaryHandItem())
end

function S.damage(player)
    return (S.option("Damage") / 100) * player:getStats():get(CharacterStat.ENDURANCE)
end

function S.wear(player, gun, sync)
    local chance = gun:getConditionLowerChance()
        + math.floor(math.floor(player:getPerkLevel(Perks.Maintenance) + (player:getPerkLevel(Perks.Aiming) / 2)) / 2)
    if ZombRand(chance) ~= 0 then return false end
    gun:setCondition(gun:getCondition() - S.option("WeaponConditionLost"))
    if sync then gun:syncItemFields() end
    return true
end

local function tire(player)
    local stats = player:getStats()
    stats:set(CharacterStat.ENDURANCE, math.max(0, stats:get(CharacterStat.ENDURANCE) - S.option("EnduranceLost")))
end

local function sound(player)
    local emitter = player:getEmitter()
    if emitter:isPlaying("Buttstroke_Hit") then return end
    emitter:setVolume(emitter:playSound("Buttstroke_Hit"), 1.5)
end

-- This client runs the zombie: its health is the copy everyone else takes.
local function runsHere(zombie) return not zombie:isRemoteZombie() end

local function onHitZombie(zombie, player)
    if not instanceof(zombie, "IsoZombie") or not S.isStroke(player) then return end
    -- Another player's stroke: only the sound, as Buttstroke plays it on every game nearby.
    if not player:isLocalPlayer() then
        sound(player)
        return
    end
    local damage = S.damage(player)
    if M.isMultiplayerClient() then
        if runsHere(zombie) then zombie:setHealth(zombie:getHealth() - damage) end
        sendClientCommand(player, S.NET, "hit", { id = zombie:getOnlineID(), damage = damage })
    else
        zombie:setHealth(zombie:getHealth() - damage)
        S.wear(player, player:getPrimaryHandItem(), false)
    end
    tire(player)
    sound(player)
end

local function zombieById(id)
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z:getOnlineID() == id then return z end
    end
    return nil
end

-- The server's half: what it applied, or nil when it refused.
function S.serverHit(player, args)
    if player == nil or player:isDead() or type(args) ~= "table" then return nil end
    local damage = tonumber(args.damage)
    if damage == nil or damage < 0 or damage > S.option("Damage") / 100 + 0.0001 then return nil end
    local gun = player:getPrimaryHandItem()
    if not isGun(gun) then return nil end
    local zombie = zombieById(tonumber(args.id))
    if zombie == nil or zombie:isDead() then return nil end
    local dx, dy = zombie:getX() - player:getX(), zombie:getY() - player:getY()
    if dx * dx + dy * dy > S.REACH * S.REACH then return nil end
    -- One swing per player at a time, holding the zombies it already struck, so the table never
    -- grows past the players online.
    local now = getTimestampMs()
    local who = player:getOnlineID()
    local swing = lastStroke[who]
    if swing == nil or now - swing.at >= S.SWING_MS then
        swing = { at = now, hit = {} }
        lastStroke[who] = swing
    end
    if swing.hit[zombie] then return nil end
    swing.hit[zombie] = true
    zombie:setHealth(zombie:getHealth() - damage)
    local worn = S.wear(player, gun, true)
    sendServerCommand(S.NET, "hit", { id = zombie:getOnlineID(), damage = damage, by = player:getOnlineID() })
    return { damage = damage, worn = worn }
end

local function onClientCommand(module, command, player, args)
    if module ~= S.NET or command ~= "hit" then return end
    S.serverHit(player, args)
end

-- A client's half of another player's stroke, as the server passed it on: the health, here, only
-- when this client runs the zombie. The shover already took it if it runs the zombie itself.
function S.clientHit(args)
    if type(args) ~= "table" then return nil end
    local by = getPlayerByOnlineID(tonumber(args.by) or -1)
    if by ~= nil and by:isLocalPlayer() then return nil end
    local zombie = zombieById(tonumber(args.id))
    local damage = tonumber(args.damage)
    if zombie == nil or zombie:isDead() or damage == nil or not runsHere(zombie) then return nil end
    zombie:setHealth(zombie:getHealth() - damage)
    return damage
end

local function onServerCommand(module, command, args)
    if module ~= S.NET or command ~= "hit" then return end
    S.clientHit(args)
end

local function capture(ctx)
    local ev = Events.OnHitZombie
    ctx.wrap(ev, "Add", function(add)
        return function(fn)
            if M.closureFrom(fn, S.FILE) then captured[#captured + 1] = fn end
            return add(fn)
        end
    end)
end

local function standDownStock(ctx)
    if not ctx.enabled() then return end
    while #captured > 0 do
        local fn = table.remove(captured)
        Events.OnHitZombie.Remove(fn)
        ctx.undo(function() Events.OnHitZombie.Add(fn) end)
    end
end

local function install(ctx)
    captured, lastStroke = {}, {}
    capture(ctx)
    local standDown = function() standDownStock(ctx) end
    ctx.at("OnGameStart", standDown)
    ctx.at("OnServerStarted", standDown)
    if M.isDedicatedServer() then
        ctx.on("OnClientCommand", onClientCommand)
    else
        ctx.on("OnHitZombie", onHitZombie)
        if M.isMultiplayerClient() then ctx.on("OnServerCommand", onServerCommand) end
    end
end

M.addPart({
    name = "buttstroke-sides",
    switch = "ButtstrokeSides",
    title = "Buttstroke: one hit, one wear roll, decided by your own game",
    tip = "Buttstroke's code runs on every player's game near a gun-stock hit, so in multiplayer the gun's condition is rolled on each game unsynced, whether the hit lands depends on how each game sees your aim, and every nearby game fires a second fake gun hit, which can set off Ultimate Marksman's special arrows from a crossbow stock or cancel the hit through a barricade. With this on, only your own game decides the stroke and tells the server, which checks it, wears your gun once, synced, and passes the damage to the game that runs the zombie. Nothing runs from a vehicle seat. Buttstroke's own sandbox settings still apply. Only active with Buttstroke.",
    kind = "fix",
    all = { "Buttstroke" },
    side = "both",
    phase = "load",
    pins = { "bstroke.hit", "bstroke.hitreg", "bstroke.options" },
    install = install,
})
