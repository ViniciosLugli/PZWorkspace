-- server/ loads on a multiplayer client too, so the directory is not the guard: this is.
if not isServer() then return end

require "LugliAchievements/Core"

local M = LugliAchievements
local PART = "Progress store"

-- Global ModData IS saved with the world in a server process, which is the whole reason progress
-- lives here rather than on the client.
local TABLE_NAME = "LugliAchievementsPlayers"

-- A malformed packet must not be walked forever, and a value the character save cannot serialise
-- is worse than useless: the engine deletes the row and kicks the player.
local MAX_DEPTH = 6

local function sanitise(v, depth)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then return v end
    if t ~= "table" or depth >= MAX_DEPTH then return nil end
    local out = {}
    for k, sub in pairs(v) do
        local kt = type(k)
        if kt == "number" or kt == "string" then
            local clean = sanitise(sub, depth + 1)
            if clean ~= nil then out[k] = clean end
        end
    end
    return out
end

local function store()
    if ModData == nil or ModData.getOrCreate == nil then return nil end
    local ok, t = pcall(ModData.getOrCreate, TABLE_NAME)
    if not ok or type(t) ~= "table" then return nil end
    return t
end

local function onClientCommand(module, command, player, packet)
    if module ~= M.NET_MODULE then return end
    if player == nil or player.getUsername == nil then return end
    local user = player:getUsername()
    if type(user) ~= "string" or user == "" then return end
    local all = store()
    if all == nil then return end

    if command == "load" then
        sendServerCommand(player, M.NET_MODULE, "data", all[user] or {})
    elseif command == "save" and type(packet) == "table" then
        -- The counters are taken at face value: this mod only ever watches, so a player editing
        -- their own achievements changes nothing anyone else can see. The SHAPE is not.
        all[user] = sanitise(packet, 0)
    end
end

M.addHandler(PART, "OnClientCommand", onClientCommand)
M.status(PART, true, "per-player progress, saved with the world")
