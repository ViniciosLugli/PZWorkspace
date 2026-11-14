--[[
'67 Chevy Impala: the Impala spawns in the parking, traffic and junkyard zones it registers for.

What happens today. The mod's spawn list (42.20/media/lua/shared/67chevyImpala_SpawnList.lua)
puts "Base.67chevyImpala" into six vehicle zones, but the mod defines no vehicle by that name: its
two vehicles are Base.67chevyImpalaSedanS and Base.67chevyImpalaBaby. The engine keeps the entry
and warns at every boot ('vehicle type "Base.67chevyImpala" doesn't exist', VehicleType.java:60-66
on 42.22.2), so the Impala never spawns there, and a roll that lands on that entry has no vehicle
script, so RandomizeModel returns false and the chunk's spawn for that zone stops
(IsoChunk.java:1323-1346, 1010-1013).

What this part changes. Before the engine reads the zones, each of those entries is moved, with
its own index and chance, to Base.67chevyImpalaSedanS, the plain sedan. Base.67chevyImpalaBaby,
a themed skin, stays as the mod left it: it never had a zone entry. Where a zone already lists the
sedan, that entry is kept and the dead one is only dropped.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local DEAD, SEDAN = "Base.67chevyImpala", "Base.67chevyImpalaSedanS"

local function install(ctx)
    if type(VehicleZoneDistribution) ~= "table" then error("VehicleZoneDistribution is missing") end
    local scripts = getScriptManager()
    if scripts:getVehicle(DEAD) ~= nil then error(DEAD .. " exists: nothing to move") end
    if scripts:getVehicle(SEDAN) == nil then error(SEDAN .. " is missing") end
    local moved = {}
    for zone, def in pairs(VehicleZoneDistribution) do
        local vehicles = type(def) == "table" and def.vehicles or nil
        if type(vehicles) == "table" and vehicles[DEAD] ~= nil then
            local entry, kept = vehicles[DEAD], vehicles[SEDAN] ~= nil
            vehicles[DEAD] = nil
            if not kept then vehicles[SEDAN] = entry end
            moved[#moved + 1] = { vehicles = vehicles, entry = entry, kept = kept }
        end
    end
    if #moved == 0 then error("no zone lists " .. DEAD) end
    ctx.undo(function()
        for i = 1, #moved do
            local m = moved[i]
            m.vehicles[DEAD] = m.entry
            if not m.kept then m.vehicles[SEDAN] = nil end
        end
    end)
end

M.addPart({
    name = "imp-spawn",
    switch = "ImpSpawn",
    title = "'67 Chevy Impala: the Impala spawns where its mod lists it",
    tip = "The Impala mod lists a vehicle name it does not define in its spawn zones, so the Impala never spawns in parking lots, traffic jams or junkyards, and a spawn roll that lands on it leaves that spot empty. This lists the Impala sedan there instead, with the mod's own chances. Only active with the '67 Chevy Impala.",
    kind = "fix",
    all = { "67chevyImpala" },
    side = "server",
    phase = "boot",
    pins = { "imp.spawn" },
    install = install,
})
