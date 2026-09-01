require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Progress sync"

-- The container Stats.lua reads on a multiplayer client. Created unconditionally so the store
-- selector never has to care which file loaded first.
M.mpContainer = M.mpContainer or {}

if not M.isMpClient() then
    M.status(PART, nil, "not a multiplayer client", "dep")
    return
end

-- Ten-minute polls to wait for the server before giving up on it.
local REPLY_POLLS = 2

local hydrated = false
local dirty = false
local polls = 0

--- Called by every stat write, so an unchanged table is not sent every ten game-minutes.
function M.markDirty() dirty = true end

--- The player's own ModData, rather than the server's per-player store. True when the player
--- asked for per-character progress, and when the server turned out not to have this mod.
local function usingCharacterStore()
    return M.isPerCharacter() or M.mpCharacterFallback == true
end

--- Character ModData is saved with the character on the server, but only what has been
--- transmitted. A null square is the engine's own bail-out in transmitModData.
local function flushCharacter()
    M.forEachLocalPlayer(function(player)
        if player.transmitModData ~= nil and player:getSquare() ~= nil then
            player:transmitModData()
        end
    end)
end

local function flush()
    if not dirty then return end
    if usingCharacterStore() then
        dirty = false
        flushCharacter()
        return
    end
    -- Never before the server's copy has arrived, or an empty table would overwrite it.
    if not hydrated then return end
    dirty = false
    sendClientCommand(M.NET_MODULE, "save", M.mpContainer)
end

--- No reply means the server is not running a build of this mod that answers, usually because it
--- has not been updated yet. Character ModData is then the only store the server persists by
--- itself, so progress moves there instead of being lost. It dies with the character, and with it
--- the save-wide ledger of what earlier survivors earned, which is why this is the fallback and
--- not the default.
local function fallbackToCharacter()
    M.mpCharacterFallback = true
    M.forEachLocalPlayer(function(player)
        local md = player:getModData()
        if type(md) == "table" and md[M.MODDATA_KEY] == nil then
            md[M.MODDATA_KEY] = M.mpContainer[M.MODDATA_KEY]
        end
    end)
    M.invalidateSummary()
    dirty = true
    flush()
    M.status(PART, false, "the server did not answer, so progress is kept with your character " ..
                          "and is lost when they die. The server needs this mod too", "dep")
end

local function onServerCommand(module, command, packet)
    if module ~= M.NET_MODULE or command ~= "data" then return end
    if type(packet) ~= "table" then packet = {} end

    for k in pairs(M.mpContainer) do M.mpContainer[k] = nil end
    for k, v in pairs(packet) do M.mpContainer[k] = v end
    hydrated = true
    M.invalidateSummary()
    M.status(PART, true, "progress is kept by the server, per player")

    -- The backfill at OnCreatePlayer ran against an empty store. Silently: this is the mod
    -- catching up with counters that have just arrived, not the player earning them.
    local wasQuiet = M.toastQuiet
    M.toastQuiet = true
    M.forEachLocalPlayer(function(player) M.recheckAll(player) end)
    M.toastQuiet = wasQuiet
end

--- Rejoining, possibly a different server. The last session's copy is not this one's and must
--- not be sent to it, so everything goes back to cold and the server is asked again.
local function resetForNewServer()
    hydrated = false
    dirty = false
    polls = 0
    M.mpCharacterFallback = nil
    for k in pairs(M.mpContainer) do M.mpContainer[k] = nil end
    M.invalidateSummary()
end

local function onEveryTenMinutes()
    if not hydrated and not usingCharacterStore() then
        polls = polls + 1
        if polls > REPLY_POLLS then fallbackToCharacter() end
        return
    end
    flush()
end

M.addHandler(PART, "OnServerCommand", onServerCommand)
M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.addHandler(PART, "OnPlayerDeath", flush)
M.addHandler(PART, "OnDisconnect", flush)

local chained = false

M.addHandler(PART, "OnGameStart", function()
    if M.isPerCharacter() then
        M.status(PART, true, "progress is kept with your character on the server")
    else
        resetForNewServer()
        sendClientCommand(M.NET_MODULE, "load", {})
    end
    -- Chained here rather than at load, because every file that owns this hook has run by now.
    -- Once, because a second world load would otherwise stack another flush onto every unlock.
    if not chained then
        chained = true
        local previous = M.onUnlocked
        M.onUnlocked = function(player, def)
            if previous ~= nil then pcall(previous, player, def) end
            flush()
        end
    end
end)

M.status(PART, nil, "waiting for the server", "pending")
