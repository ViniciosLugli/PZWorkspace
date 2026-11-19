--[[
    Spots
    Where a dead man hid his stash: which buildings hold one, which of their rooms, and which
    square of that room. Pure: Stash.lua reads the engine into plain tables and calls in here, so
    every rule below is exercised offline (dms-spots).

    A STASH IS TUCKED AWAY, NEVER LEFT IN THE OPEN. A square qualifies only when it is bare
    floor, has a wall (never a railing) on at least one side, is not a one-tile passage (walls or
    railings on two opposite sides), is not in or beside a doorway or window, can be reached from
    a walkable square of the same room, is not in front of a neighbour's open side (cell.faces:
    the sides its furniture faces), does not take the last open side of a piece of furniture,
    and has a wall the box can back onto whose opposite side, where the box opens, is no wall and
    holds nothing that blocks a front (cell.blocksFront; a bed's foot is fine). The box goes
    against such a wall only. A closet of SNUG_TILES or fewer may use the square beside its door
    square, facing it, never beside a window square. Among those, corners and alcoves beat a plain
    wall, a spot beside furniture beats a bare one, and the farther from the room's openings the
    better. A room with no qualifying square gets no stash: the room's centre is never a fallback,
    and a room that already holds a box (cell.box) gets no second one.

    EVERY CHOICE IS A HASH OF THE MAP AND A PER-WORLD SALT, never a roll. A building is judged
    again on every load of a chunk it touches, so a roll would re-roll; the hash gives the same
    answer every time, and the authority stores only what it placed.
]]

require "LugliDeadMansStash/Core"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash

    -- THE BOXES, one per gate kind. Each kind has four sealed tiles from `sealed`, pushed against
    -- the north, west, south and east wall, and the same four opened from `opened`. The indices
    -- are load-bearing for every save that holds one.
    M.STASH_TILESET = "lugli_deadmansstash_01"
    M.SPOT_DIR_INDEX = { N = 0, W = 1, S = 2, E = 3 }
    M.GATE_FACINGS = 4
    -- stance: how far from its square's centre a survivor kneels to work the box, so the hands
    -- meet its front. Each box's front face (tools/dms-tiles.py: 0.075 off its wall, then its
    -- depth) plus the 0.8 a crouched survivor's hands reach, measured on the crate in game (its
    -- face 0.025 behind the centre, worked from 0.78). A safe is solid (solidtrans) and holds a
    -- body off at 0.78; the boxes are walked over.
    M.GATE_BOXES = {
        crate = { container = "dmsstash", sealed = 0, opened = 4, stance = 0.78 },
        lockbox = { container = "dmslockbox", sealed = 8, opened = 12, stance = 0.66 },
        footlocker = { container = "dmsfootlocker", sealed = 16, opened = 20, stance = 0.80 },
        dialsafe = { container = "dmsdialsafe", sealed = 24, opened = 28, safe = true, stance = 0.78 },
        keypadsafe = { container = "dmskeypadsafe", sealed = 32, opened = 36, safe = true, stance = 0.78 },
    }
    M.STASH_CONTAINER = M.GATE_BOXES.crate.container

    --- The sprite name for a box of `kind` against `dir`, sealed or opened, or nil.
    function M.gateSprite(kind, dir, opened)
        local box = M.GATE_BOXES[kind]
        local i = M.SPOT_DIR_INDEX[dir]
        if box == nil or i == nil then return nil end
        local base = opened and box.opened or box.sealed
        return M.STASH_TILESET .. "_" .. (base + i)
    end

    --- The crate's sprite against `dir`, sealed or opened.
    function M.stashSprite(dir, opened) return M.gateSprite("crate", dir, opened) end

    --- The tile index of a sprite name in the box tileset, or nil for any other name.
    local function boxTileIndex(name)
        if type(name) ~= "string" then return nil end
        local prefix = M.STASH_TILESET .. "_"
        if string.sub(name, 1, #prefix) ~= prefix then return nil end
        local i = tonumber(string.sub(name, #prefix + 1))
        if i == nil or i ~= math.floor(i) then return nil end
        return i
    end

    --- The gate kind a box sprite shows and whether it is the opened one, or nil for any other
    --- sprite: the only proof an object is one of the mod's boxes that a client cannot forge.
    local function judgeSprite(name)
        local i = boxTileIndex(name)
        if i == nil then return false, false end
        for kind, box in pairs(M.GATE_BOXES) do
            if i >= box.sealed and i < box.sealed + M.GATE_FACINGS then return kind, false end
            if i >= box.opened and i < box.opened + M.GATE_FACINGS then return kind, true end
        end
        return false, false
    end

    -- Asked for every object a hook meets, so each name is parsed once: the tile set is finite.
    local kindByName, openedByName = {}, {}

    function M.kindOfSprite(name)
        if type(name) ~= "string" then return nil end
        local kind = kindByName[name]
        if kind == nil then
            kind, openedByName[name] = judgeSprite(name)
            kindByName[name] = kind
        end
        if kind == false then return nil end
        return kind, openedByName[name]
    end

    --- The opened twin of a sealed box sprite of any kind, or nil for any other sprite.
    function M.openedSpriteOf(name)
        local kind, opened = M.kindOfSprite(name)
        if kind == nil or opened then return nil end
        local box = M.GATE_BOXES[kind]
        return M.STASH_TILESET .. "_" .. (box.opened + boxTileIndex(name) - box.sealed)
    end

    --- Where a survivor kneels to work a box of any kind, sealed or opened: the square its open
    --- side faces, away from the wall it is pushed against, as { dx, dy } from the box. nil for
    --- any other sprite.
    local FRONT = { N = { 0, 1 }, W = { 1, 0 }, S = { 0, -1 }, E = { -1, 0 } }
    local DIR_OF = {}
    for d, i in pairs(M.SPOT_DIR_INDEX) do DIR_OF[i] = d end
    function M.frontOfSprite(name)
        local kind, opened = M.kindOfSprite(name)
        if kind == nil then return nil end
        local box = M.GATE_BOXES[kind]
        return FRONT[DIR_OF[boxTileIndex(name) - (opened and box.opened or box.sealed)]]
    end

    -- ROOMS A STASH HIDES IN, weighted: the higher, the likelier it is the one picked in its
    -- building. Private and back rooms only. A living room, kitchen, hall or bathroom is where
    -- the dead man lived in plain sight, so it never hides one. Names are the map's own
    -- (scratch room census of the 42.22.2 lotheaders). A laundry or a changing room is a room
    -- people walk through, so neither hides one; the army surplus and gun store floors are the
    -- last place tried in their building.
    M.STASH_ROOMS = {
        attic = 4, basement = 4, bunker = 4,
        closet = 3, storage = 3, storageunit = 3, garagestorage = 3, shed = 3, officestorage = 3,
        farmstorage = 3, armystorage = 3, gunstorestorage = 3, policestorage = 3, pawnshopstorage = 3,
        bedroom = 2, janitor = 2, garage = 2, barn = 2, warehouse = 2, security = 2,
        lockerroom = 2, mechanic = 2, medicalstorage = 2, pharmacystorage = 2,
        office = 1, grocerystorage = 1, producestorage = 1, armysurplus = 1, gunstore = 1,
    }

    -- MAP MODS' NAMES FOR VANILLA ROOMS, misspelt or their own (room census of the lotheaders of
    -- Raven Creek, Dirkerdam, the ARC maps, Fort Waterfront, Fort Benning, Atlas and Nellis,
    -- 2026-11-19): each hides as the vanilla room it is. Names no vanilla room shares only.
    M.ROOM_ALIASES = {
        stroge = "storage", stoage = "storage", generalstorage = "storage", warehousestorage = "storage",
        sparebedroom = "bedroom", ofiice = "office", janitorscloset = "janitor",
        garagenstorage = "garagestorage", polistorage = "policestorage", pharmarcystorage = "pharmacystorage",
        gunshop = "gunstore", gunshopstorage = "gunstorestorage", armysurplustorage = "armystorage",
        pawnsshop = "pawnshop", jewelrystorestorage = "jewelrystorage",
    }

    -- An underground room the map names `storage` is a basement storeroom (42.22.2: 372 of them,
    -- against 3 underground rooms named basement), so it hides as a basement.
    function M.hidingName(roomName, z)
        roomName = M.ROOM_ALIASES[roomName] or roomName
        if roomName == "storage" and (tonumber(z) or 0) < 0 then return "basement" end
        return roomName
    end

    -- WHICH BOX A ROOM HIDES, fixed by the room's exact name. A keyed lockbox where a man keeps
    -- papers and valuables (a bedroom, an office and its storeroom, a closet, a locker room, a
    -- pawnshop's back room of pawned cash, jewellery and handguns); a
    -- padlocked military footlocker where vanilla keeps military lockers (Distributions.lua:
    -- army, gun, police and security rooms) and in an attic or a basement, where an old army
    -- trunk is put away (2026-11-19: with the military rooms alone a world held about 4); a nailed
    -- crate everywhere else: bunker, garage, shed, barn, warehouse, mechanic and every other
    -- storeroom, a pharmacy's paying medicine (Payout). A room no list names hides a crate.
    M.DEFAULT_KIND = "crate"
    M.ROOM_KINDS = {
        bedroom = "lockbox", office = "lockbox", closet = "lockbox", lockerroom = "lockbox",
        officestorage = "lockbox",
        armystorage = "footlocker", armysurplus = "footlocker", gunstore = "footlocker",
        gunstorestorage = "footlocker", policestorage = "footlocker", security = "footlocker",
        attic = "footlocker", basement = "footlocker",
        pawnshopstorage = "lockbox",
    }

    -- THE RICHER THE BOX, THE RARER. A room that would hide a box of tier t keeps it at
    -- LEVEL_KEEP[t], a stable draw on the room's own key; a room that does not is passed over and
    -- the building tries its next one, so a gun store usually hides an ordinary box, not a rich one.
    M.LEVEL_KEEP = { 1, 0.4, 0.2 }

    --- Does this room keep a box of `tier`? Stable for a room and a world. A safe (`kind` a safe
    --- kind) always keeps its tier: SafeChance is already its rarity, and both together left a
    --- safe in under 1 percent of eligible buildings.
    function M.keepsLevel(roomId, salt, tier, kind)
        local box = kind ~= nil and M.GATE_BOXES[kind] or nil
        if box ~= nil and box.safe then return true end
        local keep = M.LEVEL_KEEP[tier]
        if keep == nil or keep >= 1 then return true end
        return M.unit("l|" .. tostring(roomId) .. "|" .. tostring(salt)) < keep
    end

    -- A LUCKY BOX (2026-11-19, user review: Good and Rich too far from Ordinary). The quality a
    -- box's room gives it (Gates.tierFor) is where its quality starts: one stable draw on the gate
    -- and the world lifts it, so a reload never changes it. An Ordinary box turns Rich below
    -- LUCK[1].rich and Good below LUCK[1].good; a Good one (a safe, a rich room's box) Rich below
    -- LUCK[2].rich. Map-wide at the defaults that reads about 60 % Ordinary, 30 % Good, 10 % Rich.
    M.LUCK = { { rich = 0.05, good = 0.22 }, { rich = 0.12 } }

    --- The quality of the box at `gateId` that its room starts at `tier`, after its luck.
    function M.luckyTier(gateId, salt, tier)
        local luck = M.LUCK[tier]
        if luck == nil then return tier end
        -- Hashing a first hash, as hostsSafe does: the draw owes the placement draws nothing.
        local u = M.unit("lucky|" .. M.hash(tostring(gateId) .. "|" .. tostring(salt)))
        if luck.rich ~= nil and u < luck.rich then return 3 end
        if luck.good ~= nil and u < luck.good then return 2 end
        return tier
    end

    -- A building holds one stash, and one more for every this many tiles of footprint, up to the
    -- sandbox cap. A 32 by 32 footprint is a large store; every house holds at most one.
    M.AREA_PER_EXTRA = 1000

    -- ---- the hash ----------------------------------------------------------------------------------

    local MOD = 2147483647
    local MULT = 48271

    --- A well-mixed integer in 1..2^31-2 for a string. djb2 alone moves by one when the last
    --- character does, so neighbouring buildings would draw alike: three Park-Miller steps spread
    --- that one into the whole range.
    function M.hash(s)
        s = tostring(s)
        local h = 5381
        for i = 1, #s do h = (h * 33 + string.byte(s, i)) % MOD end
        if h == 0 then h = 1 end
        for _ = 1, 3 do h = (h * MULT) % MOD end
        return h
    end

    --- A uniform draw in (0, 1) for a string.
    function M.unit(s) return M.hash(s) / MOD end

    -- ---- buildings and rooms -----------------------------------------------------------------------

    --- Does this building hold a stash, at `pct` percent of buildings?
    function M.hostsStash(buildingKey, salt, pct)
        if type(pct) ~= "number" or pct <= 0 then return false end
        return M.unit("b|" .. tostring(buildingKey) .. "|" .. tostring(salt)) * 100 < pct
    end

    -- WHERE A BOX IS LIKELIER (2026-11-19, user review: Louisville too stashed, a player who never
    -- reaches a city must still meet the whole mod). Every chance (stash, safe, vault safe) is the
    -- chance of a regular town street; a remote farm or cabin, whose owner trusted no bank, hides
    -- one more often, a dense city block less often. Read off the share of the ground built on
    -- within DENSITY_RADIUS of the building's middle, so it holds on any map without a list of
    -- towns. Not a count of buildings: a downtown of banks and offices has few, all of them big,
    -- and read as a village. Vanilla, the middle building of each town at radius 300: Louisville
    -- 13 % built (its suburbs from 7, downtown 30), Rosewood, March Ridge and West Point about 8,
    -- Riverside, Brandenburg, Muldraugh, Ekron and Irvington 4 to 6, Fallas Lake 3.5, Valley
    -- Station, Echo Creek and Jefferson about 1, the countryside 0.5.
    M.DENSITY_RADIUS = 300
    M.DENSITY_CURVE = { { 1, 1.5 }, { 3, 1.25 }, { 6, 1.0 }, { 10, 0.8 }, { 14, 0.6 }, { 25, 0.45 } }

    --- A chance's multiplier for a building whose surroundings are `built` percent built on: the
    --- curve read linearly between its points, flat beyond its ends.
    function M.densityFactor(built)
        local n, c = tonumber(built) or 0, M.DENSITY_CURVE
        if n <= c[1][1] then return c[1][2] end
        for i = 2, #c do
            if n <= c[i][1] then
                local a, b = c[i - 1], c[i]
                return a[2] + (b[2] - a[2]) * (n - a[1]) / (b[1] - a[1])
            end
        end
        return c[#c][2]
    end

    --- A chance (StashChance, SafeChance, VaultSafeChance) for a building whose surroundings are
    --- `built` percent built on. 100 stays every building.
    function M.localChance(pct, built)
        if type(pct) ~= "number" or pct >= 100 then return pct end
        return math.min(100, pct * M.densityFactor(built))
    end

    -- THE SAFES. A building is judged for a safe on its own draw, apart from its stash, and holds
    -- at most one, in one of these rooms. Names are the map's own (42.22.2 lotheaders: office
    -- 3981, pawnshop 13, pawnshopoffice 1, pawnshopstorage 3). A keypad safe sits in a back room,
    -- never on a public floor: the bank lobby, the police bullpen and the jeweller's sales floor
    -- held 57 % of them when they were hosts. A building with a keypad room keeps its safe in the
    -- first of KEYPAD_ORDER it has a hiding square in (vault 7, depositboxes 5, bankstorage 11,
    -- jewelrystorage 7, policegunstorage 19, evidenceroom 5, policestorage 2, captainoffice 2).
    -- A pharmacy's stockroom keeps its drugs, a gun store's back room its guns, in a keypad safe
    -- (2026-11-19): nearly every small town has one or the other, where only a few have a bank or a
    -- police station, so a player who never reaches a city still meets a keypad.
    M.KEYPAD_ORDER = { "vault", "depositboxes", "bankstorage", "jewelrystorage", "policegunstorage",
        "evidenceroom", "policestorage", "captainoffice", "gunstorestorage", "pharmacystorage" }
    M.SAFE_ROOMS = { office = "dialsafe", pawnshop = "dialsafe", pawnshopoffice = "dialsafe", pawnshopstorage = "dialsafe" }
    M.KEYPAD_RANK = {}
    for i = 1, #M.KEYPAD_ORDER do
        M.SAFE_ROOMS[M.KEYPAD_ORDER[i]] = "keypadsafe"
        M.KEYPAD_RANK[M.KEYPAD_ORDER[i]] = i
    end

    -- A BUILDING'S TRAITS, from its room names. A bedroom keeps a dial safe only in a big house:
    -- one kitchen (an apartment block or a flat over a shop has several), BIG_HOUSE_BEDROOMS
    -- bedrooms, over BIG_HOUSE_AREA tiles of footprint, and no school, clinic, hospital or church
    -- room. A footlocker in such a civic building becomes a crate: nobody kept military kit there.
    M.SAFE_BEDROOM = "bedroom"
    M.BIG_HOUSE_AREA = 150
    -- Two since 2026-11-19 (user review: safes found too late): a family house keeps a home safe.
    M.BIG_HOUSE_BEDROOMS = 2
    M.CIVIC_ROOMS = { "classroom", "school", "daycare", "hospital", "clinic", "medical", "church" }

    --- { area, kitchens, bedrooms, civic, built } of a building with these rooms ({ name = ... }),
    --- `area` tiles of footprint and surroundings `built` percent built on (nil when not known).
    --- Kitchens and bedrooms count every room whose name holds the word.
    function M.buildingProfile(rooms, area, built)
        local p = { area = tonumber(area) or 0, kitchens = 0, bedrooms = 0, civic = false,
            built = tonumber(built) }
        for i = 1, #rooms do
            local name = rooms[i].name
            if type(name) == "string" then
                if string.find(name, "kitchen", 1, true) ~= nil then p.kitchens = p.kitchens + 1 end
                if string.find(name, "bedroom", 1, true) ~= nil then p.bedrooms = p.bedrooms + 1 end
                for k = 1, #M.CIVIC_ROOMS do
                    if string.find(name, M.CIVIC_ROOMS[k], 1, true) ~= nil then p.civic = true end
                end
            end
        end
        return p
    end

    --- Is a building of this profile one big household?
    function M.isBigHouse(p)
        return type(p) == "table" and p.kitchens == 1 and p.bedrooms >= M.BIG_HOUSE_BEDROOMS
            and (tonumber(p.area) or 0) > M.BIG_HOUSE_AREA and not p.civic
    end

    --- Does this building hold a safe, at `pct` percent of buildings? Its own draw, so a building
    --- that hosts a stash is no likelier to host a safe. M.hash is affine in its characters, so
    --- two strings of one length differing only by a prefix draw a constant offset apart; hashing
    --- the decimal digits of a first hash breaks that, and the safe draw owes the stash's nothing.
    function M.hostsSafe(buildingKey, salt, pct)
        if type(pct) ~= "number" or pct <= 0 then return false end
        return M.unit("safe|" .. M.hash(tostring(buildingKey) .. "|" .. tostring(salt))) * 100 < pct
    end

    --- The safe kind a room of this name keeps in a building of profile `p` (buildingProfile), or nil.
    function M.safeKindFor(roomName, p)
        if type(roomName) ~= "string" then return nil end
        local kind = M.SAFE_ROOMS[roomName]
        if kind ~= nil then return kind end
        if roomName == M.SAFE_BEDROOM and M.isBigHouse(p) then return "dialsafe" end
        return nil
    end

    --- The rooms that can keep the building's safe, as { room, kind }, in the order they are
    --- tried, and whether it is a vault building: one with a keypad room keeps its safe in a
    --- keypad room alone, in KEYPAD_ORDER. Dial rooms, and rooms of one name, go by a stable draw
    --- on each room's key.
    function M.rankSafeRooms(rooms, p, salt)
        local all, vault = {}, false
        for i = 1, #rooms do
            local r = rooms[i]
            local kind = M.safeKindFor(r.name, p)
            if kind ~= nil then
                if kind == "keypadsafe" then vault = true end
                all[#all + 1] = { room = r, kind = kind, rank = M.KEYPAD_RANK[r.name] or 0,
                    key = M.unit("sr|" .. tostring(r.id) .. "|" .. tostring(salt)) }
            end
        end
        local out = {}
        for i = 1, #all do
            if not vault or all[i].kind == "keypadsafe" then out[#out + 1] = all[i] end
        end
        table.sort(out, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.key ~= b.key then return a.key < b.key end
            return tostring(a.room.id) < tostring(b.room.id)
        end)
        return out, vault
    end

    --- How many stashes a hosting building holds, from its footprint and the sandbox cap.
    function M.stashCountFor(area, cap)
        local n = 1 + math.floor((tonumber(area) or 0) / M.AREA_PER_EXTRA)
        return M.clamp(n, 1, math.max(1, tonumber(cap) or 1))
    end

    --- The rooms that can hide a stash, in the order they are tried: a weighted shuffle
    --- (Efraimidis-Spirakis, u ^ (1 / weight)), so an attic usually goes first without always
    --- going first. `rooms` is a list of { id = <stable key>, name = <room name>, ... }; the
    --- entries are returned as given.
    function M.rankRooms(rooms, salt)
        local out = {}
        for i = 1, #rooms do
            local r = rooms[i]
            local w = type(r.name) == "string" and M.STASH_ROOMS[r.name] or nil
            if w ~= nil and w > 0 then
                out[#out + 1] = { room = r, key = M.unit("r|" .. tostring(r.id) .. "|" .. tostring(salt)) ^ (1 / w) }
            end
        end
        table.sort(out, function(a, b)
            if a.key ~= b.key then return a.key > b.key end
            return tostring(a.room.id) < tostring(b.room.id)
        end)
        for i = 1, #out do out[i] = out[i].room end
        return out
    end

    -- A COUNTRY TRUNK (2026-11-19). Out where the buildings thin out (REMOTE_BUILT percent or less
    -- of the ground built on), the garage, shed, barn or farm storeroom keeps a footlocker of
    -- hunting and camping gear, not a crate: still the room's own kind, no draw.
    M.REMOTE_BUILT = 3
    M.COUNTRY_TRUNK_ROOMS = { garage = true, garagestorage = true, shed = true, barn = true, farmstorage = true }

    --- The gate kind of the box this room hides: ROOM_KINDS by its exact name, else DEFAULT_KIND;
    --- a country trunk room's in a remote building is a footlocker. A footlocker in a civic
    --- building (profile `p`, buildingProfile) is a crate.
    function M.kindFor(roomName, p)
        local kind = type(roomName) == "string" and M.ROOM_KINDS[roomName] or M.DEFAULT_KIND
        local profile = type(p) == "table" and p or nil
        if kind == M.DEFAULT_KIND and profile ~= nil and M.COUNTRY_TRUNK_ROOMS[roomName]
            and profile.built ~= nil and profile.built <= M.REMOTE_BUILT then
            kind = "footlocker"
        end
        if kind == "footlocker" and profile ~= nil and profile.civic then return "crate" end
        return kind
    end

    -- ---- the square ---------------------------------------------------------------------------------

    -- A room's squares, as Stash.lua reads them: cells["x,y"] = { room, clean, free, furn,
    -- blocksFront, wN, wW, rN, rW, oN, oW, winN, winW }, for the room and a one-square ring around
    -- it. The N and W edges belong to the square itself; its S edge is the N edge of the square
    -- below, its E edge the W edge of the square to the right, which is why the ring is there.
    --   room         the square is part of this room
    --   free         a survivor can stand on it
    --   clean        nothing on it but the floor and wall pieces: a box fits
    --   furn         it holds furniture or a container
    --   blocksFront  it holds a piece no box may open toward (furniture, a drum kit; never a bed)
    --   wN/wW  a solid wall on that edge, which a box backs onto
    --   rN/rW  a railing or see-through wall piece on that edge: it closes the edge, backs no box
    --   oN/oW  a door, doorway or window on that edge     winN/winW  that opening is a window
    local ORDER = { "N", "W", "S", "E" }
    local STEP = { N = { 0, -1 }, W = { -1, 0 }, S = { 0, 1 }, E = { 1, 0 } }

    local function at(cells, x, y) return cells[x .. "," .. y] end

    --- Is there a wall ("w"), a railing ("r"), an opening ("o") or a window ("win") on the `dir` edge of x,y?
    local function edge(cells, x, y, dir, what)
        local c
        if dir == "N" then c = at(cells, x, y); return c ~= nil and c[what .. "N"] == true end
        if dir == "W" then c = at(cells, x, y); return c ~= nil and c[what .. "W"] == true end
        if dir == "S" then c = at(cells, x, y + 1); return c ~= nil and c[what .. "N"] == true end
        c = at(cells, x + 1, y)
        return c ~= nil and c[what .. "W"] == true
    end

    local function hasEdge(cells, x, y, what)
        for i = 1, #ORDER do
            if edge(cells, x, y, ORDER[i], what) then return true end
        end
        return false
    end

    local function hasOpening(cells, x, y) return hasEdge(cells, x, y, "o") end

    --- Does nothing cross the `dir` edge of x,y: a wall or a railing?
    local function closed(cells, x, y, dir) return edge(cells, x, y, dir, "w") or edge(cells, x, y, dir, "r") end

    local function walkable(c) return c ~= nil and c.room == true and c.free == true end

    --- The room's squares that have a door, doorway or window on an edge.
    function M.openingsOf(cells)
        local out = {}
        for _, c in pairs(cells) do
            if c.room == true and hasOpening(cells, c.x, c.y) then out[#out + 1] = c end
        end
        return out
    end

    M.SPOT_FAR = 6

    -- A SNUG CLOSET (42.22.2: 5,402 closets, 87 % of them 2 tiles or fewer) has no square clear of
    -- its door, so it may hide its box on the square beside the door square, turned to face it.
    -- Never beside a window square: a box under a window is in plain sight.
    -- The squares on either side of the door's edge stay free: a door owns one edge of its own
    -- square, swings within it, and is blocked only by a solid object there (IsoDoor.isDoorObstructed).
    -- A 1-tile closet's one square is the door square, so it still hides none.
    M.SNUG_ROOM = "closet"
    M.SNUG_TILES = 4

    local OPPOSITE = { N = "S", S = "N", W = "E", E = "W" }

    --- How well x,y hides a box: a score, the walls a box there may back onto (the square it
    --- opens toward is clear: no wall, nothing that blocks a front) and, in a snug room, the side
    --- its own room's door square lies on; or nil and why not.
    function M.spotScore(cells, x, y, openings, snug)
        local c = at(cells, x, y)
        if c == nil or c.room ~= true or c.clean ~= true or c.free ~= true then return nil, "occupied" end
        if hasOpening(cells, x, y) then return nil, "opening" end
        local walls, shut, shutCount, reach = {}, {}, 0, 0
        for i = 1, #ORDER do
            local d = ORDER[i]
            if edge(cells, x, y, d, "w") then walls[#walls + 1] = d end
            if closed(cells, x, y, d) then
                shut[d] = true
                shutCount = shutCount + 1
            elseif walkable(at(cells, x + STEP[d][1], y + STEP[d][2])) then
                reach = reach + 1
            end
        end
        if #walls == 0 then return nil, "open floor" end
        if reach == 0 then return nil, "unreachable" end
        if shutCount == 2 and ((shut.N and shut.S) or (shut.W and shut.E)) then return nil, "passage" end
        local fronts = {}
        for i = 1, #walls do
            local f = OPPOSITE[walls[i]]
            local n = at(cells, x + STEP[f][1], y + STEP[f][2])
            if not shut[f] and not (n ~= nil and n.blocksFront == true) then fronts[#fronts + 1] = walls[i] end
        end
        if #fronts == 0 then return nil, "faces furniture" end
        local furniture, toward = 0, nil
        for i = 1, #ORDER do
            local d = ORDER[i]
            if not shut[d] then
                local nx, ny = x + STEP[d][1], y + STEP[d][2]
                local n = at(cells, nx, ny)
                -- Any square reached without crossing a wall, in this room or open into the next.
                if n ~= nil and hasOpening(cells, nx, ny) then
                    if not (snug and n.room == true and not hasEdge(cells, nx, ny, "win")) then return nil, "doorway" end
                    toward = d
                end
                if n ~= nil and n.faces ~= nil and n.faces[OPPOSITE[d]] then return nil, "in front of furniture" end
                if n ~= nil and n.room == true then
                    if n.furn == true then
                        local access = 0
                        for k = 1, #ORDER do
                            local e = ORDER[k]
                            local ax, ay = nx + STEP[e][1], ny + STEP[e][2]
                            if not (ax == x and ay == y) and not closed(cells, nx, ny, e)
                                and walkable(at(cells, ax, ay)) then
                                access = access + 1
                            end
                        end
                        if access == 0 then return nil, "blocks furniture" end
                        furniture = furniture + 1
                    end
                end
            end
        end
        local far = M.SPOT_FAR
        for i = 1, #openings do
            local o = openings[i]
            local d = math.max(math.abs(o.x - x), math.abs(o.y - y))
            if d < far then far = d end
        end
        return #walls * 4 + math.min(furniture, 2) * 2 + far, fronts, toward
    end

    --- The best hiding square of a room named `roomName`: { x, y, dir } with `dir` the wall the
    --- box goes against, one whose front is clear, or nil when no square qualifies, or when the room already holds a mod
    --- box (one box a room: a safe beside a lockbox reads as a stack). Ties go to a hash, so the
    --- pick is stable per world.
    function M.pickSpot(cells, salt, roomName)
        for _, c in pairs(cells) do
            if c.room == true and c.box == true then return nil end
        end
        local openings = M.openingsOf(cells)
        local snug = false
        if roomName == M.SNUG_ROOM then
            local tiles = 0
            for _, c in pairs(cells) do if c.room == true then tiles = tiles + 1 end end
            snug = tiles <= M.SNUG_TILES
        end
        local best, bestScore, bestTie, bestFronts, bestToward = nil, nil, nil, nil, nil
        for _, c in pairs(cells) do
            if c.room == true then
                local score, fronts, toward = M.spotScore(cells, c.x, c.y, openings, snug)
                if score ~= nil then
                    local tie = M.unit("s|" .. c.x .. "," .. c.y .. "|" .. tostring(salt))
                    if bestScore == nil or score > bestScore or (score == bestScore and tie < bestTie) then
                        best, bestScore, bestTie, bestFronts, bestToward = c, score, tie, fronts, toward
                    end
                end
            end
        end
        if best == nil then return nil end
        if bestToward ~= nil then
            for i = 1, #bestFronts do
                if bestFronts[i] == OPPOSITE[bestToward] then
                    return { x = best.x, y = best.y, dir = bestFronts[i], score = bestScore }
                end
            end
        end
        local k = 1 + math.floor(M.unit("d|" .. best.x .. "," .. best.y .. "|" .. tostring(salt)) * #bestFronts)
        return { x = best.x, y = best.y, dir = bestFronts[math.min(k, #bestFronts)], score = bestScore }
    end
end
