--[[
Vehicle loot: names that point at nothing.

What happens today. When the engine reads the vehicle loot tables (ItemPickerJava.ParseVehicleDistributions,
ItemPickerJava.java:252-294 on 42.22) it drops every item name no item script resolves, with a
debug-only log line and nothing else (:398-408), and a vehicle whose Normal table is missing gets no
entry at all (:293). Several tables name items by a name that no longer exists:
  - Specific Loot and the KI5 vehicle mods' own files still use names vanilla or the mod renamed
    since: Gloves_LeatherGloves_Black, ShirtFormalTINT, DehydrateMeatStick, EmptyPetrolCan,
    AssaultRiffle(2), WhiskeyFull, Cigarettes, Hoodie_OshkoshBlack/Gray, W460MilitaryTire;
    each is a fixed typo or a rename with exactly one successor, so those items never spawn.
  - Vanilla gives the Genuine Beer step van VehicleDistributions.StepVan_ImportedBeer
    (VehicleDistributions.lua:11775), which no file defines; its table is StepVan_Genuine_Beer
    (:10470), so the van spawns with every container empty.

What this part changes. Before the engine reads the tables, each of those names is replaced by its
successor wherever a vehicle's loot (Normal and specific tables, their junk and bags) lists it, but
only while the old name still resolves to nothing and the new one resolves, so a mod that defines
the old name again, or drops the new one, is left as it is. The beer van gets its own table only
while its entry still has none.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- Old name to its only successor, matched with or without the Base module. Evidence per pair: vanilla generated item scripts on 42.22, the
-- 82oshkoshM911 mod's 42.20 OshkoshShirts.txt (its B41 copy named the hood-up hoodie Hoodie_*), the
-- 84mercW460 mod's vehicle items, and vanilla's own VehicleDistribution_TrunkJunk.lua for PetrolCanEmpty.
local RENAMES = {
    ["Gloves_LeatherGloves_Black"] = "Gloves_LeatherGlovesBlack",
    ["ShirtFormalTINT"] = "Shirt_FormalTINT",
    ["DehydrateMeatStick"] = "DehydratedMeatStick",
    ["EmptyPetrolCan"] = "PetrolCanEmpty",
    ["AssaultRiffle"] = "AssaultRifle",
    ["AssaultRiffle2"] = "AssaultRifle2",
    ["WhiskeyFull"] = "Whiskey",
    ["Cigarettes"] = "CigarettePack",
    ["Hoodie_OshkoshBlack"] = "HoodieUP_OshkoshBlack",
    ["Hoodie_OshkoshGray"] = "HoodieUP_OshkoshGray",
    ["W460MilitaryTire"] = "W460MilitaryTire2",
}

local BEER_VAN, BEER_TABLE = "StepVan_Genuine_Beer", "StepVan_Genuine_Beer"

-- As the engine resolves a loot name: an item script, or an empty fluid container of one
-- (InventoryItemFactory.java:62).
local function resolves(name)
    local sm = getScriptManager()
    if sm:FindItem(name) ~= nil then return true end
    return name:sub(-5) == "Empty" and sm:FindItem(name:sub(1, -6)) ~= nil
end

local renamed, beer, verdicts = {}, nil, {}

-- Answered once per name and merge: scripts do not change while the tables are read.
local function renamable(old)
    if verdicts[old] == nil then verdicts[old] = not resolves(old) and resolves(RENAMES[old]) end
    return verdicts[old]
end

local function renameIn(list)
    if type(list) ~= "table" then return end
    for i = 1, #list, 2 do
        local name = list[i]
        local module = type(name) == "string" and name:sub(1, 5) == "Base." and "Base." or ""
        local bare = type(name) == "string" and name:sub(#module + 1) or nil
        local new = bare ~= nil and RENAMES[bare] ~= nil and renamable(bare) and module .. RENAMES[bare] or nil
        if new ~= nil then
            renamed[#renamed + 1] = { list = list, index = i, old = list[i], new = new }
            list[i] = new
        end
    end
end

-- A container the engine reads (ExtractContainersFromLua): its items, its junk's and its bags'.
local function container(c)
    if type(c) ~= "table" then return end
    renameIn(c.items)
    if type(c.junk) == "table" then renameIn(c.junk.items) end
    if type(c.bags) == "table" then renameIn(c.bags.items) end
end

local function room(r)
    if type(r) ~= "table" then return end
    for key, c in pairs(r) do
        if key ~= "specificId" then container(c) end
    end
end

local function byVehicle()
    local vd = VehicleDistributions
    local t = type(vd) == "table" and vd[1] or nil
    if type(t) ~= "table" then error("VehicleDistributions[1] is missing") end
    return t
end

local function apply()
    local entries = byVehicle()
    verdicts = {}
    for _, entry in pairs(entries) do
        if type(entry) == "table" then
            room(entry.Normal)
            if type(entry.Specific) == "table" then
                for i = 1, #entry.Specific do room(entry.Specific[i]) end
            end
        end
    end
    local van, normal = entries[BEER_VAN], VehicleDistributions[BEER_TABLE]
    if type(van) == "table" and van.Normal == nil and type(normal) == "table" then
        van.Normal = normal
        beer = { entry = van, normal = normal }
    end
end

local function remove()
    for i = #renamed, 1, -1 do
        local r = renamed[i]
        if r.list[r.index] == r.new then r.list[r.index] = r.old end
    end
    if beer ~= nil and beer.entry.Normal == beer.normal then beer.entry.Normal = nil end
    renamed, beer = {}, nil
end

local function hasApplied() return #renamed > 0 or beer ~= nil end

-- As vehicle-loot: the save's sandbox page is read after the tables, so the switch is checked again
-- once the world is up and the tables are read again only when that changed the answer.
local function reconcile(def)
    local want = M.switchOn(def)
    if want == hasApplied() then return end
    if want then apply() else remove() end
    ItemPickerJava.Parse()
end

local function install(ctx)
    ctx.undo(remove)
    ctx.on("OnPostDistributionMerge", apply)
    ctx.at("OnGameStart", function() reconcile(ctx.def) end)
    ctx.at("OnServerStarted", function() reconcile(ctx.def) end)
end

M.addPart({
    name = "loot-names",
    switch = "LootNames",
    title = "Vehicle loot: item and table names that point at nothing",
    tip = "Some vehicle loot tables name items by an old or misspelled name (leather gloves, a formal shirt, meat sticks, petrol cans, assault rifles, whiskey, cigarettes, the Oshkosh hoodies, a W460 tire), so those items never spawn, and vanilla's Genuine Beer step van points at a loot table that does not exist, so it spawns empty. The names are corrected and the van gets its own loot. A name is changed only while the old one is unknown and the new one exists.",
    kind = "fix",
    side = "server",
    phase = "boot",
    pins = { "vanilla.beervan" },
    install = install,
})
