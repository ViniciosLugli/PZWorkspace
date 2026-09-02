--[[
    Crack
    Cracking a stick, and the timed action that does it.
]]

require "LugliEmergencyLights/Core"
require "TimedActions/ISBaseTimedAction"
require "LugliEmergencyLights/Items"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- Crack -------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Crack"

    --- Swap one sealed item for its lit form, IN THE HAND. Returns the new item, or nil.
    ---
    --- WHO MAKES THE SWAP IS THE WHOLE MULTIPLAYER CORRECTNESS OF THIS MOD. A multiplayer client
    --- cannot create an inventory item: ItemContainer.AddItem has no network effect, so an item
    --- minted here would exist on this machine and nowhere else. The server's copy of the
    --- inventory would keep the sealed one, EquipPacket.processServer resolves the equipped item
    --- by id against that copy and would find nothing, so every other player would see an empty
    --- hand and no light; and the throw's server-side drop, which lands the sender's OWN item,
    --- would refuse it and hand the stick back. Vanilla mints items on the server for the same
    --- reason (server/ClientCommands.lua: AddItem, sendAddItemToContainer, setPrimaryHandItem,
    --- sendEquip), and so does this: in multiplayer the client asks, the authority swaps
    --- (World.lua's authoritySwap) and the engine's own inventory and equip packets carry the
    --- result back. In single player this process is the authority and swaps directly.
    function M.crackHeld(player, item)
        if player == nil or item == nil then return nil end
        local litType = M.LIT_OF[item:getFullType()]
        if litType == nil then return nil end

        local info = M.LIT[litType]
        if info == nil then
            M.defect(PART, "no lit record for " .. tostring(litType))
            return nil
        end

        -- NOT AN ITEM LYING ON THE GROUND.
        if item:getWorldItem() ~= nil then return nil end

        -- The crack is a noise wherever it happens. WorldSoundManager replicates from a client, so
        -- this is said once, here, and not again by the server.
        local sq = player:getCurrentSquare()
        if sq ~= nil then
            M.noiseAt(player, sq:getX(), sq:getY(), sq:getZ(), M.cfg("CrackNoise"))
        end

        if M.isMultiplayer() then
            if M.sendCrack ~= nil and M.sendCrack(player, item, info.family) then return item end
            M.defect(PART, "could not ask the server to crack " .. tostring(item:getFullType()))
            return nil
        end

        if M.authoritySwap == nil then
            M.defect(PART, "no authority swap on this build; the sealed item is untouched")
            return nil
        end
        local lit, location = M.authoritySwap(player, item, litType, M.burnHours(info.family))
        if lit == nil then
            M.defect(PART, "crack refused: " .. tostring(location))
            return nil
        end
        -- AND BACK ONTO THE BELT. Cracking mints a new item, and an attachment lives on the ITEM, so
        -- without this the stick you cracked fell off your belt and the replacement appeared loose in
        -- your bag.
        if location ~= nil and M.reattachAt ~= nil then M.reattachAt(player, lit, location) end
        return lit
    end

    --- Queue the whole gesture: bring it to the hand, then perform the act.
    local function queueCrack(player, item, family)
        if player == nil or item == nil or family == nil then return false end
        if ISTimedActionQueue == nil or LugliEL_CrackAction == nil then return false end

        -- QUEUE AN EQUIP ONLY WHEN THE ITEM IS SOMEWHERE ELSE, and set the hand ourselves otherwise.
        local remote = false
        if luautils ~= nil and luautils.haveToBeTransfered ~= nil then
            local ok, v = pcall(luautils.haveToBeTransfered, player, item)
            if ok then remote = v == true end
        end

        if remote and ISInventoryPaneContextMenu ~= nil then
            -- Genuinely elsewhere: vanilla walks to the container and transfers, which is worth the
            -- queued action and which we have no wish to reimplement.
            pcall(function()
                ISInventoryPaneContextMenu.equipWeapon(item, true, false, player:getPlayerNum())
            end)
        end

        local ok = pcall(function()
            ISTimedActionQueue.add(LugliEL_CrackAction:new(player, item, family))
        end)
        return ok
    end

    --- The label for a family, falling back to the generic verb rather than to a raw key.
    local function verbFor(family)
        return M.T("ContextMenu_LugliEL_Crack_" .. tostring(family),
                   M.T("ContextMenu_LugliEL_Crack", "Crack"))
    end

    local function onContext(playerNum, context, items)
        local player = getSpecificPlayer(playerNum)
        if player == nil then return end

        -- ONE item, and one family. A multi-select spanning two families cannot be labelled with one
        -- verb without lying about the other, and cracking a whole stack at once was never wanted:
        -- each one is a separate physical act with its own animation.
        local list = M.selectedItems(items)
        local item, family = nil, nil
        for i = 1, #list do
            local f = M.sealedFamily(list[i])
            if f ~= nil then
                -- An item on the FLOOR reports the loot window's throwaway container, so cracking it
                -- would act on a container the next refresh wipes. Those are excluded here rather
                -- than failing later inside the action.
                if list[i]:getWorldItem() == nil then
                    item, family = list[i], f
                    break
                end
            end
        end
        if item == nil then return end

        -- On top, not appended: cracking is the only thing you ever do to a sealed stick, so it has
        -- no business sitting below a dozen generic options.
        local option = context:addOptionOnTop(
            verbFor(family),
            item,
            function(it) queueCrack(player, it, family) end)

        local tip = ISToolTip:new()
        tip:setName(verbFor(family))
        tip.description = M.T("ContextMenu_LugliEL_CrackTooltip_" .. tostring(family),
            M.T("ContextMenu_LugliEL_CrackTooltip", "Snap it once. It cannot be put out."))
        option.toolTip = tip
    end

    -- Double-click cracks, so the common case costs one gesture instead of three.
    local function hookDoubleClick()
        if ISInventoryPane == nil or type(ISInventoryPane.doContextualDblClick) ~= "function" then
            M.status(PART, false, "ISInventoryPane.doContextualDblClick is not on this build", "dep")
            return
        end
        if ISInventoryPane._lugliEL_dblClick then return end
        local original = ISInventoryPane.doContextualDblClick
        ISInventoryPane.doContextualDblClick = function(self, item)
            -- Same gesture as the menu option, so the two cannot drift apart. A floor item is left
            -- to vanilla: it reports the loot window's throwaway container, and vanilla only routes
            -- a double click here for items already in the player's own inventory anyway.
            if item ~= nil and item:getWorldItem() == nil then
                local family = M.sealedFamily(item)
                if family ~= nil then
                    local player = getSpecificPlayer(self.player)
                    if player ~= nil and queueCrack(player, item, family) then
                        return
                    end
                end
            end
            return original(self, item)
        end
        ISInventoryPane._lugliEL_dblClick = true
    end

    local h = M.addHandler(PART, "OnFillInventoryObjectContextMenu", onContext)

    -- After every other mod has had its turn at the class.
    M.addHandler(PART, "OnGameStart", hookDoubleClick)

    if h ~= nil then M.status(PART, true) end
end

-- ---- CrackAction -------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights

    -- BORROWED MOTIONS, because there is no other kind available.
    local ANIM = {
        GlowStick = "RipSheets",
        ChemLight = "RipSheets",
        RoadFlare = "OpenBeerBottle",
    }

    -- The model shown in hand while the motion plays.
    local HAND_MODEL = {
        GlowStick = "LugliEmergencyLights.GlowStick_Ground",
        ChemLight = "LugliEmergencyLights.ChemLight_Ground",
        RoadFlare = "LugliEmergencyLights.RoadFlare_Ground",
    }

    -- THE MOVING VARIANT, and this is the difference between an animation and no animation.
    local WALK_ANIM = {
        GlowStick = "MixFluids",
        ChemLight = "MixFluids",
        RoadFlare = "OpenAmmoBox",
    }

    local RUN_ANIM = {
        GlowStick = "InsertBullets",
        ChemLight = "InsertBullets",
        RoadFlare = "OpenAmmoBox",
    }

    local MAX_TIME = { GlowStick = 45, ChemLight = 45, RoadFlare = 60 }

    -- CRACKING ON THE MOVE COSTS TIME, IT DOES NOT FORBID IT.
    local PENALTY_WALK = 1.15
    local PENALTY_RUN  = 1.25

    LugliEL_CrackAction = ISBaseTimedAction:derive("LugliEL_CrackAction")

    --- Polled every character update.
    function LugliEL_CrackAction:isValid()
        if self.done then return false end

        -- Re-resolved by ID rather than trusting the cached reference, as vanilla's own equip action
        -- does. The flat main-inventory lookup is the right one: the equip queued ahead of us has
        -- already transferred the item out of whatever bag or crate it was in.
        local item = self.character:getInventory():getItemWithID(self.itemId)
        if item == nil then return false end

        -- Still crackable? Guards against another mod swapping the type under us.
        if M.LIT_OF[item:getFullType()] == nil then return false end
        self.item = item

        -- NO HAND TEST HERE, and that is a multiplayer correctness point rather than laxity.
        return true
    end

    function LugliEL_CrackAction:waitToStart()
        return false
    end

    function LugliEL_CrackAction:start()
        -- CAPTURED HERE, NOT IN new().
        self.baseMax = self.maxTime
        self.penaltyNow = self:penalty()
        if self.baseMax ~= nil and self.baseMax > 1 and self.penaltyNow ~= 1.0 then
            -- Started already moving: price it from the first frame rather than waiting for a change
            -- that may never come.
            local newMax = math.floor(self.baseMax * self.penaltyNow + 0.5)
            pcall(function() self.action:setTime(newMax < 1 and 1 or newMax) end)
        end

        -- INTO THE HAND, HERE, rather than through a queued equip action.
        pcall(function()
            if self.character:getPrimaryHandItem() ~= self.item
                and self.character:getSecondaryHandItem() ~= self.item then
                self.character:setPrimaryHandItem(self.item)
            end
        end)

        -- ORDER MATTERS: the hand-model override goes in before the animation, or the motion plays
        -- with nothing in the hand.
        self:setOverrideHandModelsString(HAND_MODEL[self.family], nil)

        -- ONE ARGUMENT ONLY.
        self:setActionAnim(ANIM[self.family] or "RipSheets")
        self.animGait = "still"

        -- THE SOUND GOES HERE, not in perform.
        M.playOn(self.character, M.SND_CRACK)
    end

    --- 1.0 standing, 1.15 walking, 1.25 running. Sprinting counts as running: it is a faster run, not
    --- a third state, and pricing it separately would be a number nobody asked for.
    function LugliEL_CrackAction:penalty()
        local ok, v = pcall(function()
            if self.character:isRunning() or self.character:isSprinting() then return PENALTY_RUN end
            if self.character:isPlayerMoving() then return PENALTY_WALK end
            return 1.0
        end)
        if not ok or type(v) ~= "number" then return 1.0 end
        return v
    end

    --- RESCALE THE TOTAL AND KEEP THE FRACTION, which is the only version of this that survives a
    --- player changing their mind halfway through.

    --- Play the motion that fits what the feet are doing.
    function LugliEL_CrackAction:setMotionAnim(gait)
        if gait == self.animGait then return end
        self.animGait = gait
        local node
        if gait == "run" then
            node = RUN_ANIM[self.family] or "InsertBullets"
        elseif gait == "walk" then
            node = WALK_ANIM[self.family] or "MixFluids"
        else
            node = ANIM[self.family] or "RipSheets"
        end
        -- The hand model first, as in start(): a node change with no model behind it plays the motion
        -- with an empty hand for a frame.
        pcall(function()
            self:setOverrideHandModelsString(HAND_MODEL[self.family], nil)
            self:setActionAnim(node)
        end)
    end

    function LugliEL_CrackAction:update()
        -- The animation follows the feet, whatever the timing does below. Checked first so it still
        -- runs for the instant-action case, which returns early.
        local p = self:penalty()
        local gait = "still"
        if p == PENALTY_RUN then gait = "run"
        elseif p == PENALTY_WALK then gait = "walk" end
        self:setMotionAnim(gait)

        -- The debug instant-action cheat pins maxTime at 1, and an integer maxTime cannot express a
        -- 15% surcharge on 1. Nothing to price, so nothing to do.
        if self.baseMax == nil or self.baseMax <= 1 then return end
        if p == self.penaltyNow then return end

        local ok = pcall(function()
            local delta = self.action:getJobDelta()
            if type(delta) ~= "number" or delta ~= delta then delta = 0.0 end
            if delta < 0.0 then delta = 0.0 elseif delta > 1.0 then delta = 1.0 end

            local newMax = math.floor(self.baseMax * p + 0.5)
            if newMax < 1 then newMax = 1 end

            self.action:setTime(newMax)
            -- setJobDelta writes currentTime = maxTime * delta, so this restores the SAME fraction
            -- against the new total rather than the same elapsed time.
            self:setJobDelta(delta)
        end)
        -- Only the pricing failed, not the crack. Latching the state anyway means a failure cannot
        -- retry every single update for the rest of the action.
        self.penaltyNow = p
        if not ok then self.rescaleFailed = true end
    end

    --- Interruption. AND IT HAS TO CLEAR THE ANIMATION STATE ITSELF, because vanilla does not.
    function LugliEL_CrackAction:stop()
        -- ON self.action, NOT ON self.
        pcall(function() self.action:stopTimedActionAnim() end)
        ISBaseTimedAction.stop(self)
    end

    --- The only place the world changes.
    function LugliEL_CrackAction:perform()
        self.done = true                        -- isValid now returns false, so this cannot re-enter
        M.crackHeld(self.character, self.item)
        ISBaseTimedAction.perform(self)         -- must be last: dequeues and starts whatever follows
    end

    function LugliEL_CrackAction:new(character, item, family)
        local o = ISBaseTimedAction.new(self, character)
        o.item = item
        o.itemId = item:getID()                 -- the durable handle; the reference is not
        o.family = family
        o.done = false
        o.baseMax = nil                         -- set in start(), after adjustMaxTime has run
        o.penaltyNow = nil
        o.animGait = nil                        -- start() plays the standing node; update() swaps

        -- MOVING NO LONGER CANCELS IT; see the penalty table above.
        o.stopOnWalk = false
        o.stopOnRun = false
        o.stopOnAim = true

        o.ignoreHandsWounds = false             -- hurt hands should make this slower
        o.useProgressBar = true

        -- The explicit 1 is needed rather than relying on the scaler: adjustMaxTime only scales a
        -- maxTime above 1, so the instant-action debug cheat needs saying outright.
        o.maxTime = character:isTimedActionInstant() and 1 or (MAX_TIME[family] or 45)
        return o
    end
end
