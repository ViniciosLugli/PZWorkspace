require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Backfill"

-- Seed ambient stats silently at boot to prevent periodic timers spamming toasts later.
local function seedStats(player)
    if player == nil then return end

    local hours = nil
    local okH, h = pcall(function() return player:getHoursSurvived() end)
    if okH and type(h) == "number" and h > 0 then
        hours = h
        M.setStatIfGreater(player, "days_survived", math.floor(h / 24))
    end
    if hours ~= nil then
        local okA, awake = pcall(function()
            return hours - player:getLastHourSleeped()
        end)
        if okA and type(awake) == "number" and awake > 0 then
            M.setStatIfGreater(player, "awake_hours_best", math.floor(awake))
        end
    end

    if player.getKnownRecipes ~= nil then
        local okR, rec = pcall(function() return player:getKnownRecipes() end)
        if okR and rec ~= nil and rec.size ~= nil then
            M.setStatIfGreater(player, "recipes_known", rec:size())
        end
    end

    local WATCHED_PERKS = {
        Woodwork   = "perk_woodwork",
        Doctor     = "perk_doctor",
        Mechanics  = "perk_mechanics",
        Blacksmith = "perk_blacksmith",
    }
    if Perks ~= nil and player.getPerkLevel ~= nil then
        for perkName, stat in pairs(WATCHED_PERKS) do
            local p = Perks[perkName]
            if p ~= nil then
                local okL, lvl = pcall(function() return player:getPerkLevel(p) end)
                if okL and type(lvl) == "number" and lvl > 0 then
                    M.setStatIfGreater(player, stat, lvl)
                end
            end
        end
    end
    if PerkFactory ~= nil and PerkFactory.PerkList ~= nil and player.getPerkLevel ~= nil then
        local okList, list = pcall(function() return PerkFactory.PerkList end)
        if okList and list ~= nil and list.size ~= nil then
            local maxLvl = 0
            for i = 0, list:size() - 1 do
                local perk = list:get(i)
                if perk ~= nil then
                    local okL, lvl = pcall(function() return player:getPerkLevel(perk) end)
                    local okId, id = pcall(function() return perk:getId() end)
                    if okL and okId and type(lvl) == "number" and type(id) == "string" then
                        if lvl > maxLvl then maxLvl = lvl end
                        if lvl >= 1  then M.addUnique(player, "perks_at_1", id) end
                        if lvl >= 3  then M.addUnique(player, "perks_at_3", id) end
                        if lvl >= 5  then M.addUnique(player, "perks_at_5", id) end
                        if lvl >= 10 then M.addUnique(player, "perks_at_10", id) end
                    end
                end
            end
            if maxLvl > 0 then
                M.setStatIfGreater(player, "perk_max_level", maxLvl)
            end
        end
    end

    local inv = player:getInventory()
    if inv ~= nil then
        local okW, w = pcall(function() return inv:getContentsWeight() end)
        if okW and type(w) == "number" then
            M.setStatIfGreater(player, "heaviest_container", math.floor(w))
        end
        local okItems, items = pcall(function() return inv:getItems() end)
        if okItems and items ~= nil and items.size ~= nil then
            local n = items:size()
            for i = 0, n - 1 do
                local item = items:get(i)
                if item ~= nil then
                    local okT, full = pcall(function() return item:getFullType() end)
                    if okT and type(full) == "string" then
                        M.addUnique(player, "item_types", full)
                        if full == "Base.Spiffo" then M.setStat(player, "saw_spiffo", 1) end
                        if full == "Base.SpiffoBig" then M.setStat(player, "saw_bigspiffo", 1) end
                        if full == "Base.Sledgehammer" or full == "Base.Sledgehammer2" or full == "Base.SledgehammerForged" then
                            M.setStat(player, "saw_sledgehammer", 1)
                        end
                    end
                end
            end
        end
    end

    local okSq, square = pcall(function() return player:getCurrentSquare() end)
    if okSq and square ~= nil then
        local okR, region = pcall(function() return square:getSquareRegion() end)
        if okR and type(region) == "string" and region ~= "General" then
            M.addUnique(player, "regions_seen", region)
            if region == "Louisville" then M.setStat(player, "saw_louisville", 1) end
        end
        local okZ, z = pcall(function() return player:getZ() end)
        if okZ and type(z) == "number" and z < 0 then
            M.setStat(player, "saw_basement", 1)
        end
    end
end

-- Silent backfill catches up with existing progress without toast spam.
local h = M.addHandler(PART, "OnCreatePlayer", function(playerIndex, player)
    if player == nil then return end
    local ok, fired = M.quietly(function()
        seedStats(player)
        return M.recheckAll(player)
    end)
    if ok and type(fired) == "number" and fired > 0 then
        M.log("boot", "backfilled " .. fired .. " achievement(s) this character had already met")
    end
end)

if h ~= nil then M.status(PART, true) end
