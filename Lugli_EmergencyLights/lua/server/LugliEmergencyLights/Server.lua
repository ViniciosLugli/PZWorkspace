--[[
    Server
    Loot, and one honest line for whoever reads a server log.
]]

require "LugliEmergencyLights/Items"
require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"
require "LugliEmergencyLights/Config"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- Server ------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Server"

    --- COUNTED, not a formula with a constant on the end. This used to be `pairs * 2 + 5`, where
    --- the 5 stood for three spent items, a cartridge and a gun, so adding the recipe manual
    --- would have left the log quietly reporting one item fewer than the mod ships.
    local function itemCount()
        local n = 2                                       -- the gun and the manual
        for _ in pairs(M.LIT_OF) do n = n + 2 end         -- one sealed and one lit each
        for _ in pairs(M.SPENT) do n = n + 1 end
        for _ in pairs(M.CARTRIDGES) do n = n + 1 end
        return n
    end

    local function report()
        M.log(PART, M.envName() .. ", " .. itemCount() .. " items registered")
        if M.isDedicatedServer() then
            M.log(PART, "lights are client-side; this process only carries item state and loot")
        end
        M.status(PART, true)
    end

    -- BOTH EVENTS, and report() is idempotent so whichever arrives first wins.
    local reported = false
    local function reportOnce()
        if reported then return end
        reported = true
        report()
    end

    local h = M.addHandler(PART, "OnServerStarted", reportOnce)
    local g = M.addHandler(PART, "OnGameStart", reportOnce)
    if h ~= nil or g ~= nil then
        M.status(PART, nil, "reports when a world loads", "pending")
    end
end

-- ---- Loot --------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Loot"

    -- container -> chance, per family. A family's chances are split across its colours, so adding a
    -- fifth colour later makes each one rarer rather than making the family five times as common.
    --
    -- A CHANCE IS A PERCENT PER ROLL, NOT A WEIGHT. ItemPickerJava:1023-1042 tests every item
    -- in the list independently each roll -- Rand.Next(10000) < chance * 100 * modifiers (:2138)
    -- -- so items never compete, and one set too low is simply an item that never appears.
    --
    -- Vanilla's own rows run 0.00 to 20.00, and the two shapes of container differ wildly: big
    -- house containers sit at a p25 of 0.03 to 0.20, small curated ones at 1.00 to 10.00. The
    -- first pass used 0.15 to 1.2 everywhere, which is right for the first and a fortieth of the
    -- commonest thing in the second -- so a glow stick in a supermarket and a road flare in a car
    -- supply shelf, the best homes either has, were where they would never turn up.
    --
    -- THE RULE: a family's primary container gets a per-colour chance at that container's p25, a
    -- secondary about half, and the house containers keep what they had. Values are per FAMILY,
    -- so a four-colour family is four times the per-colour figure.
    local PLACES = {
        GlowStick = {
            -- Unchanged: already at or above p25 for these.
            BedroomDresser = 0.6, ClosetShelfGeneric = 0.5, KitchenRandom = 0.3,
            ShelfGeneric = 0.4, WardrobeChild = 1.2,
            -- 0.2/colour against a container whose rarest item is 2.00. A supermarket novelty
            -- aisle is where a civilian buys these, so each colour goes to that minimum.
            GigamartCandy = 8.0,
            CrateCamping = 3.0,      -- 0.75/colour, just under p25 1.00
            DresserGeneric = 0.8,    -- 0.2/colour = p25
            GarageTools = 2.0,       -- 0.5/colour, half of p25: plausible, not primary
        },
        ChemLight = {
            ArmyStorageOutfit = 4.0,      -- 1.0/colour = p25. Military kit is the primary source.
            ArmyStorageAmmunition = 4.0,  -- 1.0/colour = p25 and the container minimum
            PoliceStorageGuns = 8.0,      -- 2.0/colour = the container minimum
            ToolStoreAccessories = 4.0,   -- 1.0/colour = the container minimum
            CrateCamping = 2.0,           -- 0.5/colour, secondary
            GarageTools = 1.0,            -- 0.25/colour, tertiary
        },
        RoadFlare = {
            -- One colour, so these are the per-item figures.
            CarSupplyGasCans = 8.0,   -- the container minimum, in a container of five items. This
                                      -- is the road flare's home: a car emergency kit.
            MechanicShelfMisc = 4.0,  -- p25
            PoliceStorageGuns = 2.0,  -- the container minimum
            ArmyStorageOutfit = 1.0,  -- p25
            CrateCamping = 0.8,       -- unchanged, just under p25
            GarageTools = 0.8,        -- unchanged, just under p25
        },
    }

    -- The gun is rarer than its ammunition in every container that carries both, which is how
    -- vanilla treats every firearm it ships.
    local GUN_PLACES = { PoliceStorageGuns = 2.0, ArmyStorageOutfit = 1.0, CrateCamping = 0.5 }
    local CART_PLACES = { PoliceStorageGuns = 3.0, ArmyStorageAmmunition = 4.0, CrateCamping = 1.0 }

    -- The recipe manual, and it is deliberately not common. It is the only thing in the mod that
    -- unlocks something rather than being used up, so finding one should be an event; a survivor
    -- who never does still reaches the recipes through the Reloading skill.
    --
    -- Vanilla's own recipe magazines are the yardstick: 4.0 in the container built for them,
    -- 2.0 in a themed one and 0.1 on an ordinary living room shelf. This mod has no container of
    -- its own, so a mechanic's shelf is the closest thing to a home.
    local MANUAL_PLACES = {
        MechanicShelfMisc = 2.0,
        CarSupplyGasCans = 1.5,
        GarageTools = 1.0, PoliceStorageGuns = 1.0, ArmyStorageOutfit = 1.0,
        BookstoreMisc = 0.5, CrateBooks = 0.5, MagazineRackMixed = 0.5,
        LivingRoomShelfNoTapes = 0.1,
    }
    local VEHICLE_MANUAL = { MechanicGloveBox = 1.0, GloveBox = 0.1 }

    -- ---- VEHICLES ------------------------------------------------------------------------------
    -- A SEPARATE TABLE, and the biggest hole in this mod's loot. ItemPickerJava.Parse reads a
    -- global named VehicleDistributions (:255); both it and ProceduralDistributions are read AFTER
    -- OnPreDistributionMerge (IsoWorld:1885 fires it, :1900 calls Parse), so one handler fills both.
    --
    -- The names below are the LEAF tables, not the per-vehicle profiles: VehicleDistributions.Police
    -- is a map of slot to table whose fields POINT AT them, so writing to a profile would land the
    -- item in every slot at once. Same p25 rule as above, against these tables' own ranges.
    local VEHICLE_PLACES = {
        GlowStick = {
            BadTeensGloveBox = 16.0,     -- 4.0/colour = that table's own minimum. Teenagers.
            CamperTruckBed = 8.0, CamperGloveBox = 4.0,
            AdventurerTruckBed = 20.0,   -- half its p25: thematic, not the primary home
            AdventurerGloveBox = 4.0,
            RangerTruckBed = 2.0,
        },
        ChemLight = {
            ArmyLightTruckBed = 8.0, ArmyHeavyTruckBed = 8.0, ArmyGloveBox = 4.0,
            PoliceSWATTruckBed = 8.0, PoliceSWATGloveBox = 4.0,
            PoliceTruckBed = 4.0, PoliceGloveBox = 2.0,
            SurvivalistTruckBed = 4.0, SurvivalistGloveBox = 2.0,
            RangerTruckBed = 4.0, FireTruckBed = 4.0,
        },
        RoadFlare = {
            FireTruckBed = 10.0, FireGloveBox = 6.0,
            AmbulanceTruckBed = 6.0, AmbulanceGloveBox = 4.0,
            PoliceTruckBed = 6.0, PoliceGloveBox = 4.0,
            RangerTruckBed = 6.0, RangerGloveBox = 4.0,
            PoliceSWATTruckBed = 4.0, PoliceSWATGloveBox = 2.0,
            MechanicTruckBed = 4.0, MechanicGloveBox = 2.0,
            SurvivalistTruckBed = 4.0, SurvivalistGloveBox = 2.0,
            ArmyLightTruckBed = 4.0, ArmyHeavyTruckBed = 4.0, ArmyGloveBox = 2.0,
            CamperTruckBed = 2.0, CamperGloveBox = 1.0,
            -- Every ordinary car in the world: TrunkStandard's one vanilla row is NormalTire1 at
            -- 0.5, and matching it is about one boot in two hundred. Raise these with care.
            TrunkStandard = 0.5, TrunkHeavy = 0.5, GloveBox = 0.25,
        },
    }

    local VEHICLE_GUN = {
        RangerGloveBox = 2.0, PoliceGloveBox = 1.0, FireGloveBox = 1.0,
        SurvivalistGloveBox = 1.0, AdventurerGloveBox = 1.0, CamperGloveBox = 0.5,
    }
    local VEHICLE_CART = {
        RangerGloveBox = 4.0, PoliceGloveBox = 2.0, FireGloveBox = 2.0,
        SurvivalistGloveBox = 2.0, AdventurerGloveBox = 2.0, ArmyGloveBox = 2.0,
        CamperGloveBox = 1.0,
    }

    local added, missing = 0, 0

    local function add(container, fullType, chance)
        local list = ProceduralDistributions and ProceduralDistributions.list
        local entry = list and list[container] or nil
        if entry == nil or entry.items == nil then
            missing = missing + 1
            return
        end
        -- items is ONE flat array of interleaved name, chance pairs. Two inserts in this order is
        -- the whole contract: a single insert shifts every pair after it.
        table.insert(entry.items, fullType)
        table.insert(entry.items, chance)
        added = added + 1
    end

    local vAdded, vMissing = 0, 0

    --- The same insert against a VEHICLE table. Shaped differently: containers sit at the top
    --- level, not under `.list`, and one may carry only `junk` with no `items` array at all (the
    --- stock GloveBox does), so an absent array is created rather than counted as missing.
    local function addVehicle(container, fullType, chance)
        local entry = VehicleDistributions and VehicleDistributions[container] or nil
        if entry == nil then
            vMissing = vMissing + 1
            return
        end
        if entry.items == nil then entry.items = {} end
        table.insert(entry.items, fullType)
        table.insert(entry.items, chance)
        vAdded = vAdded + 1
    end

    --- family id -> how many colours it ships, so a chance can be split evenly.
    local function colourCounts()
        local n = {}
        for _, lit in pairs(M.LIT_OF) do
            local info = M.LIT[lit]
            if info ~= nil then
                n[info.family] = (n[info.family] or 0) + 1
            end
        end
        return n
    end

    -- Guards a double merge WITHIN one world load, not across worlds.
    local done = false

    --- The loot multiplier, read from the JAVA option rather than the Lua mirror.
    local function lootMultiplier()
        local v = nil
        if getSandboxOptions ~= nil then
            local ok, got = pcall(function()
                local o = getSandboxOptions():getOptionByName("LugliEL.LootMultiplier")
                return o ~= nil and o:getValue() or nil
            end)
            if ok and type(got) == "number" then v = got end
        end
        -- The mirror is the fallback, not the source: on a new game it is already correct, and if the
        -- option is ever renamed this degrades to the declared default rather than to nothing.
        if v == nil then v = M.cfg("LootMultiplier") end
        return v
    end

    local function run()
        if done then return end

        local mult = lootMultiplier()
        if type(mult) ~= "number" then mult = 1.0 end
        if mult <= 0 then
            M.status(PART, true, "loot disabled by sandbox option")
            return
        end
        done = true

        local counts = colourCounts()
        -- Sealed variants only. A cracked or spent one in a cupboard makes no sense.
        for sealed, lit in pairs(M.LIT_OF) do
            local info = M.LIT[lit]
            local places = info ~= nil and PLACES[info.family] or nil
            if places ~= nil then
                local share = counts[info.family] or 1
                for container, chance in pairs(places) do
                    add(container, sealed, chance * mult / share)
                end
            end
        end

        for container, chance in pairs(GUN_PLACES) do
            add(container, M.GUN.item, chance * mult)
        end
        for fullType, _ in pairs(M.CARTRIDGES) do
            for container, chance in pairs(CART_PLACES) do
                add(container, fullType, chance * mult)
            end
        end

        for container, chance in pairs(MANUAL_PLACES) do
            add(container, M.MANUAL.item, chance * mult)
        end

        -- The same three passes again, against the vehicle tables.
        for sealed, lit in pairs(M.LIT_OF) do
            local info = M.LIT[lit]
            local places = info ~= nil and VEHICLE_PLACES[info.family] or nil
            if places ~= nil then
                local share = counts[info.family] or 1
                for container, chance in pairs(places) do
                    addVehicle(container, sealed, chance * mult / share)
                end
            end
        end

        for container, chance in pairs(VEHICLE_GUN) do
            addVehicle(container, M.GUN.item, chance * mult)
        end
        for fullType, _ in pairs(M.CARTRIDGES) do
            for container, chance in pairs(VEHICLE_CART) do
                addVehicle(container, fullType, chance * mult)
            end
        end

        for container, chance in pairs(VEHICLE_MANUAL) do
            addVehicle(container, M.MANUAL.item, chance * mult)
        end

        M.log(PART, added .. " container entries and " .. vAdded .. " vehicle entries added, "
                    .. missing .. " container(s) and " .. vMissing
                    .. " vehicle table(s) not on this build")
        M.status(PART, true)
    end

    local h = M.addHandler(PART, "OnPreDistributionMerge", run)
    if h ~= nil then M.status(PART, nil, "runs when a world loads", "pending") end
end
