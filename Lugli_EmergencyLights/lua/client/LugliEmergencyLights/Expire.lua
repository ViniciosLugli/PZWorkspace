--[[
    Expire
    Burning out, and what the tooltip says about it.
]]

require "LugliEmergencyLights/Items"
require "LugliEmergencyLights/Time"
require "LugliEmergencyLights/Config"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- Expire ------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Expiry"

    local swapped = 0

    --- Replace one burnt-out item in place, keeping where it was.
    local function replace(player, container, item)
        local spentType = M.SPENT_OF[item:getFullType()]
        if spentType == nil then return false end

        -- Out of the hands first. Removing an equipped item without this leaves the character
        -- holding a reference to something no container owns. Which hand is REMEMBERED, because a
        -- flare that burns out is still a thing you were holding.
        local wasPrimary = player:getPrimaryHandItem() == item
        local wasSecondary = player:getSecondaryHandItem() == item
        pcall(function()
            if wasPrimary or wasSecondary then player:removeFromHands(item) end
        end)

        -- ADD FIRST, THEN REMOVE. The order is the whole safety property.
        local spent = nil
        local okAdd = pcall(function() spent = container:AddItem(spentType) end)
        if not okAdd or spent == nil then
            M.defect(PART, "could not create " .. tostring(spentType) .. "; leaving the item alone")
            -- Put it back where it was, since the hand was already emptied above.
            if wasPrimary then pcall(function() player:setPrimaryHandItem(item) end)
            elseif wasSecondary then pcall(function() player:setSecondaryHandItem(item) end) end
            return false
        end
        if not pcall(function() container:Remove(item) end) then
            -- The replacement exists but the original will not leave. Taking the replacement back out
            -- is the only way to avoid handing the player both.
            pcall(function() container:Remove(spent) end)
            M.defect(PART, "could not remove the burnt-out item; no swap made")
            return false
        end

        -- BACK INTO THE HAND IT BURNED OUT IN.
        if spent ~= nil then
            pcall(function()
                if wasPrimary then
                    player:setPrimaryHandItem(spent)
                elseif wasSecondary then
                    player:setSecondaryHandItem(spent)
                end
            end)
            -- And onto the belt it burned out on, for the same reason: an attachment lives on the item,
            -- so a swap silently drops it. Crack does the same in the other direction.
            M.moveAttachment(item, spent, player)
        end

        -- NO sendRemoveItemFromContainer FROM A CLIENT. It gets the player KICKED.
        swapped = swapped + 1
        return true
    end

    --- Walk a container and the containers inside it. Depth is bounded because a bag inside a bag
    --- inside a bag is not a case worth recursing forever for.
    local function walk(player, container, depth)
        if container == nil or depth > 3 then return end
        local items = container:getItems()
        if items == nil then return end

        -- Collected first, then acted on: removing from a container while iterating it skips entries.
        local dead, bags = {}, {}
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item ~= nil then
                -- NOT WHILE IT IS IN THE AIR. Kept as a guard rather than as a fix.
                local flying = M.isInFlight ~= nil and M.isInFlight(item)
                if M.litInfo(item) ~= nil and M.isExpired(item) and not flying then
                    dead[#dead + 1] = item
                elseif item:IsInventoryContainer() then
                    -- ASK, do not try. getInventory() exists only on InventoryContainer, while
                    -- IsInventoryContainer() is declared on InventoryItem itself and is therefore
                    local inner = item:getInventory()
                    if inner ~= nil and inner ~= container then
                        bags[#bags + 1] = inner
                    end
                end
            end
        end

        for i = 1, #dead do replace(player, container, dead[i]) end
        for i = 1, #bags do walk(player, bags[i], depth + 1) end
    end

    local function tick()
        -- NO pcall HERE. addTicker already drops and reports a part that throws, once. Wrapping the
        -- body swallows exactly that failure, so a real bug came back as 49 identical stack traces
        -- in one session instead of one defect line and silence.
        M.forEachLocalPlayer(function(player)
            walk(player, player:getInventory(), 0)
        end)
    end

    -- On the scan interval rather than every frame: an item that burned out a second ago has not
    -- hurt anyone, and this walks every bag the player is carrying.
    local h = M.addTicker(PART, M.scanInterval, tick)
    if h ~= nil then M.status(PART, true) end
end

-- ---- Tooltip -----------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Tooltip"

    local function round(n) return math.floor(n + 0.5) end

    --- Remaining life as a sentence, or nil.
    local function litLine(item)
        local hours = M.hoursLeft(item)
        if hours == nil then return nil end
        if hours <= 0 then
            return M.T("Tooltip_LugliEL_Spent", "Burnt out. Nothing left to give.")
        end
        local prefix = M.T("Tooltip_LugliEL_BurnsFor", "Burns for about")
        if hours < 1 then
            local mins = round(hours * 60)
            if mins < 1 then mins = 1 end
            return prefix .. " " .. mins .. " " .. M.T("Tooltip_LugliEL_UnitMinutes", "more minutes")
        end
        return prefix .. " " .. round(hours) .. " " .. M.T("Tooltip_LugliEL_UnitHours", "more hours")
    end

    --- What a sealed one promises, so the choice is informed before it is irreversible.
    local function sealedLine(item)
        local lit = M.LIT_OF[item:getFullType()]
        local info = lit ~= nil and M.LIT[lit] or nil
        if info == nil then return nil end
        local hours = M.burnHours(info.family)

        -- SUB-HOUR TOO, like the lit line.
        if type(hours) == "number" and hours < 1.0 then
            return M.T("Tooltip_LugliEL_Sealed", "Sealed.") .. " "
                .. M.T("Tooltip_LugliEL_SealedBurns", "Once cracked it burns for") .. " "
                .. round(hours * 60.0) .. " "
                .. M.T("Tooltip_LugliEL_UnitMinutesTotal", "minutes, and cannot be put out")
        end

        return M.T("Tooltip_LugliEL_Sealed", "Sealed.") .. " "
            .. M.T("Tooltip_LugliEL_SealedBurns", "Once cracked it burns for") .. " "
            .. round(hours) .. " "
            .. M.T("Tooltip_LugliEL_UnitHoursTotal", "hours, and cannot be put out")
    end

    --- What a cartridge will do, so the one round you have is not spent finding out. Read through
    --- the SAME two calls Gun.lua makes, never from the defaults: anything else is a promise the
    --- shot stops keeping the moment a slider moves.
    local function cartridgeLine(item)
        local cart = M.cartridgeInfo(item)
        if cart == nil then return nil end

        local tiles = M.cfg("AerialShotRange")
        if type(tiles) ~= "number" or tiles <= 0 then tiles = 30 end
        local secs = M.positive("AerialSeconds", cart.aloftSeconds)

        local line = M.T("Tooltip_LugliEL_CartFlight", "Fired high into the air, in the direction you aim,")
            .. " " .. M.T("Tooltip_LugliEL_CartUpTo", "out to") .. " " .. round(tiles) .. " "
            .. M.T("Tooltip_LugliEL_UnitTiles", "tiles.") .. " "

        -- The slider bottoms out at 30 s, which must not render as "0 minutes".
        if secs < 60 then
            return line .. M.T("Tooltip_LugliEL_CartHangs", "It hangs there burning for about") .. " "
                .. round(secs) .. " " .. M.T("Tooltip_LugliEL_UnitSecondsAloft", "seconds")
                .. " " .. M.T("Tooltip_LugliEL_UnitGameTime", "of in-game time.")
        end
        return line .. M.T("Tooltip_LugliEL_CartHangs", "It hangs there burning for about") .. " "
            .. round(secs / 60.0) .. " " .. M.T("Tooltip_LugliEL_UnitMinutesAloft", "minutes")
            .. " " .. M.T("Tooltip_LugliEL_UnitGameTime", "of in-game time.")
    end

    --- Make a finished sentence safe to hand to setTooltip.
    local function safeTip(text)
        if type(text) ~= "string" then return text end
        return (text:gsub("%%", "%%%%"))
    end

    local function describe(item)
        if M.litInfo(item) ~= nil then return litLine(item) end
        if M.LIT_OF[item:getFullType()] ~= nil then return sealedLine(item) end
        if M.cartridgeInfo(item) ~= nil then return cartridgeLine(item) end
        if M.SPENT[item:getFullType()] ~= nil then
            return M.T("Tooltip_LugliEL_Spent", "Burnt out. Nothing left to give.")
        end
        return nil
    end

    --- Drive the condition bar from remaining life.
    local function setBar(item)
        local frac = M.fractionLeft(item)
        if frac == nil then return end
        local n = round(frac * 100)
        if n < 1 then n = 1 end
        pcall(function()
            if item:getCondition() ~= n then item:setConditionNoSound(n) end
        end)
    end

    --- Walk a container and the bags inside it, to the same depth the expiry sweep uses.
    local function refresh(container, depth)
        if container == nil or depth > 3 then return end
        local items = container:getItems()
        if items == nil then return end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item ~= nil then
                local txt = describe(item)
                if txt ~= nil then
                    pcall(function() item:setTooltip(safeTip(txt)) end)
                    if M.litInfo(item) ~= nil then setBar(item) end
                elseif item:IsInventoryContainer() then
                    -- ASK, do not try. getInventory() exists only on InventoryContainer, while
                    -- IsInventoryContainer() is declared on InventoryItem itself. Kahlua's pcall does
                    -- NOT contain "Tried to call nil", so a speculative call cannot be guarded.
                    local inner = item:getInventory()
                    if inner ~= nil and inner ~= container then
                        refresh(inner, depth + 1)
                    end
                end
            end
        end
    end

    local function tick()
        M.forEachLocalPlayer(function(player)
            refresh(player:getInventory(), 0)
        end)
    end

    --- Bring one item's burn display up to date: the sentence and the gauge together.
    function M.refreshBurnDisplay(item)
        if item == nil then return end
        local txt = describe(item)
        if txt == nil then return end
        pcall(function() item:setTooltip(safeTip(txt)) end)
        if M.litInfo(item) ~= nil then setBar(item) end
    end

    -- Two seconds. A tooltip counts down in game HOURS, so refreshing it any faster
    -- redraws the same text.
    local h = M.addTicker(PART, 2.0, tick)
    if h ~= nil then M.status(PART, true) end
end
