--[[
Zero to Chad: the Hardened panic cap holds on a server too.

What happens today. Zero to Chad caps panic at 100 minus the record's capReduction, but only in the
player's own game (ZTC_Main.lua, from OnPlayerUpdate, which the server never fires for a player:
IsoPlayer.java:2277-2312 on 42.22.2). In multiplayer the server works panic out itself
(BodyDamage.Update returns early on a client, BodyDamage.java:2104-2114) and sends it to the player
every second (NetworkPlayerManager, PlayerStatsPacket). So the server's panic is never capped: the
damage the server works out for a melee hit still takes the full panic penalty (Hit.getHitDamageData,
CombatManager.java:862), and panic still drains sanity there, while the moodle the player sees is
capped.

What this part changes. Every server tick, a player with a cap and without Desensitized has panic
lowered to the cap, and the panic moodle worked out again when it still shows more than the cap
allows, so the next hit the server works out sees the capped moodle. The cap is the one Zero to Chad
recorded at the player's last join or midnight, the same one the player's game uses. In single
player the mod's own cap already runs before the moodles, so this rarely has anything to lower.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- One entry per capped player: the panic ceiling, and the panic moodle level seen at it.
local capped = {}

-- getOnlinePlayers() is empty in single player and getNumActivePlayers() is 0 on a server.
local function eachPlayer(fn)
    if M.isDedicatedServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local player = list:get(i)
            if player ~= nil then fn(player) end
        end
        return
    end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then fn(player) end
    end
end

local function refreshCaps()
    local previous = {}
    for i = 1, #capped do previous[capped[i].player] = capped[i] end
    local list = {}
    eachPlayer(function(player)
        if player:isDead() or player:hasTrait(CharacterTrait.DESENSITIZED) then return end
        local record = ZTC_Common.readData(player)
        local cap = type(record) == "table" and record.capReduction or nil
        if type(cap) ~= "number" or cap <= 0 then return end
        local ceiling = math.max(0, 100 - cap)
        local before = previous[player]
        list[#list + 1] = { player = player, ceiling = ceiling,
            level = before ~= nil and before.ceiling == ceiling and before.level or nil }
    end)
    capped = list
end

local function holdCaps()
    for i = 1, #capped do
        local c = capped[i]
        local stats = c.player:getStats()
        if stats:get(CharacterStat.PANIC) > c.ceiling then
            stats:set(CharacterStat.PANIC, c.ceiling)
            local moodles = c.player:getMoodles()
            if c.level == nil or moodles:getMoodleLevel(MoodleType.PANIC) > c.level then
                moodles:Update()
                c.level = moodles:getMoodleLevel(MoodleType.PANIC)
            end
        end
    end
end

local function install(ctx)
    if type(ZTC_Common) ~= "table" or type(ZTC_Common.readData) ~= "function" then
        error("ZTC_Common.readData is missing")
    end
    capped = {}
    ctx.on("EveryOneMinute", refreshCaps)
    ctx.on("OnTick", holdCaps)
end

M.addPart({
    name = "ztc-panic",
    switch = "ZtcPanic",
    title = "Zero to Chad: the panic cap holds on a server",
    tip = "Zero to Chad lowers your maximum panic only in your own game, but in multiplayer the server works out panic itself, so the hits it settles still take the full panic penalty. The server holds panic to the same cap. Only active with Zero to Chad.",
    kind = "fix",
    all = { "ZeroToChad" },
    side = "server",
    phase = "world",
    pins = { "ztc.count", "ztc.cap", "ztc.clamp" },
    install = install,
})
