--[[
    Gates
    What a gate is and what each way of opening it costs: the gate kinds, the container types
    each kind takes, the route table, and the trait, profession and skill math on top of it.

    PURE ON PURPOSE. The client menu shows these numbers and the authority re-derives them from
    its own player object before it honours a submit, so both must compute the same answer from
    the same inputs. Nothing here registers an event or writes to the world. Every read of the
    player (traits, profession, perks, inventory) goes through one small accessor, so a stub
    player drives the whole module offline.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Spots"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Gates"

    M.GATE_VERSION = 1

    -- The mod's own trait, granted by its trait registry.
    M.LOCKSMITH_TRAIT = "lugli_dms:dms_locksmith"

    -- The safes' refusals, which the route table names.
    M.REASON_LOCKED_OUT = "IGUI_LugliDMS_LockedOut"
    M.REASON_NO_POWER = "IGUI_LugliDMS_NoPower"
    M.REASON_HAS_POWER = "IGUI_LugliDMS_HasPower"
    M.REASON_DEAF = "IGUI_LugliDMS_Deaf"
    M.REASON_NEEDS_ELECTRICITY = "IGUI_LugliDMS_NeedsElectricity"
    M.REASON_NEEDS_METALWORKING = "IGUI_LugliDMS_NeedsMetalworking"
    M.REASON_NO_FUEL = "IGUI_LugliDMS_NoFuel"
    M.REASON_NO_SCRAP = "IGUI_LugliDMS_NoScrap"
    M.REASON_NO_BATTERY = "IGUI_LugliDMS_NoBattery"
    -- The safes' outcomes, which the authority replies with: a wrong code (arg: tries left), a
    -- lockout, the alarm, a digit the manipulation found (arg: the masked code), a manipulation
    -- that found nothing, and a keypad a battery powered.
    M.REASON_WRONG_CODE = "IGUI_LugliDMS_WrongCode"
    M.REASON_LOCKOUT = "IGUI_LugliDMS_Lockout"
    M.REASON_ALARM = "IGUI_LugliDMS_Alarm"
    M.REASON_REVEALED = "IGUI_LugliDMS_Revealed"
    M.REASON_DIAL_SLIPS = "IGUI_LugliDMS_DialSlips"
    M.REASON_POWERED = "IGUI_LugliDMS_Powered"

    -- THE ROUTE TABLE. items are item full types and tools are ItemTag field names, resolved at
    -- call time; an intact item of any listed type or tag opens the route, items tried first.
    -- xp.perk is a Perks field name; World.lua resolves it and owns the claw's nail salvage.
    -- damage is full brute force (the BruteDamage setting), brute = "light" the light level.
    -- wear: World damages the tool. chance: base + step * (perk - from), capped at max, the odds
    -- the authority's roll opens it; jams: a failed roll jams the lock. A key route takes no tool.
    -- traits: any one of them is required; maxTier and minPerk bound who and what it opens.
    -- wrecks: the route tears the box open, so it can never be carried away after (Carry.lua);
    -- every other route undoes or breaks only the lock.
    -- spends: by item full type, what a failed roll does to the tool when it is one of them: "use"
    -- uses it up, "wear" takes one condition and uses it up at its last, as Neat Lockpicking's own
    -- picks do (Gates.spendPick). skill: XP in another perk on an opened and on a failed roll; a
    -- perk no loaded mod defines trains nothing. chance.perks: odds added per level of each perk;
    -- chance.tools: odds added by the tool's full type.
    M.ROUTES = {
        pry = {
            seconds = 12, noise = 8, damage = false, wear = true,
            tools = { "CROWBAR", "PRY_BAR" },
            xp = { perk = "Strength", amount = 4 },
        },
        claw = {
            seconds = 20, noise = 6, damage = false, wear = true,
            tools = { "HAMMER" },
            xp = { perk = "Woodwork", amount = 5 },
        },
        smash = {
            seconds = 4, noise = 12, damage = true, wear = true, wrecks = true,
            tools = { "SLEDGEHAMMER", "CHOP_TREE" },
        },
        key = {
            seconds = 1, noise = 0, damage = false, key = true,
        },
        pick = {
            seconds = 15, noise = 1, damage = false, finesse = true, jams = true,
            -- Neat Lockpicking's store and handmade picks before a paperclip, the screwdriver last.
            items = { "NeatLockpicking.Lockpick", "NeatLockpicking.HandmadeLockpick", "Base.Paperclip" },
            tools = { "SCREWDRIVER" },
            spends = { ["Base.Paperclip"] = "use", ["NeatLockpicking.HandmadeLockpick"] = "use",
                       ["NeatLockpicking.Lockpick"] = "wear" },
            traits = { "BURGLAR", M.LOCKSMITH_TRAIT },
            chance = { perk = "Nimble", base = 0.30, from = 0, step = 0.07, max = 0.9,
                perks = { Lockpicking = 0.05 }, tools = { ["NeatLockpicking.Lockpick"] = 0.10 } },
            xp = { perk = "Nimble", amount = 4 },
            skill = { perk = "Lockpicking", opened = 20, failed = 2 },
        },
        force = {
            seconds = 6, noise = 9, damage = false, brute = "light", wear = true,
            tools = { "CROWBAR", "PRY_BAR" },
            xp = { perk = "Strength", amount = 3 },
        },
        jimmy = {
            seconds = 30, noise = 2, damage = false, finesse = true, maxTier = 1,
            tools = { "SCREWDRIVER" },
        },
        cut = {
            seconds = 3, noise = 3, damage = false, wear = true,
            tools = { "BOLT_CUTTERS" },
        },
        snap = {
            seconds = 8, noise = 10, damage = false,
            tools = { "CROWBAR" },
            minPerk = { perk = "Strength", level = 4 },
            chance = { perk = "Strength", entry = 0.15, base = 0.4, from = 5, step = 0.05, max = 1 },
            xp = { perk = "Strength", amount = 3 },
        },

        -- THE SAFES (docs/31 section 8). code: the authority compares the typed code; the route
        -- only says whether the keypad or dial takes one now. powered: a keypad needs power (a dial
        -- never does); unpowered: only a keypad without power. lockout: refused while locked out.
        -- fresh: the work is never saved, a put-down try starts over. consumes: items one try
        -- uses up whatever the outcome, each with the refusal when it is missing. fuel: blow torch
        -- uses a try burns. burn: the odds each paper, money and food item burns, and the lower
        -- odds for its profession. alarm: a failed roll trips the alarm and a lockout.
        -- wearsSession: World wears the tool on every session, a put-down one included.
        -- chance.traits adds per held trait; chance.fromFloor counts levels over minPerk's floor.
        -- chance.entry: the odds at the floor itself, one level before base; burn.step: what each
        -- level of burn.perk over burn.from takes off the burn odds.
        -- Half a second: the code was typed in its window, so the submit is only the handle turning
        -- (4 s until 2026-11-19, when the user found the wait after OK strange).
        code = {
            seconds = 0.5, noise = 0, damage = false, code = true, powered = true, lockout = true, fresh = true,
        },
        manipulate = {
            seconds = 15, noise = 0, damage = false, lockout = true, fresh = true, hears = true,
            items = { "Base.Stethoscope" },
            chance = { perk = "Nimble", base = 0.40, from = 0, step = 0.05, max = 0.9,
                traits = { KEEN_HEARING = 0.15, HARD_OF_HEARING = -0.30, BURGLAR = 0.25, [M.LOCKSMITH_TRAIT] = 0.30 } },
            xp = { perk = "Nimble", amount = 3 },
        },
        -- The no-skill, no-clue way in, so the slowest, and loud for all of it.
        drill = {
            seconds = 120, noise = 10, damage = false, wear = true, wearsSession = true, wrecks = true,
            items = { "Base.HandDrill" }, tools = { "DRILL_METAL" },
        },
        torch = {
            seconds = 60, noise = 6, damage = false, fuel = 4, wrecks = true,
            items = { "Base.BlowTorch" }, tools = { "BLOW_TORCH" },
            minPerk = { perk = "MetalWelding", level = 3, profession = "METALWORKER", professionLevel = 0,
                reason = M.REASON_NEEDS_METALWORKING },
            burn = { chance = 0.2, profession = "METALWORKER", professionChance = 0.1,
                perk = "MetalWelding", from = 3, step = 0.015 },
            xp = { perk = "MetalWelding", amount = 5 },
        },
        bypass = {
            seconds = 30, noise = 2, damage = false, powered = true, lockout = true, fresh = true, alarm = true,
            tools = { "SCREWDRIVER" },
            consumes = { { item = "Base.ElectronicsScrap", reason = M.REASON_NO_SCRAP } },
            minPerk = { perk = "Electricity", level = 3, profession = "ELECTRICIAN", professionLevel = 1,
                reason = M.REASON_NEEDS_ELECTRICITY },
            chance = { perk = "Electricity", entry = 0.15, base = 0.40, fromFloor = true, step = 0.10, max = 0.9 },
            xp = { perk = "Electricity", amount = 5 },
        },
        battery = {
            seconds = 3, noise = 0, damage = false, unpowered = true, fresh = true,
            consumes = { { item = "Base.Battery", charged = true, reason = M.REASON_NO_BATTERY } },
        },
    }

    -- THE GATE KINDS. containers maps an exact container type to its base tier; routes is the
    -- fixed order the menu lists them in. Every container is one of the mod's own boxes
    -- (Spots.GATE_BOXES): no map container is ever a gate, so where a stash sits is always this
    -- mod's choice.
    M.KINDS = {
        crate = {
            containers = { [M.GATE_BOXES.crate.container] = 1 },
            routes = { "pry", "claw", "smash" },
        },
        lockbox = {
            containers = { [M.GATE_BOXES.lockbox.container] = 1 },
            routes = { "key", "pick", "force", "jimmy" },
        },
        footlocker = {
            containers = { [M.GATE_BOXES.footlocker.container] = 1 },
            routes = { "key", "cut", "snap" },
        },
        -- A safe starts a tier up. keypad: its code and bypass need power.
        dialsafe = {
            containers = { [M.GATE_BOXES.dialsafe.container] = 2 },
            routes = { "code", "manipulate", "drill", "torch" },
        },
        keypadsafe = {
            containers = { [M.GATE_BOXES.keypadsafe.container] = 2 },
            routes = { "code", "battery", "bypass", "drill", "torch" },
            keypad = true,
        },
    }

    -- THE KEYS. Every key the mod mints has an id in [KEY_ID_BASE, KEY_ID_BASE + KEY_ID_SPAN); a
    -- gate opens only to a key in that range, so any other key the survivor holds never counts.
    M.KEY_ID_BASE = 1900000000
    M.KEY_ID_SPAN = 100000000

    -- Rooms whose own loot is military, weapons or pawned stock, and the bunkers a prepper
    -- built: a stash there is one tier richer.
    M.RICH_ROOMS = {
        armystorage = true, armysurplus = true, gunstore = true, gunstorestorage = true,
        policestorage = true, pawnshopstorage = true, bunker = true,
        -- A bank's or jeweller's back room keeps only a keypad safe: the hardest box pays the most.
        vault = true, depositboxes = true, bankstorage = true, jewelrystorage = true,
    }

    -- MODIFIERS. Strength 5 is the unmodified baseline, as every new character starts there.
    M.STRENGTH_BASE = 5
    M.STRENGTH_STEP = 0.05
    M.STRENGTH_MIN_FACTOR = 0.75
    M.STRENGTH_MAX_FACTOR = 1.25
    -- Woodwork 10 (the cap) claws in 60% of the time.
    M.WOODWORK_STEP = 0.04
    M.PERK_MAX = 10
    M.CARPENTER_FACTOR = 0.7
    M.DEXTROUS_FACTOR = 0.8
    M.ALL_THUMBS_FACTOR = 1.25
    M.BURGLAR_NOISE_FACTOR = 0.7
    -- A Locksmith picks and jimmies in 80% of the time.
    M.LOCKSMITH_FACTOR = 0.8
    -- Listening at a dial (a `hears` route): a keen ear finds the gates sooner, a dulled one
    -- has to turn the dial over twice.
    M.KEEN_HEARING_FACTOR = 0.75
    M.HARD_OF_HEARING_FACTOR = 2

    M.REASON_NOT_SEALED = "IGUI_LugliDMS_NotSealed"
    M.REASON_UNKNOWN_ROUTE = "IGUI_LugliDMS_UnknownRoute"
    M.REASON_NO_TOOL = "IGUI_LugliDMS_NoTool"
    M.REASON_TOOL_BROKEN = "IGUI_LugliDMS_ToolBroken"
    M.REASON_NO_KEY = "IGUI_LugliDMS_NoKey"
    M.REASON_WRONG_KEY = "IGUI_LugliDMS_WrongKey"
    M.REASON_JAMMED = "IGUI_LugliDMS_Jammed"
    -- The odds a failed roll on a route that jams leaves the lock jammed for good.
    M.JAM_CHANCE = 0.05
    M.REASON_NEEDS_TRAIT = "IGUI_LugliDMS_NeedsTrait"
    M.REASON_TOO_STURDY = "IGUI_LugliDMS_TooSturdy"
    M.REASON_TOO_WEAK = "IGUI_LugliDMS_TooWeak"

    -- ---- accessors: the only places that touch the player ----------------------------------------

    --- A vanilla trait by its CharacterTrait field name, else a registered one by its resource id
    --- ("lugli_dms:dms_locksmith"); nil when neither resolves.
    local function traitOf(name)
        if CharacterTrait == nil then return nil end
        local vanilla = CharacterTrait[name]
        if vanilla ~= nil then return vanilla end
        local ok, trait = pcall(function() return CharacterTrait.get(ResourceLocation.of(name)) end)
        if ok then return trait end
        return nil
    end

    local function hasTrait(player, name)
        local trait = traitOf(name)
        if trait == nil then return false end
        local ok, v = pcall(function() return player:hasTrait(trait) end)
        return ok and v == true
    end

    local function hasAnyTrait(player, names)
        for i = 1, #names do
            if hasTrait(player, names[i]) then return true end
        end
        return false
    end

    local function isProfession(player, name)
        if CharacterProfession == nil or CharacterProfession[name] == nil then return false end
        local ok, v = pcall(function()
            local desc = player:getDescriptor()
            return desc ~= nil and desc:isCharacterProfession(CharacterProfession[name])
        end)
        return ok and v == true
    end

    --- World.lua's claw salvage reads the same profession test.
    function M.isCarpenter(player) return isProfession(player, "CARPENTER") end

    --- A perk by name: a vanilla Perks field, else one a mod's perks.txt defines (Perks.FromString,
    --- which answers MAX for a name nothing defines); nil for none.
    function M.perkOf(name)
        if Perks == nil or type(name) ~= "string" then return nil end
        local vanilla = Perks[name]
        if vanilla ~= nil then return vanilla end
        if Perks.FromString == nil then return nil end
        local ok, perk = pcall(Perks.FromString, name)
        if not ok or perk == nil or perk == Perks.MAX then return nil end
        return perk
    end

    local function perkLevel(player, name)
        local perk = M.perkOf(name)
        if perk == nil then return 0 end
        local ok, v = pcall(function() return player:getPerkLevel(perk) end)
        return ok and M.finite(v) or 0
    end

    --- Give `player` `amount` XP in the perk named `name`; nothing for a perk none defines.
    function M.grantXp(player, name, amount)
        local perk = M.perkOf(name)
        if perk == nil or addXp == nil or type(amount) ~= "number" or amount <= 0 then return end
        pcall(addXp, player, perk, amount)
    end

    local function fullTypeOf(item)
        if item == nil then return nil end
        local ok, full = pcall(function() return item:getFullType() end)
        return ok and full or nil
    end

    --- What a failed roll does to `tool` on a route: "use", "wear" or false.
    function M.spendKind(def, tool)
        if def == nil or type(def.spends) ~= "table" then return false end
        return def.spends[fullTypeOf(tool) or ""] or false
    end

    --- What a failed roll's halo adds for a spend kind: "" for none.
    function M.spentText(kind)
        if kind == "wear" then return " " .. M.T("IGUI_LugliDMS_PickWorn", "The lockpick wears down.") end
        if kind == "use" then return " " .. M.T("IGUI_LugliDMS_ClipSpent", "The tool is used up.") end
        return ""
    end

    --- WHAT A ROUTE'S LIST SAYS OF IT, as data, so the menu, the inspect window and the door pick
    --- never disagree: whole seconds (at least 1, of the work still to do when `left`), noise in
    --- tiles, the odds as a whole percent (100 for no roll), and the warnings that apply.
    function M.routeFacts(route)
        local chance = M.finite(route.chance) or 1
        local rolls = chance < 1
        return {
            seconds = math.max(1, math.floor((M.finite(route.seconds) or 0) + 0.5)),
            left = route.resumed == true,
            noise = math.max(0, M.finite(route.noise) or 0),
            chance = math.floor(chance * 100 + 0.5),
            jams = rolls and route.jams == true,
            spends = rolls and (route.spends == "wear" or route.spends == "use") and route.spends or nil,
            wrecks = route.wrecks == true,
            breaks = (route.damage == true or route.brute ~= nil) and (M.finite(M.cfg("BruteDamage")) or 1) > 1,
            alarm = route.alarm == true,
            burns = (M.finite(route.burn) or 0) > 0,
        }
    end

    --- The facts as the lines of a context-menu tooltip (rich text), for the menu and the door pick.
    function M.routeFactsTip(f)
        local PLAIN, BAD = " <RGB:1,1,1> ", " <RGB:0.95,0.6,0.5> "
        local function line(c, s) return c .. s .. " <LINE> " end
        local text = ""
        if f.chance < 100 then
            text = text .. line(PLAIN, M.T("Tooltip_LugliDMS_Chance", "Chance") .. ": " .. f.chance .. "%")
        end
        if f.jams then text = text .. line(BAD, M.T("Tooltip_LugliDMS_MayJam", "A failed try can jam the lock")) end
        if f.spends == "wear" then
            text = text .. line(BAD, M.T("Tooltip_LugliDMS_Wears", "A failed try wears the lockpick down"))
        elseif f.spends == "use" then
            text = text .. line(BAD, M.T("Tooltip_LugliDMS_Spends", "A failed try uses up the tool"))
        end
        if f.wrecks then
            text = text .. line(BAD, M.T("Tooltip_LugliDMS_Wrecks", "Wrecks the box: it can't be carried away after"))
        end
        local unit = f.seconds == 1 and M.T("Tooltip_LugliDMS_Second", "second") or M.T("Tooltip_LugliDMS_Seconds", "seconds")
        local label = f.left and M.T("Tooltip_LugliDMS_TimeLeft", "Time left") or M.T("Tooltip_LugliDMS_Time", "Time")
        text = text .. line(PLAIN, label .. ": " .. f.seconds .. " " .. unit)
        if f.noise <= 0 then
            text = text .. line(PLAIN, M.T("Tooltip_LugliDMS_Silent", "Makes no noise"))
        else
            text = text .. line(PLAIN, M.Tf("Tooltip_LugliDMS_Noise", "Heard up to %1 tiles away", f.noise))
        end
        if f.breaks then text = text .. line(BAD, M.T("Tooltip_LugliDMS_Damage", "Fragile things inside may break")) end
        if f.alarm then
            text = text .. line(BAD, M.T("Tooltip_LugliDMS_Alarm", "A failed try sets off the alarm and locks it"))
        end
        if f.burns then text = text .. line(BAD, M.T("Tooltip_LugliDMS_Burns", "Paper, money and food inside may burn")) end
        return text
    end

    --- A failed roll's cost to the tool: "wear" takes one condition; "use", or a worn pick at its
    --- last, removes it from its container, mirrored to the clients in multiplayer.
    function M.spendPick(tool, kind)
        if tool == nil or (kind ~= "use" and kind ~= "wear") then return end
        if kind == "wear" then
            local ok, cond = pcall(function() return tool:getCondition() end)
            cond = ok and M.finite(cond) or 0
            if cond > 1 then
                pcall(function() tool:setCondition(cond - 1) end)
                if M.isMultiplayer() then pcall(function() tool:syncItemFields() end) end
                return
            end
        end
        local okC, container = pcall(function() return tool:getContainer() end)
        if not okC or container == nil then return end
        container:Remove(tool)
        if M.isMultiplayer() and sendRemoveItemFromContainer ~= nil then
            pcall(sendRemoveItemFromContainer, container, tool)
        end
    end

    local function notBroken(item) return not item:isBroken() end

    local function inventoryOf(player)
        local ok, inv = pcall(function() return player:getInventory() end)
        if ok then return inv end
        return nil
    end

    local function usesOf(item)
        local ok, v = pcall(function() return item:getCurrentUses() end)
        return ok and M.finite(v) or 0
    end

    --- The first usable (by default intact) item of any listed full type or tag, else (nil, the
    --- first one held that is not usable).
    local function findTool(player, tags, items, usable)
        usable = usable or notBroken
        local inv = inventoryOf(player)
        if inv == nil then return nil, nil end
        for i = 1, #items do
            local ok, item = pcall(function() return inv:getFirstTypeEvalRecurse(items[i], usable) end)
            if ok and item ~= nil then return item, nil end
        end
        if ItemTag ~= nil then
            for i = 1, #tags do
                local tag = ItemTag[tags[i]]
                if tag ~= nil then
                    local ok, item = pcall(function() return inv:getFirstTagEvalRecurse(tag, usable) end)
                    if ok and item ~= nil then return item, nil end
                end
            end
        end
        for i = 1, #items do
            local ok, item = pcall(function() return inv:getFirstTypeRecurse(items[i]) end)
            if ok and item ~= nil then return nil, item end
        end
        if ItemTag ~= nil then
            for i = 1, #tags do
                local tag = ItemTag[tags[i]]
                if tag ~= nil then
                    local ok, item = pcall(function() return inv:getFirstTagRecurse(tag) end)
                    if ok and item ~= nil then return nil, item end
                end
            end
        end
        return nil, nil
    end

    --- Is this a key id the mod mints?
    function M.isGateKeyId(id)
        return type(id) == "number" and id == math.floor(id)
            and id >= M.KEY_ID_BASE and id < M.KEY_ID_BASE + M.KEY_ID_SPAN
    end

    local function isGateKey(item) return M.isGateKeyId(item:getKeyId()) end

    --- A key ring, by ItemContainer.haveThisKeyId's own test: its type, or the KeyRing tag.
    local function isKeyRing(item)
        if item:getType() == "KeyRing" then return true end
        return ItemTag ~= nil and ItemTag.KEY_RING ~= nil and item:hasTag(ItemTag.KEY_RING)
    end

    --- The first key the mod minted where ItemContainer.haveThisKeyId looks for a door's key: the
    --- container's own items and the key rings among them, never inside a bag.
    local function firstGateKey(container)
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if instanceof(item, "Key") then
                if isGateKey(item) then return item end
            elseif isKeyRing(item) then
                local found = firstGateKey(item:getInventory())
                if found ~= nil then return found end
            end
        end
        return nil
    end

    --- The key that opens this gate, found where a door's key is (main inventory and key rings):
    --- with keyId (the authority, passing the stored id), only that exact key, by the engine's own
    --- haveThisKeyId; without it (the client, which never sees the id), any key the mod minted.
    local function findKey(player, keyId)
        local inv = inventoryOf(player)
        if inv == nil then return nil end
        local ok, item
        if keyId ~= nil then
            ok, item = pcall(function() return inv:haveThisKeyId(keyId) end)
        else
            ok, item = pcall(firstGateKey, inv)
        end
        if ok then return item end
        return nil
    end

    -- ---- the gate --------------------------------------------------------------------------------

    --- The gate kind that takes this container type, or nil.
    function M.kindForContainer(containerType)
        if type(containerType) ~= "string" then return nil end
        for id, kind in pairs(M.KINDS) do
            if kind.containers[containerType] ~= nil then return id end
        end
        return nil
    end

    --- Does a keypad have power: a battery was put in (md.powered, from the authority's record),
    --- or its square has power from the grid (hasGridPower) or a generator (haveElectricity,
    --- which counts generators only).
    function M.keypadPowered(md, square)
        if type(md) == "table" and md.powered == true then return true end
        if square == nil then return false end
        local ok, v = pcall(function() return square:hasGridPower() or square:haveElectricity() end)
        return ok and v == true
    end

    --- The world's age in game hours, or nil when there is no clock to read.
    function M.worldHours()
        local ok, v = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then return M.finite(v) end
        return nil
    end

    --- Game hours left on a safe's lockout, from md.lockedUntil: 0 when free (absent, junk, 0 or
    --- past). With no clock to read, a set lockout counts as running: lockedUntil itself.
    function M.lockedFor(md)
        local untilHour = type(md) == "table" and M.finite(md.lockedUntil) or nil
        if untilHour == nil or untilHour <= 0 then return 0 end
        local now = M.worldHours()
        if now == nil then return untilHour end
        return math.max(0, untilHour - now)
    end

    --- " #12" for a box numbered 12 (Gating.numberGate), "" for one with none: what a box's
    --- title, its key's name and its notes' names end in.
    function M.numberSuffix(no)
        local n = tonumber(no)
        if n == nil then return "" end
        return " #" .. tostring(math.floor(n))
    end

    --- 1..3 for an eligible container type, nil otherwise.
    function M.tierFor(containerType, roomName)
        local kind = M.kindForContainer(containerType)
        if kind == nil then return nil end
        local tier = M.KINDS[kind].containers[containerType]
        if type(roomName) == "string" and M.RICH_ROOMS[roomName] then tier = tier + 1 end
        return M.clamp(tier, 1, 3)
    end

    --- The name of the sprite the object shows now. getSpriteName is not it: setSprite(IsoSprite)
    --- and the client's UpdateItemSprite packet both swap the sprite and leave that name stale.
    function M.liveSpriteName(obj)
        if obj == nil then return nil end
        -- pcall on the method itself: a closure here would be garbage on every object asked about.
        local ok, sprite = pcall(obj.getSprite, obj)
        if not ok or sprite == nil then return nil end
        return sprite:getName()
    end

    --- The object's gate record when it is a well-formed one on a box of its kind showing its
    --- state, else nil. Object modData is client-writable (docs/31 section 7): a tag stamped on a
    --- fridge, or a sealed tag on an opened box, is no gate.
    function M.gateRecord(obj)
        if obj == nil then return nil end
        -- The sprite first, and hasModData before getModData, which creates a table on any object.
        local kind, opened = M.kindOfSprite(M.liveSpriteName(obj))
        if kind == nil then return nil end
        local okHas, has = pcall(obj.hasModData, obj)
        if not okHas or has ~= true then return nil end
        local ok, md = pcall(obj.getModData, obj)
        if not ok or type(md) ~= "table" then return nil end
        local rec = md[M.OBJ_KEY]
        if type(rec) ~= "table" or rec.v ~= M.GATE_VERSION or M.KINDS[rec.kind] == nil then return nil end
        if rec.state ~= "sealed" and rec.state ~= "opened" then return nil end
        if kind ~= rec.kind or opened ~= (rec.state == "opened") then return nil end
        return rec
    end

    local function routeOfKind(kind, routeId)
        local list = M.KINDS[kind].routes
        for i = 1, #list do
            if list[i] == routeId then return true end
        end
        return false
    end

    local function refuse(routeId, reason, tool)
        return { ok = false, id = routeId, reason = reason, tool = tool }
    end

    local function timeFactor(player, routeId, def)
        local f = 1
        if def.finesse and hasTrait(player, M.LOCKSMITH_TRAIT) then f = f * M.LOCKSMITH_FACTOR end
        if routeId == "pry" or routeId == "force" or routeId == "smash" then
            local s = perkLevel(player, "Strength")
            f = f * M.clamp(1 - (s - M.STRENGTH_BASE) * M.STRENGTH_STEP, M.STRENGTH_MIN_FACTOR, M.STRENGTH_MAX_FACTOR)
        end
        if routeId == "claw" then
            local w = M.clamp(perkLevel(player, "Woodwork"), 0, M.PERK_MAX)
            f = f * (1 - w * M.WOODWORK_STEP)
            if M.isCarpenter(player) then f = f * M.CARPENTER_FACTOR end
        end
        if def.hears then
            if hasTrait(player, "KEEN_HEARING") then f = f * M.KEEN_HEARING_FACTOR end
            if hasTrait(player, "HARD_OF_HEARING") then f = f * M.HARD_OF_HEARING_FACTOR end
        end
        if routeId == "pry" or routeId == "claw" or def.finesse then
            if hasTrait(player, "DEXTROUS") then f = f * M.DEXTROUS_FACTOR end
            if hasTrait(player, "ALL_THUMBS") then f = f * M.ALL_THUMBS_FACTOR end
        end
        return f
    end

    local function savedProgress(md, routeId, def)
        if def.fresh or type(md.progress) ~= "table" then return 0 end
        local p = M.finite(md.progress[routeId])
        if p == nil then return 0 end
        return M.clamp(p, 0, 1)
    end

    --- The level a minPerk asks of this player: its profession's level when it has one.
    local function perkFloor(player, mp)
        if mp.profession ~= nil and isProfession(player, mp.profession) then return mp.professionLevel end
        return mp.level
    end

    --- The odds the authority's roll opens it with `tool`: 1 for a route without a chance.
    local function chanceOf(player, def, tool)
        local c = def.chance
        if c == nil then return 1 end
        local from = c.from
        if c.fromFloor then from = perkFloor(player, def.minPerk) + (c.entry ~= nil and 1 or 0) end
        local level = perkLevel(player, c.perk)
        local v = c.base + c.step * (level - from)
        if c.entry ~= nil and level < from then v = c.entry end
        if c.traits ~= nil then
            for name, add in pairs(c.traits) do
                if hasTrait(player, name) then v = v + add end
            end
        end
        if c.perks ~= nil then
            for name, add in pairs(c.perks) do v = v + add * perkLevel(player, name) end
        end
        if c.tools ~= nil then v = v + (c.tools[fullTypeOf(tool) or ""] or 0) end
        return M.clamp(v, 0, c.max)
    end

    -- A route's tool, odds and time factor, for the door pick (Doors.lua) to take as a box's are.
    function M.findRouteTool(player, routeId)
        local def = M.ROUTES[routeId]
        if def == nil then return nil end
        return (findTool(player, def.tools or {}, def.items or {}))
    end
    function M.routeChance(player, routeId, tool) return chanceOf(player, M.ROUTES[routeId], tool) end
    function M.routeTimeFactor(player, routeId) return timeFactor(player, routeId, M.ROUTES[routeId]) end

    --- The odds a torch burns each paper, money and food item, for this player; 0 for any other route.
    local function burnOf(player, def)
        local b = def.burn
        if b == nil then return 0 end
        local v = isProfession(player, b.profession) and b.professionChance or b.chance
        if b.perk ~= nil then v = v - b.step * math.max(0, perkLevel(player, b.perk) - b.from) end
        return math.max(0, v)
    end

    --- The items one try uses up, or nil and the refusal for the first one missing.
    local function findConsumed(player, list)
        local out = {}
        if list == nil then return out, nil end
        local inv = inventoryOf(player)
        for i = 1, #list do
            local want = list[i]
            local item = nil
            if inv ~= nil then
                local ok, found = pcall(function()
                    if want.charged then
                        return inv:getFirstTypeEvalRecurse(want.item, function(it) return usesOf(it) >= 1 end)
                    end
                    return inv:getFirstTypeRecurse(want.item)
                end)
                if ok then item = found end
            end
            if item == nil then return nil, want.reason end
            out[#out + 1] = item
        end
        return out, nil
    end

    --- What opening this gate by this route costs this player, or why it cannot. keyId matters
    --- only to a key route: the authority passes the gate's stored id, the client passes nil.
    --- square is the gate's square, read for a keypad's grid power; nil reads as no grid power.
    --- A safe's md carries lockedUntil (the world-age hour its lockout ends, 0 when free) and
    --- powered, as view() and the authority's record give them.
    function M.route(player, md, routeId, keyId, square)
        local def = M.ROUTES[routeId]
        if def == nil then return refuse(routeId, M.REASON_UNKNOWN_ROUTE) end
        if type(md) ~= "table" or md.state ~= "sealed" or M.KINDS[md.kind] == nil then
            return refuse(routeId, M.REASON_NOT_SEALED)
        end
        if not routeOfKind(md.kind, routeId) then return refuse(routeId, M.REASON_UNKNOWN_ROUTE) end
        if def.jams and md.jammed == true then return refuse(routeId, M.REASON_JAMMED) end
        if def.lockout and M.lockedFor(md) > 0 then return refuse(routeId, M.REASON_LOCKED_OUT) end
        if M.KINDS[md.kind].keypad then
            local powered = M.keypadPowered(md, square)
            if def.powered and not powered then return refuse(routeId, M.REASON_NO_POWER) end
            if def.unpowered and powered then return refuse(routeId, M.REASON_HAS_POWER) end
        end
        if def.hears and hasTrait(player, "DEAF") then return refuse(routeId, M.REASON_DEAF) end
        if def.traits ~= nil and not hasAnyTrait(player, def.traits) then return refuse(routeId, M.REASON_NEEDS_TRAIT) end
        if def.maxTier ~= nil and not (type(md.tier) == "number" and md.tier <= def.maxTier) then
            return refuse(routeId, M.REASON_TOO_STURDY)
        end
        if def.minPerk ~= nil and perkLevel(player, def.minPerk.perk) < perkFloor(player, def.minPerk) then
            return refuse(routeId, def.minPerk.reason or M.REASON_TOO_WEAK)
        end

        local tool, key = nil, nil
        local fuel = M.fuelFor(def.fuel, 1 - savedProgress(md, routeId, def))
        if def.key then
            if keyId ~= nil and not M.isGateKeyId(keyId) then return refuse(routeId, M.REASON_WRONG_KEY) end
            key = findKey(player, keyId)
            if key == nil then
                if keyId ~= nil then return refuse(routeId, M.REASON_WRONG_KEY) end
                return refuse(routeId, M.REASON_NO_KEY)
            end
        elseif def.tools ~= nil or def.items ~= nil then
            local usable = nil
            if def.fuel ~= nil then
                usable = function(item) return not item:isBroken() and usesOf(item) >= fuel end
            end
            local unusable
            tool, unusable = findTool(player, def.tools or {}, def.items or {}, usable)
            if tool == nil then
                if unusable ~= nil and def.fuel ~= nil and not unusable:isBroken() then
                    return refuse(routeId, M.REASON_NO_FUEL, unusable)
                end
                if unusable ~= nil then return refuse(routeId, M.REASON_TOOL_BROKEN, unusable) end
                return refuse(routeId, M.REASON_NO_TOOL)
            end
        end
        local consumes, missing = findConsumed(player, def.consumes)
        if consumes == nil then return refuse(routeId, missing) end

        local timeScale = M.finite(M.cfg("TimeScale")) or 1
        local saved = savedProgress(md, routeId, def)
        local seconds = def.seconds * timeFactor(player, routeId, def) * timeScale * (1 - saved)

        local noise = def.noise * (M.finite(M.cfg("NoiseScale")) or 1)
        if (routeId == "pry" or routeId == "force") and hasTrait(player, "BURGLAR") then
            noise = noise * M.BURGLAR_NOISE_FACTOR
        end

        local xp = nil
        if def.xp ~= nil then xp = { perk = def.xp.perk, amount = def.xp.amount } end
        local skill = nil
        if def.skill ~= nil then skill = { perk = def.skill.perk, opened = def.skill.opened, failed = def.skill.failed } end
        return {
            ok = true, id = routeId, seconds = seconds, resumed = saved > 0, noise = math.floor(noise + 0.5),
            damage = def.damage, brute = def.brute, wear = def.wear == true, tool = tool, key = key, xp = xp,
            chance = chanceOf(player, def, tool), spends = M.spendKind(def, tool), skill = skill,
            jams = def.jams == true and not hasTrait(player, M.LOCKSMITH_TRAIT),
            code = def.code == true, resumes = not def.fresh, consumes = consumes, fuel = fuel,
            burn = burnOf(player, def), alarm = def.alarm == true, wearsSession = def.wearsSession == true,
            wrecks = def.wrecks == true,
        }
    end

    -- THE REST IN THE WORK (WorkPanel.lua offers it, World.lua honours it). A drill gathers one
    -- second of heat a second of drilling, up to `heatUp`, where it is red; at rest, put down or
    -- walked away from, it cools as hot metal does, heat * exp(-seconds / tau), so a short rest
    -- leaves it warm and the next red comes sooner. A finishing session that ran red longer than
    -- `grace` seconds in one run wears it `extraWear` more. A torch's seam reaches the contents at `from`
    -- of the work; every second it rests, stopped or walked away from near the contents, earns
    -- 1 / `pause` of the cooling, and full cooling scales each burn chance by `burnFactor`.
    -- THE BOUND: the client sends its rests, `max` at most, each `maxRest` seconds at most, at
    -- the work second each began; the authority honours them only when its own clock shows them
    -- all paid on top of the submit floor, and otherwise counts none. A rest can only take a
    -- wear away down to the route's own one, or lower the burn chance; it never shortens the
    -- floor, adds progress or opens anything, and is never credited as work. A red or a near seam
    -- left `grace` seconds without a rest stops the work on the client, progress kept.
    M.WORK_CHOICES = {
        drill = { heatUp = 60, tau = 1.67, cold = 3, max = 8, maxRest = 120, extraWear = 1, grace = 6 },
        torch = { from = 0.75, pause = 8, max = 8, maxRest = 120, burnFactor = 0.5, grace = 6 },
    }

    --- The heat a drill keeps after `seconds` at rest. Infinite rest is cold.
    function M.coolHeat(routeId, heat, seconds)
        local c = M.WORK_CHOICES[routeId]
        if c == nil or c.tau == nil then return 0 end
        heat = M.clamp(M.finite(heat) or 0, 0, c.heatUp)
        if seconds == math.huge then return 0 end
        return heat * math.exp(-math.max(0, M.finite(seconds) or 0) / c.tau)
    end

    --- A seam's cooling, 0..1, full within a rounding of it: time measured in ms and divided back
    --- into seconds must still read as fully cooled.
    local function creditOf(x)
        if x > 1 - 1e-9 then return 1 end
        return x
    end

    --- Drill `work` seconds from `heat`: the heat it ends on and the seconds of it spent red.
    local function heatWork(c, heat, work)
        if c.heatUp == nil then return 0, 0 end
        work = math.max(0, work)
        local reach = c.heatUp - heat
        if work <= reach then return heat + work, 0 end
        return c.heatUp, work - math.max(0, reach)
    end

    --- A session replayed from what it started on (`from`: { heat, credit }) through its rests
    --- ({ at, s }, in work order) to `work` seconds: { heat, red, spell, run, credit }. red: every
    --- second spent red; spell: the longest red run, which only a rest that took the drill out of
    --- the gauge's red zone (its last 10 s) ends; run: the red run still going at the end.
    function M.workReplay(routeId, from, rests, work)
        local c = M.WORK_CHOICES[routeId]
        from = type(from) == "table" and from or {}
        local out = { heat = 0, red = 0, spell = 0, run = 0, credit = 0 }
        if c == nil then return out end
        local heat = c.heatUp ~= nil and M.clamp(M.finite(from.heat) or 0, 0, c.heatUp) or 0
        local credit = M.clamp(M.finite(from.credit) or 0, 0, 1)
        local red, run, spell, t = 0, 0, 0, 0
        for i = 1, #rests do
            local r = rests[i]
            local add
            heat, add = heatWork(c, heat, r.at - t)
            red, run = red + add, run + add
            spell = math.max(spell, run)
            heat = M.coolHeat(routeId, heat, r.s)
            if c.heatUp ~= nil and heat < c.heatUp - 10 then run = 0 end
            if c.pause ~= nil then credit = credit + r.s / c.pause end
            t = r.at
        end
        local add
        heat, add = heatWork(c, heat, (M.finite(work) or 0) - t)
        out.heat, out.red, out.spell, out.run = heat, red + add, math.max(spell, run + add), run + add
        out.credit = creditOf(credit)
        return out
    end

    --- The rests a client claims, as { at, s } in work order, with their total; nil for a list
    --- that is not one: not a table of tables, more than `max`, a rest out of 0..maxRest, or
    --- out of order.
    local function restList(c, rests)
        if rests == nil then return {}, 0 end
        if type(rests) ~= "table" then return nil end
        local out, last, total = {}, 0, 0
        for i = 1, c.max + 1 do
            local r = rests[i]
            if r == nil then break end
            if i > c.max or type(r) ~= "table" then return nil end
            local at, s = M.finite(r.at), M.finite(r.s)
            if at == nil or s == nil or at < last or s <= 0 or s > c.maxRest then return nil end
            out[i] = { at = at, s = s }
            last, total = at, total + s
        end
        return out, total
    end

    -- The seconds the client's clock may run ahead of the authority's: a claim and its release or
    -- submit cross the network with different delays.
    local REST_SLACK = 0.5

    --- A session as the authority counts it, from the rests the client claims, the seconds its
    --- claim was held (`elapsed`), the seconds of work the floor asks (`floor`, 0 where the floor
    --- is skipped) and what the session started on (`from`, Gates.workResume): { rests, work,
    --- heat, credit, hot, burnFactor }. A list that is not one, or rests that leave the work under
    --- the floor (less REST_SLACK), count as no rests; a rest past the work there was is moved to
    --- its end, the least it can cool. hot: a drill red past its grace.
    function M.workSession(routeId, rests, elapsed, floor, from)
        elapsed = M.finite(elapsed) or 0
        floor = math.max(0, M.finite(floor) or 0)
        local c = M.WORK_CHOICES[routeId]
        local list, total = {}, 0
        if c ~= nil then
            list, total = restList(c, rests)
            if list == nil or elapsed - total < floor - REST_SLACK then list, total = {}, 0 end
        end
        local work = math.max(0, elapsed - total)
        for i = 1, #list do
            if list[i].at > work then list[i].at = work end
        end
        local out = { rests = #list, work = work, heat = 0, credit = 0, hot = false, burnFactor = 1 }
        if c == nil then return out end
        local r = M.workReplay(routeId, from, list, work)
        out.heat, out.credit = r.heat, r.credit
        if c.heatUp ~= nil then out.hot = r.spell > c.grace end
        if c.burnFactor ~= nil then out.burnFactor = 1 - (1 - c.burnFactor) * r.credit end
        return out
    end

    --- What a session started on saved `saved` work inherits from the one before it, left
    --- `leftMs` ms ago: { heat, credit }. The drill's heat has cooled for the time away; a seam
    --- left near the contents has earned that time's cooling on top of what it had. leftMs nil:
    --- no record, so as long as it takes.
    function M.workResume(routeId, saved, leftMs, nowMs)
        local c = M.WORK_CHOICES[routeId]
        saved = type(saved) == "table" and saved or {}
        if c == nil then return { heat = 0, credit = 0 } end
        local left = M.finite(leftMs)
        local away = left == nil and math.huge or math.max(0, ((M.finite(nowMs) or 0) - left) / 1000)
        if c.heatUp ~= nil then return { heat = M.coolHeat(routeId, saved.heat, away), credit = 0 } end
        if (M.finite(saved.progress) or 0) < c.from then return { heat = 0, credit = 0 } end
        local had = M.clamp(M.finite(saved.credit) or 0, 0, 1)
        return { heat = 0, credit = away == math.huge and 1 or creditOf(had + away / c.pause) }
    end

    --- The fuel `share` of a route's whole work burns: at least one use for any work at all.
    function M.fuelFor(fuel, share)
        fuel = M.finite(fuel) or 0
        share = M.clamp(M.finite(share) or 0, 0, 1)
        if fuel <= 0 or share <= 0 then return 0 end
        return math.max(1, math.ceil(fuel * share - 0.0001))
    end

    --- Every route of the gate's kind, in the kind's fixed order. Empty for anything not a gate.
    function M.routes(player, md, square)
        local out = {}
        if type(md) ~= "table" or M.KINDS[md.kind] == nil then return out end
        local list = M.KINDS[md.kind].routes
        for i = 1, #list do out[i] = M.route(player, md, list[i], nil, square) end
        return out
    end

    --- The trait script's MutuallyExclusiveTraits is one-way: CharacterTraitDefinitionScript adds
    --- base:burglar to Locksmith's list only, so Burglar's own list never names Locksmith, and the
    --- profession screen, which reads the granted Burglar trait's list, would let a Burglar take
    --- it. setMutualExclusive links both. Scripts load before OnGameBoot on every boot path.
    function M.linkLocksmith()
        local locksmith = traitOf(M.LOCKSMITH_TRAIT)
        if locksmith == nil or CharacterTraitDefinition == nil or CharacterTrait.BURGLAR == nil then
            M.defect(PART, "Locksmith is not registered, so Burglar cannot exclude it")
            return false
        end
        CharacterTraitDefinition.setMutualExclusive(CharacterTrait.BURGLAR, locksmith)
        return true
    end
    M.addHandler(PART, "OnGameBoot", M.linkLocksmith)

    -- Neat Lockpicking opens its own lockpicking to a Burglar or to whoever knows its pick recipe
    -- (NeatLockpick_Chances.canLockpick), so a Locksmith learns the recipe on entering the world.
    -- Without Neat the recipe does not exist and nothing is learned.
    M.NEAT_PICK_RECIPE = "NeatLockpick_CreateLockpick"
    function M.teachLocksmith(player)
        if player == nil or not hasTrait(player, M.LOCKSMITH_TRAIT) or getScriptManager == nil then return false end
        local okR, recipe = pcall(function()
            local sm = getScriptManager()
            return sm:getCraftRecipe(M.NEAT_PICK_RECIPE) or sm:getCraftRecipe("Base." .. M.NEAT_PICK_RECIPE)
        end)
        if not okR or recipe == nil then return false end
        local okK, known = pcall(function() return player:isRecipeActuallyKnown(M.NEAT_PICK_RECIPE) end)
        if not okK or known == true then return false end
        local okL, learned = pcall(function() return player:learnRecipe(M.NEAT_PICK_RECIPE) end)
        return okL and learned == true
    end
    M.addHandler(PART, "OnCreatePlayer", function(_, player) M.teachLocksmith(player) end)

    M.status(PART, true)
end
