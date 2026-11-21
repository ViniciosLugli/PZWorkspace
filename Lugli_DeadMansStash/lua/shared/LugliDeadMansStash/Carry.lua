--[[
    Carry
    AN OPENED BOX IS FURNITURE. Its opened tiles are IsMoveAble and CanScrap (tools/dms-tiles.py
    CARRY), so vanilla's moveables pick it up, turn it and place it as storage, and Disassemble or
    a sledge clears it away; a sealed tile is neither.
    A BOX A ROUTE WRECKED STAYS WHERE IT IS: drilled, cut open with a torch or smashed in (a
    route with `wrecks`, Gates.lua), it is refused pickup and turning. Every other route undoes
    or breaks only the lock, and leaves a box that can be carried home.
    Vanilla turns a moveable by picking it up and placing a new one (rotateMoveable), and its
    server never asks canRotateMoveable, so both the check and the turn itself are refused here.
    The authority judges from its store (Gating.gateOf); an MP client from the object's tag,
    which only draws the cursor: the server's own pickup asks again.
    A BOX THAT LEAVES ITS SQUARE LEAVES ITS RECORD BEHIND, so the authority retires an opened
    gate's record when its box is removed: placed elsewhere, or a new one on its square, is an
    ordinary container. The engine fires OnObjectAboutToBeRemoved on every square removal, in single
    player and on a dedicated server (IsoGridSquare.RemoveTileObject, RemoveItemFromSquarePacket,
    42.22.2): a pickup, a turn, a Disassemble and a sledge. A chunk unloading is no removal.
]]

require "Moveables/ISMoveableSpriteProps"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Gates"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Carry"

    M.WRECKED_TEXT = "IGUI_LugliDMS_Wrecked"

    local function wrecks(routeId)
        local def = type(routeId) == "string" and M.ROUTES[routeId] or nil
        return def ~= nil and def.wrecks == true
    end

    --- Did a wrecking route open this box? On the authority from the store, on a client from the tag.
    function M.isWrecked(obj)
        if obj == nil then return false end
        if M.isWorldAuthority() then
            if M.gateOf == nil then return false end
            local okCount, count = pcall(obj.getContainerCount, obj)
            if not okCount or type(count) ~= "number" then return false end
            for i = 0, count - 1 do
                local rec = M.gateOf(obj, i)
                if rec ~= nil and rec.state == "opened" and wrecks(rec.by) then return true end
            end
            return false
        end
        local rec = M.gateRecord(obj)
        return rec ~= nil and rec.state == "opened" and wrecks(rec.by)
    end

    --- The object on the square showing this sprite, as vanilla's own findOnSquare matches it.
    local function onSquare(square, spriteName)
        if square == nil or spriteName == nil then return nil end
        local objects = square:getObjects()
        for k = 0, objects:size() - 1 do
            local obj = objects:get(k)
            if M.liveSpriteName(obj) == spriteName then return obj end
        end
        return nil
    end

    --- Run `check`, and on any error answer `fallback`, reported once: a broken hook leaves vanilla's say.
    local function guarded(check, fallback)
        local ok, res = pcall(check)
        if ok then return res end
        M.defect(PART, tostring(res))
        return fallback
    end

    local function install()
        local P = ISMoveableSpriteProps
        if P == nil or type(P.canPickUpMoveableInternal) ~= "function" or type(P.canRotateMoveable) ~= "function"
            or type(P.rotateMoveable) ~= "function" or type(P.getInfoPanelDescription) ~= "function" then
            M.defect(PART, "ISMoveableSpriteProps is missing a hook: a wrecked box can be carried", true)
            return
        end
        local canPickUp = P.canPickUpMoveableInternal
        P.canPickUpMoveableInternal = function(self, character, square, object, isMulti)
            if not canPickUp(self, character, square, object, isMulti) then return false end
            return not guarded(function() return M.isWrecked(object) end, false)
        end
        local canRotate = P.canRotateMoveable
        P.canRotateMoveable = function(self, square, object, origProps)
            if not canRotate(self, square, object, origProps) then return false end
            return not guarded(function() return M.isWrecked(object) end, false)
        end
        local rotate = P.rotateMoveable
        P.rotateMoveable = function(self, character, square, origSpriteName)
            if guarded(function() return M.isWrecked(onSquare(square, origSpriteName)) end, false) then return end
            return rotate(self, character, square, origSpriteName)
        end
        local describe = P.getInfoPanelDescription
        P.getInfoPanelDescription = function(self, square, object, player, mode)
            local info = describe(self, square, object, player, mode)
            if (mode == "pickup" or mode == "rotate") and type(info) == "table"
                and guarded(function() return M.isWrecked(object) end, false) then
                local bhc = ISMoveableSpriteProps.bhc
                local r, g, b = 255, 64, 64
                if bhc ~= nil then r, g, b = bhc:getR() * 255, bhc:getG() * 255, bhc:getB() * 255 end
                info = ISMoveableSpriteProps.addLineToInfoTable(info,
                    M.T(M.WRECKED_TEXT, "Wrecked open: too damaged to move."), r, g, b)
            end
            return info
        end
        M.status(PART, true)
    end
    install()

    --- Retire the store record of every opened gate in this object, about to leave the world.
    function M.retireOpened(obj)
        if obj == nil or M.gateOf == nil then return 0 end
        local square = obj:getSquare()
        if square == nil then return 0 end
        local gates = M.store().gates
        local retired = 0
        for i = 0, obj:getContainerCount() - 1 do
            local rec = M.gateOf(obj, i)
            if rec ~= nil and rec.state == "opened" then
                gates[M.gateId(square:getX(), square:getY(), square:getZ(), i)] = nil
                retired = retired + 1
            end
        end
        return retired
    end

    if M.isWorldAuthority() then
        -- Every removal in the world comes through here: an error is reported, never let out to
        -- take the handler down with it.
        M.addHandler(PART, "OnObjectAboutToBeRemoved", function(obj)
            local ok, err = pcall(M.retireOpened, obj)
            if not ok then M.defect(PART, "retire: " .. tostring(err)) end
        end)
    end
end
