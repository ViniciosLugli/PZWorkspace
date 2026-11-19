--[[
    Keys
    The key to every keyed box (a lockbox or a footlocker): its id, which only the authority's
    store knows, and where the dead man left it.

    THE ID IS A HASH OF THE GATE AND THE WORLD'S SALT, in [KEY_ID_BASE, KEY_ID_BASE + KEY_ID_SPAN)
    (Gates.lua), probed forward on a collision so no two gates share one. It lives only on the
    gate's store record (store.gates[id].keyId): the object's tag is a mirror any client reads
    (docs/31 section 7), and Gating's view never copies it there.

    THE KEY IS MINTED ONCE PER GATE, in one place (mint), which checks and sets keyGiven on the
    gate's record. Every path goes through it: the building's own furniture once the building is
    fully streamed in, the retry on the building's next chunk, and the zombie fallback.

    WHERE IT GOES. Into a container of the same building that is no gate: another room than the
    box's first (the box's own room only when no other has one), and a desk, side table, dresser,
    wardrobe or counter before anything else. A safe's notes go the same way. Until the
    building is fully streamed in (BuildingDef.isFullyStreamedIn) the key waits on the building's
    stash record (store.stashes[bkey].keys) and Stash.visitBuilding retries it on every chunk of
    the building. A building with no container at all leaves it to the fallback: the first zombie
    killed within KEY_FALLBACK_RANGE tiles of the building carries it, minted at its death, since
    a zombie's own items are never saved (docs/31 section 1). OnZombieDead fires after the engine
    fills the zombie's inventory and before DoDeath turns it into the corpse
    (IsoZombie.onKilled, 42.22.2), so the key is on the body.

    A SAFE'S CLUE NOTES TAKE THE SAME QUEUE. Each is its own entry (noteId: the gate id, "|note|",
    its number), minted once (notesGiven on the safe's record) as a found paper: NOTE_FORMS[n] is
    its vanilla Literature item and its name ("Crumpled note: the office safe", the form's key
    filled with Codes.clueNoteName), with one page, clue n of Codes.safeClues in the authority's
    language. Notes 1 and 3 are placed like a key, in another room of the building than the
    safe's; note NOTE_ON_BODY never is: it waits for the fallback, so the first zombie killed near
    the building, the dead owner, carries it. Every note is read only, locked by NOTE_LOCKED_BY,
    which no player's username can be (Literature.lockedBy is saved, Literature.java:307/378), so
    vanilla offers Read Note even to a survivor with a pen (ISInventoryPaneContextMenu.lua:566),
    and setCanBeWrite(true), also saved (flag 16), gives Base.Note, which its script leaves
    unwritable, that menu at all. Each is tagged modData[Codes.NOTE_TAG] = the gate id. The queue
    table keeps its saved name, `keys`.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Spots"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Codes"
require "LugliDeadMansStash/Gating"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Keys"

    M.KEY_ITEM = "Base.Key1"
    M.KEY_NAME_PREFIX = "IG_UI_LugliDMS_Key_"
    M.KEY_FALLBACK_RANGE = 15
    -- Each note's paper, by number: its vanilla Literature item and the key of its name.
    M.NOTE_FORMS = {
        { item = "Base.Note", name = "IGUI_LugliDMS_NoteForm_1" },
        { item = "Base.SheetPaper2", name = "IGUI_LugliDMS_NoteForm_2" },
        { item = "Base.Notepad", name = "IGUI_LugliDMS_NoteForm_3" },
    }
    M.NOTE_ON_BODY = 2
    -- A username no player can have: vanilla reads a note locked by anyone else as read only.
    M.NOTE_LOCKED_BY = "*LugliDMS dead owner*"
    -- Furniture a man keeps a spare key in.
    M.KEY_HOLDERS = { desk = true, sidetable = true, dresser = true, wardrobe = true, counter = true }

    --- Does this gate kind open to a key?
    function M.isKeyedKind(kind)
        local def = M.KINDS ~= nil and M.KINDS[kind] or nil
        if def == nil then return false end
        for i = 1, #def.routes do
            if def.routes[i] == "key" then return true end
        end
        return false
    end

    --- The stable id of a room, as Stash ranks and records it.
    function M.roomIdOf(roomDef)
        return roomDef:getX() .. "," .. roomDef:getY() .. "," .. roomDef:getZ() .. "," .. tostring(roomDef:getName())
    end

    --- The key id of a keyed gate, assigned on first call and kept on its store record. nil for a
    --- gate with no record or of a kind no key opens.
    function M.assignKeyId(gateId)
        local s = M.store()
        local rec = s.gates[gateId]
        if type(rec) ~= "table" or not M.isKeyedKind(rec.kind) then return nil end
        if M.isGateKeyId(rec.keyId) then return rec.keyId end
        if type(s.keyIds) ~= "table" then s.keyIds = {} end
        local offset = M.hash("key|" .. tostring(gateId) .. "|" .. tostring(s.salt)) % M.KEY_ID_SPAN
        while s.keyIds[tostring(M.KEY_ID_BASE + offset)] ~= nil do
            offset = (offset + 1) % M.KEY_ID_SPAN
        end
        local id = M.KEY_ID_BASE + offset
        s.keyIds[tostring(id)] = gateId
        rec.keyId = id
        return id
    end

    -- ---- pending keys ------------------------------------------------------------------------------

    -- Buildings with a key still to place: at[bkey] = { x, y, w, h }, and n of them, what
    -- OnZombieDead reads first, so a death costs one comparison while nothing is pending (Kahlua
    -- has no next(), docs/15). Built from the store on first use.
    local pending = nil

    local function rectOf(bkey)
        local x, y, w, h = string.match(tostring(bkey), "^(%-?%d+),(%-?%d+),(%d+),(%d+)$")
        if x == nil then return nil end
        return { tonumber(x), tonumber(y), tonumber(w), tonumber(h) }
    end

    local function hasKeys(srec)
        if type(srec) ~= "table" or type(srec.keys) ~= "table" then return false end
        for _ in pairs(srec.keys) do return true end
        return false
    end

    local function mark(bkey, on)
        if pending == nil then return end
        local was = pending.at[bkey] ~= nil
        if on and not was then
            pending.at[bkey] = rectOf(bkey) or false
            pending.n = pending.n + 1
        elseif not on and was then
            pending.at[bkey] = nil
            pending.n = pending.n - 1
        end
    end

    local function index()
        if pending ~= nil then return pending end
        pending = { at = {}, n = 0 }
        for bkey, srec in pairs(M.store().stashes) do
            if hasKeys(srec) then mark(bkey, true) end
        end
        return pending
    end
    M.addTeardown(PART, function() pending = nil end)

    --- The queue id of a safe's clue note n.
    function M.noteId(gateId, n) return tostring(gateId) .. "|note|" .. tostring(n) end

    --- Is this entry out of the queue for good: minted, or nothing left to mint it for? A key is
    --- queued under its gate's id; a note carries its gate and number.
    local function settled(id, entry)
        if type(entry) == "table" and entry.note ~= nil then
            local safe = M.store().gates[entry.gate]
            return type(safe) ~= "table" or not M.isSafeKind(safe.kind)
                or (type(safe.notesGiven) == "table" and safe.notesGiven[tostring(entry.note)] == true)
        end
        local gate = M.store().gates[id]
        return type(gate) ~= "table" or gate.keyGiven == true or not M.isGateKeyId(gate.keyId)
    end

    local function drop(bkey, id)
        local srec = M.store().stashes[bkey]
        if type(srec) ~= "table" or type(srec.keys) ~= "table" then return end
        srec.keys[id] = nil
        if not hasKeys(srec) then mark(bkey, false) end
    end

    --- Queue the key of a freshly sealed keyed gate on its building's stash record. False when the
    --- building has no record, the gate no key id, or the key is already queued or minted.
    function M.queueKey(bkey, gateId, roomId)
        return M.queueDrop(bkey, gateId, { room = roomId })
    end

    --- Queue clue note n (1..Codes.CLUE_MAX) of a freshly placed safe in a room of `roomName`.
    --- False as queueKey is.
    function M.queueNote(bkey, gateId, n, roomId, roomName)
        -- A note with no clue to carry would wait in the queue for good.
        if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > M.CLUE_MAX then return false end
        return M.queueDrop(bkey, M.noteId(gateId, n), { room = roomId, gate = gateId, note = n, name = roomName })
    end

    --- Put one entry on the building's drop queue, unless it is settled or already there.
    function M.queueDrop(bkey, id, entry)
        local s = M.store()
        local srec = s.stashes[bkey]
        if type(srec) ~= "table" or settled(id, entry) then return false end
        if type(srec.keys) ~= "table" then srec.keys = {} end
        if srec.keys[id] ~= nil then return false end
        srec.keys[id] = entry
        mark(bkey, true)
        return true
    end

    --- A clue's text: its template filled with its args, positions as ordinal words.
    function M.clueText(clue)
        return M.Tf(clue.key, nil, unpack(M.clueArgs(clue)))
    end

    --- THE ONE PLACE A CLUE NOTE IS MADE: note n's paper, named for its form and the safe's room,
    --- read only, tagged with its safe, its one page clue n of the safe. nil when there is no clue n.
    local function mintNote(entry, container)
        local safe = M.store().gates[entry.gate]
        local clue = M.safeClues(entry.gate, M.store().salt, entry.note)[entry.note]
        local form = M.NOTE_FORMS[entry.note]
        if clue == nil or form == nil then return nil end
        local item = container:AddItem(form.item)
        if item == nil then return nil end
        item:setName(M.Tf(form.name, nil, M.T(M.clueNoteName(entry.name))) .. M.numberSuffix(safe.no))
        item:setCustomName(true)
        item:setCanBeWrite(true)
        item:setLockedBy(M.NOTE_LOCKED_BY)
        item:getModData()[M.NOTE_TAG] = tostring(entry.gate)
        item:addPage(1, M.clueText(clue))
        if type(safe.notesGiven) ~= "table" then safe.notesGiven = {} end
        safe.notesGiven[tostring(entry.note)] = true
        M.debug(PART, "clue note " .. tostring(entry.note) .. " for " .. tostring(entry.gate) .. " minted")
        return item
    end

    --- THE ONE PLACE A KEY IS MADE: into `container`, cut to the gate's stored id, named for its
    --- kind. nil when the key was already minted or the gate has no id. A note entry is minted
    --- as its note.
    local function mint(gateId, entry, container)
        if settled(gateId, entry) then return nil end
        if type(entry) == "table" and entry.note ~= nil then return mintNote(entry, container) end
        local gate = M.store().gates[gateId]
        local item = container:AddItem(M.KEY_ITEM)
        if item == nil then return nil end
        item:setKeyId(gate.keyId)
        -- A missing phrase echoes its key: the key keeps the vanilla name rather than show that.
        local phrase = M.KEY_NAME_PREFIX .. tostring(gate.kind)
        local okName, name = pcall(getText, phrase)
        if not (okName and type(name) == "string" and name ~= phrase) then name = item:getName() end
        item:setName(name .. M.numberSuffix(gate.no))
        item:setCustomName(true)
        gate.keyGiven = true
        M.debug(PART, "key for " .. tostring(gateId) .. " minted")
        return item
    end

    -- ---- the building's furniture ------------------------------------------------------------------

    local function furniture(obj)
        if instanceof(obj, "IsoDeadBody") or instanceof(obj, "IsoWorldInventoryObject")
            or instanceof(obj, "IsoMovingObject") then return false end
        return true
    end

    --- Every container of the building's furniture a key may go in: never one of the mod's boxes,
    --- recorded or not, sealed or opened (their container types are the gate kinds'). Each is
    --- { c, room = its room's id, holder = a key holder type, at = its place for the tie hash }.
    local function holdersOf(def)
        local cell = getCell()
        local out = {}
        local rooms = def:getRooms()
        for r = 0, rooms:size() - 1 do
            local room = rooms:get(r)
            local roomId = M.roomIdOf(room)
            local z = room:getZ()
            local rects = room:getRects()
            for k = 0, rects:size() - 1 do
                local rect = rects:get(k)
                for x = rect:getX(), rect:getX() + rect:getW() - 1 do
                    for y = rect:getY(), rect:getY() + rect:getH() - 1 do
                        local sq = cell:getGridSquare(x, y, z)
                        local objects = sq ~= nil and sq:getObjects() or nil
                        for o = 0, (objects ~= nil and objects:size() or 0) - 1 do
                            local obj = objects:get(o)
                            -- The count first: walls and floors hold none, and it is one call.
                            local count = obj:getContainerCount()
                            if count > 0 and furniture(obj) then
                                for i = 0, count - 1 do
                                    local c = obj:getContainerByIndex(i)
                                    local ctype = c ~= nil and c:getType() or nil
                                    if ctype ~= nil and M.kindForContainer(ctype) == nil then
                                        out[#out + 1] = { c = c, room = roomId, holder = M.KEY_HOLDERS[ctype] == true,
                                            at = x .. "," .. y .. "," .. z .. "," .. o .. "," .. i }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return out
    end

    --- The holder of `holders` the key goes in, or nil. The preferred room scores 2, a key holder
    --- type 1; ties go to a hash, so the choice is the same on every try. The preferred room is
    --- any other room of the building than the gate's, so a key or a note is not found beside its
    --- box; the gate's room is the fallback. `seed` joins the tie hash, so a safe's notes need not
    --- all land in one holder.
    local function scoreOf(h, roomId)
        local preferred = h.room ~= roomId
        return (preferred and 2 or 0) + (h.holder and 1 or 0)
    end

    local function pickHolder(holders, roomId, seed)
        local top = nil
        for n = 1, #holders do
            local score = scoreOf(holders[n], roomId)
            if top == nil or score > top then top = score end
        end
        if top == nil then return nil end
        -- Only the top score's holders are hashed: the hash is the dear part.
        local tail = "|" .. tostring(M.store().salt) .. (seed ~= nil and ("|" .. tostring(seed)) or "")
        local best, bestTie = nil, nil
        for n = 1, #holders do
            local h = holders[n]
            if scoreOf(h, roomId) == top then
                local tie = M.unit("h|" .. h.at .. tail)
                if bestTie == nil or tie < bestTie then best, bestTie = h.c, tie end
            end
        end
        return best
    end

    --- The container of the building's furniture the key for a box in `roomId` goes in, or nil.
    function M.keyHolder(def, roomId, seed)
        return pickHolder(holdersOf(def), roomId, seed)
    end

    --- Place what keys this building still owes, once it is fully streamed in. Stash calls it on
    --- every visit. With a deadline (getTimestampMs) it stops once that passes, one entry minted
    --- at least. Returns how many it placed, and true when it stopped with entries left to try.
    function M.placeKeys(def, bkey, deadline)
        local srec = M.store().stashes[bkey]
        if not hasKeys(srec) then return 0 end
        local okFull, full = pcall(def.isFullyStreamedIn, def)
        if not okFull or full ~= true then return 0 end
        local placed = 0
        local holders = nil
        for id, entry in pairs(srec.keys) do
            if placed > 0 and deadline ~= nil and getTimestampMs() >= deadline then return placed, true end
            -- No container in the whole building: the key stays queued and the fallback carries it.
            -- A key or a note goes to another room than its box's; the body's note waits for a body.
            local isNote = entry.note ~= nil
            if not (isNote and entry.note == M.NOTE_ON_BODY) then
                if holders == nil then holders = holdersOf(def) end
                local container = pickHolder(holders, entry.room, isNote and id or nil)
                if container ~= nil then
                    local item = mint(id, entry, container)
                    if item ~= nil then
                        placed = placed + 1
                        if M.isMultiplayer() then sendAddItemToContainer(container, item) end
                    end
                end
            end
            if settled(id, entry) then drop(bkey, id) end
        end
        return placed
    end

    -- ---- the fallback ------------------------------------------------------------------------------

    --- Squared distance from x,y to the nearest point of a building's footprint.
    local function dist2(r, x, y)
        local dx = math.max(r[1] - x, 0, x - (r[1] + r[3]))
        local dy = math.max(r[2] - y, 0, y - (r[2] + r[4]))
        return dx * dx + dy * dy
    end

    --- The entry a body takes first: a body's note before anything else, so the dead owner
    --- carries it even when a key or another note waits on the same building.
    local function bodyFirst(keys)
        local list = {}
        for id, entry in pairs(keys) do
            if type(entry) == "table" and entry.note == M.NOTE_ON_BODY then
                table.insert(list, 1, { id = id, entry = entry })
            else
                list[#list + 1] = { id = id, entry = entry }
            end
        end
        return list
    end

    --- A zombie died: the first building with a key pending within range gives it the key, or
    --- the safe's body note before anything. The authority only. Returns the item, or nil.
    function M.onZombieDead(zombie)
        if not M.isWorldAuthority() then return nil end
        local idx = index()
        if idx.n <= 0 or zombie == nil then return nil end
        local zx, zy = zombie:getX(), zombie:getY()
        local range2 = M.KEY_FALLBACK_RANGE * M.KEY_FALLBACK_RANGE
        local stashes = M.store().stashes
        for bkey, r in pairs(idx.at) do
            if r and dist2(r, zx, zy) <= range2 then
                local srec = stashes[bkey]
                if hasKeys(srec) then
                    local order = bodyFirst(srec.keys)
                    for i = 1, #order do
                        local id, entry = order[i].id, order[i].entry
                        local item = mint(id, entry, zombie:getInventory())
                        if settled(id, entry) then drop(bkey, id) end
                        if item ~= nil then return item end
                    end
                else
                    mark(bkey, false)
                end
            end
        end
        return nil
    end

    -- NOT M.addHandler, for Gating's reason: one odd zombie must not end the fallback.
    if M.isWorldAuthority() then
        if Events ~= nil and Events.OnZombieDead ~= nil then
            Events.OnZombieDead.Add(function(zombie)
                local ok, err = pcall(M.onZombieDead, zombie)
                if not ok then M.defect(PART, "zombie death: " .. tostring(err)) end
            end)
            M.status(PART, true)
        else
            M.defect(PART, "Events.OnZombieDead does not exist on this build", true)
        end
    end
end
