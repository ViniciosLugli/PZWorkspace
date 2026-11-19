--[[
    Gating
    The authority's record of every gate, and what makes an object one. A gate is a stash box
    this mod placed (Stash.lua): its container is empty and the store holds its record. The payout
    is rolled only when a route opens it (World.lua), so a sealed box is empty to every reader in
    between: the loot window, a proximity-loot mod, crafting, a sledge dump, a modified client
    (docs/31 section 1).

    A SEALED GATE THAT GETS REFILLED IS EMPTIED AGAIN. The box is placed explored, so the engine
    never rolls loot into it; this is the guard for anything that refills it anyway (loot
    respawn, another mod); every other container costs one store lookup. OnFillContainer fires only
    where loot is rolled: single player and the authority, never an MP client
    (ItemPickerJava.java:560). An opened gate is an ordinary container from then on.

    THE STORE IS THE ONLY TRUTH; THE OBJECT'S TAG IS A MIRROR. Any logged-in client can write an
    object's modData on the server (ObjectModDataPacket.parse, 42.22.2), so the tag is never read
    back here: a gate is a store record whose square holds a box sprite with a container at the
    record's index, and kind, tier, theme, state and progress come from the record alone. The
    tag is rewritten from the record (M.mirror) whenever the record changes, and whenever a
    request finds it forged, so the clients can draw it.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Spots"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Codes"
require "LugliDeadMansStash/Payout"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Gating"

    -- Progress kept by an interrupted route never reaches the end: finishing is a submit.
    M.PROGRESS_CAP = 0.95
    -- 2: every gate record carries state, progress and by (1 kept them on the object alone).
    M.STORE_VERSION = 2

    local store = nil

    --- A record from store version 1 ({ x, y, z, i, kind, tier, theme, opened }) in the current
    --- shape. Its state was always on the record as `opened`; only its progress lived on the
    --- object, and is read from it once, at the first resolve (`legacy`).
    local function migrate(rec)
        if type(rec) ~= "table" or rec.state ~= nil then return end
        rec.state = rec.opened ~= nil and "opened" or "sealed"
        rec.by = rec.opened
        rec.opened = nil
        rec.progress = {}
        if rec.state == "sealed" then rec.legacy = true end
    end

    --- The authority's own record, never transmitted: every gate, every building that holds a
    --- stash and the per-world salt the placement hashes with. Global ModData is loaded before
    --- the first chunk streams in (IsoWorld.java:2035 against WorldStreamer at :2208), so a lazy
    --- read at the first chunk already sees the saved table.
    function M.store()
        if store ~= nil then return store end
        local t = nil
        if ModData ~= nil then
            local ok, got = pcall(function() return ModData.getOrCreate(M.MODDATA_KEY) end)
            if ok and type(got) == "table" then t = got end
        end
        if t == nil then t = {} end
        if t.v == nil then t.v = M.STORE_VERSION end
        if type(t.gates) ~= "table" then t.gates = {} end
        if type(t.stashes) ~= "table" then t.stashes = {} end
        if t.v < M.STORE_VERSION then
            for _, rec in pairs(t.gates) do migrate(rec) end
            t.v = M.STORE_VERSION
        end
        if t.salt == nil then t.salt = tostring(ZombRand(1, 1000000000)) end
        store = t
        -- A box from before the numbers (2026-11-19) takes the next one at this load.
        for _, rec in pairs(t.gates) do
            if type(rec) == "table" and rec.no == nil then M.numberGate(rec) end
        end
        return store
    end

    --- THE BOX'S NUMBER, shown on it, its key and its notes so a survivor carrying several can
    --- tell which opens which (user review 2026-11-19): the world's next, once, never reused.
    function M.numberGate(rec)
        if rec.no ~= nil then return rec.no end
        local s = M.store()
        s.lastNo = (tonumber(s.lastNo) or 0) + 1
        rec.no = s.lastNo
        return rec.no
    end
    M.addTeardown(PART, function() store = nil end)

    function M.gateId(x, y, z, i)
        return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. "," .. tostring(i)
    end

    --- The world object a container belongs to, when it is a placed object on a square. Bags,
    --- corpses, zombies and vehicle parts are never gates.
    local function worldParent(container)
        local obj = container:getParent()
        if obj == nil or not instanceof(obj, "IsoObject") then return nil end
        if instanceof(obj, "IsoDeadBody") or instanceof(obj, "IsoWorldInventoryObject")
            or instanceof(obj, "IsoMovingObject") then return nil end
        if obj:getSquare() == nil then return nil end
        return obj
    end

    --- A version-1 record's saved progress, read off its object once and never again.
    local function adoptLegacy(obj, rec)
        if not rec.legacy then return end
        rec.legacy = nil
        local ok, tag = pcall(function() return obj:getModData()[M.OBJ_KEY] end)
        local old = ok and type(tag) == "table" and tag.progress or nil
        if type(old) ~= "table" then return end
        for route, p in pairs(old) do
            p = M.finite(p)
            if type(route) == "string" and p ~= nil then rec.progress[route] = M.clamp(p, 0, M.PROGRESS_CAP) end
        end
    end

    --- The store record that makes container `i` of `obj` a gate, and that container, or nil:
    --- a record at the object's square and index, on a box tile of the record's kind, sealed or
    --- opened.
    function M.gateOf(obj, i)
        if obj == nil or i == nil then return nil end
        local square = obj:getSquare()
        if square == nil then return nil end
        local rec = M.store().gates[M.gateId(square:getX(), square:getY(), square:getZ(), i)]
        -- The sprite it shows now, never getSpriteName: setSprite leaves that name stale.
        local kind = M.kindOfSprite(M.liveSpriteName(obj))
        if type(rec) ~= "table" or kind ~= rec.kind then return nil end
        local container = obj:getContainerByIndex(i)
        if container == nil then return nil end
        adoptLegacy(obj, rec)
        return rec, container
    end

    --- The world object, its container and its store record at a gate id's coordinates, or nil.
    function M.gateAt(x, y, z, i)
        if getCell == nil then return nil end
        local square = getCell():getGridSquare(x, y, z)
        if square == nil then return nil end
        local objects = square:getObjects()
        for k = 0, objects:size() - 1 do
            local obj = objects:get(k)
            local rec, container = M.gateOf(obj, i)
            if rec ~= nil then return obj, container, rec end
        end
        return nil
    end

    --- Is this gate kind one of the safes?
    function M.isSafeKind(kind)
        local box = M.GATE_BOXES[kind]
        return box ~= nil and box.safe == true
    end

    --- A safe's code with only the digits the manipulation found: "?4??". revealed[pos] is a digit.
    function M.maskedCode(revealed)
        local out = {}
        for pos = 1, M.CODE_DIGITS do
            local d = type(revealed) == "table" and revealed[pos] or nil
            out[pos] = (type(d) == "string" and string.find(d, "^%d$") ~= nil) and d or "?"
        end
        return table.concat(out)
    end

    --- Wrong codes a safe still takes before it locks out.
    function M.safeTriesLeft(rec)
        local tries = type(rec) == "table" and M.finite(rec.tries) or nil
        return math.max(0, math.floor(M.cfg("SafeTries")) - (tries or 0))
    end

    --- What a client may see of a record: a fresh copy, never the record itself, and nothing
    --- beyond what the client's M.gateRecord and M.route read. Never the key id, never a safe's
    --- code. A safe adds what its window reads between replies: the found digits masked, the
    --- tries left, the world-age hour its lockout ends (0 when free) and whether it has power.
    local function view(rec)
        local progress = {}
        if type(rec.progress) == "table" then
            for route, p in pairs(rec.progress) do progress[route] = p end
        end
        local out = { v = M.GATE_VERSION, kind = rec.kind, tier = rec.tier, theme = rec.theme, state = rec.state,
            progress = progress, by = rec.by, jammed = rec.jammed, no = rec.no }
        if M.isSafeKind(rec.kind) then
            out.revealed = M.maskedCode(rec.revealed)
            out.triesLeft = M.safeTriesLeft(rec)
            out.lockedUntil = M.lockedFor(rec) > 0 and rec.lockedUntil or 0
            out.powered = rec.powered == true
        end
        return out
    end

    -- Recursion is bounded by `want`, which nests two deep: a deeper forged table fails at once.
    local function same(have, want)
        if type(have) ~= "table" or type(want) ~= "table" then return have == want end
        for k, v in pairs(have) do
            if not same(v, want[k]) then return false end
        end
        for k in pairs(want) do
            if have[k] == nil then return false end
        end
        return true
    end

    --- Write the record's view onto the object's tag. Returns true when the tag changed.
    function M.mirror(obj, rec)
        local want = view(rec)
        local md = obj:getModData()
        if same(md[M.OBJ_KEY], want) then return false end
        md[M.OBJ_KEY] = want
        return true
    end

    --- M.mirror, and send the tag to the clients when it changed.
    function M.syncMirror(obj, rec)
        if M.mirror(obj, rec) then obj:transmitModData() end
    end

    --- Make a placed object's container a sealed gate: emptied, recorded, tagged. Returns the
    --- gate's store record, or nil when the container's type is no gate kind. Stash.lua calls it
    --- on a box before the box is sent, so the tag travels with the object.
    function M.sealObject(obj, container, roomName)
        if obj == nil or container == nil or worldParent(container) ~= obj then return nil end
        local square = obj:getSquare()
        local ctype = container:getType()
        local kind = M.kindForContainer(ctype)
        if kind == nil then return nil end
        local i = obj:getContainerIndex(container)
        if i == nil or i < 0 then return nil end
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local tier = M.luckyTier(M.gateId(x, y, z, i), M.store().salt, M.tierFor(ctype, roomName))
        local theme = M.themeFor ~= nil and M.themeFor(roomName, ctype) or "default"
        -- A record is never overwritten: the gate it names would be left with no record at all.
        if M.store().gates[M.gateId(x, y, z, i)] ~= nil then return nil end
        container:removeAllItems()
        local rec = { x = x, y = y, z = z, i = i, kind = kind, tier = tier, theme = theme, state = "sealed", progress = {} }
        -- A safe's code is minted with its record and lives only there (view never copies it).
        if M.isSafeKind(kind) then rec.code = M.safeCode(M.gateId(x, y, z, i), M.store().salt) end
        M.numberGate(rec)
        M.store().gates[M.gateId(x, y, z, i)] = rec
        M.mirror(obj, rec)
        M.debug(PART, "sealed " .. kind .. " tier " .. tier .. " theme " .. theme .. " at " .. M.gateId(x, y, z, i)
            .. " (" .. tostring(roomName) .. ")")
        return rec
    end

    --- A fill reached a container. Returns "restrip" when it was a sealed gate's, else nil.
    function M.onFill(roomName, containerType, container)
        -- Every container in the world fills through here: only the mod's own types can be gates.
        if M.kindForContainer(containerType) == nil then return nil end
        if container == nil or not instanceof(container, "ItemContainer") then return nil end
        local obj = worldParent(container)
        if obj == nil then return nil end
        local rec = M.gateOf(obj, obj:getContainerIndex(container))
        if rec == nil or rec.state ~= "sealed" then return nil end
        container:removeAllItems()
        return "restrip"
    end

    -- NOT M.addHandler. That drops a handler after its first failure, and this one runs once per
    -- container: one odd container would end the guard for the session. A failure here is a
    -- defect, rate-limited, and the next container is judged on its own.
    if M.isWorldAuthority() then
        if Events ~= nil and Events.OnFillContainer ~= nil then
            Events.OnFillContainer.Add(function(roomName, containerType, container)
                local ok, err = pcall(M.onFill, roomName, containerType, container)
                if not ok then M.defect(PART, "fill of " .. tostring(containerType) .. ": " .. tostring(err)) end
            end)
            M.status(PART, true)
        else
            M.defect(PART, "Events.OnFillContainer does not exist on this build", true)
        end
    end
end
