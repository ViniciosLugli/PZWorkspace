--[[
Server admins: what each mod sends to players, counted per command, to find the mod behind
network lag.

What happens today. Every mod message from the server to players leaves as one of two packet
types, ClientCommand (sendServerCommand) or GlobalModData (ModData.transmit), so the server's
network statistics cannot tell one mod from another. Its cmd log records only what players send.

What this part changes. On a server whose cache folder holds Lua/serverprof-on.txt, each
sendServerCommand and ModData.transmit is counted per module and command (or per ModData key):
calls, the players it reached, and the bytes it put on the wire, estimated from a walk of its
table that stops at WALK_NODES entries. Once a minute the counts are appended to
Lua/serverprof-sends.txt and reset. The flag is looked for once a minute, so creating or deleting
it starts or stops counting without a restart. Without the flag each send costs one check. A mod
that kept its own copy of sendServerCommand before this mod loaded goes uncounted; this mod loads
its shared Lua before any server script, and last among the mods if it is listed last.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- A .txt name, because getFileWriter accepts only ini/cfg/txt/log/json: an admin's Lua can create it.
local FLAG = "serverprof-on.txt"
local OUT = "serverprof-sends.txt"
local HEADER = "epoch_s\twindow_ms\tkind\tkey\tcommand\tcalls\trecipients\test_bytes\twalk"
local CHECK_MS = 60000
local WALK_NODES = 2000
-- TableNetworkUtils.save on 42.22.2: a 4-byte entry count per table, a type byte before every key
-- and value, a string as a 2-byte length and its bytes, a number as 8, a boolean as 1. An
-- inventory item or corpse in a payload counts as its type byte only. HEADER_COST is the two
-- length prefixes and the has-arguments flag GameServer.sendServerCommand writes per packet.
local TABLE_COST, STRING_COST, NUMBER_COST, BOOLEAN_COST, TYPE_COST, HEADER_COST = 4, 2, 8, 1, 1, 5

local active = false
local counts = {}
local windowStart = 0
local lastCheck = 0

local function valueBytes(v)
    local t = type(v)
    if t == "string" then return TYPE_COST + STRING_COST + #v end
    if t == "number" then return TYPE_COST + NUMBER_COST end
    if t == "boolean" then return TYPE_COST + BOOLEAN_COST end
    return TYPE_COST
end

local function payloadBytes(root)
    if type(root) ~= "table" then return 0, false end
    local bytes, nodes, stack, seen = TABLE_COST, 0, { root }, {}
    while #stack > 0 do
        local t = stack[#stack]
        stack[#stack] = nil
        if not seen[t] then
            seen[t] = true
            for k, v in pairs(t) do
                nodes = nodes + 1
                if nodes > WALK_NODES then return bytes, true end
                bytes = bytes + valueBytes(k) + valueBytes(v)
                if type(v) == "table" then
                    bytes = bytes + TABLE_COST
                    stack[#stack + 1] = v
                end
            end
        end
    end
    return bytes, false
end

local function onlineCount()
    local ok, n = pcall(function() return getOnlinePlayers():size() end)
    return ok and type(n) == "number" and n or 0
end

local function count(kind, key, command, recipients, bytes, capped)
    local byKey = counts[kind]
    if byKey == nil then
        byKey = {}
        counts[kind] = byKey
    end
    local id = key .. "\t" .. command
    local c = byKey[id]
    if c == nil then
        c = { calls = 0, recipients = 0, bytes = 0, capped = false }
        byKey[id] = c
    end
    c.calls = c.calls + 1
    c.recipients = c.recipients + recipients
    c.bytes = c.bytes + bytes * recipients
    if capped then c.capped = true end
end

local function flagPresent()
    local ok, reader = pcall(getFileReader, FLAG, false)
    if not ok or reader == nil then return false end
    pcall(function() reader:close() end)
    return true
end

local function flush(now)
    local okRead, reader = pcall(getFileReader, OUT, false)
    local fresh = not okRead or reader == nil
    if not fresh then pcall(function() reader:close() end) end
    local writer = getFileWriter(OUT, true, true)
    if writer == nil then error("cannot write Lua/" .. OUT) end
    if fresh then writer:write(HEADER .. "\n") end
    local epoch = string.format("%d", math.floor(now / 1000))
    local windowMs = string.format("%d", now - windowStart)
    for kind, byKey in pairs(counts) do
        for id, c in pairs(byKey) do
            writer:write(epoch .. "\t" .. windowMs .. "\t" .. kind .. "\t" .. id .. "\t"
                .. string.format("%d\t%d\t%d", c.calls, c.recipients, c.bytes) .. "\t"
                .. (c.capped and "capped" or "full") .. "\n")
        end
    end
    writer:close()
    counts = {}
    windowStart = now
end

local function onTick()
    local now = getTimestampMs()
    if now - lastCheck < CHECK_MS then return end
    lastCheck = now
    if active then flush(now) end
    local was = active
    active = flagPresent()
    if active and not was then
        counts = {}
        windowStart = now
        M.log("srv-prof: counting sends into Lua/" .. OUT)
    elseif was and not active then
        M.log("srv-prof: Lua/" .. FLAG .. " is gone, counting stopped")
    end
end

local function install(ctx)
    if type(getFileReader) ~= "function" or type(getFileWriter) ~= "function"
        or type(getTimestampMs) ~= "function" then
        error("file or clock API missing")
    end
    -- Varargs, not (a, b, c, d): the engine picks the Java overload by argument count, so a
    -- broadcast passed on with a trailing nil would reach the per-player overload.
    ctx.wrap(_G, "sendServerCommand", function(send)
        return function(...)
            if active then
                local a, b, c, d = ...
                if type(a) == "string" then
                    local bytes, capped = payloadBytes(c)
                    count("cmd", a, tostring(b), onlineCount(), bytes + HEADER_COST + #a + #tostring(b), capped)
                else
                    local bytes, capped = payloadBytes(d)
                    count("cmd", tostring(b), tostring(c), 1, bytes + HEADER_COST + #tostring(b) + #tostring(c), capped)
                end
            end
            return send(...)
        end
    end)
    ctx.wrap(ModData, "transmit", function(transmit)
        return function(tag)
            if active then
                local okGet, data = pcall(ModData.get, tag)
                local bytes, capped = payloadBytes(okGet and data or nil)
                count("moddata", tostring(tag), "-", onlineCount(), bytes + STRING_COST + #tostring(tag), capped)
            end
            return transmit(tag)
        end
    end)
    active = flagPresent()
    lastCheck = getTimestampMs()
    windowStart = lastCheck
    if active then M.log("srv-prof: counting sends into Lua/" .. OUT) end
    ctx.on("OnTick", onTick)
end

M.addPart({
    name = "srv-prof",
    switch = "SrvProf",
    title = "Server admins: count what each mod sends to players",
    tip = "For finding the mod behind network lag on a dedicated server. Does nothing until the server's admin creates the file Lua/serverprof-on.txt in the server's cache folder; then, once a minute, it writes how many messages each mod sent to players, to how many players, and roughly how many bytes, to Lua/serverprof-sends.txt. Delete the file to stop.",
    kind = "tool",
    side = "server",
    phase = "load",
    install = install,
})
