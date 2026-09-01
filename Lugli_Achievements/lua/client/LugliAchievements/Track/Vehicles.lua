require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Travel tracking"

-- There is no odometer in the engine, so distance is sampled once a minute and the step added
-- to whichever counter matches how the survivor was travelling. A minute of sprinting covers
-- well under MAX_STEP; anything bigger is a teleport or a chunk load, and is discarded.
local MAX_STEP = 400

local lastX, lastY = {}, {}

local function onEveryOneMinute()
    M.forEachLocalPlayer(function(player, idx)
        local okP, x, y = pcall(function() return player:getX(), player:getY() end)
        if not okP or type(x) ~= "number" then return end

        local px, py = lastX[idx], lastY[idx]
        lastX[idx], lastY[idx] = x, y
        if px == nil then return end

        local dx, dy = x - px, y - py
        local step = math.sqrt(dx * dx + dy * dy)
        if step <= 0 or step > MAX_STEP then return end

        local vehicle = player.getVehicle ~= nil and player:getVehicle() or nil
        if vehicle ~= nil then
            M.incStat(player, "metres_driven", math.floor(step))
            local okF, fuel = pcall(function() return vehicle:getRemainingFuelPercentage() end)
            if okF and type(fuel) == "number" and fuel > 0 and fuel < 5 then
                M.setStat(player, "low_fuel_drives", 1)
            end
        else
            M.incStat(player, "metres_walked", math.floor(step))
        end
    end)
end

local function onEnterVehicle(character)
    if character == nil then return end
    M.incStat(character, "vehicle_enters", 1)
    local vehicle = character.getVehicle ~= nil and character:getVehicle() or nil
    if vehicle == nil then return end
    local ok, script = pcall(function() return vehicle:getScriptName() end)
    if ok and type(script) == "string" and script ~= "" then
        M.addUnique(character, "vehicles_used", script)
    end
end

local function onSeatSwitch(character)
    if character ~= nil then M.incStat(character, "seat_changes", 1) end
end

--- Gated on success. The event carries no part, so this counts repairs, not parts.
local function onMechanic(character, success)
    if character == nil or success ~= true then return end
    M.incStat(character, "vehicle_repairs", 1)
end

M.addHandler(PART, "EveryOneMinute", onEveryOneMinute)
M.addHandler(PART, "OnEnterVehicle", onEnterVehicle)
M.addHandler(PART, "OnSwitchVehicleSeat", onSeatSwitch)
M.addHandler(PART, "OnMechanicActionDone", onMechanic)
M.status(PART, true)
