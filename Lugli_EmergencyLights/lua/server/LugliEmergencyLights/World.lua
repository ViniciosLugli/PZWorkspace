--[[
    World
    The one file that changes the world, and the one machine that runs it.
]]

-- Core FIRST, and named explicitly rather than relied upon. The engine loads every shared/ file
-- before any server/ one, so it would already be there; declaring it means this file cannot be
-- moved or reordered into a state where isWorldAuthority() is nil and the election silently throws.
require "LugliEmergencyLights/Core"
require "LugliEmergencyLights/Items"
require "LugliEmergencyLights/Time"
require "LugliEmergencyLights/Config"
require "LugliEmergencyLights/Pose"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- THE ELECTION, and the directory is NOT the guard.
--
-- server/ loads on a multiplayer CLIENT too: GameLoadingState.java:149 calls LoadDirBase("server")
-- unconditionally. What does not load on a dedicated server is client/, because GameServer.java:1458
-- passes onlyChecksum = true and LuaManager skips RunLua. So the work below cannot live in client/,
-- and putting it in server/ is not by itself enough.
--
-- isServer() cannot elect anybody -- it is false in single player, where this work still has to
-- happen, which is why electing on it was tried and reverted. isWorldAuthority() is not-isClient():
-- true on a dedicated server, on a co-op CHILD server, and in single player -- exactly one process
-- per world.
--
-- IT WRAPS THE REGISTRATIONS, and it is not written as an early `return`. A `do ... end` is a
-- BLOCK, not a function, so a `return` inside one at file scope ends the whole chunk -- which the
-- offline harness cats together with its own assertions, so an early return would silently carry
-- them off and the gate would pass having tested nothing at all.
--
-- The functions below are pure definitions and cost a client nothing. What must not happen on a
-- client is any of them being CALLED, and that is decided in exactly the two places below.
local AUTHORITY = LugliEmergencyLights.isWorldAuthority()

-- ---- World -------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "World"

    --- How many items may be stamped or swapped in one pass. The same guard the client sweep uses
    --- against walking into a room somebody filled with burning sticks.
    local MAX_ACTS_PER_PASS = 24

    --- And a ceiling on the walk itself. A circular pass at SweepRadius 10 is about 317
    --- getGridSquare calls per player per second; thirty players would be 9,500 a second on the
    --- server's main thread. Past this the pass stops, and the next one resumes where it stopped.
    ---
    --- IT IS CHECKED BETWEEN PLAYERS, NEVER INSIDE ONE, and the number is sized so that it can
    --- always admit at least one whole player: SweepRadius is capped at 32, which is about 3,200
    --- squares. Checking it inside the walk instead looked tighter and was a livelock -- at the
    --- maximum radius no player would ever be FINISHED, so `covered` stayed 0, the offset never
    --- advanced, and the first player was swept half-way over and over while nobody else ever was.
    local MAX_SQUARES_PER_PASS = 4096

    --- Where the round-robin left off, so a full server still covers everyone, just not all in one
    --- pass. Discovery does not depend on this: LoadChunk catches every square as it streams in.
    local resumeAt = 0

    --- Swap an expired ground item for its family's spent item.
    ---
    --- THIS ONLY WORKS HERE. IsoWorldInventoryObject.swapItem sends IsoObjectChange.SWAP_ITEM
    --- inside `if (GameServer.server)` and nowhere else, so the same call from a client is a purely
    --- local swap: the server never hears it, the save keeps the lit item, and every client redoes
    --- the swap on every chunk load, forever. On the authority it replicates and it persists.
    local function expire(square, worldObj, item, spentType)
        if square == nil or worldObj == nil or spentType == nil then return end

        -- instanceItem, NOT InventoryItemFactory.CreateItem.
        local okX, errX = pcall(function()
            local spent = instanceItem ~= nil and instanceItem(spentType) or nil
            -- swapItem throws if the incoming item already belongs to a world object, so a freshly
            -- instanced one (which has none) is the only safe thing to hand it.
            if spent ~= nil then
                worldObj:swapItem(spent)
            else
                -- THE FALLBACK REPAIRS ITSELF, because the overload it has to use is the broken one.
                square:transmitRemoveItemFromSquare(worldObj)
                local placed = square:AddWorldInventoryItem(spentType, 0.5, 0.5, 0.0)
                if placed ~= nil then pcall(function() placed:addToWorld() end) end
            end
        end)
        if not okX then
            M.defect(PART, "could not swap a burnt-out item: " .. tostring(errX))
        end
    end

    --- Stamp, pose and expire whatever is lying on one square. Returns the budget left.
    local function actOnSquare(square, budget)
        if budget <= 0 then return budget end
        local objs = square:getWorldObjects()
        if objs == nil then return budget end
        local n = objs:size()
        if n == 0 then return budget end

        -- COLLECTED FIRST, THEN ACTED ON: swapping while iterating the list skips entries.
        local dead, live = nil, nil
        for i = 0, n - 1 do
            local wo = objs:get(i)
            local item = wo ~= nil and wo:getItem() or nil
            local info = item ~= nil and M.litInfo(item) or nil
            if info ~= nil then
                if M.isExpired(item) then
                    dead = dead or {}
                    dead[#dead + 1] = { wo = wo, item = item }
                elseif live == nil then
                    live = { item = item, info = info, wo = wo }
                end
            end
        end
        if dead == nil and live == nil then return budget end

        if live ~= nil then
            local item, info = live.item, live.info

            -- ON THE GROUND, LIT, AND NEVER STAMPED: loot spawned it, an admin gave it, or another
            -- mod made it. It gets its burn time here and nowhere else.
            --
            -- The burn hours ARE the second argument, and their absence was the bug: markCracked
            -- refuses a non-numeric burn time, so the one-argument form this replaces could never
            -- stamp anything and every such item burned forever.
            if M.fractionLeft(item) == nil then
                local stamped = false
                pcall(function()
                    stamped = M.markCracked(item, M.burnHours(info.family))
                end)
                if stamped then
                    budget = budget - 1
                    M.debug(PART, "stamped an unstamped lit item at "
                                .. tostring(square:getX()) .. "," .. tostring(square:getY())
                                .. "," .. tostring(square:getZ()))
                end
            end

            -- HOW IT LIES. Here rather than on each client because poseIfUnposed rolls a RANDOM
            -- heading and then calls syncExtendedPlacement, which is a real packet: two clients
            -- seeing the same unposed item rolled two different headings and fought over the wire.
            if M.poseIfUnposed ~= nil then
                pcall(M.poseIfUnposed, item, live.wo, info.family)
            end
        end

        if dead ~= nil then
            for i = 1, #dead do
                if budget <= 0 then break end
                budget = budget - 1
                expire(square, dead[i].wo, dead[i].item, M.SPENT_OF[dead[i].item:getFullType()])
            end
        end
        return budget
    end

    -- ---- DISCOVERY IS CHUNK-DRIVEN ---------------------------------------------------------------
    -- IsoChunk fires LoadChunk unconditionally, with no GameServer gate, so it reaches this process
    -- as chunks stream in around each connected player. The radial pass below is maintenance only.
    local function sweepChunk(chunk, budget)
        if chunk == nil then return budget end

        local okLo, lo = pcall(function() return chunk:getMinLevel() end)
        local okHi, hi = pcall(function() return chunk:getMaxLevel() end)
        if not okLo or not okHi or type(lo) ~= "number" or type(hi) ~= "number" then return budget end

        for z = lo, hi do
            for x = 0, 7 do
                for y = 0, 7 do
                    local okSq, sq = pcall(function() return chunk:getGridSquare(x, y, z) end)
                    if okSq and sq ~= nil then
                        -- Caught per square: one bad tile must not take the whole handler with it.
                        local ok, res = pcall(actOnSquare, sq, budget)
                        if ok then budget = res end
                    end
                end
            end
        end
        return budget
    end

    local ready = false

    --- ONE SQUARE, ON DEMAND, for a process that is already walking the world for its own reasons.
    ---
    --- In SINGLE PLAYER this file and the client sweep are the same process, and they were walking
    --- the same squares twice a second each: two getGridSquare and two getWorldObjects per tile per
    --- pass, two 8x8xZ walks per streaming chunk, and the whole loaded chunk map twice at
    --- OnGameStart. So in single player the authority does not walk at all -- the client sweep calls
    --- this as it goes, which also means an item is POSED BEFORE the light record reads its
    --- rotation, in the same visit, rather than a pass later.
    ---
    --- Unbudgeted across squares on purpose: the caller's own walk is what bounds this, and the work
    --- per item is two ModData writes, three rotation setters, or one swap.
    ---
    --- PUBLISHED ONLY ON THE AUTHORITY, below, and that is the whole safety property. This global
    --- existing on a multiplayer client would hand every connected machine the stamping, posing and
    --- swapping back -- through the client sweep, which is exactly the code path this change exists
    --- to take it out of. Light.lua tests for it by name and does nothing when it is absent.
    local function actOnSquarePublic(square)
        if not ready or square == nil then return end
        actOnSquare(square, MAX_ACTS_PER_PASS)
    end

    --- Does this process have to find its own squares? Only where there is no client sweep to ride:
    --- a dedicated server, or a co-op child server. Read live rather than latched, because the
    --- answer decides work rather than registration and a runtime read is one a test can drive.
    local function walksAlone()
        return M.isMultiplayer()
    end

    local function onLoadChunk(chunk)
        if not ready or not walksAlone() then return end
        sweepChunk(chunk, MAX_ACTS_PER_PASS)
    end

    --- Everything already loaded when the world came up. SINGLE PLAYER ONLY in practice, and that
    --- is correct: forEachLocalPlayer yields nothing on a dedicated server, which has no window open
    --- until somebody joins -- and when they do, LoadChunk covers it.
    local function sweepLoadedWorld()
        if not walksAlone() or getWorld == nil then return end
        local okCell, cell = pcall(function() return getWorld():getCell() end)
        if not okCell or cell == nil then return end

        M.forEachLocalPlayer(function(player, idx)
            local okMap, map = pcall(function() return cell:getChunkMap(idx) end)
            if not okMap or map == nil then return end
            local okW, wide = pcall(function() return map:getWidthInTiles() end)
            if not okW or type(wide) ~= "number" then return end

            local chunks = math.floor(wide / 8)
            for cx = 0, chunks - 1 do
                for cy = 0, chunks - 1 do
                    local okC, chunk = pcall(function() return map:getChunk(cx, cy) end)
                    if okC and chunk ~= nil then sweepChunk(chunk, MAX_ACTS_PER_PASS) end
                end
            end
        end)
    end

    -- ---- THE INVENTORY SWAP, which only the authority may make --------------------------------
    --
    -- A multiplayer client cannot create an inventory item. ItemContainer.AddItem and Remove
    -- have no network effect from a client (ItemContainer.java:467, :2019), the server keeps its
    -- own copy of every player's inventory, and the two only agree through what the SERVER sends:
    -- sendAddItemToContainer and sendRemoveItemFromContainer are `if (GameServer.server)` globals
    -- (LuaManager.java:10158, :10186) and sendEquip likewise (:3888). EquipPacket.processServer
    -- resolves the equipped item's id against the server's copy (EquipPacket.java:171-186), so a
    -- client-minted item equips as NOTHING for every other player. Vanilla mints on the server
    -- for exactly this reason (server/ClientCommands.lua:186-198), and so does this.
    --
    -- One function for both swaps this mod makes, cracking and burning out, and for both worlds:
    -- on a server the send globals carry each step to the owner and the equip to everybody; in
    -- single player they are no-ops and this process is the authority anyway.

    --- Where an item hangs on the character's model, or nil: the attachment location string the
    --- character indexes its attached items by, which the owner's client uses to put the
    --- replacement back in the same hotbar slot.
    function M.attachedLocationOf(player, item)
        local location = nil
        pcall(function()
            local attached = player:getAttachedItems()
            if attached ~= nil then location = attached:getLocation(item) end
        end)
        if location == "" then location = nil end
        return location
    end

    --- Take an item off the character's model and out of their hands, on the authority. Returns
    --- which hand it was in (primary, secondary) and the attachment location it hung at, or nil.
    ---
    --- EVERY REMOVAL FROM AN INVENTORY HAS TO DO THIS, and that is why it is its own function
    --- rather than four lines inside the swap. `ItemContainer.Remove` clears the hand itself
    --- (ItemContainer.java:2020-2022), but `DoRemoveItem` -- which is what the drop uses, because
    --- it is the unsynchronised half of the pair -- does NOT (`:2057-2080`). An item left in the
    --- server's copy of a hand is relayed to every other client by EquipPacket.write
    --- (EquipPacket.java:51-83), so the thrower goes on holding, on everybody else's screen, a
    --- stick that is lying on the ground.
    ---
    --- Exactly as Transaction.updateItem does before it removes a transferred item
    --- (Transaction.java:290-296), or the character keeps a reference to something no container
    --- owns.
    function M.takeOffModel(player, item)
        if player == nil or item == nil then return false, false, nil end

        local location = M.attachedLocationOf(player, item)
        local wasPrimary, wasSecondary = false, false
        pcall(function()
            wasPrimary = player:isPrimaryHandItem(item)
            wasSecondary = player:isSecondaryHandItem(item)
        end)

        pcall(function()
            if location ~= nil then player:removeAttachedItem(item) end
            if wasPrimary or wasSecondary then player:removeFromHands(item) end
        end)
        return wasPrimary, wasSecondary, location
    end

    --- Replace `item` in the player's inventory with a fresh `newType`, keeping its container and
    --- its hand, and stamp the new one with `burnHours` when given. Returns the new item and the
    --- attachment location the old one hung at (nil for none), or nil and a reason.
    function M.authoritySwap(player, item, newType, burnHours)
        if player == nil or item == nil or type(newType) ~= "string" then
            return nil, "nothing to swap"
        end
        local holder = nil
        pcall(function() holder = item:getContainer() end)
        if holder == nil then return nil, "the item is in no container" end

        local wasPrimary, wasSecondary, location = M.takeOffModel(player, item)

        -- REMOVE, THEN ADD, each told to the owner. ItemContainer.Remove is the ordinary call:
        -- it drops the hand reference itself and flags the container for the hot save.
        local okRemove = pcall(function()
            holder:Remove(item)
            if sendRemoveItemFromContainer ~= nil then sendRemoveItemFromContainer(holder, item) end
        end)
        if not okRemove then return nil, "could not take the old one out" end

        local fresh = nil
        local okAdd = pcall(function() fresh = holder:AddItem(newType) end)
        if not okAdd or fresh == nil then
            -- The old one is gone and the new one never came. Put the old one back rather than
            -- have the swap destroy an item.
            pcall(function()
                holder:AddItem(item)
                if sendAddItemToContainer ~= nil then sendAddItemToContainer(holder, item) end
            end)
            return nil, "could not create " .. tostring(newType)
        end

        -- STAMPED BEFORE IT IS SENT: the add packet carries ModData, anything written after it
        -- has missed the wire.
        if type(burnHours) == "number" then M.markCracked(fresh, burnHours) end
        pcall(function()
            if sendAddItemToContainer ~= nil then sendAddItemToContainer(holder, fresh) end
        end)

        -- BACK INTO THE HAND IT WAS IN, and told to everybody: sendEquip is the server-side
        -- updateHandEquips, which is what puts the lit stick in every other player's view.
        pcall(function()
            if wasPrimary then player:setPrimaryHandItem(fresh)
            elseif wasSecondary then player:setSecondaryHandItem(fresh) end
            if (wasPrimary or wasSecondary) and sendEquip ~= nil then sendEquip(player) end
        end)
        return fresh, location
    end

    --- Items a client has told the server are in the air: item id -> the moment the flight is
    --- surely over. A burn-out swap on an item mid-flight would race the landing.
    local inFlight = {}
    local inFlightN = 0

    function M.markFlightOnAuthority(itemId, untilMs)
        if type(itemId) ~= "number" then return end
        if inFlight[itemId] == nil then inFlightN = inFlightN + 1 end
        inFlight[itemId] = untilMs
    end

    local function flying(item, nowMs)
        if inFlightN > 0 then
            local ok, id = pcall(function() return item:getID() end)
            if ok and inFlight[id] ~= nil then
                if nowMs < inFlight[id] then return true end
                inFlight[id] = nil
                inFlightN = inFlightN - 1
            end
        end
        -- Single player: the client's own flag, in this same process.
        return M.isInFlight ~= nil and M.isInFlight(item) == true
    end

    --- One player's bags, to the same depth the client's tooltip sweep uses. Every burnt-out
    --- item is swapped for its spent form and the owner is told which slot it hung in.
    --- Returns the budget left.
    local function sweepInventory(player, budget)
        if budget <= 0 then return budget end
        local nowMs = getTimestampMs ~= nil and getTimestampMs() or 0
        local dead = {}

        local function walk(container, depth)
            if container == nil or depth > 3 then return end
            local items = container:getItems()
            if items == nil then return end
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item ~= nil then
                    if M.litInfo(item) ~= nil and M.isExpired(item) and not flying(item, nowMs) then
                        dead[#dead + 1] = item
                    elseif item:IsInventoryContainer() then
                        local inner = item:getInventory()
                        if inner ~= nil and inner ~= container then walk(inner, depth + 1) end
                    end
                end
            end
        end
        pcall(function() walk(player:getInventory(), 0) end)

        for i = 1, #dead do
            if budget <= 0 then break end
            local item = dead[i]
            local spentType = M.SPENT_OF[item:getFullType()]
            if spentType ~= nil then
                local oldId = nil
                pcall(function() oldId = item:getID() end)
                local fresh, location = M.authoritySwap(player, item, spentType)
                budget = budget - 1
                if fresh == nil then
                    M.defect(PART, "burn-out swap refused: " .. tostring(location))
                elseif sendServerCommand ~= nil and M.isMultiplayer() then
                    local newId = nil
                    pcall(function() newId = fresh:getID() end)
                    sendServerCommand(player, M.NET_MODULE, M.NET_EXPIRE_ECHO,
                                      { oldId = oldId, newId = newId, location = location })
                end
            end
        end
        return budget
    end

    --- MAINTENANCE, not discovery: an item already found still has to burn down and be swapped.
    local function pass()
        if not ready or not walksAlone() or getCell == nil then return end
        local cell = getCell()
        if cell == nil then return end

        local radius = M.cfg("SweepRadius")
        if type(radius) ~= "number" or radius < 1 then radius = 10 end
        if radius > 32 then radius = 32 end

        local budget = MAX_ACTS_PER_PASS
        local squares = 0

        -- Collected first, because the round-robin needs to know how many there are.
        local players = {}
        M.forEachWorldPlayer(function(player) players[#players + 1] = player end)
        local total = #players
        if total == 0 then return end
        if resumeAt >= total then resumeAt = 0 end

        -- THE OFFSET IS READ ONCE AND WRITTEN ONCE, and both halves of that matter.
        --
        -- Advancing it inside the loop compounds: each step then offsets from the step before, so
        -- with two players online the walk was 1, 1 and player two was never swept at all -- their
        -- burnt-out flares stayed lit forever, and only chunk stream-in ever caught them. With
        -- three it was 1, 3, 3. `covered` also has to count players FINISHED rather than players
        -- started, or the square budget below drops whoever it interrupted and the next pass
        -- resumes past them.
        local start = resumeAt
        local covered = 0

        for step = 0, total - 1 do
            if squares >= MAX_SQUARES_PER_PASS then break end
            local who = players[((start + step) % total) + 1]

            -- WHAT THEY ARE CARRYING burns down too, and on a server only this process may swap it.
            budget = sweepInventory(who, budget)

            local px = math.floor(who:getX())
            local py = math.floor(who:getY())
            local pz = math.floor(who:getZ())
            local r2 = radius * radius
            for dy = -radius, radius do
                local room = r2 - dy * dy
                for dx = -radius, radius do
                    if dx * dx <= room then
                        squares = squares + 1
                        local sq = cell:getGridSquare(px + dx, py + dy, pz)
                        if sq ~= nil then
                            local okSq, res = pcall(actOnSquare, sq, budget)
                            if okSq then
                                budget = res
                            else
                                M.defect(PART, "square skipped after: " .. tostring(res))
                            end
                        end
                    end
                end
            end
            covered = step + 1
        end

        resumeAt = (start + covered) % total
    end

    --- The world is up and this process may start acting on it.
    ---
    --- BOTH EVENTS, because neither one covers both worlds this file runs in. **OnGameStart never
    --- fires on a dedicated server** -- it is the client's world-entry event -- and OnServerStarted
    --- never fires in single player. Registering only OnGameStart left `ready` false on a real
    --- server, so the authority silently did nothing at all: no stamping, no posing, nothing ever
    --- burned out, and the only symptom was a log line that was not there. Server.lua has always
    --- registered both for exactly this reason; this file did not, and tools/servertest.sh is what
    --- found it. Idempotent, so whichever arrives first wins.
    local started = false
    local function onWorldUp()
        if started then return end
        started = true
        M.resetConfig()
        ready = true
        -- A NEW WORLD STARTS A NEW CLOCK. worldHours clamps to the highest value it has seen, so a
        -- mark carried over from the last world would freeze every burn time in this one.
        if M.resetWorldClock ~= nil then M.resetWorldClock() end
        sweepLoadedWorld()
        -- THE BUILD STAMP, because servertest has served a three-day-old copy before and a log line
        -- that does not say which build printed it proves nothing.
        M.log(PART, M.envName() .. " owns ground items: stamping, posing and burn-out"
                  .. "  [build " .. tostring(M.BUILD or "unstamped") .. "]")
    end

    if AUTHORITY then
        M.worldActOnSquare = actOnSquarePublic

        M.addHandler(PART, "LoadChunk", onLoadChunk)

        local h = M.addHandler(PART, "OnGameStart", onWorldUp)
        local g = M.addHandler(PART, "OnServerStarted", onWorldUp)

        M.addTicker(PART, M.scanInterval, pass)

        if h ~= nil or g ~= nil then
            M.status(PART, nil, "owns ground items when a world loads", "pending")
        end
    end
end

-- ---- Relay -------------------------------------------------------------------------------------
-- A fired flare is the one thing in this mod that no other player can derive from replicated state:
-- it leaves no item behind and the aim point exists only on the shooter's machine. So it is the one
-- thing that needs the wire.
do
    local M = LugliEmergencyLights
    local PART = "Relay"

    --- One flare per player per this many milliseconds. The gun's own reload is slower, so this
    --- costs a legitimate player nothing and bounds what a modified client can paint on everyone
    --- else's screen.
    local MIN_GAP_MS = 2000

    --- username -> the moment they may fire again. PRUNED, because a dedicated server runs for
    --- weeks and this file registers no teardown: without it the table keeps one entry per distinct
    --- name that ever connected, for the life of the process.
    local lastAt = {}
    local lastN = 0

    --- The same shape for drops, on its own budget: a throw is a different act from a flare and
    --- rate-limiting them together would make one starve the other.
    local MIN_DROP_GAP_MS = 250
    local dropAt = {}
    local dropN = 0

    --- Above this many remembered names, drop the ones whose window has long since passed.
    local PRUNE_AT = 64

    local function pruneDrops(now)
        if dropN < PRUNE_AT then return end
        local stale = {}
        for who, at in pairs(dropAt) do
            if now > at + MIN_DROP_GAP_MS then stale[#stale + 1] = who end
        end
        for i = 1, #stale do
            dropAt[stale[i]] = nil
            dropN = dropN - 1
        end
    end

    local function prune(now)
        if lastN < PRUNE_AT then return end
        local stale = {}
        for who, at in pairs(lastAt) do
            if now > at + MIN_GAP_MS then stale[#stale + 1] = who end
        end
        for i = 1, #stale do
            lastAt[stale[i]] = nil
            lastN = lastN - 1
        end
    end

    local function finite(v)
        return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
    end

    local function clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    --- The longest id this will carry. The id exists so the shooter can drop its own echo, and
    --- "name-timestamp-tile" is comfortably inside this.
    ---
    --- BOUNDED BECAUSE IT IS REBROADCAST. Whatever arrives here goes back out to every connection,
    --- so an unbounded string is an amplifier: a modified client sending 32 KB every two seconds
    --- makes the server ship 32 KB to every player. Worse, GameWindow$StringUTF writes the length
    --- as a SHORT, so past 32,767 bytes it wraps negative and the receiver stops consuming the
    --- payload -- which desynchronises the rest of that packet's parse, on every client at once.
    local MAX_ID = 64

    local function shortString(v, limit)
        if type(v) ~= "string" then return "" end
        if #v > limit then return string.sub(v, 1, limit) end
        return v
    end

    --- Rebuild the payload from what the SERVER believes, not from what arrived.
    ---
    --- Everything a client sends is a suggestion. The coordinates are checked against the shooter's
    --- own server-side position, and every duration and radius is re-read from the server's sandbox
    --- rather than trusted, because a sandbox option that a client can talk the server out of is not
    --- a setting. A relay that forwards its input is a griefing surface.
    local function sanitise(player, args)
        if type(args) ~= "table" or player == nil then return nil end
        if not finite(args.x) or not finite(args.y) or not finite(args.z) then return nil end
        if not finite(args.mx) or not finite(args.my) or not finite(args.mz) then return nil end
        if not finite(args.secs) or not finite(args.travel) or not finite(args.apex) then return nil end

        local okP, px, py, pz = pcall(function()
            return player:getX(), player:getY(), player:getZ()
        end)
        if not okP or not finite(px) then return nil end

        -- The muzzle is on the shooter. Anything else is somebody else's gun.
        local mdx, mdy = args.mx - px, args.my - py
        if mdx * mdx + mdy * mdy > 4.0 then return nil end
        if math.abs(args.mz - pz) > 1.5 then return nil end

        -- And the aim point is within the range the SERVER allows, plus slack for the wind lean.
        local reach = M.cfg("AerialShotRange")
        if not finite(reach) or reach <= 0 then reach = 30 end
        reach = reach + 8.0
        local dx, dy = args.x - px, args.y - py
        if dx * dx + dy * dy > reach * reach then return nil end
        if math.abs(args.z - pz) > 1.5 then return nil end

        return {
            id     = shortString(args.id, MAX_ID),
            who    = "",
            x      = args.x,  y  = args.y,  z  = math.floor(args.z),
            mx     = args.mx, my = args.my, mz = args.mz,
            -- The SERVER's numbers, whatever arrived.
            secs   = M.positive("AerialSeconds", 300),
            range  = clamp(M.cfg("AerialRange") or 150, 10, 400),
            radius = clamp(M.cfg("AerialLightRadius") or 20, 4, 20),
            -- Shape only, and bounded: these come from the cartridge record, which every client has.
            travel = clamp(args.travel, 0.05, 20.0),
            apex   = clamp(args.apex, 0.1, 40.0),
            r      = clamp(finite(args.r) and args.r or 1.0, 0.0, 1.0),
            g      = clamp(finite(args.g) and args.g or 0.3, 0.0, 1.0),
            b      = clamp(finite(args.b) and args.b or 0.2, 0.0, 1.0),
        }
    end

    --- The flare gun in the sender's primary hand, on the SERVER's copy of them, or nil.
    ---
    --- THEY HAVE TO BE HOLDING THE GUN. Without this the geometry is the only brake, and a
    --- modified client can fire a flare every MIN_GAP_MS with no gun and no cartridge -- each echo
    --- costing every receiving client a projectile, one of its 128 ground light slots and a looping
    --- emitter. A handful of accounts doing that holds the whole pool and no real light on the map
    --- can be lit.
    local function heldGun(player)
        local gun = nil
        pcall(function()
            local held = player:getPrimaryHandItem()
            if held ~= nil and held:getFullType() == M.GUN.item then gun = held end
        end)
        return gun
    end

    --- Spend the cartridge on the server's copy of the gun. True when a round was there to spend.
    ---
    --- THE ENGINE DOES NOT DO THIS FOR US, and that was the "one shell fires forever" report.
    --- Vanilla spends ammo in ISReloadWeaponAction.onShoot, hooked on OnWeaponSwingHitPoint, and
    --- only where `not isClient()`: a multiplayer client leaves it to the server. The server raises
    --- OnWeaponSwingHitPoint from the attack packet only for an AIMED firearm
    --- (network/fields/hit/Player.java:141-150), and the flare gun is deliberately not one, so
    --- nothing on the server ever ran onShoot for it and the count stayed at 1.
    ---
    --- So the relay, which is the one server-side thing that hears about every shot, runs the same
    --- vanilla function the server would have run: it decrements, records the spent round, and
    --- sends SyncHandWeaponFields back to the shooter. Single player never reaches this file's
    --- handler and spends the round client-side as vanilla does.
    local function spendRound(player, gun)
        local ammo = 0
        pcall(function() ammo = gun:getCurrentAmmoCount() end)
        if type(ammo) ~= "number" or ammo <= 0 then return false end

        local shoot = ISReloadWeaponAction ~= nil and ISReloadWeaponAction.onShoot or nil
        if type(shoot) ~= "function" then
            M.defect(PART, "ISReloadWeaponAction.onShoot is not on this build; cartridges are not spent")
            return true
        end
        local ok, err = pcall(shoot, player, gun)
        if not ok then M.defect(PART, "could not spend a cartridge: " .. tostring(err)) end
        return true
    end

    --- Is this a type this mod actually ships? THE most important check in the file: without it a
    --- modified client names any item in the game and the server spawns it, on the ground, for
    --- everybody. A drop may only ever put back something Emergency Lights owns.
    local function ourItem(fullType)
        if type(fullType) ~= "string" then return nil end
        local lit = M.LIT ~= nil and M.LIT[fullType] or nil
        if lit ~= nil then return lit end
        -- A sealed or spent one has no burn record but is still ours.
        if M.LIT_OF ~= nil and M.LIT_OF[fullType] ~= nil then return false end
        if M.SPENT ~= nil and M.SPENT[fullType] ~= nil then return false end
        if M.CARTRIDGES ~= nil and M.CARTRIDGES[fullType] ~= nil then return false end
        if M.GUN ~= nil and M.GUN.item == fullType then return false end
        return nil
    end

    --- Tell the thrower we are not taking this one, so it can hand the item straight back.
    ---
    --- A REFUSAL IS SENT, NOT WITHHELD, and it is sent to THAT PLAYER. Silence makes the client wait
    --- out its whole deadline and then latch the route off, so every negative answer here has to be
    --- an answer -- including the rate limit, which is the commonest one of all. Targeted rather
    --- than broadcast because an echo carries a drop id: broadcasting one lets any client act on
    --- another player's id, and a client that guessed a victim's id could make the victim's machine
    --- discard an item it is holding.
    local function refuse(player, args, why)
        M.debug(PART, "refused a drop: " .. tostring(why))
        if type(args) == "table" and args.id ~= nil and player ~= nil then
            sendServerCommand(player, M.NET_MODULE, M.NET_DROP_ECHO,
                              { id = shortString(args.id, MAX_ID), ok = false })
        end
    end

    --- Find one of this type in the sender's own inventory, and say which container holds it.
    --- Walks bags, because a thrown item may well have come out of one.
    local function findCarried(player, fullType, itemId)
        local found, holder = nil, nil

        local function walk(container, depth)
            if container == nil or depth > 3 or found ~= nil then return end
            local items = container:getItems()
            if items == nil then return end
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it ~= nil then
                    if it:getFullType() == fullType then
                        -- EXACT INSTANCE FIRST. Two identical sticks can carry different burn
                        -- times, so taking whichever one turned up would land the wrong one and
                        -- leave the player holding the one they just threw.
                        if itemId ~= nil and it:getID() == itemId then
                            found, holder = it, container
                            return
                        end
                        if found == nil then found, holder = it, container end
                    end
                    if it:IsInventoryContainer() then
                        local inner = it:getInventory()
                        if inner ~= nil and inner ~= container then walk(inner, depth + 1) end
                    end
                end
            end
        end

        pcall(function() walk(player:getInventory(), 1) end)
        return found, holder
    end

    --- The longest throw this mod can make, in tiles, plus slack for the walk during the flight.
    local function maxThrow()
        local best = 0.0
        if M.FAMILIES ~= nil then
            for _, fam in pairs(M.FAMILIES) do
                if type(fam.throwRange) == "number" and fam.throwRange > best then
                    best = fam.throwRange
                end
            end
        end
        if best <= 0.0 then best = 20.0 end
        local mult = M.cfg ~= nil and M.cfg("ThrowRangeMult") or 1.0
        if not finite(mult) or mult <= 0 then mult = 1.0 end
        -- DERIVED, NOT GUESSED. A hardcoded 12 was under the glow stick's own 18.2 tile range, so
        -- every full-length throw of the mod's furthest-throwing item was refused.
        return best * mult + 6.0
    end

    --- Put an item on the ground on behalf of a client, and tell everybody.
    ---
    --- IT PLACES THE SENDER'S OWN ITEM, taken out of the sender's own inventory HERE. That is not a
    --- nicety, it is the whole correctness of the feature:
    ---
    --- * `ItemContainer.Remove` on a client has no network effect whatsoever, so the copy this
    ---   process holds of that player still has the item. Creating a NEW item from the type string
    ---   and leaving that one alone is an item printer: throw, relog, and it is on the ground AND
    ---   back in the bag. Removing it here, where `sendRemoveItemFromContainer` actually reaches the
    ---   client, is the only way the two ever agree.
    --- * it is also the entitlement check. A whitelist stops a modified client naming somebody
    ---   else's item; only looking for the thing in their inventory stops them conjuring one of ours.
    --- * and it keeps the item. A string-built replacement loses the condition, the burn stamp, the
    ---   tint and any other mod's ModData; the real one carries all of it over the wire, because
    ---   `InventoryItem.save` writes ModData and the world rotations unconditionally.
    ---
    --- ORDER MATTERS: the stamp and the pose go on BEFORE the add, because
    --- `AddWorldInventoryItem` transmits the finished object from inside itself. Anything written
    --- afterwards has already missed the packet.
    local function onDrop(player, args)
        if type(args) ~= "table" or player == nil then return end
        if not finite(args.x) or not finite(args.y) or not finite(args.z) then
            return refuse(player, args, "a coordinate was not a finite number")
        end

        local burnRec = ourItem(args.type)
        if burnRec == nil then
            return refuse(player, args, "type " .. tostring(args.type) .. " is not this mod's")
        end

        local okP, px, py, pz = pcall(function()
            return player:getX(), player:getY(), player:getZ()
        end)
        if not okP or not finite(px) then
            return refuse(player, args, "the sender has no position")
        end

        local reach = maxThrow()
        local dx, dy = args.x - px, args.y - py
        if dx * dx + dy * dy > reach * reach then
            return refuse(player, args, "too far from the thrower")
        end
        if math.abs(args.z - pz) > 1.5 then
            return refuse(player, args, "a different floor")
        end

        local sq = nil
        pcall(function() sq = getCell():getGridSquare(args.x, args.y, args.z) end)
        if sq == nil then
            return refuse(player, args, "that square is not loaded here")
        end

        -- THEIRS TO THROW, or it does not happen.
        local itemId = finite(args.itemId) and math.floor(args.itemId) or nil
        local item, holder = findCarried(player, args.type, itemId)
        if item == nil then
            return refuse(player, args, "the sender is not carrying one")
        end

        local ox = finite(args.ox) and clamp(args.ox, 0.02, 0.98) or 0.5
        local oy = finite(args.oy) and clamp(args.oy, 0.02, 0.98) or 0.5

        -- OUT OF THE HANDS AND OFF THE BELT FIRST, because DoRemoveItem below does neither.
        -- Without this the server's copy of the thrower goes on holding an item that is now lying
        -- on the ground, and EquipPacket relays that hand to every other client: the thrown stick
        -- stays visible in their hand for everybody except themselves. See M.takeOffModel.
        local wasPrimary, wasSecondary = M.takeOffModel(player, item)
        local wasHeld = wasPrimary or wasSecondary

        -- AND THE EMPTY HAND IS TOLD TO EVERYBODY, on the same step that empties it. sendEquip is
        -- the server-side updateHandEquips, the same call authoritySwap makes for a crack.
        --
        -- ANNOUNCED HERE RATHER THAN AFTER THE LANDING, because from this line on the hand is
        -- empty whatever happens next, and every one of those outcomes is a hand the thrower has
        -- already emptied on their own machine: the item reaches the ground, or the engine refuses
        -- it and it goes back to their bag, or the removal below fails and the throw is refused.
        -- Announcing only on the way to a successful landing would leave the two refusal paths
        -- with an empty hand on the server that nobody else had been told about.
        if wasHeld and sendEquip ~= nil then
            pcall(function() sendEquip(player) end)
            M.debug(PART, "took " .. tostring(args.type) .. " out of the thrower's hand "
                        .. "and told everybody")
        end

        -- OUT OF THE INVENTORY, ON THE AUTHORITY, and told to the client. DoRemoveItem is the
        -- unsynchronised removal; sendRemoveItemFromContainer is what carries it, and it is safe
        -- here because it is the SERVER sending. The same call from a client is the one that kicks.
        local okRemove = pcall(function()
            if holder ~= nil then
                holder:DoRemoveItem(item)
                if sendRemoveItemFromContainer ~= nil then
                    sendRemoveItemFromContainer(holder, item)
                end
            end
        end)
        if not okRemove then
            return refuse(player, args, "could not take it out of their inventory")
        end

        -- STAMPED AND POSED BEFORE THE ADD.
        pcall(function()
            -- The item already carries its own burn stamp, written when it was cracked against this
            -- same world clock. It is re-bounded rather than rewritten: a stamp longer than the
            -- family's own burn time did not come from this mod.
            if burnRec ~= false then
                local md = item:getModData()
                local burn = M.burnHours(burnRec.family)
                local now = M.worldHours() or 0
                local expires = md[M.KEY_EXPIRES]
                if type(expires) ~= "number" or expires > now + burn then
                    expires = now + burn
                end
                if expires < now then expires = now end
                md[M.KEY_BURN] = burn
                md[M.KEY_EXPIRES] = expires
            end

            -- HOW IT LANDED. Only the thrower knew, so it is carried rather than recomputed, and
            -- bounded because it reaches a rotation the engine replicates. Applied to the ITEM with
            -- no world object yet: the rotations ride out on the same packet as the object.
            if M.applyPose ~= nil and finite(args.pitch) and finite(args.yaw) then
                M.applyPose(item, nil, clamp(args.pitch, 0.0, 360.0), clamp(args.yaw, 0.0, 360.0))
            end
        end)

        local placed = nil
        local okAdd, err = pcall(function()
            -- The InventoryItem overload, and it has to be that one: it calls addToWorld itself and
            -- transmits the finished object, ModData and rotations included. The String overload
            -- builds a fresh item and would throw all of that away.
            placed = sq:AddWorldInventoryItem(item, ox, oy, 0.0, true)
        end)
        if not okAdd or placed == nil then
            M.defect(PART, "could not land a client's item: " .. tostring(err))
            -- It came out of their inventory and did not reach the ground. Put it back, or the
            -- throw has destroyed it.
            pcall(function()
                if holder ~= nil then
                    holder:AddItem(item)
                    if sendAddItemToContainer ~= nil then
                        sendAddItemToContainer(holder, item)
                    end
                end
            end)
            return refuse(player, args, "the engine would not take it")
        end

        pcall(function()
            local wo = placed:getWorldItem()
            if wo ~= nil then wo:setIgnoreRemoveSandbox(true) end
        end)

        -- The object itself is already on its way to every client in range, sent from inside
        -- AddWorldInventoryItem. This only tells the THROWER that its held copy can go.
        sendServerCommand(player, M.NET_MODULE, M.NET_DROP_ECHO,
                          { id = shortString(args.id, MAX_ID), ok = true })

        -- ---- AND THE THROW IS OVER, TOLD TO EVERYBODY ------------------------------------------
        --
        -- The world object replicates, but WHEN and WHERE the flight ended does not, and both are
        -- needed on every machine that watched the arc:
        --
        -- * each receiver flies its OWN copy of the throw (Net.lua, onThrowEcho) through the same
        --   physics with its own jitter and its own wind sample, so it stops at a different tile
        --   at a different moment. Nothing ends it but its own simulation.
        -- * and the ground light is built by each client's sweep, which runs once a second. So
        --   between the arc's light going out and the landed item's light coming on there is up to
        --   a second of darkness -- for the THROWER too, because M.place hands the landing over
        --   here and returns before lighting anything.
        --
        -- One broadcast closes both. It carries nothing this handler has not already validated
        -- against the sender's own position and this mod's own item tables.
        local throwId = type(args.throwId) == "string" and shortString(args.throwId, MAX_ID) or nil
        sendServerCommand(M.NET_MODULE, M.NET_LAND_ECHO, {
            id = throwId, type = args.type,
            x = math.floor(args.x), y = math.floor(args.y), z = math.floor(args.z),
            ox = ox, oy = oy,
            pitch = finite(args.pitch) and clamp(args.pitch, 0.0, 360.0) or nil,
            yaw = finite(args.yaw) and clamp(args.yaw, 0.0, 360.0) or nil,
            -- THE SERVER'S OWN READING of how much is left, as the throw relay sends: every
            -- receiver shades the light it builds with this rather than with a client's number.
            frac = clamp(M.fractionLeft(item) or 1.0, 0.0, 1.0),
        })
    end

    -- ---- CRACKING, on the authority ------------------------------------------------------------
    -- The client asks; this process makes the swap (authoritySwap, above) and the engine's own
    -- packets carry the new item and the equip to the owner and to everybody else. The answer
    -- names both ids and the belt location, which is all the owner's hotbar needs.

    local MIN_CRACK_GAP_MS = 500
    local crackAt = {}
    local crackN = 0

    local function pruneCracks(now)
        if crackN < PRUNE_AT then return end
        local stale = {}
        for who, at in pairs(crackAt) do
            if now > at + MIN_CRACK_GAP_MS then stale[#stale + 1] = who end
        end
        for i = 1, #stale do
            crackAt[stale[i]] = nil
            crackN = crackN - 1
        end
    end

    local function answerCrack(player, args, ok, why, extra)
        if not ok then M.debug(PART, "refused a crack: " .. tostring(why)) end
        if type(args) ~= "table" or player == nil then return end
        local payload = extra or {}
        payload.id = shortString(args.id, MAX_ID)
        payload.ok = ok
        sendServerCommand(player, M.NET_MODULE, M.NET_CRACK_ECHO, payload)
    end

    local function onCrack(player, args)
        if type(args) ~= "table" or player == nil then return end
        local litType = type(args.type) == "string" and M.LIT_OF ~= nil and M.LIT_OF[args.type] or nil
        if litType == nil then
            return answerCrack(player, args, false, "type " .. tostring(args.type) .. " is not a sealed one of ours")
        end
        local info = M.LIT[litType]
        if info == nil then
            return answerCrack(player, args, false, "no lit record for " .. tostring(litType))
        end
        local itemId = finite(args.itemId) and math.floor(args.itemId) or nil
        if itemId == nil then
            return answerCrack(player, args, false, "no item id")
        end
        -- THEIRS, and exactly that one: a crack is a swap of one specific item, never of "a
        -- sealed one somewhere", or two identical sticks could swap the wrong one.
        local item = findCarried(player, args.type, itemId)
        local ok, id = pcall(function() return item ~= nil and item:getID() or nil end)
        if item == nil or not ok or id ~= itemId then
            return answerCrack(player, args, false, "the sender is not carrying that item")
        end
        local fresh, location = M.authoritySwap(player, item, litType, M.burnHours(info.family))
        if fresh == nil then
            return answerCrack(player, args, false, location)
        end
        local newId = nil
        pcall(function() newId = fresh:getID() end)
        answerCrack(player, args, true, nil, { oldId = itemId, newId = newId, location = location })
    end

    -- ---- A THROW IN THE AIR, relayed like a flare -----------------------------------------------
    -- The landed item reaches everybody through the server's placement (onDrop). The flight
    -- would not: it exists only on the thrower's machine. So the arc is relayed at launch and
    -- every other client flies a visual-only copy. The sender's own echo is dropped by its id,
    -- as with flares. It also marks the item as airborne here, so the burn-out sweep does not
    -- swap an item that is between a hand and the ground.

    local MIN_THROW_GAP_MS = 250
    local throwAt = {}
    local throwN = 0

    local function pruneThrows(now)
        if throwN < PRUNE_AT then return end
        local stale = {}
        for who, at in pairs(throwAt) do
            if now > at + MIN_THROW_GAP_MS then stale[#stale + 1] = who end
        end
        for i = 1, #stale do
            throwAt[stale[i]] = nil
            throwN = throwN - 1
        end
    end

    local function onThrow(player, args, who)
        if type(args) ~= "table" or player == nil then return end
        for _, k in ipairs({ "x0", "y0", "z0", "x1", "y1", "flight", "apex" }) do
            if not finite(args[k]) then
                return M.debug(PART, "refused a throw: " .. k .. " is not a finite number")
            end
        end
        local burnRec = ourItem(args.type)
        if burnRec == nil or burnRec == false then
            return M.debug(PART, "refused a throw: type " .. tostring(args.type) .. " is not a lit one of ours")
        end
        local okP, px, py, pz = pcall(function() return player:getX(), player:getY(), player:getZ() end)
        if not okP or not finite(px) then return M.debug(PART, "refused a throw: the sender has no position") end
        -- It leaves the thrower's hand, and it lands within the mod's own reach of them.
        local dx0, dy0 = args.x0 - px, args.y0 - py
        if dx0 * dx0 + dy0 * dy0 > 4.0 or math.abs(args.z0 - pz) > 1.5 then
            return M.debug(PART, "refused a throw: it did not start at the thrower")
        end
        local reach = maxThrow()
        local dx1, dy1 = args.x1 - px, args.y1 - py
        if dx1 * dx1 + dy1 * dy1 > reach * reach then
            return M.debug(PART, "refused a throw: too far from the thrower")
        end
        local itemId = finite(args.itemId) and math.floor(args.itemId) or nil
        local item = findCarried(player, args.type, itemId)
        local okI, id = pcall(function() return item ~= nil and item:getID() or nil end)
        if item == nil or not okI or (itemId ~= nil and id ~= itemId) then
            return M.debug(PART, "refused a throw: the sender is not carrying one")
        end
        local flight = clamp(args.flight, 0.2, 6.0)
        local now = getTimestampMs ~= nil and getTimestampMs() or 0
        M.markFlightOnAuthority(id, now + flight * 1000.0 + 5000.0)

        -- The burn fraction is the SERVER's reading of the item, which every client stamped the
        -- same way; the colour, the radius and the material come from the type on each receiver.
        local frac = M.fractionLeft(item) or 1.0
        sendServerCommand(M.NET_MODULE, M.NET_THROW_ECHO, {
            id = shortString(args.id, MAX_ID), who = shortString(who, MAX_ID),
            type = args.type,
            x0 = args.x0, y0 = args.y0, z0 = args.z0, x1 = args.x1, y1 = args.y1,
            flight = flight, apex = clamp(args.apex, 0.1, 12.0), frac = clamp(frac, 0.0, 1.0),
        })
    end

    local function onClientCommand(module, command, player, args)
        if module ~= M.NET_MODULE then return end
        if sendServerCommand == nil then return end

        local whoNow = "?"
        pcall(function() whoNow = tostring(player:getUsername()) end)
        local nowT = getTimestampMs ~= nil and getTimestampMs() or 0

        if command == M.NET_CRACK then
            if crackAt[whoNow] ~= nil and nowT < crackAt[whoNow] then
                return answerCrack(player, args, false, "too soon after the last one")
            end
            pruneCracks(nowT)
            if crackAt[whoNow] == nil then crackN = crackN + 1 end
            crackAt[whoNow] = nowT + MIN_CRACK_GAP_MS
            local ok, err = pcall(onCrack, player, args)
            if not ok then M.defect(PART, "crack failed: " .. tostring(err)) end
            return
        end

        if command == M.NET_THROW then
            if throwAt[whoNow] ~= nil and nowT < throwAt[whoNow] then return end
            pruneThrows(nowT)
            if throwAt[whoNow] == nil then throwN = throwN + 1 end
            throwAt[whoNow] = nowT + MIN_THROW_GAP_MS
            local ok, err = pcall(onThrow, player, args, whoNow)
            if not ok then M.defect(PART, "throw relay failed: " .. tostring(err)) end
            return
        end

        if command == M.NET_DROP then
            -- Rate-limited on its own budget: a throw is a deliberate act and nobody makes more
            -- than a few a second, but an unbounded one spawns items for everybody.
            if dropAt[whoNow] ~= nil and nowT < dropAt[whoNow] then
                -- ANSWERED. Silence here made the client wait out its fifteen second deadline and
                -- then latch the whole route off for the session: two quick swings cost the feature.
                return refuse(player, args, "too soon after the last one")
            end
            pruneDrops(nowT)
            if dropAt[whoNow] == nil then dropN = dropN + 1 end
            dropAt[whoNow] = nowT + MIN_DROP_GAP_MS
            local ok, err = pcall(onDrop, player, args)
            if not ok then M.defect(PART, "drop failed: " .. tostring(err)) end
            return
        end

        if command ~= M.NET_FLARE then return end

        local who = "?"
        pcall(function() who = tostring(player:getUsername()) end)

        local now = getTimestampMs ~= nil and getTimestampMs() or 0
        if lastAt[who] ~= nil and now < lastAt[who] then return end
        prune(now)
        if lastAt[who] == nil then lastN = lastN + 1 end
        lastAt[who] = now + MIN_GAP_MS

        local gun = heldGun(player)
        if gun == nil then
            M.debug(PART, "refused a flare packet from " .. who .. ": not holding the gun")
            return
        end
        -- SPENT BEFORE THE GEOMETRY IS JUDGED. The shot already happened on the shooter's screen,
        -- and a refused relay must not hand the round back. An empty gun, on the copy that counts,
        -- fires nothing for anybody.
        if not spendRound(player, gun) then
            M.debug(PART, "refused a flare packet from " .. who .. ": no cartridge")
            return
        end

        local clean = sanitise(player, args)
        if clean == nil then
            M.debug(PART, "refused a flare packet from " .. who)
            return
        end
        -- The name the SERVER knows, truncated like the id and for the same reason.
        clean.who = shortString(who, MAX_ID)

        sendServerCommand(M.NET_MODULE, M.NET_FLARE_ECHO, clean)
    end

    if AUTHORITY then
        local h = M.addHandler(PART, "OnClientCommand", onClientCommand)
        if h ~= nil then
            M.status(PART, true, "cracks, drops and burn-outs on the authority; flares and throws relayed")
        end
    end
end
