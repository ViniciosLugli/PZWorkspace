-- What an admin needs to know: that it loaded, what it writes, and whose progress is whose.
-- client/ never loads in a server process, so no achievement can be earned here; Store.lua is
-- the one thing that does run: it holds what the clients earn and relays the body damage only
-- this process sees.
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
            "back when they connect, and tells each player about the hunger, thirst, poison, " ..
            "bleeding and infection damage only the server sees. client/ does not load here, " ..
            "so no tracker registers and no achievement can be earned in this process.",
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

-- A co-op host's server is a child JVM, and there it is a dedicated server like any other.
if M.isDedicatedServer() then
    -- OnServerStarted is the honest moment: the world exists and the log is being read.
    local hooked = M.addHandler(PART, "OnServerStarted", announce)
    if hooked == nil then
        hooked = M.addHandler(PART, "OnGameStart", announce)
    end
    M.status(PART, hooked ~= nil,
             "reports on start; the progress store keeps each player's progress here",
             hooked ~= nil and nil or "bug")
else
    -- Single player and plain multiplayer clients have a server process they never see. Saying
    -- "dep" rather than failing is the difference between "not applicable" and "broken".
    M.status(PART, nil, "not a server process", "dep")
end
