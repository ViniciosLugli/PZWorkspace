require "LugliAchievements/Challenge"
-- Toast ASSIGNS M.onUnlocked rather than chaining it, so this file must load after it or its
-- own chain below would be clobbered. The loader sorts by path, which already puts toast.lua
-- first, but an ordering that depends on a filename is one rename away from failing silently.
require "LugliAchievements/Toast"

local M = LugliAchievements
local PART = "Challenges"

-- The engine half. ATOMS and TRIGGERS are the ONLY vocabulary: check-achievements.py reads both
-- out of this file, so a challenge naming one that does not exist fails the build.

-- Reached through M.CHALLENGE_LIFE_SEQ, so the gate cannot see it as a literal.
local INTERNAL_STATS = {
    "chal_life_seq",
}

-- A zombie landing a hit raises NO Lua event: BodyDamage.AddRandomDamageFromZombie contains no
-- triggerEvent, and OnPlayerGetDamage only fires for POISON, HUNGRY, SICK, BLEEDING, THIRST,
-- INFECTION, HEAVYLOAD, LOWWEIGHT, FALLDOWN, FIRE and vehicle damage. So "between one hit and
-- the next" cannot be built on that event. AddRandomDamageFromZombie does set the hit reaction
-- first, which is observable, so a rising edge on it is what a hit actually looks like.
local lastReaction = {}

--- A real clock, not getWorldAgeHours: that is in-game time, so a ten second window would be
--- under a second, and its float32 resolution collapses the window on an old save. nil, never
--- 0, when unreadable: a constant puts every stamp inside every window.
local function nowSeconds()
    if getTimestampMs == nil then return nil end
    local ok, t = pcall(getTimestampMs)
    if not ok or type(t) ~= "number" then return nil end
    return t / 1000
end

local function moodle(c, kind)
    local m = c.moodles
    if m == nil then return nil end
    return m:getMoodleLevel(kind)
end

--- No aggregate getter exists for fractures. Straight line, not a loop over a table literal:
--- that allocates per zombie death.
local function legFractured(c)
    local bd = c.bodyDamage
    if bd == nil then return nil end
    local p = bd:getBodyPart(BodyPartType.LowerLeg_L)
    if p ~= nil and p:getFractureTime() > 0 then return true end
    p = bd:getBodyPart(BodyPartType.LowerLeg_R)
    if p ~= nil and p:getFractureTime() > 0 then return true end
    return false
end

-- A nil return makes the clause false. The three shared Java handles are resolved once per
-- event on the context, not once per atom.
local ATOMS = {
    health_pct = function(c)
        if c.bodyDamage == nil then return nil end
        return c.bodyDamage:getOverallBodyHealth()
    end,
    bleeding_parts = function(c)
        if c.bodyDamage == nil then return nil end
        return c.bodyDamage:getNumPartsBleeding()
    end,
    leg_fractured = legFractured,

    on_fire  = function(c) return c.player:isOnFire() end,
    sneaking = function(c) return c.player:isSneaking() end,
    aiming   = function(c) return c.player:isAiming() end,

    moodle_panic     = function(c) return moodle(c, MoodleType.PANIC) end,
    moodle_endurance = function(c) return moodle(c, MoodleType.ENDURANCE) end,
    moodle_drunk     = function(c) return moodle(c, MoodleType.DRUNK) end,
    -- HEAVY_LOAD, not HEAVY: getMoodleLevel(nil) throws a box pcall cannot suppress.
    moodle_heavy     = function(c) return moodle(c, MoodleType.HEAVY_LOAD) end,

    -- numChasingZombies is a public INSTANCE field, which Kahlua reads as nil: getter only.
    chasing = function(c)
        if c.stats == nil then return nil end
        return c.stats:getNumChasingZombies()
    end,
    visible = function(c)
        if c.stats == nil then return nil end
        return c.stats:getNumVisibleZombies()
    end,

    night = function(c)
        if c.gameTime == nil then return nil end
        local h = c.gameTime:getHour()
        return h >= 19 or h < 6
    end,

    zombie_feeding    = function(c) return c.zombie ~= nil and c.zombie:getEatBodyTarget() ~= nil end,
    zombie_reanimated = function(c) return c.zombie ~= nil and c.zombie:isReanimatedPlayer() end,

    -- getFullType is save-stable; a Java identity would not be.
    weapon_type = function(c)
        local item = c.player:getPrimaryHandItem()
        if item == nil then return "base.unarmed" end
        return item:getFullType()
    end,
}

-- One table for the session. A generation counter invalidates every memo without walking pairs.
local ctx = {
    player = nil, playerIndex = nil, zombie = nil, gameTime = nil,
    bodyDamage = nil, moodles = nil, stats = nil,
    now = nil, nowGen = -1,
    val = {}, gen = {}, n = 0,
}

local function readAtom(c, name)
    if c.gen[name] == c.n then return c.val[name] end
    local fn = ATOMS[name]
    local v = nil
    if fn ~= nil then
        -- pcall with an argument, not a closure: a closure allocates per kill.
        local ok, got = pcall(fn, c)
        if ok then v = got end
    end
    c.val[name] = v
    c.gen[name] = c.n
    return v
end

--- Both bursts ask the same clock in one event, so it is read once.
local function ctxNow(c)
    if c.nowGen == c.n then return c.now end
    c.now = nowSeconds()
    c.nowGen = c.n
    return c.now
end

-- trigger name -> { rows..., n = count, dirty = bool }
local pending = {}
local resetsBy = {}   -- trigger name -> rows whose streak this trigger breaks
local burstRings = {} -- challenge id -> player index -> ring

local function listFor(map, key)
    local l = map[key]
    if l == nil then
        l = { n = 0, dirty = false }
        map[key] = l
    end
    return l
end

local function apply(row, player)
    local w = row.when
    local mode = w.count

    if mode == "each" then
        M.incStat(player, row.stat, 1)
    elseif mode == "once" then
        M.setStat(player, row.stat, 1)
    elseif mode == "best" then
        local v = readAtom(ctx, w.value)
        if type(v) == "number" then M.setStatIfGreater(player, row.stat, v) end
    elseif mode == "unique" then
        local id = readAtom(ctx, w.uniqueBy)
        if id ~= nil then M.addUnique(player, row.stat, id) end
    elseif mode == "streak" then
        local run = M.getStat(player, row.runKey) + 1
        M.setStat(player, row.runKey, run)
        M.setStatIfGreater(player, row.stat, run)
    elseif mode == "life" then
        local live = M.getStat(player, M.CHALLENGE_LIFE_SEQ)
        local run = M.challengeRunValue(M.getStat(player, row.runKey),
                                        M.getStat(player, row.seqKey), live) + 1
        M.setStat(player, row.runKey, run)
        M.setStat(player, row.seqKey, live)
        M.setStatIfGreater(player, row.stat, run)
    elseif mode == "burst" then
        local now = ctxNow(ctx)
        -- No clock, no burst.
        if now == nil then return end
        local perPlayer = burstRings[row.id]
        if perPlayer == nil then
            perPlayer = {}
            burstRings[row.id] = perPlayer
        end
        local idx = ctx.playerIndex or 0
        local ring = perPlayer[idx]
        if ring == nil then
            ring = {}
            perPlayer[idx] = ring
        end
        if M.burstPush(ring, now, w.window, w.need) then
            M.setStat(player, row.stat, 1)
        end
    end
end

--- Compact a pending list in place, dropping rows retired during the loop that just ran.
local function compact(list)
    if not list.dirty then return end
    local n = 0
    for i = 1, list.n do
        local row = list[i]
        if not row.done then
            n = n + 1
            list[n] = row
        end
    end
    for i = n + 1, list.n do list[i] = nil end
    list.n = n
    list.dirty = false
end

--- The hot path. Two operations when every challenge on this trigger is already earned.
local function fire(trigger, player, zombie, idx)
    local list = pending[trigger]
    if list == nil or list.n == 0 then return end

    ctx.player = player
    ctx.playerIndex = idx or M.playerIndex(player)
    ctx.zombie = zombie
    ctx.n = ctx.n + 1

    -- Guarded individually so one missing accessor nils its own atoms rather than throwing.
    local ok, got = pcall(player.getBodyDamage, player)
    ctx.bodyDamage = ok and got or nil
    ok, got = pcall(player.getMoodles, player)
    ctx.moodles = ok and got or nil
    ok, got = pcall(player.getStats, player)
    ctx.stats = ok and got or nil

    -- apply() reaches M.onUnlocked, whose hook edits this list. Mark done, compact after:
    -- removing in place would skip rows.
    local count = list.n
    for i = 1, count do
        local row = list[i]
        if row ~= nil and not row.done then
            if M.evalWhen(row.when, ctx, readAtom) then apply(row, player) end
        end
    end
    compact(list)
end

--- Every streak, whatever breaks it normally.
local function resetAllStreaks(player)
    local rows = M.getChallenges()
    for i = 1, #rows do
        local row = rows[i]
        if row.when.count == "streak" then M.setStat(player, row.runKey, 0) end
    end
end

local function fireReset(trigger, player)
    local list = resetsBy[trigger]
    if list == nil then return end
    for i = 1, list.n do
        local row = list[i]
        if not row.done then M.setStat(player, row.runKey, 0) end
    end
end

-- Same attribution test Track/Combat.lua uses. The index comes back with the killer because
-- finding it already walked every active player.
local function localKiller(zombie)
    local killer = zombie:getAttackedBy()
    if killer == nil then return nil, nil end
    local idx = M.playerIndex(killer)
    if idx == nil then return nil, nil end
    return killer, idx
end

-- Installed only if a shipped challenge names the trigger.
local TRIGGERS = {
    zombie_killed = function()
        M.addHandler(PART, "OnZombieDead", function(zombie)
            if zombie == nil then return end
            -- Ahead of attribution: once all are earned this is one table index per death.
            local list = pending.zombie_killed
            if list == nil or list.n == 0 then return end
            local player, idx = localKiller(zombie)
            if player == nil then return end
            fire("zombie_killed", player, zombie, idx)
        end)
    end,
    -- A rising edge on the hit reaction, per player update. Cheap because it leaves before the
    -- Java call once nothing is waiting on it.
    player_struck = function()
        M.addHandler(PART, "OnPlayerUpdate", function(character)
            if character == nil then return end
            local resets = resetsBy.player_struck
            local waiting = pending.player_struck
            if (resets == nil or resets.n == 0) and (waiting == nil or waiting.n == 0) then
                return
            end
            local idx = M.playerIndex(character)
            if idx == nil then return end
            local ok, reaction = pcall(character.getHitReaction, character)
            if not ok then return end
            local struck = type(reaction) == "string" and reaction ~= ""
            if struck and not lastReaction[idx] then
                fireReset("player_struck", character)
                fire("player_struck", character, nil, idx)
            end
            lastReaction[idx] = struck
        end)
    end,
    player_died = function()
        -- OnPlayerDeath is local-only, so this is the one trigger with no playerIndex guard.
        M.addHandler(PART, "OnPlayerDeath", function(player)
            if player == nil then return end
            -- Makes a dead survivor's run read as zero, which the per-world store would not.
            M.incStat(player, M.CHALLENGE_LIFE_SEQ, 1)
            -- Death breaks every streak. player_struck filters attrition, so dying of
            -- infection or hunger reaches no reset, and a run would otherwise carry across
            -- survivors and complete on the next one's first kill.
            resetAllStreaks(player)
            -- Fire like every other trigger, or a challenge naming player_died would pass the
            -- gate and never progress.
            fire("player_died", player, nil, nil)
        end)
    end,
    vehicle_entered = function()
        M.addHandler(PART, "OnEnterVehicle", function(player)
            if player == nil or M.playerIndex(player) == nil then return end
            fire("vehicle_entered", player, nil, nil)
        end)
    end,
    window_climbed = function()
        return M.onAction(PART, "ISClimbThroughWindow", function(self)
            if self == nil or self.character == nil then return end
            local idx = M.playerIndex(self.character)
            if idx == nil then return end
            fire("window_climbed", self.character, nil, idx)
        end)
    end,
    fence_climbed = function()
        return M.onAction(PART, "ISClimbOverFence", function(self)
            if self == nil or self.character == nil then return end
            local idx = M.playerIndex(self.character)
            if idx == nil then return end
            fire("fence_climbed", self.character, nil, idx)
        end)
    end,
    rope_climbed = function()
        return M.onAction(PART, "ISClimbSheetRopeAction", function(self)
            if self == nil or self.character == nil then return end
            local idx = M.playerIndex(self.character)
            if idx == nil then return end
            fire("rope_climbed", self.character, nil, idx)
        end)
    end,
    bandaged = function()
        return M.onAction(PART, "ISApplyBandage", function(self)
            if self == nil or self.character == nil then return end
            local idx = M.playerIndex(self.character)
            if idx == nil then return end
            fire("bandaged", self.character, nil, idx)
        end)
    end,
}

--- Under split screen with per-character progress, retiring on one player would stop the other
--- being credited.
local function retiredForEveryone(id)
    local any, all = false, true
    M.forEachLocalPlayer(function(player)
        any = true
        if not M.isUnlocked(player, id) then all = false end
    end)
    return any and all
end

--- Rebuild from what is still locked. Also called by Sync.lua after hydration: the server's
--- copy arrives already unlocked and fires no unlock event, so nothing would retire those rows.
function M.rebuildChallengeBindings()
    for k in pairs(pending) do pending[k] = nil end
    for k in pairs(resetsBy) do resetsBy[k] = nil end

    local rows = M.getChallenges()
    for i = 1, #rows do
        local row = rows[i]
        row.done = retiredForEveryone(row.id)
        if not row.done then
            local list = listFor(pending, row.when.trigger)
            list.n = list.n + 1
            list[list.n] = row
            local reset = row.when.reset
            if reset ~= nil then
                local rl = listFor(resetsBy, reset.trigger)
                rl.n = rl.n + 1
                rl[rl.n] = row
            end
        end
    end
end

--- Deferred: this runs inside fire()'s loop, through incStat -> onStatChanged -> doUnlock.
local function onUnlocked(player, def)
    local row = M.getChallenge(def.id)
    if row == nil then return end
    if not retiredForEveryone(def.id) then return end
    row.done = true
    local list = pending[row.when.trigger]
    if list ~= nil then list.dirty = true end
end

-- Chained, not assigned: Toast owns this hook. Same shape as Track/Meta.lua.
local previousUnlocked = M.onUnlocked
M.onUnlocked = function(player, def)
    if previousUnlocked ~= nil then pcall(previousUnlocked, player, def) end
    local ok, err = pcall(onUnlocked, player, def)
    if not ok then M.defect(PART, "retiring '" .. tostring(def.id) .. "' threw: " .. tostring(err)) end
end

M.addHandler(PART, "OnGameStart", function()
    if getGameTime ~= nil then
        local ok, gt = pcall(getGameTime)
        if ok then ctx.gameTime = gt end
    end

    -- Demand driven.
    local used, missing = {}, 0
    local rows = M.getChallenges()
    for i = 1, #rows do
        used[rows[i].when.trigger] = true
        local reset = rows[i].when.reset
        if reset ~= nil then used[reset.trigger] = true end
    end
    -- A per-life challenge needs the death hook even if nothing names player_died.
    for i = 1, #rows do
        if rows[i].when.count == "life" then used.player_died = true; break end
    end

    local n = 0
    for name in pairs(used) do
        local install = TRIGGERS[name]
        if install == nil then
            missing = missing + 1
            M.defect(PART, "no installer for trigger '" .. tostring(name) .. "'")
        elseif install() == false then
            -- onAction returns false when the class is gone from the build. Ignoring it
            -- reported "25 challenge(s) on 8 trigger(s)" in green while three were dead.
            missing = missing + 1
        else
            n = n + 1
        end
    end

    M.rebuildChallengeBindings()

    if missing == 0 then
        M.status(PART, true, #rows .. " challenge(s) on " .. n .. " trigger(s)")
    else
        M.status(PART, false, missing .. " trigger(s) have no installer", "bug")
    end
end)

M.addHandler(PART, "OnCreatePlayer", function()
    M.rebuildChallengeBindings()
end)

M.status(PART, nil, "checked when you load a world", "pending")
