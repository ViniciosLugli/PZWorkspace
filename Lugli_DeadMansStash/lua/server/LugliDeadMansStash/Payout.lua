--[[
    Payout
    What a gate pays out once a route opens it: the themes, the roll, and what brute force does to
    the haul. The authority calls M.payout at the moment a route succeeds; until then the
    container is empty (docs/31 section 1).

    A THEME IS A SET OF (room, container, list) TRIPLES, never bare list names. The only path from
    Lua to one vanilla procedural list is ItemPickerJava.getItemContainer(room, container, list),
    and it answers only for a list that room's container already names in its procList
    (ItemPickerJava.java:1658). Every triple below is copied from vanilla Distributions.lua.

    RESOLVED AGAINST THE MERGED DISTRIBUTIONS, at OnGameStart or OnServerStarted, never at
    OnInitWorld (CLAUDE.md invariant), so a modpack's injected items come along. A triple is
    dropped when its list is gone from ProceduralDistributions.list, or when getItemContainer
    answers with the room's own container instead of the list: it does that, rather than nil, for
    a list the procList does not name, and rolling that would pay out the wrong loot. Lua `==` on
    two Java objects is reference identity (se.krka.kahlua.stdlib.BaseLib.luaEquals, installed jar), so
    the comparison is exact. One defect line names everything dropped.

    M.themeFor IS PURE AND RUNS BEFORE THE RESOLVE: the first chunks fill during world load, ahead
    of OnGameStart, and md.theme outlives a modpack change. So the empty-or-unknown theme
    fallback lives in M.payout alone, at open time.

    THE JAVA LIST IS FETCHED AT ROLL TIME, never cached: IsoWorld.parseDistributions() (Power
    Grid's Loot.lua runs it at world start) replaces every ItemPickerContainer.

    Nothing here transmits. The caller syncs the container to clients after the payout (spike S4).
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Payout"

    M.DEFAULT_THEME = "default"

    M.THEMES = {
        warehouse = {
            { "warehouse", "smallbox", "CrateTools" },
            { "warehouse", "smallbox", "CrateCarpentry" },
            { "warehouse", "smallbox", "CrateMetalwork" },
        },
        garage = {
            { "garagestorage", "crate", "CrateTools" },
            { "garagestorage", "crate", "CrateMechanics" },
            { "garagestorage", "crate", "CrateMetalwork" },
            { "garagestorage", "crate", "CrateElectronics" },
        },
        farm = {
            { "barn", "crate", "CrateFarming" },
            { "barn", "crate", "BarnTools" },
            { "garagestorage", "crate", "CrateGardening" },
        },
        military = {
            { "armystorage", "militarycrate", "ArmyStorageGuns" },
            { "armystorage", "militarycrate", "ArmyStorageAmmunition" },
            { "armystorage", "militarycrate", "ArmyStorageMedical" },
            { "armystorage", "militarycrate", "ArmyStorageElectronics" },
        },
        medical = {
            { "medicalstorage", "metal_shelves", "MedicalClinicDrugs" },
            { "medicalstorage", "metal_shelves", "MedicalClinicTools" },
            { "pharmacystorage", "other", "MedicalClinicDrugs" },
            { "hospitalstorage", "other", "MedicalStorageDrugs" },
        },
        -- THE PAYOUT FOLLOWS THE BOX, AND IS WORTH ITS EFFORT. Valuables alone are flavour in this
        -- game (gems and cash have no use, gold and silver only feed the forge), so every kind
        -- below the crate mixes one useful list in with them. A list appears once per share it
        -- gets: each payout roll draws one entry.
        -- A lockbox is a person's own stash: the handgun and its rounds, their medicine, and the
        -- floorboard odds and ends (jewellery, smokes, a flask). PlankStashMoney is no list of its
        -- own anywhere: cards, certificates and bundles of cash have no use in 42, and the gun and
        -- misc stashes already carry loose money.
        personal = {
            { "bedroom", "plankstash", "PlankStashGun" },
            { "gunstore", "counter", "GunStoreAmmunition" },
            { "dentist", "counter", "MedicalClinicDrugs" },
            { "bedroom", "plankstash", "PlankStashMisc" },
        },
        -- A footlocker is kit put away: a soldier's locker, camping and survival gear, ammunition.
        gear = {
            { "armytent", "locker", "LockerArmyBedroom" },
            { "storageunit", "other", "SurvivalGear" },
            { "storageunit", "other", "CrateCamping" },
            { "gunstore", "counter", "GunStoreAmmunition" },
        },
        -- A safe at home, in an office or a pawn shop: the gun and its rounds, the medicine, and the
        -- jewellery, whose gold and silver feed the forge. Not MayorWestPointSafe: its item list
        -- is empty in 42.22.2.
        safe = {
            { "bedroom", "plankstash", "PlankStashGun" },
            { "gunstore", "counter", "GunStoreAmmunition" },
            { "hospitalstorage", "other", "MedicalStorageDrugs" },
            { "jewelrystorage", "filingcabinet", "JewelryStorageAll" },
        },
        -- A police safe: the station's guns, twice the ammunition, and the evidence locker.
        safe_police = {
            { "captainoffice", "locker", "PoliceStorageGuns" },
            { "gunstore", "counter", "GunStoreAmmunition" },
            { "gunstore", "counter", "GunStoreAmmunition" },
            { "evidenceroom", "other", "PoliceEvidence" },
        },
        -- A bank or jeweller's vault, the deposit boxes people trusted most: a handgun and its
        -- rounds, the prescriptions, gold bars and jewellery for the forge. Rich, so three rolls.
        safe_vault = {
            { "bedroom", "plankstash", "PlankStashGun" },
            { "gunstore", "counter", "GunStoreAmmunition" },
            { "hospitalstorage", "other", "MedicalStorageDrugs" },
            { "bedroom", "plankstash", "PlankStashGold" },
            { "jewelrystorage", "filingcabinet", "JewelryStorageAll" },
        },
        -- A gun store's back-room safe: the stock it locked away, handguns and shotguns, and the rounds.
        safe_gunstore = {
            { "captainoffice", "locker", "PoliceStorageGuns" },
            { "gunstore", "counter", "GunStoreAmmunition" },
            { "gunstore", "counter", "GunStoreAmmunition" },
            { "bedroom", "plankstash", "PlankStashGun" },
        },
        -- A pharmacy's drug safe: the controlled stock, antibiotics and painkillers, and the dressings.
        safe_pharmacy = {
            { "hospitalstorage", "other", "MedicalStorageDrugs" },
            { "hospitalstorage", "other", "MedicalStorageDrugs" },
            { "dentist", "counter", "MedicalClinicDrugs" },
            { "armystorage", "militarycrate", "ArmyStorageMedical" },
        },
        default = {
            { "storageunit", "other", "CrateCamping" },
            { "storageunit", "other", "SurvivalGear" },
            { "storageunit", "other", "Hiker" },
            { "storageunit", "other", "MechanicSpecial" },
            { "storageunit", "other", "CrateTools" },
        },
    }

    -- A crate's theme by its room's exact name, for every room that can hide one (Spots); any other
    -- is the default. A substring once paid a pharmacy's storeroom planks and nails as "storage".
    M.THEME_ROOMS = {
        armystorage = "military", armysurplus = "military",
        garage = "garage", garagestorage = "garage", mechanic = "garage",
        farmstorage = "farm", barn = "farm", shed = "farm",
        medicalstorage = "medical", pharmacystorage = "medical",
        warehouse = "warehouse", storage = "warehouse", storageunit = "warehouse", officestorage = "warehouse",
        grocerystorage = "warehouse", producestorage = "warehouse", gunstorestorage = "warehouse",
        policestorage = "warehouse", pawnshopstorage = "warehouse",
    }
    M.THEME_CONTAINERS = { militarycrate = "military", toolcabinet = "garage" }
    -- The mod's own boxes other than the crate hold what their kind promises, in any room: the
    -- inspect hint says cash and valuables for a lockbox, gear for a footlocker.
    M.KIND_THEMES = {
        dmslockbox = "personal", dmsfootlocker = "gear", dmsdialsafe = "safe", dmskeypadsafe = "safe",
    }
    -- A keypad safe's room makes its theme richer, by the room's exact name (Spots.KEYPAD_ORDER).
    M.SAFE_ROOM_THEMES = {
        policegunstorage = "safe_police", evidenceroom = "safe_police", policestorage = "safe_police",
        captainoffice = "safe_police",
        vault = "safe_vault", depositboxes = "safe_vault", bankstorage = "safe_vault", jewelrystorage = "safe_vault",
        gunstorestorage = "safe_gunstore", pharmacystorage = "safe_pharmacy",
    }

    -- BruteDamage index -> what brute force does. 1 (Off) has no entry. breakPct is the chance a
    -- fragile item is destroyed; an item with condition loses 1..wearPct percent of its maximum.
    -- M.BRUTE_LIGHT is a route's light brute force (Gates brute = "light"): a forced lock jars
    -- the box without smashing it.
    M.BRUTE_LIGHT = "light"
    M.BRUTE = {
        [2] = { breakPct = 25, wearPct = 10 },
        [3] = { breakPct = 50, wearPct = 25 },
        [4] = { breakPct = 80, wearPct = 50 },
        [M.BRUTE_LIGHT] = { breakPct = 10, wearPct = 5 },
    }

    --- 0..n-1. Replace it to make a payout deterministic.
    M.payoutRand = function(n) return ZombRand(n) end

    --- The theme id for a gate, from its room name and container type. Pure: the fill can run
    --- before the resolve.
    function M.themeFor(roomName, containerType)
        local own = type(containerType) == "string" and M.KIND_THEMES[containerType] or nil
        if own == "safe" and type(roomName) == "string" and M.SAFE_ROOM_THEMES[roomName] ~= nil then
            return M.SAFE_ROOM_THEMES[roomName]
        end
        if own ~= nil then return own end
        if type(roomName) == "string" and M.THEME_ROOMS[roomName] ~= nil then return M.THEME_ROOMS[roomName] end
        local byContainer = type(containerType) == "string" and M.THEME_CONTAINERS[containerType] or nil
        return byContainer or M.DEFAULT_THEME
    end

    local resolved = nil

    local function javaList(room, container, list)
        if ItemPickerJava == nil then return nil end
        local ok, dist = pcall(ItemPickerJava.getItemContainer, room, container, list, false)
        if not ok then return nil end
        return dist
    end

    local function reachable(t)
        local lists = ProceduralDistributions ~= nil and ProceduralDistributions.list or nil
        if type(lists) ~= "table" or lists[t[3]] == nil then return false, "missing" end
        local dist = javaList(t[1], t[2], t[3])
        if dist == nil then return false, "unreachable" end
        local own = javaList(t[1], t[2], "")
        if own ~= nil and own == dist then return false, "unreachable" end
        return true
    end

    --- Rebuild the resolved themes from M.THEMES. Runs once per world; a second start event is a
    --- no-op, so the defect line is printed once.
    function M.resolveThemes()
        if resolved ~= nil then return resolved end
        local out, dropped = {}, {}
        for id, triples in pairs(M.THEMES) do
            local kept = {}
            for i = 1, #triples do
                local t = triples[i]
                local ok, why = reachable(t)
                if ok then
                    kept[#kept + 1] = t
                else
                    dropped[#dropped + 1] = id .. ":" .. t[3] .. " (" .. why .. ")"
                end
            end
            if #kept > 0 then out[id] = kept end
        end
        resolved = out
        if #dropped > 0 then
            table.sort(dropped)
            M.defect(PART, "loot list(s) dropped: " .. table.concat(dropped, ", "))
        end
        if out[M.DEFAULT_THEME] == nil then
            M.defect(PART, "the default theme resolved empty: a gate with no theme of its own pays nothing")
        elseif ItemTag == nil or ItemTag.GLASS == nil or ItemTag.SHOW_CONDITION == nil then
            M.defect(PART, "ItemTag.GLASS or ItemTag.SHOW_CONDITION is gone: brute force breaks nothing")
        elseif #dropped == 0 then
            M.status(PART, true)
        end
        return out
    end

    local function onWorldStart()
        if not M.isWorldAuthority() then return end
        M.resolveThemes()
    end

    --- The triples a theme id rolls from: its own, or the default's when it has none left.
    function M.themeLists(themeId)
        local themes = M.resolveThemes()
        return themes[themeId] or themes[M.DEFAULT_THEME]
    end

    local function hasTag(item, tag)
        if tag == nil then return false end
        local ok, v = pcall(function() return item:hasTag(tag) end)
        return ok and v == true
    end

    -- ItemPickerJava.trashItem's own test for an item whose condition means something
    -- (ItemPickerJava.java:1690): every item has a conditionMax, 10 by default (Item.java:134).
    local function hasCondition(item)
        if ItemTag ~= nil and hasTag(item, ItemTag.SHOW_CONDITION) then return true end
        return instanceof ~= nil and instanceof(item, "HandWeapon") == true
    end

    local function snapshot(container)
        local list = container:getItems()
        local out = {}
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        return out
    end

    --- Brute force on what is in the container now. Returns how many items it destroyed.
    local function bruteForce(container, damageLevel)
        local profile = M.BRUTE[damageLevel]
        if profile == nil then return 0 end
        local glass = ItemTag ~= nil and ItemTag.GLASS or nil
        local broken = 0
        local items = snapshot(container)
        for i = 1, #items do
            local item = items[i]
            -- base:glass is the B42 fragile signal: jars, bottles, glassware (ItemTag.java:166).
            if hasTag(item, glass) then
                if M.payoutRand(100) < profile.breakPct then
                    container:Remove(item)
                    broken = broken + 1
                end
            elseif hasCondition(item) then
                local cond = item:getCondition()
                -- Above 1 only: never to 0 (broken), and a broken item is not mended back to 1.
                if cond > 1 then
                    local loss = math.max(1,
                        math.floor(item:getConditionMax() * (M.payoutRand(profile.wearPct) + 1) / 100))
                    item:setConditionNoSound(math.max(1, cond - loss))
                end
            end
        end
        return broken
    end

    --- Roll the gate's payout into its container. Authority only: anywhere else it changes nothing
    --- and returns nil. 1 + PayoutRolls * tier rolls, each from one of the theme's lists, then
    --- brute force when damageLevel (a BruteDamage index) is above 1 (Off).
    --- Returns { added = items left in the container by the payout, broken = items it destroyed }.
    function M.payout(container, md, damageLevel)
        if not M.isWorldAuthority() then return nil end
        if container == nil or type(md) ~= "table" then return nil end
        local before = container:getItems():size()
        local lists = M.themeLists(md.theme)
        if lists ~= nil then
            local tier = M.clamp(math.floor(M.finite(md.tier) or 1), 1, 3)
            -- One list per step of quality (1, 2, 3), each extra sandbox roll another set: a census
            -- of 300 rolls per kind found 12 to 27 items a box at 1 + tier, a gun in half the lockboxes.
            local rolls = tier * (1 + M.cfg("PayoutRolls"))
            for _ = 1, rolls do
                local t = lists[M.payoutRand(#lists) + 1]
                local dist = javaList(t[1], t[2], t[3])
                if dist == nil then
                    M.defect(PART, t[1] .. "/" .. t[2] .. "/" .. t[3] .. " stopped answering after the resolve")
                else
                    local ok, err = pcall(ItemPickerJava.rollItem, dist, container, true, nil, nil)
                    if not ok then M.defect(PART, "rollItem failed on " .. t[3] .. ": " .. tostring(err)) end
                end
            end
        end
        local broken = bruteForce(container, damageLevel)
        return { added = container:getItems():size() - before, broken = broken }
    end

    M.addHandler(PART, "OnGameStart", onWorldStart)
    M.addHandler(PART, "OnServerStarted", onWorldStart)
    M.addTeardown(PART, function() resolved = nil end)

    -- Reported at load so the boot line, printed by Core's earlier start handler, lists the part;
    -- the resolve's verdict replaces it.
    if M.isWorldAuthority() then
        M.status(PART, true)
    else
        M.status(PART, true, "the authority rolls payouts")
    end
end
