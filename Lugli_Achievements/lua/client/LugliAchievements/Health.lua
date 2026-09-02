require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Health"

-- Every part records how it went in M.parts and nothing read that table: a health status no
-- player or admin could see. A log is the right reader, because a player reporting a problem
-- pastes a log. Admin.lua does this in a server process, under the same prefix.
local PREFIX = "[LugliAchievements]"

-- Sync.lua is still "waiting for the server" at OnGameStart and settles a minute later, so one
-- report at load would always show the least interesting moment. Reprinted only when the picture
-- changes, and capped: this is a diagnostic, not a heartbeat.
local MAX_REPORTS = 3

local reports = 0
local last = nil

local function summarise()
    local keys, ok, waiting, na, broken = {}, 0, 0, 0, 0
    for k in pairs(M.parts) do keys[#keys + 1] = k end
    table.sort(keys)   -- pairs order is not stable, and two logs should be diffable

    local detail = {}
    for i = 1, #keys do
        local p = M.parts[keys[i]]
        local label
        if p.ok == true then
            ok = ok + 1
        elseif p.ok == false and p.kind == "dep" then
            -- A dependency the player chose not to install. Counting it as broken sends people
            -- looking for a fault that is not there.
            na = na + 1
            label = "unavailable"
        elseif p.ok == false then
            broken = broken + 1
            label = "BROKEN"
        elseif p.kind == "pending" then
            waiting = waiting + 1
            label = "waiting"
        else
            na = na + 1
            label = "not applicable"
        end
        if label ~= nil then
            detail[#detail + 1] = PREFIX .. "   " .. keys[i] .. ": " .. label ..
                (type(p.note) == "string" and (" -- " .. p.note) or "")
        end
    end

    return PREFIX .. " parts: " .. ok .. " ok, " .. waiting .. " waiting, " ..
           na .. " not applicable, " .. broken .. " broken",
           table.concat(detail, "\n")
end

--- The report as one string, so a player can be asked for this rather than a whole session.
function M.clientReport()
    local head, detail = summarise()
    local where = PREFIX .. " running as: " .. M.envName()
    if detail == "" then return where .. "\n" .. head end
    return where .. "\n" .. head .. "\n" .. detail
end

local function announce()
    local head, detail = summarise()
    local key = head .. "\n" .. detail
    if key == last then return end
    last = key
    if reports >= MAX_REPORTS then return end
    reports = reports + 1
    print(M.clientReport())
end

M.addHandler(PART, "OnGameStart", announce)
M.addHandler(PART, "EveryOneMinute", announce)

M.status(PART, true, "prints a part report to the log at world load")
