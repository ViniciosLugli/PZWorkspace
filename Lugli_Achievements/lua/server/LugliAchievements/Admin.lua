-- What an admin needs to know: that it loaded, what it writes, and whose progress is whose.
-- client/ never loads in a server process, so no achievement can be earned here; Store.lua is
-- the one thing that does run, and it holds what the clients earn.
require "LugliAchievements/Core"

local M = LugliAchievements
local PART = "Server"

--- A function rather than a print, so it can be called again without re-triggering an event.
function M.serverReport()
    local skipped = M.serverSkipped or 0
    local where = (type(M.envName) == "function") and M.envName() or "unknown"
    local lines = {
        "[LugliAchievements] running as: " .. where,
        "[LugliAchievements] server-side work: it keeps each player's progress and hands it " ..
            "back when they connect. client/ does not load here, so no tracker registers and " ..
            "no achievement can be earned in this process.",
        "[LugliAchievements] definitions held in memory: " ..
            (M.isDedicatedServer() and ("0 (" .. skipped .. " refused, by design)")
                                    or tostring(#(M.getAllDefinitions and M.getAllDefinitions() or {}))),
        "[LugliAchievements] save impact: one GlobalModData table, LugliAchievementsPlayers, " ..
            "keyed by username and saved with the world. Counters and unlock ids only. One " ..
            "player's progress is never another's, and nothing else is written to server state.",
    }
    return table.concat(lines, "\n")
end

--- Print it once, when the world the admin just started is up.
local function announce()
    print(M.serverReport())
end

if M.isDedicatedServer() or M.isCoopHost() then
    -- OnServerStarted is the honest moment: the world exists and the log is being read.
    -- Falls back to world load, because a co-op host reaches that and may not reach the other.
    local hooked = M.addHandler(PART, "OnServerStarted", announce)
    if hooked == nil then
        hooked = M.addHandler(PART, "OnGameStart", announce)
    end
    M.status(PART, hooked ~= nil,
             "reports on start; stores nothing server-side", hooked ~= nil and nil or "bug")
else
    -- Single player and plain multiplayer clients have a server process they never see. Saying
    -- "dep" rather than failing is the difference between "not applicable" and "broken".
    M.status(PART, nil, "not a server process", "dep")
end
