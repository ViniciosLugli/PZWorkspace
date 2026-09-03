--[[
    Net
    The one thing in this mod that has to go over the wire, and the replay at the other end.
]]

require "LugliEmergencyLights/Core"
require "LugliEmergencyLights/Gun"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- Net ---------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Flare relay"

    --- How long a sent id is remembered so its own echo can be dropped, in ms. Comfortably longer
    --- than any round trip and shorter than the flare it describes.
    local ECHO_TTL_MS = 30000

    --- id -> the moment it may be forgotten. Not a set: an echo that never arrives, because the
    --- server has no mod, must not leak an entry for the life of the session.
    local mine = {}
    local mineN = 0

    --- Shots sent with nothing coming back, which is what a server without this mod looks like.
    local unanswered = 0
    local SAID_AFTER = 2
    local said = false

    local function nowMs()
        return getTimestampMs ~= nil and getTimestampMs() or 0
    end

    --- Forget ids whose echo is never coming.
    local function reap()
        if mineN == 0 then return end
        local now = nowMs()
        local stale = nil
        for id, at in pairs(mine) do
            if now > at then
                stale = stale or {}
                stale[#stale + 1] = id
            end
        end
        if stale == nil then return end
        for i = 1, #stale do
            mine[stale[i]] = nil
            mineN = mineN - 1
        end
        -- Every one of these was a shot the server never echoed.
        if unanswered >= SAID_AFTER and not said then
            said = true
            -- kind "dep", not "bug": nothing here is broken, the other end is simply absent.
            -- A literal string, like every other status note: these are not player-facing UI.
            M.status("Flare gun", false,
                     "the server does not have this mod, so your flares are visible only to you",
                     "dep")
            M.log(PART, "no echo for " .. tostring(unanswered)
                      .. " flare(s); this server is not running Emergency Lights")
        end
    end

    --- EVERYTHING A FIRED FLARE DOES ONCE IT IGNITES, in one place, so the shot and the replay
    --- cannot drift apart. `source` is the shooter, and it is the ONLY thing the two callers
    --- disagree about.
    ---
    --- @param source  the shooting character, or nil on a replay. NOT optional decoration: it gates
    ---               the zombie draw, and a replay must not make one. WorldSoundManager.addSound
    ---               replicates from a client, so the shooter's own call has already reached the
    ---               server and every other player; calling it again on each receiver would
    ---               multiply the horde this flare pulls by the number of people who saw it.
    function M.aerialComposition(x, y, z, secs, range, r, g, b, source, aloft)
        if source ~= nil then
            M.noiseAt(source, math.floor(x), math.floor(y), z, M.cfg("AerialNoise"))
        end
        if aloft ~= true then return end

        -- NO SKY WASH. The engine's WorldFlares effect rebuilt the grid stack every frame and greyed
        -- the whole scene for the flare's life; see the Flare block in Gun.lua. Both timers below
        -- run on worldHours, so `secs` is in-game seconds throughout.
        -- EVERY CLIENT MARKS ITS OWN MAP. That is the point of a signal.
        if M.markFlare ~= nil then
            M.markFlare(x, y, range, secs, r, g, b)
        end
        -- A CARRIER RECORD ON THE LANDING TILE, and without it the flare was mute and inert.
        if M.addTimedCluster ~= nil then
            M.addTimedCluster(math.floor(x), math.floor(y), z, 0.02, 0.02, 0.02, 1, secs,
                              M.SND_FLARE_BURN_AERIAL)
        end
    end

    --- Tell the server this machine just fired one.
    ---
    --- SINGLE PLAYER IS EXCLUDED ON PURPOSE, and not because there is nobody to tell. The single
    --- player path is BROKEN: SinglePlayerClient.sendClientCommand writes a leading playerIndex byte
    --- that its own receiveServerCommand never skips before reading the module and command strings,
    --- and it raises OnServerCommand rather than OnClientCommand. Sending there would parse garbage.
    function M.sendFlare(character, x, y, z, secs, range, mx, my, mz, travel, apex, cart)
        if not M.isMultiplayer() or sendClientCommand == nil then return end

        local who = "?"
        pcall(function() who = tostring(character:getUsername()) end)
        local id = who .. "-" .. tostring(nowMs()) .. "-" .. tostring(math.floor(x))
                       .. "." .. tostring(math.floor(y))

        -- REMEMBERED BEFORE IT IS SENT. The echo comes back to the shooter too, and replaying your
        -- own flare would double every light, wash and map mark you fired.
        if mine[id] == nil then mineN = mineN + 1 end
        mine[id] = nowMs() + ECHO_TTL_MS
        unanswered = unanswered + 1

        pcall(sendClientCommand, M.NET_MODULE, M.NET_FLARE, {
            id = id, who = who,
            x = x, y = y, z = z,
            mx = mx, my = my, mz = mz,
            secs = secs, travel = travel, apex = apex,
            r = cart.r, g = cart.g, b = cart.b,
        })
    end

    -- ---- CRACKING, WHICH ONLY THE SERVER MAY DO ------------------------------------------------
    --
    -- A multiplayer client cannot create an inventory item. ItemContainer.AddItem has no network
    -- effect from a client, the server keeps its own copy of every inventory, and EquipPacket
    -- resolves what a player holds by item id against THAT copy: a stick minted here would light
    -- this screen and read as an empty hand on every other one, and the server's drop would
    -- refuse to land it. So the client asks and the authority swaps (World.lua, authoritySwap).
    -- The new item and the equip come back as the engine's own packets; the answer below carries
    -- the ids and the belt location for the one thing only this machine can do, its hotbar.

    local crackSeq = 0

    --- Ask the server to crack this sealed item of ours. True when the request is away.
    function M.sendCrack(player, item, family)
        if not M.isMultiplayer() or sendClientCommand == nil then return false end
        if player == nil or item == nil then return false end
        local fullType, itemId = nil, nil
        pcall(function() fullType = item:getFullType(); itemId = item:getID() end)
        if fullType == nil or itemId == nil then return false end

        local who = "?"
        pcall(function() who = tostring(player:getUsername()) end)
        crackSeq = crackSeq + 1
        local id = who .. "-c" .. tostring(nowMs()) .. "-" .. tostring(crackSeq)
        local ok = pcall(sendClientCommand, M.NET_MODULE, M.NET_CRACK,
                         { id = id, itemId = itemId, type = fullType })
        return ok
    end

    --- The server swapped one of ours, cracked or burnt out: put the replacement back in the
    --- hotbar slot the old one hung in, and bring its tooltip up to date.
    local function onSwapEcho(args, what)
        if args.ok == false then
            M.debug(PART, what .. " refused by the server (" .. tostring(args.id) .. ")")
            return
        end
        local newId = tonumber(args.newId)
        if newId == nil then return end
        M.forEachLocalPlayer(function(player)
            local fresh = nil
            pcall(function() fresh = player:getInventory():getItemWithIDRecursiv(newId) end)
            if fresh == nil then return end
            if args.location ~= nil and M.reattachAt ~= nil then
                M.reattachAt(player, fresh, args.location)
            end
            if M.refreshBurnDisplay ~= nil then M.refreshBurnDisplay(fresh) end
        end)
    end

    -- ---- A THROW IN THE AIR, so other people see the arc and not just the landing -------------

    local throwSeq = 0

    --- Tell the server this machine just threw one, so everybody else can fly a copy.
    ---
    --- RETURNS THE ID IT SENT, or nil. The landing goes over the wire separately, once the item is
    --- actually on the ground, and it names this same id so every machine can end the copy of the
    --- arc it is flying rather than letting each one stop wherever its own physics happened to.
    function M.sendThrow(player, item, x0, y0, z0, x1, y1, flight, apex)
        if not M.isMultiplayer() or sendClientCommand == nil then return nil end
        if player == nil or item == nil then return nil end
        local fullType, itemId = nil, nil
        pcall(function() fullType = item:getFullType(); itemId = item:getID() end)
        if fullType == nil then return nil end

        local who = "?"
        pcall(function() who = tostring(player:getUsername()) end)
        throwSeq = throwSeq + 1
        local id = who .. "-t" .. tostring(nowMs()) .. "-" .. tostring(throwSeq)

        -- REMEMBERED BEFORE IT IS SENT, so the echo of our own throw is not flown a second time.
        -- Not counted against the server's silence: the drop already answers that question.
        if mine[id] == nil then mineN = mineN + 1 end
        mine[id] = nowMs() + ECHO_TTL_MS

        local ok = pcall(sendClientCommand, M.NET_MODULE, M.NET_THROW, {
            id = id, itemId = itemId, type = fullType,
            x0 = x0, y0 = y0, z0 = z0, x1 = x1, y1 = y1,
            flight = flight, apex = apex,
        })
        if not ok then return nil end
        return id
    end

    --- Somebody threw one. Fly a visual-only copy: no item, no landing, no inventory. The real
    --- item arrives on the ground through the server's own placement.
    local function onThrowEcho(args)
        local id = tostring(args.id or "")
        if mine[id] ~= nil then
            mine[id] = nil
            mineN = mineN - 1
            return
        end
        local info = type(args.type) == "string" and M.LIT ~= nil and M.LIT[args.type] or nil
        if info == nil or M.launchProjectile == nil then return end
        local fam = M.FAMILIES ~= nil and M.FAMILIES[info.family] or nil
        local bounce = fam ~= nil and { fam.bounceE, fam.bounceF, fam.slide } or nil
        local tex = nil
        pcall(function() tex = getScriptManager():getItem(args.type):getNormalTexture() end)
        local frac = type(args.frac) == "number" and args.frac or 1.0
        -- TAGGED WITH THE THROW'S OWN ID. This copy is flown by physics that cannot agree with the
        -- thrower's -- its own jitter, its own wind sample -- so it is ended by the landing echo
        -- rather than left to stop wherever it drifts to. See onLandEcho.
        local ok = M.launchProjectile(nil, args.x0, args.y0, args.z0, args.x1, args.y1,
                                      args.flight, args.flight, args.apex,
                                      info.r, info.g, info.b, M.lightRadius(info.family),
                                      nil, nil, true, bounce,
                                      M.windageFor ~= nil and M.windageFor(info.family) or 0.0,
                                      tex, info.family, frac, id)
        if ok then M.debug(PART, "replayed " .. tostring(args.who) .. "'s throw") end
    end

    -- ---- A THROW THAT HAS LANDED, which is the only moment every machine can agree on ---------
    --
    -- Sent by the server the instant the item is really on the ground (World.lua, onDrop). It does
    -- two things no client can work out for itself, and BOTH of them are why it exists:
    --
    --   1. it ends the copy of the arc this machine is flying. Every receiver simulates the throw
    --      separately and stops somewhere slightly different; without this the light lingers in
    --      mid-air, in the wrong place, after the real item is down.
    --   2. it lights the landing tile on the frame the item arrives, instead of leaving it dark
    --      until the once-a-second sweep next walks past.
    --
    -- IT IS NOT SUPPRESSED BY `mine`, and that is the one thing to remember about it. Every other
    -- echo in this file is dropped when it carries an id this machine sent, because the sender has
    -- already done the work locally. Here the sender has done the OPPOSITE: M.place handed the
    -- landing to the server and returned before lighting anything, so the thrower needs this
    -- message every bit as much as the onlookers do.
    local function onLandEcho(args)
        local id = type(args.id) == "string" and args.id or nil
        if id ~= nil and M.endProjectile ~= nil then M.endProjectile(id) end

        local info = type(args.type) == "string" and M.LIT ~= nil and M.LIT[args.type] or nil
        if info == nil or M.ensure == nil then return end
        if type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number" then
            return
        end

        local x, y, z = math.floor(args.x), math.floor(args.y), math.floor(args.z)
        local ox = type(args.ox) == "number" and args.ox or 0.5
        local oy = type(args.oy) == "number" and args.oy or 0.5
        local frac = type(args.frac) == "number" and args.frac or 1.0

        -- The same record M.place builds on the thrower's own local path. Keyed by tile and by
        -- item, so when the sweep next finds the real object here it updates this light in place
        -- rather than making a second one -- and if the object never arrives on this machine, the
        -- sweep drops the light on its next pass, exactly as it does for any tile with nothing
        -- burning on it. Self-correcting either way.
        pcall(function()
            M.ensure(x, y, z, {
                family = info.family,
                colour = info.colour,
                r = info.r, g = info.g, b = info.b,
                sound = M.burnSoundFor(info.family),
                fx = x + ox, fy = y + oy, fz = z,
                pitch = args.pitch, yaw = args.yaw,
            }, frac)
        end)
        M.debug(PART, "a throw landed at " .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z))
    end

    -- ---- DROPPING SOMETHING WHERE OTHER PEOPLE CAN SEE IT ------------------------------------
    --
    -- A multiplayer client cannot put a world item on the wire. Not through
    -- AddWorldInventoryItem (its `transmit` argument is spent at `if (transmit &&
    -- GameServer.server)`), not through transmitCompleteItemToClients, not through
    -- sendAddItemToContainer, and not through sendObjectChange, which answers a client with
    -- "sendObjectChange() can only be called on the server". See docs/13.
    --
    -- So a thrown stick placed by the thrower is visible to the thrower and to nobody else, and the
    -- authority never learns it exists. The only way to drop something everybody can see is to ask
    -- the server to do the dropping.
    --
    -- THE ITEM IS HELD, NOT DESTROYED, until the server confirms. It is already out of every
    -- container by the time it lands, so this registry is the only thing holding it: if the answer
    -- never comes, it goes back where it came from.

    --- How long to wait for the server to confirm a drop, in ms. Generous on purpose: the only
    --- thing that ever actually runs it out is a server without this mod, and a needlessly tight
    --- deadline would be an item lost to a lag spike.
    local DROP_TTL_MS = 15000

    --- id -> { item, player, container, at }
    local pending = {}
    local pendingN = 0

    --- Makes every id unique on this machine whatever the clock does. Name plus millisecond plus
    --- tile is not enough on its own: two throws that landed on the same tile in the same
    --- millisecond would share an id, and the second would overwrite the first in `pending` --
    --- losing an item that had already left its container.
    local dropSeq = 0

    --- Does the server answer drops? Latched false the first time one goes unanswered, so the very
    --- next throw lands instantly and locally instead of hanging for fifteen seconds again.
    local serverDrops = true

    --- May the caller hand a landing to the server?
    function M.serverDropReady()
        return M.isMultiplayer() and serverDrops and sendClientCommand ~= nil
    end

    local function forget(id)
        if pending[id] == nil then return nil end
        local rec = pending[id]
        pending[id] = nil
        pendingN = pendingN - 1
        return rec
    end

    --- Give up on the drops the server never answered and put those items back.
    local function reapDrops()
        if pendingN == 0 then return end
        local now = nowMs()
        local dead = nil
        for id, rec in pairs(pending) do
            if now > rec.at + DROP_TTL_MS then
                dead = dead or {}
                dead[#dead + 1] = id
            end
        end
        if dead == nil then return end
        for i = 1, #dead do
            local rec = forget(dead[i])
            if rec ~= nil and M.restoreThrown ~= nil then
                M.restoreThrown(rec.item, rec.player, rec.container)
            end
        end
        -- ONCE. Everything after this lands locally, which is what a server without this mod can
        -- support, and the player is told why other people cannot see what they put down.
        if serverDrops then
            serverDrops = false
            M.status(PART, false,
                     "the server does not have this mod, so what you put down is visible only to you",
                     "dep")
            M.log(PART, "the server did not answer a drop; landing items locally from now on")
        end
    end

    --- Ask the server to put this item on the ground. Returns true when the request is away and the
    --- item is being held for it; false means the caller must land it itself.
    ---
    --- `throwId` is the id M.sendThrow returned for this same throw, or nil for a landing that
    --- never flew. It is carried so the server's landing broadcast can name the arc every other
    --- machine is flying, and so end it at the moment the item is really down.
    function M.sendDrop(player, item, square, ox, oy, pitch, yaw, container, throwId)
        if not M.serverDropReady() or player == nil or item == nil or square == nil then
            return false
        end

        local fullType = nil
        pcall(function() fullType = item:getFullType() end)
        if fullType == nil then return false end

        local who = "?"
        pcall(function() who = tostring(player:getUsername()) end)
        dropSeq = dropSeq + 1
        local id = who .. "-d" .. tostring(nowMs()) .. "-" .. tostring(dropSeq)

        -- WHICH ONE, not just which type. The server places the sender's OWN item out of the
        -- sender's own inventory, and two identical sticks can carry different burn times: without
        -- the id it could land the wrong one and leave the player holding the one they threw.
        local itemId = nil
        pcall(function() itemId = item:getID() end)

        -- NO BURN TIME IS SENT. The item the server lands is the player's own, already carrying its
        -- stamp from when it was cracked against that same world clock. A number from here would be
        -- a client's number, and there is nothing for it to say that the item does not already.
        local ok = pcall(sendClientCommand, M.NET_MODULE, M.NET_DROP, {
            id = id, type = fullType, itemId = itemId,
            x = square:getX(), y = square:getY(), z = square:getZ(),
            ox = ox, oy = oy,
            pitch = pitch, yaw = yaw,
            throwId = type(throwId) == "string" and throwId or nil,
        })
        if not ok then return false end

        if pending[id] == nil then pendingN = pendingN + 1 end
        pending[id] = { item = item, player = player, container = container, at = nowMs() }
        return true
    end

    --- BEFORE THE WORLD IS WRITTEN, everything still waiting on the server goes back into a
    --- container -- and stays pending.
    ---
    --- A drop in flight belongs to nobody: it has left every container and the server has not
    --- answered yet. A save taken in that window would write neither, and the teardown that follows
    --- a quit restores the item AFTER the save has been written, so it would be gone on the next
    --- load. This is the same trap Throw.lua's stowInFlight exists for, and the same answer:
    --- somewhere real beats nowhere, and the round trip carries on regardless. If the server does
    --- take it, the echo below takes the item back out of the container it was parked in.
    function M.stowPendingDrops()
        if pendingN == 0 then return 0 end
        local n = 0
        for _, rec in pairs(pending) do
            if rec.item ~= nil and M.restoreThrown ~= nil then
                if M.restoreThrown(rec.item, rec.player, rec.container) then
                    rec.parked = true
                    n = n + 1
                end
            end
        end
        if n > 0 then
            M.debug(PART, "parked " .. tostring(n) .. " pending drop(s) so the save keeps them")
        end
        return n
    end

    --- Take a parked item back out of wherever the save-time stow put it. Only ever called when
    --- the server has confirmed it made its own copy, so leaving this one anywhere is a duplicate.
    local function unpark(rec)
        if rec == nil or rec.parked ~= true or rec.item == nil then return end
        pcall(function()
            local c = rec.item:getContainer()
            if c ~= nil then c:Remove(rec.item) end
        end)
    end

    --- The server answered. Either it made the object, in which case ours is a duplicate of
    --- something that exists properly and is simply released, or it refused, in which case the item
    --- comes straight back rather than waiting out the deadline.
    ---
    --- A REFUSAL IS NOT A MISSING MOD, and telling them apart is the whole reason the server sends
    --- one. A refusal is ordinary -- a chunk that has not streamed in yet looks exactly like it --
    --- and treating it as "this server has no mod" would cost the player the feature for the rest
    --- of the session over one throw at a bad moment.
    local function onDropEcho(args)
        local id = tostring(args.id or "")
        local rec = forget(id)
        if rec == nil then
            -- An answer to a drop this machine is no longer waiting on: the deadline beat it. The
            -- item has already gone back into a container and the server has made its own, so there
            -- are now two. Said out loud, because it is the one duplication this design can produce
            -- and it would otherwise happen in complete silence.
            M.log(PART, "a drop was answered after it had already been given up on (" .. id
                      .. "); if an item looks duplicated, this is why")
            return
        end

        -- Answered at all, so the route works: anything an earlier timeout latched off was wrong.
        serverDrops = true

        if args.ok == false then
            -- Already back in a container if a save parked it there; putting it back twice is a
            -- no-op, because restoreThrown checks before it adds.
            if M.restoreThrown ~= nil then
                M.restoreThrown(rec.item, rec.player, rec.container)
            end
            M.debug(PART, "the server refused the drop for " .. id .. "; the item came back")
            return
        end
        -- Taken. If a save had parked this one in a container, it has to come back OUT of it, or
        -- the player keeps a copy of something that is now lying on the ground for everybody.
        unpark(rec)
        M.debug(PART, "the server took the drop for " .. id)
    end

    --- Somebody fired one. Fly it, then light it, exactly as the shooter's own machine did.
    local function onServerCommand(module, command, args)
        if module ~= M.NET_MODULE then return end
        if type(args) ~= "table" then return end
        if command == M.NET_DROP_ECHO then return onDropEcho(args) end
        if command == M.NET_CRACK_ECHO then return onSwapEcho(args, "a crack") end
        if command == M.NET_EXPIRE_ECHO then return onSwapEcho(args, "a burn-out") end
        if command == M.NET_THROW_ECHO then return onThrowEcho(args) end
        if command == M.NET_LAND_ECHO then return onLandEcho(args) end
        if command ~= M.NET_FLARE_ECHO then return end

        local id = tostring(args.id or "")
        if mine[id] ~= nil then
            -- Our own shot coming back. It already flew here.
            mine[id] = nil
            mineN = mineN - 1
            unanswered = 0
            said = false
            return
        end

        local z = math.floor(args.z or 0)
        local function lit(aloft)
            -- nil source: see the note on aerialComposition. The shooter's noise already carried.
            M.aerialComposition(args.x, args.y, z, args.secs, args.range,
                                args.r, args.g, args.b, nil, aloft ~= false)
        end

        -- THE FLIGHT, NOT JUST THE IGNITION. The streak climbing out of somebody's position is most
        -- of what makes a flare read as a signal rather than as a light that appeared.
        --
        -- No owner, no onDone and thrown = false: this touches no item, no container and no
        -- ammunition. Nothing about the replay can affect anybody's inventory.
        if M.launchProjectile ~= nil then
            local ok = M.launchProjectile(nil, args.mx, args.my, args.mz, args.x, args.y,
                                          args.secs, args.travel, args.apex,
                                          args.r, args.g, args.b, args.radius, lit, nil, false,
                                          nil, 1.0)
            if ok then
                M.debug(PART, "replayed " .. tostring(args.who) .. "'s flare")
                return
            end
        end
        -- No projectile part, or it refused the flight: the flare still has to appear.
        lit(true)
    end

    local h = M.addHandler(PART, "OnServerCommand", onServerCommand)
    M.addTicker(PART, 5.0, reap)
    M.addTicker(PART, 2.0, reapDrops)
    M.addHandler(PART, "OnSave", function() M.stowPendingDrops() end)

    M.addTeardown(PART, function()
        mine, mineN = {}, 0
        unanswered, said = 0, false
        -- A WORLD CHANGE MUST NOT EAT AN ITEM. Anything still waiting on the server goes back into
        -- the inventory it came out of, the same way an interrupted flight does.
        for id, rec in pairs(pending) do
            if M.restoreThrown ~= nil then
                M.restoreThrown(rec.item, rec.player, rec.container)
            end
        end
        pending, pendingN = {}, 0
        serverDrops = true
    end)

    if h ~= nil then M.status(PART, true, "other players' flares and throws are visible to you") end
end
