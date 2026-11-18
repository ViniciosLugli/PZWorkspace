--[[
SpecLoot against the vehicle mods it rewrites.

What happens today. SpecLoot replaces the vehicle mods' loot files with its own copies under the
same file names, so the vehicle mods' files never run. Its copies register fewer vehicles than
the vehicle mods ship today, and a vehicle with no entry spawns with every container empty:
  - six burnt wrecks, whose own mods gave them the live vehicle's loot;
  - the seven Ford F350/F450 work trucks (flatbeds, box, dump, wreckers, ambulance), whose own
    loot table SpecLoot does not rebuild at all.
Two more get an entry whose Normal table SpecLoot never defines (VehicleDistributions.PWRPA,
VehicleDistributions.VAN63A, the latter defined only in the 63 Type 2 Van file SpecLoot replaces),
so they spawn empty unless the rarer special-loot roll picks one of their specific tables:
  - the '49 Power Wagon PA, which its own mod gives the plain Power Wagon's loot;
  - the '63 Type 2 Van Apocalypse, which its own mod gives a table of vanilla role loot.

What this part changes. Before the engine reads the loot tables, every one of those vehicles that
still has no entry gets one: a burnt wreck shares its live sibling's entry, as its own mod did, and
the F450 family gets tables written here from the vanilla role tables (work truck, mechanic,
construction, ambulance). An entry SpecLoot or anyone else already registered is never touched,
except that an entry still missing its Normal table gets the one its vehicle's own mod gives it,
keeping its specific tables.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local BURNT = {
    ["67commandoBurnt"] = "67commando",
    ["78amgeneralM35A2Burnt"] = "78amgeneralM35A2",
    ["82oshkoshM911Burnt"] = "82oshkoshM911",
    ["86oshkoshP19ABurnt"] = "86oshkoshUSMC",
    ["92amgeneralM998Burnt"] = "92amgeneralM998",
    ["ECTO1Burnt"] = "ECTO1",
}

-- Container part ids come from the F350 mod's trunk and seat templates (42.20 scripts).
local function workTruck(glove, bed, seat)
    return {
        GloveBox = glove,
        SeatFrontLeft = "DriverSeat", SeatFrontRight = seat, SeatFront = seat,
        SeatRearLeft = "SeatRear", SeatRearRight = "SeatRear",
        TruckBed = bed, F3502TrunkF = bed, F3502TrunkB = bed, F3502TrunkW = bed, F3502TrunkD = bed,
        F3502SideStorageLeft = bed, F3502SideStorageRight = bed,
    }
end
local AMBULANCE = {
    GloveBox = "AmbulanceGloveBox",
    SeatFrontLeft = "DriverSeat", SeatFrontRight = "AmbulanceSeatFront", SeatFront = "AmbulanceSeatFront",
    F3502TrunkA = "AmbulanceTruckBed",
    F3502SideStorageLFA = "AmbulanceGloveBox", F3502SideStorageLMA = "AmbulanceTruckBed",
    F3502SideStorageLRA = "AmbulanceGloveBox", F3502SideStorageRFA = "AmbulanceGloveBox",
    F3502SideStorageRMA = "AmbulanceTruckBed", F3502SideStorageRRA = "AmbulanceGloveBox",
}
local F450 = {
    ["93fordF350CCflatBed"] = workTruck("GloveBox", "TrunkHeavy", "Seat"),
    ["93fordF350SCflatBed"] = workTruck("GloveBox", "TrunkHeavy", "Seat"),
    ["93fordF450box"] = workTruck("GloveBox", "TrunkHeavy", "Seat"),
    ["93fordF450CCwrecker"] = workTruck("MechanicGloveBox", "MechanicTruckBed", "MechanicSeatFront"),
    ["93fordF450SCwrecker"] = workTruck("MechanicGloveBox", "MechanicTruckBed", "MechanicSeatFront"),
    ["93fordF450dump"] = workTruck("ConstructionWorkerGloveBox", "ConstructionWorkerTruckBed", "ConstructionWorkerSeatFront"),
    ["93fordF450ambulance"] = AMBULANCE,
}

-- Normal tables as the vehicles' own mods define them (49powerWagon and 63Type2Van, 42.20 files):
-- a loot table name used whole, or container part ids to table names.
local HOLLOW = {
    ["49powerWagonPA"] = "PWR",
    ["63Type2VanApocalypse"] = {
        GloveBox = "VAN63GloveBox",
        VAN63InnerTrunk = "SurvivalistTruckBed",
        VAN63WeldedRoofrack = "TrunkHeavy",
        VAN63ToolBoxLeft = "AmbulanceGloveBox",
        VAN63ToolBoxRight = "MetalWelderGloveBox",
        VAN63UnderMiddleLeftSeat = "RangerGloveBox",
        VAN63UnderMiddleRightSeat = "RangerGloveBox",
    },
}

local added, filled = {}, {}

local function lootTable(vd, name)
    local t = vd[name]
    if type(t) ~= "table" then return nil, "loot table " .. name .. " is missing" end
    return t
end

-- Entries that exist but have no Normal table, to the Normal table each gets.
local function hollowEntries(vd, byVehicle)
    local out = {}
    for vehicle, recipe in pairs(HOLLOW) do
        local entry = byVehicle[vehicle]
        if type(entry) == "table" and entry.Normal == nil then
            local normal, why
            if type(recipe) == "string" then
                normal, why = lootTable(vd, recipe)
                if normal == nil then return nil, why end
            else
                normal = {}
                for part, tableName in pairs(recipe) do
                    normal[part], why = lootTable(vd, tableName)
                    if normal[part] == nil then return nil, why end
                end
            end
            out[vehicle] = normal
        end
    end
    return out
end

local function entries()
    local vd = VehicleDistributions
    local byVehicle = type(vd) == "table" and vd[1] or nil
    if type(byVehicle) ~= "table" then return nil, "VehicleDistributions[1] is missing" end
    local out = {}
    for burnt, live in pairs(BURNT) do
        if byVehicle[burnt] == nil and type(byVehicle[live]) == "table" then out[burnt] = byVehicle[live] end
    end
    for vehicle, parts in pairs(F450) do
        if byVehicle[vehicle] == nil then
            local normal = {}
            for part, tableName in pairs(parts) do
                local t = vd[tableName]
                if type(t) ~= "table" then return nil, "vanilla loot table " .. tableName .. " is missing" end
                normal[part] = t
            end
            out[vehicle] = { Normal = normal }
        end
    end
    local hollow, why = hollowEntries(vd, byVehicle)
    if hollow == nil then return nil, why end
    return { byVehicle = byVehicle, out = out, hollow = hollow }
end

-- Returns why the part must stand down, having written nothing, or nil once applied.
local function apply()
    local plan, why = entries()
    if plan == nil then return why end
    local byVehicle, out, hollow = plan.byVehicle, plan.out, plan.hollow
    for vehicle, entry in pairs(out) do
        byVehicle[vehicle] = entry
        if byVehicle[vehicle] ~= entry then error("VehicleDistributions rejected " .. vehicle) end
        added[vehicle] = entry
    end
    for vehicle, normal in pairs(hollow) do
        local entry = byVehicle[vehicle]
        entry.Normal = normal
        filled[vehicle] = { entry = entry, normal = normal }
    end
end

local function remove()
    local byVehicle = VehicleDistributions and VehicleDistributions[1]
    for vehicle, entry in pairs(added) do
        if byVehicle ~= nil and byVehicle[vehicle] == entry then byVehicle[vehicle] = nil end
    end
    for _, f in pairs(filled) do
        if f.entry.Normal == f.normal then f.entry.Normal = nil end
    end
    added, filled = {}, {}
end

local function hasAdded()
    for _ in pairs(added) do return true end
    for _ in pairs(filled) do return true end
    return false
end

-- The engine reads the loot tables right after the merge events. In single player the save's
-- sandbox page is read in between, so the switch is checked again once the world is up, and the
-- tables are read again only when that changed the answer.
local function reconcile(def)
    local want = M.switchOn(def)
    if want == hasAdded() then return end
    if want then
        local why = apply()
        if why ~= nil then
            M.standDown(def, why)
            return
        end
    else
        remove()
    end
    ItemPickerJava.Parse()
end

-- Loot tables are server Lua, which loads with the world: nothing to check before the merge.
local function install(ctx)
    local function onMerge()
        local why = apply()
        if why ~= nil then ctx.standDown(why) end
    end
    ctx.undo(remove)
    ctx.on("OnPostDistributionMerge", onMerge)
    ctx.at("OnGameStart", function() reconcile(ctx.def) end)
    ctx.at("OnServerStarted", function() reconcile(ctx.def) end)
end

M.addPart({
    name = "vehicle-loot",
    switch = "VehicleLoot",
    title = "SpecLoot: loot in burnt wrecks, Ford F450 trucks and two KI5 variants",
    tip = "SpecLoot's rewritten loot files leave six burnt wrecks, seven Ford F350/F450 work trucks, the '49 Power Wagon PA and the '63 Type 2 Van Apocalypse with empty containers. This gives the wrecks their live vehicle's loot and the two KI5 variants the loot their own mods give them, and the work trucks vanilla work, mechanic, construction or ambulance loot. Only active with SpecLoot.",
    kind = "compat",
    all = { "SpecLoot" },
    side = "server",
    phase = "boot",
    pins = { "specloot.f350", "specloot.p19a", "specloot.pwrpa", "specloot.van63a" },
    install = install,
})
