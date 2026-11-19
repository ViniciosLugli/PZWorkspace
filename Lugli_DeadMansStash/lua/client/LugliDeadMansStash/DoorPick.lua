--[[
    DoorPick (client)
    The Locksmith's "Pick the lock" on a locked building door: the menu entry, the walk, the timed
    action and the answer. The rule and the authority are shared/Doors.lua; this file only
    describes and asks.

    The entry is offered to a Locksmith outside a pickable door only, and greyed with its reason
    when the tool is missing or the door is someone else's safehouse. The walk is vanilla's for a
    door (luautils.walkAdjWindowOrDoor), which stays on the survivor's side of it. The action
    claims as it starts and submits as it ends, as a box route does (Actions.lua), with the box
    pick's sounds (Sounds.lua) and its pose standing up: vanilla's container search at mid height.
]]

require "TimedActions/ISBaseTimedAction"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Sounds"
require "LugliDeadMansStash/Doors"
require "LugliDeadMansStash/Actions"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "DoorPick"

    local GOOD = " <RGB:0.6,0.9,0.6> "
    local BAD = " <RGB:0.95,0.6,0.5> "
    local PLAIN = " <RGB:1,1,1> "

    -- The pick's pins, as the box pick's work panel counts them (WorkPanel.lua LOOKS.pick).
    M.DOOR_PICK_STEPS = 5

    local function halo(player, text, good)
        if HaloTextHelper == nil or player == nil or text == nil then return end
        pcall(function()
            if good then HaloTextHelper.addGoodText(player, text) else HaloTextHelper.addBadText(player, text) end
        end)
    end

    local function reasonText(reason)
        return M.T(reason, M.T("IGUI_LugliDMS_Refused", "That did not work."))
    end

    local function nameOf(item)
        if item == nil then return nil end
        local ok, name = pcall(function() return item:getDisplayName() end)
        if ok and type(name) == "string" then return name end
        return nil
    end

    -- ---- the menu --------------------------------------------------------------------------------

    --- THE WHOLE DECISION: the door, the entry's label, whether it can be taken and its tooltip; nil
    --- when nothing is offered.
    function M.doorMenuPlanFor(player, worldObjects)
        local door = M.doorAmong(worldObjects)
        if door == nil then return nil end
        local check = M.doorPickCheck(player, door, false)
        if not check.offered then return nil end
        local label = M.T("ContextMenu_LugliDMS_Route_pick", "Pick the lock")
        local plan = { door = door, ok = check.ok, label = label, tipName = label }
        if not check.ok then
            local text = BAD .. reasonText(check.reason) .. " <LINE> "
            if check.reason == M.REASON_NO_TOOL then
                text = text .. PLAIN .. M.T("Tooltip_LugliDMS_Needs_pick", "Needs a paperclip or a screwdriver.") .. " <LINE> "
            end
            plan.tipText = text
            return plan
        end
        local tool = nameOf(check.tool)
        if tool ~= nil then plan.label = label .. " (" .. tool .. ")" end
        local text = GOOD .. M.T("Tooltip_LugliDMS_Tool", "Tool") .. ": " .. tostring(tool) .. " <LINE> "
        text = text .. PLAIN .. M.T("Tooltip_LugliDMS_Chance", "Chance") .. ": "
            .. math.floor(check.chance * 100 + 0.5) .. "% <LINE> "
        if check.spends then
            text = text .. BAD .. M.T("Tooltip_LugliDMS_Spends", "A failed try uses up the paperclip") .. " <LINE> "
        end
        local seconds = math.max(1, math.floor(check.seconds + 0.5))
        text = text .. PLAIN .. M.T("Tooltip_LugliDMS_Time", "Time") .. ": " .. seconds .. " "
            .. M.T("Tooltip_LugliDMS_Seconds", "seconds") .. " <LINE> "
        text = text .. PLAIN .. M.Tf("Tooltip_LugliDMS_Noise", "Heard up to %1 tiles away", check.noise) .. " <LINE> "
        plan.tipText = text
        return plan
    end

    -- ---- the wire --------------------------------------------------------------------------------

    function M.doorSend(player, command, args)
        if M.isMultiplayer() then
            if sendClientCommand ~= nil then sendClientCommand(player, M.DOOR_MODULE, command, args) end
            return
        end
        local ok, err = pcall(M.doorPickServe, player, command, args)
        if not ok then M.defect(PART, tostring(command) .. " request failed: " .. tostring(err)) end
    end

    -- Who asked, per door id: { player, action, door }.
    local holders = {}

    --- The authority's answer: OnServerCommand in multiplayer, a direct call in single player.
    function M.doorPickReply(args)
        if type(args) ~= "table" or args.id == nil then return end
        local h = holders[args.id]
        if h == nil then return end
        holders[args.id] = nil
        if args.outcome == "refused" then
            if h.action ~= nil then
                h.action.claimSent = false
                h.action.refusedBy = args.reason or "IGUI_LugliDMS_Refused"
            end
            halo(h.player, reasonText(args.reason), false)
            return
        end
        for _, name in ipairs(M.outcomeSounds({ route = "pick", outcome = args.outcome })) do
            pcall(function() h.player:playSound(name) end)
        end
        if args.outcome == "opened" then
            M.doorPickLearn(h.player, h.door)
            halo(h.player, M.T("IGUI_LugliDMS_DoorPicked", "The lock clicks. The door is unlocked."), true)
        elseif args.outcome == "failed" then
            local text = M.T("IGUI_LugliDMS_LockHolds", "The lock holds.")
            if args.spent == true then text = text .. " " .. M.T("IGUI_LugliDMS_ClipSpent", "The paperclip is used up.") end
            halo(h.player, text, false)
        end
    end

    -- ---- the action ------------------------------------------------------------------------------

    ISLugliDMSDoorPickAction = ISBaseTimedAction:derive("ISLugliDMSDoorPickAction")

    function ISLugliDMSDoorPickAction:isValid()
        if self.refusedBy ~= nil then return false end
        local check = M.doorPickCheck(self.character, self.door, true)
        if not check.ok then
            self.stoppedBy = check.reason
            return false
        end
        return true
    end

    function ISLugliDMSDoorPickAction:waitToStart()
        self.character:faceThisObject(self.door)
        return self.character:shouldBeTurning()
    end

    function ISLugliDMSDoorPickAction:update()
        self.character:faceThisObject(self.door)
        local step = math.min(M.DOOR_PICK_STEPS, math.floor(self:getJobDelta() * (M.DOOR_PICK_STEPS + 1)))
        if step > self.step then
            self.step = step
            local name = M.routeSound("pick", nil, "step")
            if name ~= nil then pcall(function() self.character:playSound(name) end) end
        end
    end

    function ISLugliDMSDoorPickAction:start()
        local args, id = M.doorArgs(self.door)
        if args == nil then
            self.refusedBy = "IGUI_LugliDMS_Gone"
            return
        end
        self.args, self.id = args, id
        -- Held before the send: in single player the refusal comes back inside it.
        self.claimSent = true
        holders[id] = { player = self.character, action = self, door = self.door }
        M.doorSend(self.character, M.DOOR_CLAIM, args)
        self:setActionAnim("Loot")
        self:setAnimVariable("LootPosition", "")
        local check = M.doorPickCheck(self.character, self.door, false)
        if check.ok then
            local obj, model = M.handModelOf(check.tool)
            if model ~= nil then self:setOverrideHandModelsString(model, nil) else self:setOverrideHandModels(obj, nil) end
        end
    end

    function ISLugliDMSDoorPickAction:stop()
        if self.claimSent then
            self.claimSent = false
            holders[self.id] = nil
            M.doorSend(self.character, M.DOOR_RELEASE, self.args)
        end
        if self.stoppedBy ~= nil then
            halo(self.character, reasonText(self.stoppedBy), false)
            self.stoppedBy = nil
        end
        ISBaseTimedAction.stop(self)
    end

    function ISLugliDMSDoorPickAction:perform()
        if self.claimSent then
            self.claimSent = false
            holders[self.id] = { player = self.character, door = self.door }
            M.doorSend(self.character, M.DOOR_SUBMIT, self.args)
        end
        ISBaseTimedAction.perform(self)
    end

    function ISLugliDMSDoorPickAction:new(character, door)
        local o = ISBaseTimedAction.new(self, character)
        o.door = door
        o.step = 0
        o.stopOnWalk = true
        o.stopOnRun = true
        o.stopOnAim = true
        local check = M.doorPickCheck(character, door, false)
        local seconds = (check.ok and M.finite(check.seconds)) or 1
        o.maxTime = math.max(1, math.floor(seconds * M.ACTION_UNITS_PER_SECOND))
        if character:isTimedActionInstant() then o.maxTime = 1 end
        return o
    end

    --- Say now why it cannot be done, else walk to the survivor's side of the door and pick it.
    --- True when the pick was queued.
    function M.startDoorPick(player, door)
        if player == nil or door == nil then return false end
        local check = M.doorPickCheck(player, door, false)
        if not check.ok then
            halo(player, reasonText(check.reason), false)
            return false
        end
        if not luautils.walkAdjWindowOrDoor(player, door:getSquare(), door) then
            halo(player, reasonText("IGUI_LugliDMS_TooFar"), false)
            return false
        end
        ISTimedActionQueue.add(ISLugliDMSDoorPickAction:new(player, door))
        return true
    end

    local function attachTooltip(opt, name, text)
        local okTip, tip = pcall(function() return ISWorldObjectContextMenu.addToolTip() end)
        if not okTip or tip == nil then return end
        pcall(function() tip:setName(name) end)
        tip.description = text
        opt.toolTip = tip
    end

    local function onPick(player, door)
        M.startDoorPick(player, door)
    end

    M.addHandler(PART, "OnFillWorldObjectContextMenu", function(playerIdx, context, worldObjects, test)
        if test then return end
        local player = getSpecificPlayer(playerIdx)
        if player == nil then return end
        local plan = M.doorMenuPlanFor(player, worldObjects)
        if plan == nil then return end
        local opt = context:addOption(plan.label, player, onPick, plan.door)
        if opt == nil then return end
        if not plan.ok then opt.notAvailable = true end
        attachTooltip(opt, plan.tipName, plan.tipText)
    end)

    M.addHandler(PART, "OnServerCommand", function(module, command, args)
        if module ~= M.DOOR_MODULE or command ~= M.DOOR_RESULT then return end
        M.doorPickReply(args)
    end)
    M.addTeardown(PART, function() holders = {} end)
    M.status(PART, true)
end
