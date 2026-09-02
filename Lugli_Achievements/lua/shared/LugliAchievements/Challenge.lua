require "LugliAchievements/Core"

local M = LugliAchievements

-- A challenge is an ordinary achievement definition carrying one extra field, `when`. It still
-- unlocks on stats[stat] >= target, so there is one unlock path in the mod and Registry is
-- untouched. Nothing here calls the engine; the atoms and triggers live in the client tracker.

local challenges = {}
local byId = {}
local byStat = {}

-- The only derived keys in the mod. The build gate derives them by the same rule.
local RUN_SUFFIX = "_r"
local SEQ_SUFFIX = "_s"
local LIFE_SEQ = "chal_life_seq"

local MODES = {
    each = true, once = true, best = true, unique = true,
    streak = true, life = true, burst = true,
}

-- Every field a `when` may carry. Anything else is refused rather than ignored.
local WHEN_KEYS = {
    trigger = true, all = true, count = true, value = true,
    uniqueBy = true, reset = true, window = true, need = true,
}

-- A table so the gate can read the accepted operators out of this file.
local OPS = {
    ["<"]  = function(a, b) return a < b end,
    ["<="] = function(a, b) return a <= b end,
    [">"]  = function(a, b) return a > b end,
    [">="] = function(a, b) return a >= b end,
    ["=="] = function(a, b) return a == b end,
    ["~="] = function(a, b) return a ~= b end,
}

M.CHALLENGE_MODES = MODES
M.CHALLENGE_OPS = OPS
M.CHALLENGE_RUN_SUFFIX = RUN_SUFFIX
M.CHALLENGE_SEQ_SUFFIX = SEQ_SUFFIX
M.CHALLENGE_LIFE_SEQ = LIFE_SEQ

local function reject(id, why)
    M.log("challenge", "declare REJECTED '" .. tostring(id) .. "': " .. why)
    return false
end

-- Clauses do not nest: nesting is where a declarative filter becomes a language the gate cannot
-- read. A condition that wants it is either two challenges or one new atom.
local function badClause(c)
    if type(c) ~= "table" then return "a clause must be a table" end
    if #c ~= 3 then return "a clause must be { atom, operator, value }" end
    if type(c[1]) ~= "string" then return "a clause atom must be a string" end
    if OPS[c[2]] == nil then return "unknown operator '" .. tostring(c[2]) .. "'" end
    local vt = type(c[3])
    if vt ~= "number" and vt ~= "string" and vt ~= "boolean" then
        return "a clause value must be a number, string or boolean"
    end
    return nil
end

local function badClauseList(list, field)
    if list == nil then return nil end
    if type(list) ~= "table" then return field .. " must be an array of clauses" end
    for i = 1, #list do
        local why = badClause(list[i])
        if why ~= nil then return field .. "[" .. i .. "]: " .. why end
    end
    return nil
end

function M.declareChallenge(def)
    if type(def) ~= "table" then return reject("?", "not a table") end
    local id = def.id
    if type(id) ~= "string" then return reject(id, "no id") end
    if byId[id] ~= nil then return reject(id, "already declared") end

    local w = def.when
    if type(w) ~= "table" then return reject(id, "no `when` table") end
    if type(w.trigger) ~= "string" then return reject(id, "`when.trigger` must be a string") end
    if MODES[w.count] == nil then
        return reject(id, "unknown count mode '" .. tostring(w.count) .. "'")
    end

    local why = badClauseList(w.all, "all")
    if why ~= nil then return reject(id, why) end

    -- An unknown key is a typo or a feature that does not exist, and either way the clause the
    -- author meant is silently absent, leaving a challenge that fires on EVERY trigger event.
    -- That is the fail-open case this layer is built to avoid, so it is refused.
    for k in pairs(w) do
        if WHEN_KEYS[k] == nil then
            return reject(id, "unknown `when` field '" .. tostring(k) .. "'")
        end
    end

    -- These modes write a literal 1, so a higher target could never be met.
    if (w.count == "once" or w.count == "burst") and def.target ~= 1 then
        return reject(id, "count '" .. w.count .. "' writes 1, so target must be 1")
    end
    if w.count == "best" and type(w.value) ~= "string" then
        return reject(id, "count 'best' needs `value` naming the atom to record")
    end
    if w.count == "unique" and type(w.uniqueBy) ~= "string" then
        return reject(id, "count 'unique' needs `uniqueBy` naming the atom to dedup on")
    end
    if w.count == "streak" then
        if type(w.reset) ~= "table" or type(w.reset.trigger) ~= "string" then
            return reject(id, "count 'streak' needs `reset = { trigger = ... }`")
        end
    end
    if w.count == "burst" then
        if type(w.window) ~= "number" or w.window <= 0 then
            return reject(id, "count 'burst' needs a positive `window` in seconds")
        end
        -- A burst of one is just `once`, with a ring buffer to answer what a flag answers.
        if type(w.need) ~= "number" or w.need < 2 then
            return reject(id, "count 'burst' needs `need` of at least 2")
        end
    end

    if type(def.stat) ~= "string" then return reject(id, "no stat key") end

    -- Two challenges on one key is a data race, not a duplicate row: a `once` binding writing 1
    -- clobbers an `each` binding's running total, and the counter appears to go backwards.
    local runKey, seqKey = def.stat .. RUN_SUFFIX, def.stat .. SEQ_SUFFIX
    for _, key in ipairs({ def.stat, runKey, seqKey }) do
        local owner = byStat[key]
        if owner ~= nil then
            return reject(id, "stat '" .. key .. "' is already bound by '" .. owner .. "'")
        end
    end

    local row = {
        id = id,
        stat = def.stat,
        target = def.target,
        when = w,
        runKey = runKey,
        seqKey = seqKey,
    }
    challenges[#challenges + 1] = row
    byId[id] = row
    byStat[def.stat] = id
    if w.count == "streak" or w.count == "life" then byStat[runKey] = id end
    if w.count == "life" then byStat[seqKey] = id end
    return true
end

function M.getChallenges() return challenges end
function M.getChallenge(id) return byId[id] end

-- `==` and `~=` never throw; the relational operators throw only across types. A type check
-- answers the same question without a protected call, on a path that runs per zombie death.
local function compare(opName, a, b)
    if opName == "==" then return a == b end
    if opName == "~=" then return a ~= b end
    if type(a) ~= type(b) then return false end
    local op = OPS[opName]
    if op == nil then return false end
    return op(a, b)
end

--- `read(ctx, atom)` is injected, which keeps this file free of the engine and lets the suite
--- prove an atom no clause names is never read.
---
--- A nil atom makes its clause FALSE. Unlocking on a failed read would hand every player the
--- whole category on a build where one accessor moved.
function M.evalWhen(when, ctx, read)
    local all = when.all
    if all ~= nil then
        for i = 1, #all do
            local c = all[i]
            local v = read(ctx, c[1])
            if v == nil then return false end
            if OPS[c[2]] == nil then return false end
            if not compare(c[2], v, c[3]) then return false end
        end
    end
    return true
end

--- A run tagged with an older life sequence belongs to a survivor who is gone.
function M.challengeRunValue(run, seq, liveSeq)
    if type(run) ~= "number" then return 0 end
    if seq ~= liveSeq then return 0 end
    return run
end

--- Mutated in place and returned by identity: a fresh table per zombie death is what the kill
--- path forbids.
function M.burstPush(ring, now, window, need)
    if type(ring) ~= "table" or type(now) ~= "number" then return false end
    local cut = now - window
    local n = 0
    for i = 1, #ring do
        local t = ring[i]
        if t > cut then
            n = n + 1
            ring[n] = t
        end
    end
    n = n + 1
    ring[n] = now
    for i = n + 1, #ring do ring[i] = nil end
    while n > need do
        for i = 1, n - 1 do ring[i] = ring[i + 1] end
        ring[n] = nil
        n = n - 1
    end
    return n >= need
end

M.status("Challenge", true)
