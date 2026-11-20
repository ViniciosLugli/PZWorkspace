--[[
Zero to Chad: in multiplayer the server's kill record stays the server's.

What happens today. Zero to Chad keeps its count on the server, in the player's mod data
(ZeroToChad: serverKills, reportedKills, capReduction and the rest), and reads it back at every
kill, every in-game minute and every midnight (ZTC_Server.lua). But a multiplayer client sends its
whole copy of the player's mod data to the server each time the hotbar refreshes, which vanilla
does on every change of clothes (ISHotbar:savePosition), and when a recipe is starred or an item
marked unwanted. The server takes that copy in place of its own (ObjectModDataPacket.parse, and
KahluaTableImpl.load wipes first, on 42.22.2), and the client's copy is the one it got at login,
which Zero to Chad never updates on the client. So every change of clothes winds the server's record
back to the login, and the kills made since stop counting toward the milestones. The same packet
lets a modified client write any record it likes, and the server also takes any kill total a client
reports, up to 10,000,000 (onClientCommand). Either way a client can give itself Desensitized.

What this part changes. The server keeps the record table it owns and puts it back as soon as a
client's copy replaces it: before Zero to Chad reads it (ZTC_Common.ensureData and readData) and on
every server tick. A character the server holds no record for keeps none from a client: the record
is the one Zero to Chad creates on the server. A reported total is accepted up to the server's own
count plus 25, which covers kills still on their way; the server counts every kill it sees anyway.
Single player has no client copy, so nothing changes there.

What it cannot close. The record is taken as the server's the first time a tick sees the player,
so a modified client that lands a forged copy in the same server frame as its connect, or in the
frame it disconnects (the disconnect save runs before the next tick), still writes it. Unconfirmed
whether a client can order its packets that tightly. The packet has no ownership check at all in
vanilla: any client can write any online player's mod data. The record is held for every online
player, so that covers Zero to Chad's too; the rest of the mod data is vanilla's problem.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local KEY = "ZeroToChad"
local SERVER_FILE = "ZTC_Server.lua"
local IN_FLIGHT = 25

-- Server player -> the record table the server owns, or false when it held none at first sight.
-- Kahlua has no weak tables, so players who left are dropped every in-game minute.
local owned = {}

local function hold(player)
    local md = player:getModData()
    local current = md[KEY]
    local mine = owned[player]
    if mine == nil then
        owned[player] = type(current) == "table" and current or false
    elseif mine == false then
        if current ~= nil then md[KEY] = nil end
    elseif current ~= mine then
        md[KEY] = mine
    end
end

local function eachOnline(fn)
    local list = getOnlinePlayers()
    if list == nil then return end
    for i = 0, list:size() - 1 do
        local player = list:get(i)
        if player ~= nil then fn(player) end
    end
end

local function forgetGone()
    local online, gone = {}, {}
    eachOnline(function(player) online[player] = true end)
    for player in pairs(owned) do
        if not online[player] then gone[#gone + 1] = player end
    end
    for i = 1, #gone do owned[gone[i]] = nil end
end

local function serverCount(player)
    local own = player:getZombieKills() or 0
    local record = owned[player]
    local counted = type(record) == "table" and record.serverKills or nil
    if type(counted) == "number" and counted > own then return counted end
    return own
end

local function boundReport(original)
    return function(module, command, player, args)
        if module == ZTC_Common.MOD_ID and command == ZTC_Common.CMD_KILLS and player ~= nil
            and type(args) == "table" then
            local reported = tonumber(args.kills)
            local limit = serverCount(player) + IN_FLIGHT
            if reported ~= nil and reported > limit then args = { kills = limit } end
        end
        return original(module, command, player, args)
    end
end

local function fromZeroToChad(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, SERVER_FILE, 1, true) ~= nil
        and string.find(name, KEY, 1, true) ~= nil
end

local function guardRecord(ctx, report)
    if report == nil then error("Zero to Chad's kill report handler never registered") end
    if type(ZTC_Common) ~= "table" or type(ZTC_Common.ensureData) ~= "function"
        or type(ZTC_Common.readData) ~= "function" then
        error("ZTC_Common.ensureData or readData is missing")
    end
    ctx.wrap(ZTC_Common, "ensureData", function(original)
        return function(player)
            if player == nil then return original(player) end
            hold(player)
            local record = original(player)
            if owned[player] == false and type(record) == "table" then owned[player] = record end
            return record
        end
    end)
    ctx.wrap(ZTC_Common, "readData", function(original)
        return function(player)
            if player ~= nil then hold(player) end
            return original(player)
        end
    end)
    ctx.on("OnTick", function() eachOnline(hold) end)
    ctx.on("EveryOneMinute", forgetGone)
end

local function install(ctx)
    owned = {}
    local report = nil
    -- Zero to Chad's server file registers its handler at world load, after this part installs.
    ctx.wrap(Events.OnClientCommand, "Add", function(add)
        return function(fn)
            if report ~= nil or not fromZeroToChad(fn) then return add(fn) end
            report = { fn = fn }
            ctx.wrap(report, "fn", boundReport)
            return add(report.fn)
        end
    end)
    ctx.at(M.isDedicatedServer() and "OnServerStarted" or "OnGameStart", function() guardRecord(ctx, report) end)
end

M.addPart({
    name = "ztc-record",
    switch = "ZtcRecord",
    title = "Zero to Chad: kills keep counting in multiplayer",
    tip = "In multiplayer the game sends the server your login-time copy of Zero to Chad's kill record every time you change clothes, so kills made since stop counting toward its milestones, and a modified client can send any record or kill total it likes. The server keeps its own record and checks reported kills against its own count. Only active with Zero to Chad.",
    kind = "fix",
    all = { "ZeroToChad" },
    side = "server",
    phase = "load",
    pins = { "ztc.data", "ztc.count", "ztc.start", "ztc.report", "ztc.reportreg" },
    install = install,
})
