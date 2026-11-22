--[[
    Stash
    Puts the stash boxes into the world on the authority, as the chunks under a building stream
    in. Spots.lua decides; this file reads the engine for it and places what it decided.

    ONE BUILDING AT A TIME, RESUMABLE. A building that hosts a stash (a hash, Spots.hostsStash)
    gets a record { want, k, placed }: how many boxes, which of its ranked rooms is next, how many
    went in. A room is judged only once every square of it and of the ring around it is loaded,
    since half a room would misread its walls; until then the building waits for its next chunk.
    A judged room is passed whether it took a box or had no hiding square, so a reload never
    stamps a second box and never re-judges a room. A building whose rooms are all judged is done.

    THE BOX GOES IN EXPLORED AND ALREADY SEALED, through transmitAddObjectToSquare (never
    AddTileObject then a transmit: the transmit skips an object already on the square,
    docs/28), so the object reaches every client that has its square loaded, with its tag, and
    the engine never rolls loot into it. A client still loading a neighbouring chunk drops that
    add (AddItemToMapPacket.java:56) and may have been served the chunk without the box, so in
    multiplayer the square is also announced (NET_PLACED): such a client asks for it again once
    the square is in (Actions.lua), and World.lua resends it. A sealed tile has no IsMoveAble or
    CanScrap property, so it cannot be picked up or scrapped: the only ways in are this mod's
    routes, and a sledge counts as smashing (World.lua). An opened one is IsMoveAble (Carry.lua).

    EACH ROOM HIDES ONE KIND OF BOX (Spots.kindFor): a crate, a lockbox or a footlocker, each on
    its own tiles with its own container type. A keyed box's key id is assigned before the box
    is sent, and its key waits on the building's record until Keys.lua can place it.

    A FLOOR NOBODY CAN CLIMB TO HIDES NOTHING. A room above the ground floor (or below it) is
    judged only once stairs or a ladder are found on every floor between it and the ground, in
    the building or just outside it; with none, and the building all streamed in, it is passed.
    An upper room also needs a walk to it from the top of those stairs on its own floor, through
    no wall, inside the building's bounds: a sealed room over a stairwell that serves others is
    passed too.

    ONE BOX A ROOM. A room that holds one of the mod's boxes, stash or safe, takes no other.

    A SAFE IS THE BUILDING'S OWN SECOND DRAW (Spots.hostsSafe), apart from its stashes: on
    VaultSafeChance for a building with a keypad room (a vault, a bank or jeweller's back room,
    a police armory or evidence room), which then keeps it in one of those, else on SafeChance.
    At most one, in the first room of Spots.rankSafeRooms that has a hiding square and no box, by the same
    spot rules, with no level draw (Spots.keepsLevel keeps every
    safe). A building that hosts only a safe gets a record with want = 0; rec.safe is false for
    a building drawn without one, nil on a record from before the safes (drawn at its next
    visit). Gating mints the code with the record; CluesPerSafe clue notes join Keys' queue.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Spots"
require "LugliDeadMansStash/Gating"
require "LugliDeadMansStash/Keys"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Stash"
    local CHUNK = 8

    -- Each flag's IsoFlagType, looked up by name once: a judge reads thousands of squares.
    local FLAGS = {}

    local function flag(props, name)
        if props == nil then return false end
        local f = FLAGS[name]
        if f == nil then
            f = IsoFlagType ~= nil and IsoFlagType[name] or false
            FLAGS[name] = f
        end
        if f == false then return false end
        return props:has(f) == true
    end

    -- Pieces that live on a square's edge or hang on its wall: a box still fits beside them. Not
    -- attachedFloor: that is a rug, and a box set on one clips through it.
    local EDGE_FLAGS = { "WallN", "WallW", "WallNW", "DoorWallN", "DoorWallW", "WindowN", "WindowW",
        "windowN", "windowW", "doorN", "doorW", "attachedN", "attachedW", "attachedS", "attachedE",
        "FloorOverlay" }

    local function edgePiece(props)
        for i = 1, #EDGE_FLAGS do
            if flag(props, EDGE_FLAGS[i]) then return true end
        end
        return false
    end

    -- A sprite property by name, as PropertyContainer.has(String) reads it (IsLow is no IsoFlagType).
    local function prop(props, name) return props ~= nil and props:has(name) == true end

    local ATTACHED = { "attachedN", "attachedW", "attachedS", "attachedE" }

    --- A piece hung low on a wall (rooftop_furniture_13/35, an air conditioner) stands over the
    --- floor of its square: no box fits beside it, though it is a wall piece.
    local function lowOnWall(props)
        if not prop(props, "IsLow") then return false end
        for i = 1, #ATTACHED do
            if flag(props, ATTACHED[i]) then return true end
        end
        return false
    end

    -- A bed is what vanilla sleeps on (IsoFlagType.bed), but so is every chair, couch and bench
    -- (42.22.2 tiles: 793 bed-flagged, 112 named Bed); only these names are beds.
    local BED_NAMES = { Bed = true, Beds = true, Mattress = true }
    local function isBed(props) return flag(props, "bed") and BED_NAMES[props:get("CustomName")] == true end

    local function isFurniture(o, props)
        return o:getContainer() ~= nil or flag(props, "solid") or flag(props, "solidtrans")
    end

    --- Is the square bare floor, does it hold furniture, and does it hold a piece no box may open
    --- toward (furniture or a BlocksPlacement floor piece such as a drum kit, but not a bed)? Read
    --- off its objects.
    local function contents(sq)
        local clean, furn, blocksFront = true, false, false
        local floor = sq:getFloor()
        local objects = sq:getObjects()
        for k = 0, objects:size() - 1 do
            local o = objects:get(k)
            if o ~= floor then
                local props = o:getProperties()
                local edge = edgePiece(props)
                if not edge or lowOnWall(props) then clean = false end
                if not edge then
                    local furniture = isFurniture(o, props)
                    if furniture then furn = true end
                    if (furniture or prop(props, "BlocksPlacement")) and not isBed(props) then blocksFront = true end
                end
            end
        end
        local items = sq:getWorldObjects()
        if items ~= nil and items:size() > 0 then clean = false end
        return clean, furn, blocksFront
    end

    --- Does a railing (Hoppable, TallHoppable) or a see-through wall piece (Wall*Trans) stand on
    --- the `d` edge? It closes the edge but no box backs onto it: the tour put lockboxes on stair
    --- landings against fixtures_railings_01_49 (collideN) and _37 (WallNTrans).
    local SEE_THROUGH = { N = { "HoppableN", "TallHoppableN", "WallNTrans" },
        W = { "HoppableW", "TallHoppableW", "WallWTrans" } }
    local function seeThrough(p, d)
        local names = SEE_THROUGH[d]
        return flag(p, names[1]) or flag(p, names[2]) or flag(p, names[3])
    end

    --- The N and W edges of a square, into `c`: a door, doorway or window on each (oN/oW, and
    --- winN/winW for a window), a solid wall (wN/wW), or a railing (rN/rW). Returns `c`.
    local function edgesOf(sq, c)
        local p = sq:getProperties()
        c.winN = flag(p, "windowN") or flag(p, "WindowN")
        c.winW = flag(p, "windowW") or flag(p, "WindowW")
        c.oN = c.winN or flag(p, "doorN") or flag(p, "DoorWallN")
        c.oW = c.winW or flag(p, "doorW") or flag(p, "DoorWallW")
        local shutN = not c.oN and (flag(p, "WallN") or flag(p, "WallNW") or flag(p, "collideN"))
        local shutW = not c.oW and (flag(p, "WallW") or flag(p, "WallNW") or flag(p, "collideW"))
        c.rN = shutN and seeThrough(p, "N")
        c.rW = shutW and seeThrough(p, "W")
        c.wN = shutN and not c.rN
        c.wW = shutW and not c.rW
        return c
    end

    local FACINGS = { N = true, W = true, S = true, E = true }

    --- The sides the square's furniture opens to (its `Facing` sprite property, N/W/S/E, as
    --- IsoSprite.getFacing reads it), and whether one of its objects is a mod box. Only furniture
    --- (a container, solid or solidtrans) opens onto a neighbour; a wall-hung piece faces its own
    --- square, and a bed's foot is where a chest goes.
    local function facesOf(sq)
        local faces, box = nil, false
        local floor = sq:getFloor()
        local objects = sq:getObjects()
        for k = 0, objects:size() - 1 do
            local o = objects:get(k)
            if M.kindOfSprite(M.liveSpriteName(o)) ~= nil then box = true end
            local props = o ~= floor and o:getProperties() or nil
            if props ~= nil and not edgePiece(props) and isFurniture(o, props) and not isBed(props) then
                local f = props:get("Facing")
                if FACINGS[f] then
                    faces = faces or {}
                    faces[f] = true
                end
            end
        end
        return faces, box
    end

    --- One square as Spots reads it. `inRoom` squares also get free and clean.
    local function cellOf(sq, x, y, inRoom)
        local c = { x = x, y = y, room = inRoom }
        if sq == nil then return c end
        edgesOf(sq, c)
        c.faces, c.box = facesOf(sq)
        local clean, furn, blocksFront = contents(sq)
        c.furn = furn
        c.blocksFront = blocksFront
        if inRoom then
            c.free = sq:isFree(false) == true
            c.clean = clean and not sq:HasStairs()
        end
        return c
    end

    local function inRects(rects, x, y)
        for i = 1, #rects do
            local r = rects[i]
            if x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then return true end
        end
        return false
    end

    --- The room's cells for Spots, or nil and "wait" while any of it is not streamed in. The
    --- ground square answers for whether a column is loaded: on an upper floor, an absent
    --- square outside the room is open air, not a hole in the load.
    function M.roomCells(roomDef)
        local cell = getCell()
        local z = roomDef:getZ()
        local list = roomDef:getRects()
        local rects = {}
        local x0, y0, x1, y1 = nil, nil, nil, nil
        for i = 0, list:size() - 1 do
            local r = list:get(i)
            local rx, ry, rw, rh = r:getX(), r:getY(), r:getW(), r:getH()
            rects[#rects + 1] = { rx, ry, rw, rh }
            x0 = x0 == nil and rx or math.min(x0, rx)
            y0 = y0 == nil and ry or math.min(y0, ry)
            x1 = x1 == nil and (rx + rw - 1) or math.max(x1, rx + rw - 1)
            y1 = y1 == nil and (ry + rh - 1) or math.max(y1, ry + rh - 1)
        end
        if x0 == nil then return nil, "empty" end
        local cells = {}
        for x = x0 - 1, x1 + 1 do
            for y = y0 - 1, y1 + 1 do
                if cell:getGridSquare(x, y, 0) == nil then return nil, "wait" end
                local inRoom = inRects(rects, x, y)
                local sq = cell:getGridSquare(x, y, z)
                if inRoom and sq == nil then return nil, "wait" end
                cells[x .. "," .. y] = cellOf(sq, x, y, inRoom)
            end
        end
        return cells, z
    end

    --- Place a sealed box of `kind` (default the crate) on `sq` against its `dir` wall. Returns
    --- the object and its gate, or nil and why. A keyed kind gets its key id before the box is
    --- sent. The probes place through here too.
    function M.placeStash(sq, dir, roomName, kind)
        kind = kind or "crate"
        local name = M.gateSprite(kind, dir, false)
        if sq == nil or name == nil then return nil, "no square, direction or kind" end
        if getSprite(name) == nil then return nil, "sprite " .. name .. " is not loaded" end
        -- Two boxes on one square share a gate id (x,y,z and container index 0), so the second
        -- record would orphan the first box for good.
        local objects = sq:getObjects()
        for k = 0, objects:size() - 1 do
            if M.kindOfSprite(M.liveSpriteName(objects:get(k))) ~= nil then
                return nil, "the square already holds a box"
            end
        end
        local obj = IsoObject.new(getCell(), sq, name)
        obj:createContainersFromSpriteProperties()
        local container = obj:getContainer()
        if container == nil then return nil, "sprite " .. name .. " made no container" end
        if M.kindForContainer(container:getType()) ~= kind then
            return nil, "sprite " .. name .. " made a " .. tostring(container:getType()) .. " container, not a " .. kind
        end
        container:setExplored(true)
        local md = M.sealObject(obj, container, roomName)
        if md == nil then return nil, "container type " .. tostring(container:getType()) .. " is no gate kind" end
        M.assignKeyId(M.gateId(md.x, md.y, md.z, md.i))
        sq:transmitAddObjectToSquare(obj, -1)
        -- The position only: the key id and a safe's code stay on the record.
        if M.isMultiplayer() then sendServerCommand(M.NET_MODULE, M.NET_PLACED, { x = md.x, y = md.y, z = md.z }) end
        return obj, md
    end

    local function buildingKey(def)
        return def:getX() .. "," .. def:getY() .. "," .. def:getW() .. "," .. def:getH()
    end

    --- The building's rooms, each named as it hides (Spots.hidingName); the id keeps the map's name.
    local function roomsOf(def)
        local out = {}
        local list = def:getRooms()
        for i = 0, list:size() - 1 do
            local r = list:get(i)
            out[#out + 1] = { id = M.roomIdOf(r), name = M.hidingName(r:getName(), r:getZ()), def = r }
        end
        return out
    end

    -- An outside staircase up to a door on an upper floor stands beside the rooms' bounds.
    local STAIRS_MARGIN = 2

    --- Do the stairs or ladder on `sq` belong to `def`, or to no building?
    local function ownStairs(sq, def)
        -- A terraced neighbour's stairs climb into the neighbour, not into this building.
        local owner = sq:getBuildingDef()
        return owner == nil or owner == def or (owner:getX() == def:getX() and owner:getY() == def:getY()
            and owner:getW() == def:getW() and owner:getH() == def:getH())
    end

    --- Is there a ladder on `sq`? Ladders and IsoGridSquare.getLadder came with 42.22.
    local function hasLadder(sq)
        return sq.getLadder ~= nil and sq:getLadder() ~= nil
    end

    --- Do stairs or a ladder climb from `level` to the next floor, in the building or just
    --- outside it in no other building? true, false, or "wait" while none is found and the
    --- building is still streaming.
    local function climbsFrom(def, level)
        local cell = getCell()
        for x = def:getX() - STAIRS_MARGIN, def:getX() + def:getW() - 1 + STAIRS_MARGIN do
            for y = def:getY() - STAIRS_MARGIN, def:getY() + def:getH() - 1 + STAIRS_MARGIN do
                local sq = cell:getGridSquare(x, y, level)
                if sq ~= nil and (sq:HasStairs() or hasLadder(sq)) and ownStairs(sq, def) then return true end
            end
        end
        if not def:isFullyStreamedIn() then return "wait" end
        return false
    end

    --- Can a survivor climb from the ground to floor z? Every floor between needs its own stairs.
    --- `memo` keeps each floor's answer for one visit.
    local function floorReached(def, z, memo)
        local from, to = 0, z - 1
        if z < 0 then from, to = z, -1 end
        for level = from, to do
            local climbs = memo[level]
            if climbs == nil then
                climbs = climbsFrom(def, level)
                if climbs ~= "wait" then memo[level] = climbs end
            end
            if climbs ~= true then return climbs end
        end
        return true
    end

    local WALK = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

    -- edgesOf sets every field it reads, so the walk reuses one table instead of one a step.
    local walkEdges = {}

    --- Is there a wall between x,y and its neighbour dx,dy on floor z? A square owns its N and W edges.
    local function walledTo(cell, x, y, z, dx, dy)
        local owner = cell:getGridSquare(dy == 1 and x or (dx == 1 and x + 1 or x), dy == 1 and y + 1 or y, z)
        if owner == nil then return false end
        local e = edgesOf(owner, walkEdges)
        if dy ~= 0 then return e.wN or e.rN end
        return e.wW or e.rW
    end

    local function standable(sq)
        return sq ~= nil and sq:getFloor() ~= nil and sq:isFree(false) == true
    end

    --- The squares of floor z (z > 0) a survivor walks to, without crossing a wall, from the top
    --- of the building's stairs and ladders on the floor below, within its bounds: a set of "x,y".
    --- A stair top lands one square past it (IsoGridSquare's stairsTN and stairsTW); a ladder on
    --- any side of its column.
    local function landed(def, z)
        local cell = getCell()
        local x0, y0 = def:getX() - STAIRS_MARGIN, def:getY() - STAIRS_MARGIN
        local x1, y1 = def:getX() + def:getW() - 1 + STAIRS_MARGIN, def:getY() + def:getH() - 1 + STAIRS_MARGIN
        local seen, queue = {}, {}
        local function push(x, y)
            if x < x0 or x > x1 or y < y0 or y > y1 then return end
            local k = x .. "," .. y
            if seen[k] or not standable(cell:getGridSquare(x, y, z)) then return end
            seen[k] = true
            queue[#queue + 1] = { x, y }
        end
        for x = x0, x1 do
            for y = y0, y1 do
                local below = cell:getGridSquare(x, y, z - 1)
                local topN = below ~= nil and below:HasStairTopNorth()
                local topW = below ~= nil and below:HasStairTopWest()
                local ladder = below ~= nil and hasLadder(below)
                if (topN or topW or ladder) and ownStairs(below, def) then
                    if topN then push(x, y - 1) end
                    if topW then push(x - 1, y) end
                    if ladder then
                        push(x, y)
                        for i = 1, #WALK do
                            local dx, dy = WALK[i][1], WALK[i][2]
                            if not walledTo(cell, x, y, z, dx, dy) then push(x + dx, y + dy) end
                        end
                    end
                end
            end
        end
        local i = 1
        while i <= #queue do
            local x, y = queue[i][1], queue[i][2]
            for j = 1, #WALK do
                local dx, dy = WALK[j][1], WALK[j][2]
                if not walledTo(cell, x, y, z, dx, dy) then push(x + dx, y + dy) end
            end
            i = i + 1
        end
        return seen
    end

    --- Does a walk from the stairs reach the room's own squares? true, false, or "wait" while it
    --- does not and the building is still streaming. A walk over the whole building is kept per
    --- floor in `memo`.
    local function roomReached(def, z, cells, memo)
        if z <= 0 then return true end
        local memoKey = "walk|" .. z
        local seen = memo[memoKey]
        if seen == nil then
            seen = landed(def, z)
            if def:isFullyStreamedIn() then memo[memoKey] = seen end
        end
        for k, c in pairs(cells) do
            if c.room == true and seen[k] then return true end
        end
        if memo[memoKey] == nil then return "wait" end
        return false
    end

    --- One room's turn for a box of `kind`: "placed", "none" (judged, no box) or "wait". The
    --- square is a draw on `spotSeed`, read off the room as it is now, so a room that already
    --- holds one box never takes a second. A keyed box queues its key on the
    --- building's record, a safe its clue notes.
    local function judgeRoom(def, room, salt, bkey, kind, spotSeed, memo)
        local cells, z = M.roomCells(room.def)
        if cells == nil then return z == "wait" and "wait" or "none" end
        local reached = floorReached(def, z, memo)
        if reached == "wait" then return "wait" end
        if reached ~= true then
            M.debug(PART, "no stairs reach floor " .. tostring(z) .. " of " .. room.id)
            return "none"
        end
        local walked = roomReached(def, z, cells, memo)
        if walked == "wait" then return "wait" end
        if walked ~= true then
            M.debug(PART, "no walk from the stairs reaches " .. room.id)
            return "none"
        end
        local spot = M.pickSpot(cells, spotSeed, room.name)
        if spot == nil then
            M.debug(PART, "no hiding square in " .. room.id)
            return "none"
        end
        local tier = M.tierFor(M.GATE_BOXES[kind].container, room.name)
        if not M.keepsLevel(room.id, salt, tier, kind) then
            M.debug(PART, "a tier " .. tostring(tier) .. " box passed over in " .. room.id)
            return "none"
        end
        local obj, md = M.placeStash(getCell():getGridSquare(spot.x, spot.y, z), spot.dir, room.name, kind)
        if obj == nil then
            M.defect(PART, "placing in " .. room.id .. ": " .. tostring(md))
            return "none"
        end
        if M.isKeyedKind(kind) then M.queueKey(bkey, M.gateId(md.x, md.y, md.z, md.i), room.id) end
        if M.isSafeKind(kind) then
            for n = 1, math.floor(M.cfg("CluesPerSafe")) do
                M.queueNote(bkey, M.gateId(md.x, md.y, md.z, md.i), n, room.id, room.name)
            end
        end
        return "placed"
    end

    -- The room's kind is a hash of its id and the salt (Spots.kindFor), so it is the same on every load.
    local function nowMs() return getTimestampMs ~= nil and getTimestampMs() or 0 end

    --- Has this visit used up its time? A nil deadline never does.
    local function spent(deadline) return deadline ~= nil and nowMs() >= deadline end

    local near = nil

    --- The percent of the ground built on within DENSITY_RADIUS of the building's middle, itself
    --- included (Spots): every footprint meeting the square, clipped to it.
    local function builtOf(def)
        if near == nil then near = ArrayList.new() end
        near:clear()
        local r = M.DENSITY_RADIUS
        local cx, cy = def:getX() + math.floor(def:getW() / 2), def:getY() + math.floor(def:getH() / 2)
        local x0, y0, x1, y1 = cx - r, cy - r, cx + r, cy + r
        getWorld():getMetaGrid():getBuildingsIntersecting(x0, y0, 2 * r, 2 * r, near)
        local area = 0
        for i = 0, near:size() - 1 do
            local b = near:get(i)
            local bx, by = b:getX(), b:getY()
            local w = math.min(bx + b:getW(), x1) - math.max(bx, x0)
            local h = math.min(by + b:getH(), y1) - math.max(by, y0)
            if w > 0 and h > 0 then area = area + w * h end
        end
        return 100 * area / (4 * r * r)
    end

    local function advance(def, key, rec, salt, memo, deadline)
        local rooms = roomsOf(def)
        local profile = M.buildingProfile(rooms, def:getW() * def:getH(), rec.built)
        local ranked = M.rankRooms(rooms, salt)
        -- One room at least before a yield, so a building can never yield without moving on.
        local judged = false
        while rec.placed < rec.want and rec.k <= #ranked do
            if judged and spent(deadline) then return "yield" end
            judged = true
            local room = ranked[rec.k]
            local kind = M.kindFor(room.name, profile)
            local outcome = judgeRoom(def, room, salt, key, kind, salt .. "|" .. room.id, memo)
            if outcome == "wait" then return end
            rec.k = rec.k + 1
            if outcome == "placed" then rec.placed = rec.placed + 1 end
        end
        rec.done = true
    end

    --- The building's safe rooms in the order they are tried, and whether it is a vault building
    --- (Spots.rankSafeRooms).
    local function safeRooms(def, salt, built)
        local rooms = roomsOf(def)
        return M.rankSafeRooms(rooms, M.buildingProfile(rooms, def:getW() * def:getH(), built), salt)
    end

    --- The safe's turn: its rooms in order until one keeps it; a room that waits holds the rest.
    local function advanceSafe(def, key, safe, salt, built, memo, deadline)
        local ranked = safeRooms(def, salt, built)
        local judged = false
        while safe.k <= #ranked do
            if judged and spent(deadline) then return "yield" end
            judged = true
            local entry = ranked[safe.k]
            local outcome = judgeRoom(def, entry.room, salt, key, entry.kind, salt .. "|safe|" .. entry.room.id, memo)
            if outcome == "wait" then return end
            safe.k = safe.k + 1
            if outcome == "placed" then
                safe.placed = true
                break
            end
        end
        safe.done = true
    end

    --- The building's safe draw: VaultSafeChance for a vault building, SafeChance for any other,
    --- each for surroundings `built` percent built on (Spots.localChance).
    local function drawSafe(def, key, salt, built)
        local dial, vaultPct = M.localChance(M.cfg("SafeChance"), built), M.localChance(M.cfg("VaultSafeChance"), built)
        -- One draw against a threshold: a building over both thresholds never needs its rooms read.
        if not M.hostsSafe(key, salt, math.max(dial, vaultPct)) then return false end
        local _, vault = safeRooms(def, salt, built)
        local pct = vault and vaultPct or dial
        if M.hostsSafe(key, salt, pct) then return { k = 1 } end
        return false
    end

    -- A yielded building's floor and walk answers, kept until it finishes, so its next turn does
    -- not walk the stairs again.
    local memos = {}

    --- Advance one building as far as its loaded rooms allow, then place the keys and notes it
    --- still owes. With a deadline (getTimestampMs) it stops between rooms once that passes and
    --- returns "yield"; the record keeps its place, so the next visit carries on.
    function M.visitBuilding(def, deadline)
        local s = M.store()
        local key = buildingKey(def)
        local rec = s.stashes[key]
        -- A building drawn empty keeps the chances it was drawn at, so it is judged once per
        -- setting rather than once per chunk load (drawSafe reads every room).
        -- Built only for a building not yet judged, or judged empty: a placed one skips it.
        local chances = (rec == nil or rec.none ~= nil) and (tostring(M.cfg("StashChance")) .. "|"
            .. tostring(M.cfg("SafeChance")) .. "|" .. tostring(M.cfg("VaultSafeChance"))) or nil
        if rec ~= nil and rec.none ~= nil then
            if rec.none == chances then return end
            rec = nil
        end
        if rec == nil then
            local built = builtOf(def)
            local stash = M.hostsStash(key, s.salt, M.localChance(M.cfg("StashChance"), built))
            local safe = drawSafe(def, key, s.salt, built)
            if not stash and not safe then
                s.stashes[key] = { none = chances }
                return
            end
            rec = { want = stash and M.stashCountFor(def:getW() * def:getH(), M.cfg("MaxPerBuilding")) or 0,
                k = 1, placed = 0, safe = safe, built = built }
            s.stashes[key] = rec
        end
        -- A record from before the area (2026-11-19) reads its surroundings once, at its next visit.
        if rec.built == nil then rec.built = builtOf(def) end
        if rec.safe == nil then rec.safe = drawSafe(def, key, s.salt, rec.built) end
        local memo = memos[key] or {}
        if not rec.done and advance(def, key, rec, s.salt, memo, deadline) == "yield"
            or rec.safe and not rec.safe.done and advanceSafe(def, key, rec.safe, s.salt, rec.built, memo, deadline) == "yield" then
            memos[key] = memo
            return "yield"
        end
        memos[key] = nil
        -- The holder scan reads the whole building: it starts on a fresh budget, never a spent one.
        if spent(deadline) then return "yield" end
        local _, more = M.placeKeys(def, key, deadline)
        if more then return "yield" end
    end
    M.addTeardown(PART, function() memos = {} end)

    -- THE BUDGET. Judging a big building reads every square of its rooms and walks its stairs:
    -- 516 ms for 43 rooms on 37x26 at the measured worst (docs/31). A chunk load hands its
    -- buildings to a queue that spends VISIT_BUDGET_MS a tick, so a big building costs a few
    -- frames a little each, never one long one. The budget is the tick's, not the call's: a
    -- teleport fires LoadChunk dozens of times in one tick.
    M.VISIT_BUDGET_MS = 4
    local queue, queued = {}, {}
    local budgetEnds = nil
    M.addTeardown(PART, function() queue, queued, budgetEnds = {}, {}, nil end)

    local function enqueue(def)
        local key = buildingKey(def)
        if queued[key] then return end
        queued[key] = true
        queue[#queue + 1] = def
    end

    --- Visit queued buildings until the tick's budget is spent. A yielded building keeps the head
    --- of the queue. Returns how many are still queued.
    function M.drainVisits()
        if #queue == 0 then return 0 end
        if budgetEnds == nil then
            budgetEnds = nowMs() + M.VISIT_BUDGET_MS
        elseif spent(budgetEnds) then
            return #queue
        end
        local deadline = budgetEnds
        while #queue > 0 do
            local def = queue[1]
            local ok, res = pcall(M.visitBuilding, def, deadline)
            if not ok then M.defect(PART, "building " .. tostring(def and buildingKey(def)) .. ": " .. tostring(res)) end
            if ok and res == "yield" then break end
            table.remove(queue, 1)
            queued[buildingKey(def)] = nil
            if spent(deadline) then break end
        end
        return #queue
    end

    --- A new tick: a fresh budget, then the queue carries on.
    local function onTick()
        budgetEnds = nil
        M.drainVisits()
    end

    local found = nil

    --- Every building with a square in this chunk joins the queue, which starts on it at once.
    function M.onLoadChunk(chunk)
        if M.cfg("Enabled") ~= true then return end
        local origin = chunk:getGridSquare(0, 0, 0)
        if origin == nil then return end
        if found == nil then found = ArrayList.new() end
        found:clear()
        getWorld():getMetaGrid():getBuildingsIntersecting(origin:getX(), origin:getY(), CHUNK, CHUNK, found)
        for i = 0, found:size() - 1 do enqueue(found:get(i)) end
        M.drainVisits()
    end

    -- NOT M.addHandler, for Gating's reason: one odd building must not end placement.
    if M.isWorldAuthority() then
        if Events ~= nil and Events.LoadChunk ~= nil then
            Events.LoadChunk.Add(function(chunk)
                local ok, err = pcall(M.onLoadChunk, chunk)
                if not ok then M.defect(PART, "chunk: " .. tostring(err)) end
            end)
            M.addTicker(PART, 0, onTick)
            M.status(PART, true)
        else
            M.defect(PART, "Events.LoadChunk does not exist on this build", true)
        end
    end
end
