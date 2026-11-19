--[[
    DoorPick (server)
    The authority's ear for the Locksmith's door pick: its own module on OnClientCommand, so
    World.lua never routes it, and the sweep of claims left behind. The answer itself is
    shared/Doors.lua's, which single player's client calls directly.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Doors"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "DoorPick"

    if M.isWorldAuthority() then
        if M.isMultiplayer() then
            M.addHandler(PART, "OnClientCommand", function(module, command, player, args)
                if module ~= M.DOOR_MODULE then return end
                M.doorPickServe(player, command, args)
            end)
        end
        M.addTicker(PART, 10, function() M.doorPickSweep(false) end)
        M.addTeardown(PART, function() M.doorPickSweep(true) end)
        M.status(PART, true)
    end
end
