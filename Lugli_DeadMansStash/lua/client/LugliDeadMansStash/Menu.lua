--[[
    Menu
    Right-click on a sealed gate (a box or a safe): one submenu named for the gate, holding Inspect
    and every route of its kind in the kind's fixed order. A route this survivor cannot take now stays listed,
    greyed out, with the reason, so the player learns what it would need. The client only
    describes; the authority decides (World.lua).

    THE PLAN IS PURE. planFor decides the entries and their tooltips and touches no menu, so the
    suite and the live handler cannot drift apart.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Actions"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Menu"

    local GOOD = " <RGB:0.6,0.9,0.6> "
    local BAD = " <RGB:0.95,0.6,0.5> "
    local PLAIN = " <RGB:1,1,1> "

    --- The first sealed gate among the clicked objects, else on their squares: a click on the
    --- floor beside a crate, or on a shelf stacked over it, still finds it.
    local function gateAmong(worldObjects)
        if type(worldObjects) ~= "table" then return nil end
        for _, obj in ipairs(worldObjects) do
            local md = M.sealedGateOf(obj)
            if md ~= nil then return obj, md end
        end
        local seen = {}
        for _, obj in ipairs(worldObjects) do
            local okSq, sq = pcall(function() return obj:getSquare() end)
            if okSq and sq ~= nil and not seen[sq] then
                seen[sq] = true
                local list = sq:getObjects()
                for i = 0, list:size() - 1 do
                    local o = list:get(i)
                    local md = M.sealedGateOf(o)
                    if md ~= nil then return o, md end
                end
            end
        end
        return nil
    end

    local function toolName(item)
        if item == nil then return nil end
        local ok, name = pcall(function() return item:getDisplayName() end)
        if ok and type(name) == "string" then return name end
        return nil
    end

    --- The tooltip body for one route, as plain rich text.
    local function routeTip(route)
        local text = ""
        if not route.ok then
            text = BAD .. M.reasonText(route.reason) .. " <LINE> "
            if route.reason == M.REASON_NO_TOOL or route.reason == M.REASON_TOOL_BROKEN then
                text = text .. PLAIN .. M.T("Tooltip_LugliDMS_Needs_" .. tostring(route.id), "") .. " <LINE> "
            end
            return text
        end
        local tool = toolName(route.tool)
        if tool ~= nil then
            text = text .. GOOD .. M.T("Tooltip_LugliDMS_Tool", "Tool") .. ": " .. tool .. " <LINE> "
        end
        local key = toolName(route.key)
        if key ~= nil then
            text = text .. GOOD .. M.T("Tooltip_LugliDMS_Key", "Key") .. ": " .. key .. " <LINE> "
        end
        local chance = M.finite(route.chance) or 1
        if chance < 1 then
            text = text .. PLAIN .. M.T("Tooltip_LugliDMS_Chance", "Chance") .. ": "
                .. math.floor(chance * 100 + 0.5) .. "% <LINE> "
            if route.jams then
                text = text .. BAD .. M.T("Tooltip_LugliDMS_MayJam", "A failed try can jam the lock") .. " <LINE> "
            end
            if route.spends then
                text = text .. BAD .. M.T("Tooltip_LugliDMS_Spends", "A failed try uses up the paperclip") .. " <LINE> "
            end
        end
        local seconds = math.max(1, math.floor((M.finite(route.seconds) or 0) + 0.5))
        local unit = seconds == 1 and M.T("Tooltip_LugliDMS_Second", "second") or M.T("Tooltip_LugliDMS_Seconds", "seconds")
        text = text .. PLAIN .. M.T("Tooltip_LugliDMS_Time", "Time") .. ": " .. seconds .. " " .. unit .. " <LINE> "
        local noise = M.finite(route.noise) or 0
        if noise <= 0 then
            text = text .. PLAIN .. M.T("Tooltip_LugliDMS_Silent", "Makes no noise") .. " <LINE> "
        else
            text = text .. PLAIN .. M.Tf("Tooltip_LugliDMS_Noise", "Heard up to %1 tiles away", noise) .. " <LINE> "
        end
        if (route.damage or route.brute ~= nil) and (M.finite(M.cfg("BruteDamage")) or 1) > 1 then
            text = text .. BAD .. M.T("Tooltip_LugliDMS_Damage", "Fragile things inside may break") .. " <LINE> "
        end
        if route.alarm then
            text = text .. BAD .. M.T("Tooltip_LugliDMS_Alarm", "A failed try sets off the alarm and locks it") .. " <LINE> "
        end
        if (M.finite(route.burn) or 0) > 0 then
            text = text .. BAD .. M.T("Tooltip_LugliDMS_Burns", "Paper, money and food inside may burn") .. " <LINE> "
        end
        return text
    end

    --- THE WHOLE DECISION: the gate, the submenu's title and its entries in order.
    function M.menuPlanFor(player, worldObjects)
        local obj, md = gateAmong(worldObjects)
        if obj == nil then return nil end
        local plan = {
            obj = obj, md = md,
            title = M.T("ContextMenu_LugliDMS_Gate_" .. tostring(md.kind), "Stash box"),
            entries = { { kind = "inspect", label = M.T("ContextMenu_LugliDMS_Inspect", "Inspect") } },
        }
        -- The gate's square, so a keypad on the grid reads as powered.
        local routes = M.routes(player, md, M.squareOf(obj))
        for i = 1, #routes do
            local r = routes[i]
            plan.entries[#plan.entries + 1] = {
                kind = "route", id = r.id, ok = r.ok == true, reason = r.reason,
                label = M.T("ContextMenu_LugliDMS_Route_" .. tostring(r.id), tostring(r.id)),
                tipName = M.T("ContextMenu_LugliDMS_Route_" .. tostring(r.id), tostring(r.id)),
                tipText = routeTip(r),
            }
        end
        return plan
    end

    -- A wholesale replacement of ISWorldObjectContextMenu that drops addToolTip must cost the
    -- tooltip, never the menu.
    local function attachTooltip(opt, name, text)
        local okTip, tip = pcall(function() return ISWorldObjectContextMenu.addToolTip() end)
        if not okTip or tip == nil then return end
        pcall(function() tip:setName(name) end)
        tip.description = text
        opt.toolTip = tip
    end

    local function onInspect(player, obj)
        M.startInspect(player, obj)
    end

    local function onRoute(player, obj, routeId)
        M.startRoute(player, obj, routeId)
    end

    local function onFillWorldObjectContextMenu(playerIdx, context, worldObjects, test)
        if test then return end
        local player = getSpecificPlayer(playerIdx)
        if player == nil then return end
        local plan = M.menuPlanFor(player, worldObjects)
        if plan == nil then return end

        -- First of all: the box is what was clicked. Under vanilla's first entry it sat below
        -- whatever else shares the square (Gardening on a lawn, user review 2026-11-19). Vanilla
        -- has filled the menu before this event fires.
        local head = context:addOptionOnTop(plan.title, worldObjects, nil)
        local sub = context:getNew(context)
        context:addSubMenu(head, sub)
        for _, e in ipairs(plan.entries) do
            if e.kind == "inspect" then
                sub:addOption(e.label, player, onInspect, plan.obj)
            else
                local opt = sub:addOption(e.label, player, onRoute, plan.obj, e.id)
                if opt ~= nil then
                    if not e.ok then opt.notAvailable = true end
                    attachTooltip(opt, e.tipName, e.tipText)
                end
            end
        end
    end

    M.addHandler(PART, "OnFillWorldObjectContextMenu", onFillWorldObjectContextMenu)

    -- A LEFT CLICK ON A SEALED BOX INSPECTS IT (user review 2026-11-19), on vanilla's own terms for
    -- a click on a door (ISObjectClickHandler.doClickSpecificObject, doClickDoor): not paused, not
    -- aiming or on a ladder, on the box's floor and in reach of it. An opened box is a container
    -- and keeps vanilla's click.
    M.CLICK_REACH = 2.5

    function M.onBoxClick(object)
        if object == nil or M.sealedGateOf(object) == nil then return false end
        local player = getSpecificPlayer(0)
        if player == nil or player:isDead() then return false end
        local speed = UIManager.getSpeedControls ~= nil and UIManager.getSpeedControls() or nil
        if speed ~= nil and speed:getCurrentGameSpeed() == 0 then return false end
        if player:isAiming() or player:isIgnoreContextKey() then return false end
        if player:isClimbingLadder() or player:isClimbingDownLadder() then return false end
        local sq, at = object:getSquare(), player:getCurrentSquare()
        if sq == nil or at == nil or sq:getZ() ~= at:getZ() then return false end
        if sq:DistToProper(player) > M.CLICK_REACH then return false end
        return M.startInspect(player, object) == true
    end

    M.addHandler(PART, "OnObjectLeftMouseButtonUp", function(object)
        M.onBoxClick(object)
    end)

    -- A SEALED BOX IS NOT A CONTAINER YET. Vanilla's own left click opens any object with a
    -- container as a loot window (ISObjectClickHandler.doClick): in reach it would show the empty
    -- box beside the look, and beyond reach it would walk the survivor over to open it instead.
    -- The wrap keeps vanilla's click for every other object; a sealed gate is left to onBoxClick.
    local wrappedDoClick = nil
    function M.wrapBoxClick()
        if ISObjectClickHandler == nil or type(ISObjectClickHandler.doClick) ~= "function" then
            M.defect(PART, "ISObjectClickHandler.doClick is missing: a sealed box opens as a container", true)
            return false
        end
        if ISObjectClickHandler.doClick == wrappedDoClick then return true end
        local original = ISObjectClickHandler.doClick
        local failed = false
        wrappedDoClick = function(object, x, y)
            if not failed then
                local ok, sealed = pcall(function()
                    return object ~= nil and M.sealedGateOf(object) ~= nil
                end)
                if not ok then
                    failed = true
                    M.defect(PART, "sealed click check removed after: " .. tostring(sealed))
                elseif sealed then
                    return
                end
            end
            return original(object, x, y)
        end
        ISObjectClickHandler.doClick = wrappedDoClick
        return true
    end
    M.addHandler(PART, "OnGameStart", M.wrapBoxClick)
    -- The server files load before this one in the game; a suite loads its stub before the target.
    if ISObjectClickHandler ~= nil then M.wrapBoxClick() end
    M.status(PART, true)
end
