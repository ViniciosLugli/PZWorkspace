--[[
    Sounds
    Every sound the mod plays, in one table, so a route sounds the same for the survivor doing it,
    for the players near them, and in the code window. Pure: the client plays these and the
    authority relays the outcomes (World.lua), both through M.outcomeSounds.

    ONE RULE PER MATERIAL. Wood gives way with vanilla's plank sounds (the crate), metal with its
    metal barricade sounds (the lockbox lid, the footlocker's shackle), a lock opened as made
    ends on UnlockDoor, and a safe of either kind opens on MetalDoorUnlock, its bolts drawing
    back, whichever route got there. A lock that holds rattles (MetalDoorLocked).

    THE ANSWER IS WHAT SOUNDS. A route that can fail (pick, snap, bypass) never plays its ending
    before the authority says how it went, so every ending is an outcome: opened, failed, jammed,
    wrong, lockout, revealed, slipped or powered. false is a silence chosen on purpose.

    Vanilla names are media/scripts/generated/sounds; LugliDMS_* are the mod's own recordings
    (assets/media/scripts/lugli_deadmansstash_sounds.txt, art/dms-audio/SOURCES.md).
    tools/dms-sounds.sh checks every name here against both at build time.
]]

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash

    local SAFE_OPENS = "MetalDoorUnlock"
    local LOCK_OPENS = "UnlockDoor"
    local LOCK_HOLDS = "MetalDoorLocked"
    local KEY_IN = "VehicleInsertIgnitionKey"

    --- route -> slot -> name, a list of names played together, or false. A kind's own subtable
    --- (the code route) overrides its route's slots for that kind.
    M.ROUTE_SOUNDS = {
        pry = { begin = "BeginRemoveBarricadePlankCrowbar", step = "HitBarricadePlank", opened = "RemoveBarricadePlank" },
        claw = { begin = "BeginRemoveBarricadePlank", step = "HitBarricadePlank", opened = "RemoveBarricadePlank" },
        -- The swings are the tool's own (Actions.lua animEvent); the crate breaks as wood furniture.
        smash = { begin = false, step = false, opened = "BreakFurniture" },
        key = { begin = KEY_IN, step = false, opened = LOCK_OPENS },
        pick = { begin = false, step = "LugliDMS_PickPin", opened = LOCK_OPENS, failed = LOCK_HOLDS, jammed = LOCK_HOLDS },
        -- Not vanilla "Screwdriver": its FMOD event (Carpentry/Screwing) is gone from the bank and plays nothing.
        jimmy = { begin = "Dismantle", step = "LugliDMS_PickPin", opened = LOCK_OPENS },
        -- A crowbar on a steel lid: the crowbar's own strike, then steel hits. Not
        -- BeginRemoveBarricadeMetal (the welding torch, Character/Survival/MetalWorking/Welding,
        -- user review 2026-11-19), nor the crowbar on planks (BarricadeWood/BeginRemoveCrowbar).
        force = { begin = "CrowbarHit", step = "HitBarricadeMetal", opened = "RemoveBarricadeMetal" },
        cut = { begin = false, step = false, opened = "LugliDMS_BoltCut" },
        snap = { begin = "CrowbarHit", step = "HitBarricadeMetal", opened = "BreakLockOnWindow", failed = LOCK_HOLDS },
        code = {
            begin = false, step = false, opened = SAFE_OPENS, wrong = LOCK_HOLDS, lockout = LOCK_HOLDS,
            keypadsafe = { opened = { "LugliDMS_KeypadAccept", SAFE_OPENS }, wrong = "LugliDMS_KeypadDeny", lockout = "LugliDMS_KeypadDeny" },
        },
        manipulate = { begin = false, step = "LugliDMS_DialTick", opened = SAFE_OPENS, revealed = "LugliDMS_DialContact", slipped = false },
        battery = { begin = false, step = false, powered = "LugliDMS_KeypadAccept" },
        bypass = { begin = "VehicleHotwireStart", step = false, opened = { "VehicleHotwireSuccess", SAFE_OPENS }, failed = "VehicleHotwireFail" },
        -- eased: the work's one choice taken (WorkPanel.lua); overheated: the choice ignored, the work stopped.
        drill = { begin = "LugliDMS_HandDrill", step = false, opened = SAFE_OPENS, eased = "LugliDMS_DrillEase", overheated = "LugliDMS_DrillEase" },
        torch = { begin = "LugliDMS_TorchLoop", step = false, opened = SAFE_OPENS, eased = "LugliDMS_TorchOff", overheated = "LugliDMS_TorchOff" },
    }

    --- The slots the survivor's own work plays, never an answer the authority relays.
    local WORK_SLOTS = { begin = true, step = true, eased = true, overheated = true }

    --- The code window's own sounds, by kind: a key pressed, the dial turned one number, the code
    --- sent. The dial sends nothing of its own: the answer sounds (the handle holds or the bolts draw).
    M.CODE_WINDOW_SOUNDS = {
        dialsafe = { key = false, tick = "LugliDMS_DialTick", submit = false },
        keypadsafe = { key = "LugliDMS_KeypadKey", tick = false, submit = "LugliDMS_KeypadKey" },
    }

    --- Players this near a box hear its outcome sounds (World.lua relays them); FMOD fades each
    --- by its own distance inside that.
    M.SOUND_RELAY_RANGE = 30

    --- The slot's sound(s) for a route on a kind of box, as a list (empty for none).
    function M.routeSounds(routeId, kind, slot)
        local entry = M.ROUTE_SOUNDS[routeId]
        if entry == nil then return {} end
        local v = entry[slot]
        local own = kind ~= nil and entry[kind] or nil
        if type(own) == "table" and own[slot] ~= nil then v = own[slot] end
        if type(v) == "string" then return { v } end
        if type(v) == "table" then return v end
        return {}
    end

    --- The one sound a slot starts with (a begin or a step), or nil.
    function M.routeSound(routeId, kind, slot)
        return M.routeSounds(routeId, kind, slot)[1]
    end

    --- What the authority's answer sounds like: args is the NET_RESULT (route, outcome, jammed).
    function M.outcomeSounds(args, kind)
        if type(args) ~= "table" or type(args.route) ~= "string" then return {} end
        local slot = args.outcome
        if slot == "failed" and args.jammed == true then slot = "jammed" end
        if type(slot) ~= "string" or WORK_SLOTS[slot] then return {} end
        return M.routeSounds(args.route, kind, slot)
    end

    --- Every name above, once each, sorted: tools/dms-sounds.sh checks each one resolves.
    function M.allSoundNames()
        local seen, out = {}, {}
        local function add(v)
            if type(v) == "string" and not seen[v] then
                seen[v] = true
                out[#out + 1] = v
            elseif type(v) == "table" then
                for k, w in pairs(v) do
                    if type(k) == "number" then add(w) end
                end
            end
        end
        for _, entry in pairs(M.ROUTE_SOUNDS) do
            for _, v in pairs(entry) do
                if type(v) == "table" and v[1] == nil then
                    for _, w in pairs(v) do add(w) end
                else
                    add(v)
                end
            end
        end
        for _, window in pairs(M.CODE_WINDOW_SOUNDS) do
            for _, v in pairs(window) do add(v) end
        end
        table.sort(out)
        return out
    end

    --- True for a name this table can play: a relayed sound is played only when it is one.
    function M.isModSound(name)
        if type(name) ~= "string" then return false end
        for _, v in ipairs(M.allSoundNames()) do
            if v == name then return true end
        end
        return false
    end
end
