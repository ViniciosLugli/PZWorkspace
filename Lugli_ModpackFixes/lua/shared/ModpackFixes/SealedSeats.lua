--[[
KI5 vehicles: nothing ends up in the seats and compartments they never let anyone open.

What happens today. Some KI5 vehicles seal seat containers on purpose: every seat of the '84
Cadillac Gage LAV-300 (APC and FSV, driver's seat included) answers V300.ContainerAccess.BlankSeat,
and the eight crew seats of the '85 Chevy Step Van SWAT answer damnlib's DAMN.ContainerAccess.NoStorage,
both of which never allow access. The '63 Beetle Buggy keeps the Beetle's inner trunk
(BTL63InnerTrunk, from the shared BTL63InnerTrunkCompartment template) whose test,
DAMN.ContainerAccess.TrunkSecondRow, opens it only from rear seat 2 or 3 or from the DoorFrontLeft
area, and the buggy has two seats and no such area. Items still get in two ways:
  - SpecLoot's loot tables (and 63beetle's own, for the buggy) roll loot into every one of them, on the vehicle's first spawn and again
    in its own re-roll a few ticks later (ResetContainers.lua, forceVehicleDistribution).
  - Vanilla's seat shuffle (ISVehicleMenu.moveItemsFromSeat, also used by KI5's seat UI) moves a
    full seat's items into the next seat it can switch to, with no check that the player could ever
    open it: on the LAV-300, whose seats are all sealed, sitting in a seat that holds items pushes
    them into the next one, the driver's included. (The SWAT van's crew seats have no capacity, so
    the shuffle cannot reach them.)
The engine counts a seat as taken while its container holds more than a quarter of its capacity
(BaseVehicle.isSeatOccupied, BaseVehicle.java:2274-2291 on 42.22), so those seats can never be sat
in, and nothing in them can be taken out.

What this part changes.
  - Every loot roll into a sealed seat is emptied as it happens, on the side that owns the world
    (the server, or the game in single player): both rolls go through BaseVehicle.randomizeContainer,
    which fires OnFillContainer with the vehicle's script name and the part id (BaseVehicle.java:9042-9053).
  - A vehicle already holding items in a sealed seat, from before this part, has them moved into
    its trunk the next time it is added to the world (addToWorld -> createPhysics ->
    OnSpawnVehicleEnd, BaseVehicle.java:8119, 914), and the move is sent to the clients that have
    the vehicle. Moved, not deleted: a player's own items can be in there, pushed by the shuffle
    before this part existed, and a SWAT crew seat can still be entered and emptied that way.
    The trunk may end up over its capacity; the engine allows it, and nothing is lost.
  - The seat shuffle moves nothing into a sealed seat, so a player's own items never go where they
    cannot be taken back. Moving items out of a sealed seat still works.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- The buggy's inner trunk opens from seat 2 or 3 or from its own area: sealed only while the buggy
-- still has neither, so a 63beetle update that gives it a way in turns this off by itself.
local function noWayIn(part)
    local vehicle, area = part:getVehicle(), part:getArea()
    return vehicle:getMaxPassengers() <= 2 and (area == nil or vehicle:getScript():getAreaById(area) == nil)
end

-- Script name after its module, as the engine names it for the loot tables, to the id prefix the
-- vehicle's own template seals, the trunk a sealed part's old contents go to, and, where the seal
-- is not declared outright, the check that it still holds.
local SEALED = {
    ["84gageV300apc"] = { prefix = "Seat", trunk = "V300Trunk" },
    ["84gageV300fsv"] = { prefix = "Seat", trunk = "V300Trunk" },
    ["85chevyStepVanSWAT"] = { prefix = "SeatCrew", trunk = "STP85Trunk1" },
    ["63beetleBuggy"] = { prefix = "BTL63InnerTrunk", trunk = "BTL63Trunk", holds = noWayIn },
}

local function scriptType(vehicle)
    local name = vehicle:getScriptName()
    if name == nil then return nil end
    return (name:gsub("^[^.]*%.", "", 1))
end

local function sealedId(vehicleType, id)
    local sealed = vehicleType ~= nil and SEALED[vehicleType] or nil
    if sealed ~= nil and id ~= nil and id:sub(1, #sealed.prefix) == sealed.prefix then return sealed end
    return nil
end

local function isSealed(vehicleType, part)
    local sealed = part ~= nil and sealedId(vehicleType, part:getId()) or nil
    return sealed ~= nil and (sealed.holds == nil or sealed.holds(part))
end

local function itemsOf(container)
    local list = ArrayList.new()
    local items = container:getItems()
    for j = items:size() - 1, 0, -1 do list:add(items:get(j)) end
    return list
end

-- A roll's items exist only on this side yet, so nothing is sent. The names are checked first: a
-- bag's roll passes an ItemPickerContainer, not an ItemContainer (ItemPickerJava.java:630, 1153).
local function emptyRolledSeat(roomOrVehicle, containerType, container)
    if sealedId(roomOrVehicle, containerType) == nil then return end
    if not isSealed(roomOrVehicle, container:getVehiclePart()) or container:isEmpty() then return end
    local rolled = itemsOf(container)
    for j = 0, rolled:size() - 1 do container:Remove(rolled:get(j)) end
end

local function emptyOnLoad(vehicle)
    local vehicleType = scriptType(vehicle)
    local sealed = SEALED[vehicleType]
    if sealed == nil then return end
    local trunkPart = vehicle:getPartById(sealed.trunk)
    local trunk = trunkPart ~= nil and trunkPart:getItemContainer() or nil
    if trunk == nil then return end
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        local container = part:getItemContainer()
        if container ~= nil and isSealed(vehicleType, part) and not container:isEmpty() then
            local moved = itemsOf(container)
            for j = 0, moved:size() - 1 do trunk:AddItem(moved:get(j)) end
            sendRemoveItemsFromContainer(container, moved)
            sendAddItemsToContainer(trunk, moved)
        end
    end
end

local function install(ctx)
    if not M.isMultiplayerClient() then
        ctx.on("OnFillContainer", emptyRolledSeat)
        ctx.on("OnSpawnVehicleEnd", emptyOnLoad)
    end
    if not M.isDedicatedServer() then
        ctx.wrap(ISVehicleMenu, "transferSeatItems", function(original)
            return function(player, vehicle, part, otherPart, ...)
                if isSealed(scriptType(vehicle), otherPart) then return 0 end
                return original(player, vehicle, part, otherPart, ...)
            end
        end)
    end
end

M.addPart({
    name = "sealed-seats",
    switch = "SealedSeats",
    title = "KI5 vehicles: nothing ends up in seats or compartments that cannot be opened",
    tip = "The LAV-300's seats and the Step Van SWAT's crew seats can never be opened, yet SpecLoot rolls loot into them and moving items between the LAV-300's seats pushes them into the next one, and a seat holding items can never be sat in. The '63 Beetle Buggy's inner trunk cannot be opened either, yet gets loot. Nothing goes into any of them any more, and what is already there is moved to the vehicle's trunk when it loads. Only active with the LAV-300, the '85 Chevy Step Van or the '63 Beetle.",
    kind = "fix",
    any = { "84gageV300", "85chevyStepVan", "63beetle" },
    side = "both",
    phase = "boot",
    pins = { "v300.apcseats", "v300.fsvseats", "stp85.crewseats" },
    install = install,
})
