require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Skill tracking"

-- Reached through WATCHED_PERKS, so the gate cannot see these as literals.
local DECLARED_STATS = {
    "perk_blacksmith",
    "perk_doctor",
    "perk_mechanics",
    "perk_woodwork",
}

-- Keyed by getId(), never getName(): getName() is the TRANSLATED label, so a player switching
-- language would start writing different keys. Three ids do not match their UI names at all --
-- Carpentry is Woodwork, First Aid is Doctor, Foraging is PlantScavenging.
local WATCHED_PERKS = {
    Woodwork   = "perk_woodwork",
    Doctor     = "perk_doctor",
    Mechanics  = "perk_mechanics",
    Blacksmith = "perk_blacksmith",
}

-- LevelPerk fires on LOSS as well as gain, and the fourth argument is what tells them apart.
local function onLevelPerk(character, perk, level, gained)
    if character == nil or perk == nil then return end
    if gained == false then
        M.incStat(character, "perk_levels_lost", 1)
        return
    end
    if type(level) ~= "number" then return end

    local id = nil
    local ok, v = pcall(function() return perk:getId() end)
    if ok and type(v) == "string" then id = v end
    if id == nil then return end

    M.setStatIfGreater(character, "perk_max_level", level)
    if level >= 1  then M.addUnique(character, "perks_at_1", id) end
    if level >= 3  then M.addUnique(character, "perks_at_3", id) end
    if level >= 5  then M.addUnique(character, "perks_at_5", id) end
    if level >= 10 then M.addUnique(character, "perks_at_10", id) end

    local stat = WATCHED_PERKS[id]
    if stat ~= nil then M.setStatIfGreater(character, stat, level) end
end

-- AddXP does not fire on a multiplayer client, so this total is a singleplayer figure.
local function onAddXP(character, perk, amount)
    if character == nil or type(amount) ~= "number" or amount <= 0 then return end
    M.incStat(character, "xp_total", amount)
end

--- ISReadABook:perform fires on FINISHING, because getDuration covers every remaining page.
local function onBookFinished(self)
    if self == nil or self.character == nil then return end
    local player = self.character
    M.incStat(player, "books_read", 1)

    local item = self.item
    if item == nil then return end
    local full = item:getFullType()
    if type(full) ~= "string" then return end

    -- getSkillTrained and getLearnedRecipes are declared on Literature, NOT on InventoryItem, so
    -- a modded readable that is not a Literature threw "Tried to call nil" once per read -- and
    -- through the action fan-out, where nothing logged it. Ask what the item is first.
    if instanceof == nil or not instanceof(item, "Literature") then return end

    -- A skill book is any item carrying SkillTrained; all 120 do, and nothing else does.
    local trained = item:getSkillTrained()
    if trained ~= nil and trained ~= "" then
        M.addUnique(player, "skill_books_read", full)
    else
        -- getLearnedRecipes, not the B41 getTeachedRecipes, which is absent on this build and
        -- inside a pcall reported every magazine as unread. Empty counts as none, since a plain
        -- novel must not be filed as a magazine.
        local list = item:getLearnedRecipes()
        if list ~= nil and not list:isEmpty() then
            M.addUnique(player, "magazines_read", full)
        end
    end
end

--- Known recipes is a count with no event behind it, so it is polled on the hour.
local function onEveryHours()
    M.forEachLocalPlayer(function(player)
        -- getKnownRecipes is a final field initialised at construction, so the list is never nil.
        if player.getKnownRecipes == nil then return end
        M.setStatIfGreater(player, "recipes_known", player:getKnownRecipes():size())
    end)
end

M.addHandler(PART, "LevelPerk", onLevelPerk)
M.addHandler(PART, "AddXP", onAddXP)
M.addHandler(PART, "EveryHours", onEveryHours)
M.addHandler(PART, "OnGameStart", function()
    M.onAction(PART, "ISReadABook", onBookFinished)
end)
M.status(PART, true)
