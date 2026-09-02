require "LugliAchievements/Registry"
require "LugliAchievements/Toast"

local M = LugliAchievements
local PART = "Milestone tracking"

-- Category id -> the stat that says it is finished. A table rather than a concatenation, so the
-- content gate can see the keys: built with ".." it read the literal prefix as the stat name.
--
-- There is deliberately no entry for `milestones` itself. Counted among the categories it
-- requires, the capstone could never unlock: it would always be one short of itself.
--
-- Nor for `challenges`. Those are one-off situations, several of which depend on a world seed
-- or a run going badly in a specific way, so gating the capstone on them would make it a matter
-- of luck rather than of playing the game through. `cats_done` therefore tops out at 11.
local CATEGORY_STAT = {
    waking_up        = "cat_done_waking_up",
    body_count       = "cat_done_body_count",
    still_breathing  = "cat_done_still_breathing",
    autodidact       = "cat_done_autodidact",
    nailed_it        = "cat_done_nailed_it",
    homestead        = "cat_done_homestead",
    field_medicine   = "cat_done_field_medicine",
    roadside         = "cat_done_roadside",
    house_proud      = "cat_done_house_proud",
    how_you_died     = "cat_done_how_you_died",
    secrets          = "cat_done_secrets",
}

-- Reached through CATEGORY_STAT, so the gate cannot see these as literals.
local DECLARED_STATS = {
    "cat_done_waking_up", "cat_done_body_count", "cat_done_still_breathing",
    "cat_done_autodidact", "cat_done_nailed_it", "cat_done_homestead",
    "cat_done_field_medicine", "cat_done_roadside", "cat_done_house_proud",
    "cat_done_how_you_died", "cat_done_secrets",
}

--- Measures the SAVE, not the survivor: killing five hundred zombies without ever firing a gun
--- cannot be held by the same character who fired one, so per-character counting would make a
--- hundred percent impossible by construction. Hence slot.inSave rather than slot.unlocked.
local function recheck(player)
    if player == nil then return end
    local s = M.getSummary(player)
    if s == nil or s.byCategory == nil then return end

    local done = 0
    for id, slot in pairs(s.byCategory) do
        local key = CATEGORY_STAT[id]
        if key ~= nil and slot.total > 0 and slot.inSave >= slot.total then
            done = done + 1
            M.setStat(player, key, 1)
        end
    end
    M.setStatIfGreater(player, "cats_done", done)
end

--- Re-entrancy guard: writing a stat here unlocks a milestone, which fires this handler again,
--- which without the flag is unbounded recursion on the last achievement of a category.
local inside = false

local function onUnlocked(player)
    if inside then return end
    inside = true
    pcall(recheck, player)
    inside = false
end

-- Also on load, so a save that completed a category under an older version catches up rather
-- than waiting for one more unlock that may never come.
--
-- QUIET, like every other load-time backfill. This one was not, and it is a catch-up path that
-- can unlock: a save sitting on a finished category announced its milestone with a toast and a
-- chime every time the world loaded. Boot.lua's own quiet window does not cover this, because
-- these are two separate handlers on OnCreatePlayer with no ordering guarantee between them.
M.addHandler(PART, "OnCreatePlayer", function()
    M.quietly(function() M.forEachLocalPlayer(recheck) end)
end)

-- Chained, not assigned: Toast owns this hook and requiring it above is what guarantees it has
-- already installed. Runs on the unlock rather than on a timer, since nothing here can change
-- unless an achievement was just unlocked.
local previous = M.onUnlocked
M.onUnlocked = function(player, def)
    if previous ~= nil then pcall(previous, player, def) end
    onUnlocked(player)
end

M.status(PART, true, "category completion and the capstone")
