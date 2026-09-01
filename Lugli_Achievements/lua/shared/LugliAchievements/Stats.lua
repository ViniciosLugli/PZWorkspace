require "LugliAchievements/Core"

local M = LugliAchievements

-- A dedup set is only ever the backing store for a counter, so past this size it is dead weight
-- in every save that carries it. At the cap it stops accepting members and the count freezes.
-- No shipped target comes near this.
local SET_HARD_CAP = 2000

local SAVE_TABLE = "LugliAchievements"

-- Stat keys renamed between data versions, keyed by the version being migrated FROM. A rename
-- without an entry here silently resets the counter for every existing character.
local STAT_RENAMES = {}

-- MIGRATIONS[n] takes a table at version n and leaves its CONTENT at version n+1. It must not
-- touch data.version; the loop below owns that, so a step cannot half-advance the table.
local MIGRATIONS = {}

-- pcall with an argument rather than a closure: a closure per call is garbage on a path that
-- runs once per stat write.
local function fetchModData(player)
    return player:getModData()
end

local function newData()
    return {
        version    = M.DATA_VERSION,
        stats      = {},   -- statKey -> number
        sets       = {},   -- statKey -> { [uniqueId] = true }, or false once frozen
        unlocked   = {},   -- achievementId -> true
        unlockedAt = {},   -- achievementId -> world age hours. A number, never a display string.
    }
end

local function renameStats(data, renames)
    for old, new in pairs(renames) do
        if data.stats[old] ~= nil then
            data.stats[new] = data.stats[old]
            data.stats[old] = nil
        end
        if data.sets[old] ~= nil then
            data.sets[new] = data.sets[old]
            data.sets[old] = nil
        end
    end
end

--- Forward only, one step at a time. Returns ok, reason.
local function migrate(data)
    local target = M.DATA_VERSION
    if type(data.version) ~= "number" then return false, "no version on the saved table" end
    if data.version > target then
        -- Downgrading would drop fields this build cannot see. Refuse rather than corrupt.
        return false, "saved by a newer version of the mod (" .. data.version ..
                      " > " .. target .. ")"
    end
    while data.version < target do
        local from = data.version
        local step = MIGRATIONS[from]
        if step == nil then return false, "no migration from version " .. from end
        local ok, err = pcall(step, data, renameStats, STAT_RENAMES[from] or {})
        if not ok then return false, "migration " .. from .. " threw: " .. tostring(err) end
        data.version = from + 1
    end
    return true
end

--- The save-wide unlock ledger, created on first use. Progress belongs to the survivor who ran
--- it up; unlocks do not, and the achievements earned BY dying would otherwise be recorded only
--- on the character being deleted. Nil when there is no store yet, as on a bare VM.
function M.getSaveData()
    local t
    if M.isMpClient ~= nil and M.isMpClient() then
        local c = M.mpContainer
        if type(c) ~= "table" then return nil end
        t = c.ledger
        if type(t) ~= "table" then t = {}; c.ledger = t end
    else
        if ModData == nil or ModData.getOrCreate == nil then return nil end
        local ok, got = pcall(ModData.getOrCreate, SAVE_TABLE)
        if not ok or type(got) ~= "table" then return nil end
        t = got
    end
    if type(t.version) ~= "number" then t.version = M.DATA_VERSION end
    if type(t.unlocked) ~= "table" then t.unlocked = {} end
    if type(t.unlockedAt) ~= "table" then t.unlockedAt = {} end
    if type(t.unlockedBy) ~= "table" then t.unlockedBy = {} end
    return t
end

--- Has anyone in this save earned it, this survivor or a previous one.
function M.isUnlockedInSave(id)
    local t = M.getSaveData()
    return t ~= nil and t.unlocked[id] == true
end

--- Who earned it, for the detail pane. Empty string when the ledger does not know.
function M.getSaveUnlockOwner(id)
    local t = M.getSaveData()
    if t == nil then return "" end
    local who = t.unlockedBy[id]
    return type(who) == "string" and who or ""
end

--- First writer wins: the point is who earned it FIRST, and a later character re-earning it
--- must not rewrite the hour to a much later one.
function M.recordSaveUnlock(id, hours, who)
    local t = M.getSaveData()
    if t == nil or type(id) ~= "string" then return false end
    if t.unlocked[id] == true then return false end
    t.unlocked[id] = true
    t.unlockedAt[id] = (type(hours) == "number") and hours or 0
    t.unlockedBy[id] = (type(who) == "string") and who or ""
    local mark = M.markDirty
    if mark ~= nil then mark() end
    return true
end

-- Per world is the default: one set of counters shared by every survivor in the save, so a
-- death does not restart the collection and the achievements earned BY dying stay earned.
-- Switching mid-save deletes nothing, since the other scope's table is simply not read.
local WORLD_TABLE = "LugliAchievementsWorld"

local perCharacter = false          -- cached, because getCharData is the hottest path here

--- Read at world load rather than per access: the option cannot change without the player
--- opening a menu, so reading it per stat write is pure waste.
function M.refreshScope()
    perCharacter = false
    if PZAPI == nil or PZAPI.ModOptions == nil then return perCharacter end
    local ok, opts = pcall(function() return PZAPI.ModOptions:getOptions(M.OPTIONS_ID) end)
    if not ok or opts == nil or opts.getOption == nil then return perCharacter end
    local ok2, opt = pcall(function() return opts:getOption("perCharacter") end)
    if ok2 and opt ~= nil and opt.getValue ~= nil then
        local ok3, v = pcall(function() return opt:getValue() end)
        perCharacter = (ok3 and v == true)
    end
    return perCharacter
end

function M.isPerCharacter() return perCharacter end

--- Sync.lua owns this container on a multiplayer client: it is hydrated from the server and
--- flushed back, because global ModData there is never saved.
local function worldData()
    if M.isMpClient ~= nil and M.isMpClient() then
        local c = M.mpContainer
        return (type(c) == "table") and c or nil
    end
    if ModData == nil or ModData.getOrCreate == nil then return nil end
    local ok, md = pcall(ModData.getOrCreate, WORLD_TABLE)
    if not ok or type(md) ~= "table" then return nil end
    return md
end

--- Repair, then migrate, in that order, so a migration step never has to defend against a nil
--- sub-table of its own.
local function ready(container, key, label)
    local data = container[key]
    if type(data) ~= "table" then
        data = newData()
        container[key] = data
        return data
    end
    if type(data.stats) ~= "table" then data.stats = {} end
    if type(data.sets) ~= "table" then data.sets = {} end
    if type(data.unlocked) ~= "table" then data.unlocked = {} end
    if type(data.unlockedAt) ~= "table" then data.unlockedAt = {} end

    if data.version ~= M.DATA_VERSION then
        local mok, merr = migrate(data)
        if not mok then
            -- Resetting throws away progress, so it is never silent.
            M.defect("stats", label .. " progress reset, could not migrate: " .. tostring(merr))
            data = newData()
            container[key] = data
        end
    end
    return data
end

--- The progress table everything reads and writes, and the ONLY place the per-world versus
--- per-character setting is consulted. Returns nil rather than throwing when there is no usable
--- player, so one bad call cannot take the rest of the mod down.
function M.getCharData(player)
    -- mpCharacterFallback is set by Sync.lua when a server turns out not to have this mod: the
    -- player's own ModData is then the only store anything persists.
    if not perCharacter and not M.mpCharacterFallback then
        local md = worldData()
        if md ~= nil then
            return ready(md, M.MODDATA_KEY, "world")
        end
        -- No ModData means no world is loaded. Falling through to the character store beats
        -- returning nil, which every caller would then have to handle.
    end
    if player == nil then return nil end
    local ok, md = pcall(fetchModData, player)
    if not ok or type(md) ~= "table" then return nil end
    return ready(md, M.MODDATA_KEY, "character")
end

-- Looked up per call rather than captured: a third-party mod may register achievements after
-- this file has loaded. markDirty only exists on a multiplayer client, where it decides whether
-- the store is worth sending.
local function notify(player, key)
    local mark = M.markDirty
    if mark ~= nil then mark() end
    local f = M.onStatChanged
    if f ~= nil then f(player, key) end
end

function M.getStat(player, key)
    local data = M.getCharData(player)
    if data == nil then return 0 end
    return data.stats[key] or 0
end

function M.isUnlocked(player, id)
    local data = M.getCharData(player)
    if data == nil then return false end
    return data.unlocked[id] == true
end

function M.setStat(player, key, value)
    if type(key) ~= "string" or type(value) ~= "number" then return end
    local data = M.getCharData(player)
    if data == nil then return end
    data.stats[key] = value
    notify(player, key)
    return value
end

function M.incStat(player, key, amount)
    if amount == nil then amount = 1 end
    if type(key) ~= "string" or type(amount) ~= "number" then return end
    local data = M.getCharData(player)
    if data == nil then return end
    local v = (data.stats[key] or 0) + amount
    data.stats[key] = v
    notify(player, key)
    return v
end

--- Best-of stats: a longest streak, a heaviest load. Never decreases, so a streak that breaks
--- does not take the record with it.
function M.setStatIfGreater(player, key, value)
    if type(key) ~= "string" or type(value) ~= "number" then return end
    local data = M.getCharData(player)
    if data == nil then return end
    local cur = data.stats[key] or 0
    if value <= cur then return cur end
    data.stats[key] = value
    notify(player, key)
    return value
end

--- Count distinct things. The set is the dedup structure; stats[key] is the count, kept in step
--- with it rather than derived from it, so an insert stays O(1). A uniqueId must be stable
--- across sessions: never a Java identity.
function M.addUnique(player, key, uniqueId)
    if type(key) ~= "string" then return false end
    if type(uniqueId) ~= "string" and type(uniqueId) ~= "number" then return false end
    local data = M.getCharData(player)
    if data == nil then return false end

    local set = data.sets[key]
    if set == false then return false end
    if type(set) ~= "table" then
        set = {}
        data.sets[key] = set
    end
    if set[uniqueId] ~= nil then return false end

    set[uniqueId] = true
    local n = (data.stats[key] or 0) + 1
    data.stats[key] = n
    if n >= SET_HARD_CAP then
        data.sets[key] = false
        M.log("stats", "dedup set '" .. key .. "' reached the " .. SET_HARD_CAP ..
                       " cap and is now a plain count")
    end
    notify(player, key)
    return true
end

M.SET_HARD_CAP = SET_HARD_CAP
M.status("Stats", true)
