require "LugliAchievements/Core"
require "LugliAchievements/Stats"

local M = LugliAchievements

local defs = {}        -- registration order, and the denominator
local defById = {}
local categories = {}
local catOrder = {}    -- registration order, so the sidebar is stable

-- No per-achievement event handlers: trackers write counters, every write calls onStatChanged,
-- and that consults a prebuilt stat-key -> watchers index. Three watchers cost three
-- comparisons, not one per achievement in the mod.
local statIndex = {}
local indexDirty = true

-- Bumped whenever the answer getSummary would give could have changed. The window header asks
-- every frame, and recomputing there is one getModData round trip per achievement per frame.
local epoch = 0
local cacheEpoch, cachePlayer = -1, nil
local cacheSummary = { total = 0, unlocked = 0, inSave = 0, percent = 0, byCategory = {} }

--- Definitions evaluated since load. Read as a delta, this is the only way to prove the index
--- is being consulted rather than the whole list scanned.
M.evaluations = 0

local VALID_TIERS = { bronze = true, silver = true, gold = true }

function M.registerCategory(cat)
    if type(cat) ~= "table" or type(cat.id) ~= "string" then
        M.log("registry", "registerCategory ignored: no id")
        return false
    end
    if categories[cat.id] ~= nil then return false end
    categories[cat.id] = cat
    catOrder[#catOrder + 1] = cat.id
    epoch = epoch + 1
    return true
end

--- Register one achievement.
---
--- Required: id, name, description, category, stat, and target (or a check predicate).
--- Optional: unit, hidden, hiddenText, tier, icon, source.
---
--- The first registration of an id wins; a later one is rejected and logged with both sources,
--- so no mod can silently replace another's achievement.
function M.register(def)
    -- A dedicated server cannot earn anything: client/ never loads there, so nothing writes a
    -- stat. Refuse early and keep a tally, so an admin reading the log sees a number.
    if M.isDedicatedServer ~= nil and M.isDedicatedServer() then
        M.serverSkipped = (M.serverSkipped or 0) + 1
        return false
    end
    if type(def) ~= "table" then
        M.log("registry", "register ignored: not a table")
        return false
    end
    local id = def.id
    if type(id) ~= "string" or not string.match(id, "^[a-z0-9_]+$") then
        M.log("registry", "register REJECTED: id must match ^[a-z0-9_]+$, got " .. tostring(id))
        return false
    end
    local existing = defById[id]
    if existing ~= nil then
        M.log("registry", "register REJECTED duplicate id '" .. id .. "': kept " ..
                          tostring(existing.source or "first registration") .. ", dropped " ..
                          tostring(def.source or "second registration"))
        return false
    end
    if type(def.stat) ~= "string" then
        M.log("registry", "register REJECTED '" .. id .. "': no stat key")
        return false
    end
    if def.check ~= nil then
        if type(def.check) ~= "function" then
            M.log("registry", "register REJECTED '" .. id .. "': check is not a function")
            return false
        end
        if def.target == nil then def.target = 1 end
    end
    if type(def.target) ~= "number" or def.target <= 0 then
        M.log("registry", "register REJECTED '" .. id .. "': target must be a positive number")
        return false
    end
    if def.tier ~= nil and not VALID_TIERS[def.tier] then
        M.log("registry", "register REJECTED '" .. id .. "': tier must be bronze, silver or gold")
        return false
    end

    -- Art is addressed by id, so no definition carries a path. A caller may still supply its
    -- own icon, which is how another mod points at art inside its own folder.
    if def.icon == nil then
        def.icon = "media/ui/achievements/" .. id .. ".png"
    end

    defs[#defs + 1] = def
    defById[id] = def
    indexDirty = true
    epoch = epoch + 1
    return true
end

local function buildIndex()
    statIndex = {}
    local unknownCat = nil
    for i = 1, #defs do
        local d = defs[i]
        local list = statIndex[d.stat]
        if list == nil then
            list = {}
            statIndex[d.stat] = list
        end
        list[#list + 1] = d
        if categories[d.category] == nil and unknownCat == nil then unknownCat = d.category end
    end
    indexDirty = false
    if unknownCat ~= nil then
        M.log("registry", "no category registered for '" .. tostring(unknownCat) .. "'")
    end
end

--- Force the next getSummary to recompute. The epoch only moves when a definition or an unlock
--- changes, so a store that is swapped underneath the window -- the server's copy arriving, or
--- the fallback to character data -- would otherwise be read from a cache built before it.
function M.invalidateSummary()
    epoch = epoch + 1
end

function M.getWatchers(key)
    if indexDirty then buildIndex() end
    return statIndex[key] or {}
end

local function progressValue(data, def)
    if def.check ~= nil then
        local ok, res = pcall(def.check, data.stats)
        if not ok then return 0 end
        if res then return def.target end
        return 0
    end
    return data.stats[def.stat] or 0
end

local function doUnlock(player, data, def)
    -- ORDER MATTERS. The notification used to fire FIRST, so the milestone tracker's getSummary
    -- ran one unlock behind and the capstone could only fire on the next world load. Everything
    -- a handler might read is written before it is called.
    --
    -- The two save fields go in together with nothing between them that can throw: split, a
    -- throw leaves an achievement unlocked with no timestamp, which reads as hour zero forever.
    local hours = M.worldHours()
    data.unlocked[def.id] = true
    data.unlockedAt[def.id] = hours
    -- The save-wide ledger is the only copy that survives this character, and the death
    -- achievements are earned at the moment the per-character store stops existing.
    -- descriptor is a plain field the engine itself nil-checks, so it is asked for step by step
    -- rather than chained: an error here would be dumped by the engine before any pcall unwound.
    local who = ""
    if player ~= nil and player.getDescriptor ~= nil then
        local desc = player:getDescriptor()
        if desc ~= nil then
            local d = desc:getForename()
            if type(d) == "string" then who = d end
        end
    end
    -- Both of these used to swallow a throw whole. An unlock is rare and names an id, so saying
    -- which one failed costs nothing and is the difference between a bug and a hard achievement.
    if type(M.recordSaveUnlock) == "function" then
        local ok, err = pcall(M.recordSaveUnlock, def.id, hours, who)
        if not ok then
            M.defect("registry", "the save ledger refused '" .. def.id .. "': " .. tostring(err))
        end
    end
    epoch = epoch + 1
    local notify = M.onUnlocked
    if notify ~= nil then
        local ok, err = pcall(notify, player, def)
        if not ok then
            M.defect("registry", "the unlock notification for '" .. def.id ..
                                 "' threw: " .. tostring(err))
        end
    end
end

--- Called by every stat setter. This is the hot path.
function M.onStatChanged(player, key)
    if indexDirty then buildIndex() end
    local list = statIndex[key]
    if list == nil then return end          -- an unwatched key is a no-op, not an error
    local data = M.getCharData(player)
    if data == nil then return end
    local unlocked = data.unlocked
    local n = M.evaluations
    for i = 1, #list do
        local d = list[i]
        if unlocked[d.id] ~= true then
            n = n + 1
            if progressValue(data, d) >= d.target then doUnlock(player, data, d) end
        end
    end
    M.evaluations = n
end

--- Backfill, run on every load rather than only on a version bump: it is what makes a newly
--- added achievement unlock for a character who already met it.
function M.recheckAll(player)
    if indexDirty then buildIndex() end
    local data = M.getCharData(player)
    if data == nil then return 0 end
    local unlocked = data.unlocked
    local fired = 0
    for i = 1, #defs do
        local d = defs[i]
        if unlocked[d.id] ~= true then
            M.evaluations = M.evaluations + 1
            if progressValue(data, d) >= d.target then
                doUnlock(player, data, d)
                fired = fired + 1
            end
        end
    end
    return fired
end

--- Unlocked by THIS survivor, or by anyone in this save, so a record earned by a survivor who
--- has since died is still visible. Reads the character store directly rather than through
--- M.isUnlocked: the offline suite loads this file alone, where that call is nil.
function M.isUnlockedAnywhere(player, id)
    local data = M.getCharData(player)
    if data ~= nil and data.unlocked[id] == true then return true end
    if type(M.isUnlockedInSave) ~= "function" then return false end
    return M.isUnlockedInSave(id)
end

function M.getDefinition(id) return defById[id] end
function M.getAllDefinitions() return defs end
function M.getCategory(id) return categories[id] end
function M.getCategoryOrder() return catOrder end

function M.getProgressFraction(player, def)
    local data = M.getCharData(player)
    if data == nil or def == nil then return 0 end
    if data.unlocked[def.id] == true then return 1 end
    local f = progressValue(data, def) / def.target
    if f < 0 then return 0 end
    if f > 1 then return 1 end
    return f
end

--- "37 / 100 zombies". The unit is omitted when absent rather than printing a raw key into the
--- middle of a sentence.
function M.getProgressText(player, def)
    local data = M.getCharData(player)
    if data == nil or def == nil then return "" end
    local v = progressValue(data, def)
    if v > def.target then v = def.target end
    local text = tostring(math.floor(v)) .. " / " .. tostring(math.floor(def.target))
    if def.unit ~= nil then
        local unit = M.text(def.unit, "")
        if unit ~= "" then text = text .. " " .. unit end
    end
    return text
end

--- { total, unlocked, inSave, percent, byCategory } for this survivor. Cached and returned by
--- reference: read it, do not mutate it. byCategory rides along because this loop already
--- visits every definition once.
---
--- An unlocked id with no definition behind it is an orphan, left by a cut definition or an
--- uninstalled mod. It counts towards neither half: a completion percentage that moves when you
--- unsubscribe an unrelated mod reads as a bug.
function M.getSummary(player)
    if indexDirty then buildIndex() end
    if epoch == cacheEpoch and player == cachePlayer then return cacheSummary end

    local total, done, inSave = #defs, 0, 0
    -- Guarded because the offline suite loads this file on its own, where the ledger is nil.
    local ledger = (type(M.getSaveData) == "function") and M.getSaveData() or nil
    local saved = (ledger ~= nil) and ledger.unlocked or nil
    local byCat = cacheSummary.byCategory
    for k in pairs(byCat) do byCat[k] = nil end
    local data = M.getCharData(player)
    local unlocked = (data ~= nil) and data.unlocked or nil
    for i = 1, total do
        local def = defs[i]
        local slot = byCat[def.category]
        if slot == nil then
            slot = { total = 0, unlocked = 0, inSave = 0 }
            byCat[def.category] = slot
        end
        slot.total = slot.total + 1
        local mine = (unlocked ~= nil) and unlocked[def.id] == true
        if mine then
            done = done + 1
            slot.unlocked = slot.unlocked + 1
        end
        if mine or (saved ~= nil and saved[def.id] == true) then
            inSave = inSave + 1
            slot.inSave = slot.inSave + 1
        end
    end
    cacheSummary.total = total
    cacheSummary.unlocked = done
    cacheSummary.inSave = inSave
    if total > 0 then
        cacheSummary.percent = math.floor((done / total) * 100)
    else
        cacheSummary.percent = 0
    end
    cacheEpoch, cachePlayer = epoch, player
    return cacheSummary
end

M.status("Registry", true)
