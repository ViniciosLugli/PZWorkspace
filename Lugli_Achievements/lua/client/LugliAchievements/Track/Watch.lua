require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Polled states"

-- The three things the engine never announces, so all three must be SAMPLED. Two rates, chosen
-- by how long the evidence stays visible: the hat and the fracture are states that are still
-- true on the next tick, so they ride the ten-minute poll. The surprise is a sound about a
-- second long, which that poll would miss entirely.
local STARTLE_ALIAS = "ZombieSurprisedPlayer"

-- The only OnTick in the mod, and it earns it: a Lua increment and a compare on nine frames out
-- of ten, one Java call on the tenth. Ten frames is a sixth of a second at 60 fps.
local STARTLE_EVERY = 10

local WIZARD_HAT = "Base.Hat_Wizard"

local ticks = 0

-- Was the surprise already sounding at the previous poll, per split-screen player index. This
-- is what makes one surprise one count, rather than one per poll it spans.
local sounding = {}

-- Which body part indices were fractured at the previous poll, per player index.
local fractured = {}

--- getEmitter() hands back a dummy emitter when sound is off rather than nil, and a dummy is
--- free to answer isPlaying by throwing.
local function isStartleSounding(player)
    local ok, playing = pcall(function()
        return player:getEmitter():isPlaying(STARTLE_ALIAS)
    end)
    return ok and playing == true
end

local function onTick()
    ticks = ticks + 1
    if ticks < STARTLE_EVERY then return end
    ticks = 0
    M.forEachLocalPlayer(function(player, idx)
        local now = isStartleSounding(player)
        if now and not sounding[idx] then M.incStat(player, "startled", 1) end
        sounding[idx] = now
    end)
end

--- Worn, not carried: the inventory walk in the item tracker would otherwise credit somebody
--- who found a hat and never put it on. Set-once, so the walk stops for the rest of the save.
local function checkWizardHat(player)
    if M.getStat(player, "wore_wizard_hat") > 0 then return end
    pcall(function()
        local worn = player:getWornItems()
        if worn == nil then return end
        for i = 0, worn:size() - 1 do
            local slot = worn:get(i)
            local item = slot ~= nil and slot:getItem() or nil
            if item ~= nil and item:getFullType() == WIZARD_HAT then
                M.setStat(player, "wore_wizard_hat", 1)
                return
            end
        end
    end)
end

--- The CROSSING is the achievement: a part that has never been fractured also reads zero, so a
--- part only becomes interesting after it has been seen broken. "Not above zero" rather than
--- "equal to zero" because getFractureTime is a float, and undershooting is still healed.
local function checkFractures(player, idx)
    if M.getStat(player, "fracture_healed") > 0 then
        fractured[idx] = nil
        return
    end
    local okP, parts = pcall(function() return player:getBodyDamage():getBodyParts() end)
    if not okP or parts == nil then return end
    local okN, count = pcall(function() return parts:size() end)
    if not okN or type(count) ~= "number" then return end

    local was = fractured[idx]
    if was == nil then
        was = {}
        fractured[idx] = was
    end
    for i = 0, count - 1 do
        local okT, remaining = pcall(function() return parts:get(i):getFractureTime() end)
        if okT and type(remaining) == "number" then
            if remaining > 0 then
                was[i] = true
            elseif was[i] then
                was[i] = nil
                M.setStat(player, "fracture_healed", 1)
            end
        end
    end
end

local function onEveryTenMinutes()
    M.forEachLocalPlayer(function(player, idx)
        checkWizardHat(player)
        checkFractures(player, idx)
    end)
end

M.addHandler(PART, "OnTick", onTick)
M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.status(PART, true)
