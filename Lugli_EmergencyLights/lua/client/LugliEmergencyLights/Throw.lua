--[[
    Throw
]]

require "LugliEmergencyLights/Aim"
require "LugliEmergencyLights/Pose"
require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Throw"

--- How soon after touching a wall an object must stop for the wall to be what stopped it, in
--- seconds. Past this it slid somewhere else and lies flat like anything else.
local WALL_LEAN_WINDOW = 0.45

--- Items currently in the air, keyed by item id: { item, player, container }.
local inFlight = {}

-- Counted rather than probed with `next`, which the installed VM does not provide: 42.20.4 stripped
-- part of the base library and the globals gate catches exactly this. The count is also what makes
local inFlightN = 0

local function itemId(item)
    if item == nil then return nil end
    local ok, id = pcall(function() return item:getID() end)
    if not ok then return nil end
    return id
end

function M.markInFlight(item, flag, player, container)
    local id = itemId(item)
    if id == nil then return end
    local had = inFlight[id] ~= nil
    if flag and not had then
        inFlight[id] = { item = item, player = player, container = container }
        inFlightN = inFlightN + 1
    elseif not flag and had then
        inFlight[id] = nil
        inFlightN = inFlightN - 1
    end
end

--- True while this item is mid-throw. Read by the held light and by the throw itself.
function M.isInFlight(item)
    if item == nil or inFlightN == 0 then return false end
    local id = itemId(item)
    if id == nil then return false end
    return inFlight[id] ~= nil
end

--- Put a thrown item back where it came from, because the throw could not finish.
function M.restoreThrown(item, player, container)
    if item == nil then return false end

    -- ALREADY ON THE GROUND? Then it is not lost and putting it in a bag as well would mint the
    -- second copy this whole design exists to prevent.
    local inWorld = nil
    pcall(function() inWorld = item:getWorldItem() end)
    if inWorld ~= nil then return true end

    local held = false
    pcall(function() held = container ~= nil and container:contains(item) end)
    if held then return true end

    local function into(c)
        if c == nil then return false end
        local done = false
        pcall(function()
            c:AddItem(item)
            done = c:contains(item)
        end)
        return done
    end

    local inv = nil
    pcall(function() inv = player ~= nil and player:getInventory() or nil end)

    if into(container) then return true end
    if inv ~= container and into(inv) then return true end

    M.defect(PART, "could not return a thrown item to any container")
    return false
end

--- Everything still in the air goes back into a container before the world is written.
function M.stowInFlight()
    if inFlightN == 0 then return 0 end
    local n = 0
    for _, rec in pairs(inFlight) do
        if rec ~= nil and rec.item ~= nil then
            if M.restoreThrown(rec.item, rec.player, rec.container) then n = n + 1 end
        end
    end
    if n > 0 then
        M.debug(PART, "stowed " .. tostring(n) .. " in-flight item(s) so the save keeps them")
    end
    return n
end

--- Nothing may stay "in the air" across a world change.
function M.clearInFlight()
    for _, rec in pairs(inFlight) do
        if rec ~= nil and rec.item ~= nil then
            M.restoreThrown(rec.item, rec.player, rec.container)
        end
    end
    inFlight = {}
    inFlightN = 0
end

--- Put an item on a square, assuming it has already left every container.
--- Split out of the landing so the projectile can place it on arrival, not on release.
---
--- `origin` is the container the item came out of, and it is only used when the landing has to be
--- handed to the server: if that request is never answered the item goes back THERE rather than
--- into the main inventory. By this point the throw has already emptied every container, so it
--- cannot be recovered from the item itself.
function M.place(player, item, square, rest, origin)
    if player == nil or square == nil or item == nil then return false end

    -- IS THERE STILL A WORLD TO PLACE IT IN. Checked BEFORE anything is removed from anywhere.
    if getCell == nil or getCell() == nil then
        M.debug(PART, "no world to land in; the item stays in the inventory")
        return false
    end

    -- Still held or still in a container when called directly rather than through the arc: the
    -- item's OWN container, because ItemContainer.Remove does not recurse into bags, so removing
    local already = nil
    pcall(function() already = item:getWorldItem() end)
    if already ~= nil then
        M.debug(PART, "the thrown item is already in the world; leaving it where it is")
        return false
    end

    local inv = item:getContainer()
    if inv ~= nil then
        -- ONE MUTATION PER pcall, and the removal VERIFIED.
        pcall(function() player:removeFromHands(item) end)
        pcall(function() inv:Remove(item) end)

        local stillThere = false
        pcall(function() stillThere = inv:contains(item) end)
        if stillThere then
            M.defect(PART, "could not remove the thrown item from its container; "
                           .. "leaving it there rather than duplicating it")
            return false
        end
    -- NO sendRemoveItemFromContainer FROM A CLIENT. It gets the player KICKED.
    end

    -- The 5-argument form. The overloads it sits among differ in their FIRST parameter's type
    -- (InventoryItem against String against ItemKey), which Kahlua can tell apart.
    local ox, oy = 0.5, 0.5
    -- ONLY IF IT IS THE SAME TILE.
    local sameTile = rest ~= nil and type(rest.x) == "number"
        and math.floor(rest.x) == square:getX()
        and math.floor(rest.y) == square:getY()
    if sameTile then
        ox = rest.x - math.floor(rest.x)
        oy = rest.y - math.floor(rest.y)
        if ox < 0.02 then ox = 0.02 elseif ox > 0.98 then ox = 0.98 end
        if oy < 0.02 then oy = 0.02 elseif oy > 0.98 then oy = 0.98 end
    end

    -- HOW IT WILL LIE, worked out here because only this machine knows how the throw ended: the
    -- impact velocity, the wall it stopped against, how steeply it came down. The server cannot
    -- derive any of that, so it is sent rather than recomputed.
    local restPitch, restYaw = nil, nil
    if M.poseFor ~= nil then
        local info0 = M.litInfo(item)
        local fam0 = info0 ~= nil and info0.family or nil
        restPitch, restYaw = M.poseFor(fam0, rest or {})
    end

    -- ---- THE SERVER DROPS IT, IF THERE IS ONE THAT CAN ------------------------------------------
    -- A multiplayer client cannot put a world item on the wire by any route (docs/13), so an item
    -- this machine places is visible to this machine alone and the authority never learns it exists.
    -- Asking the server to do the dropping is the only way anybody else sees what you put down.
    --
    -- The item is HELD by Net.lua until the server confirms, and handed back if it never does. It is
    -- already out of every container by now, so there is nothing to undo either way.
    if M.serverDropReady ~= nil and M.serverDropReady() then
        -- The arc's own id travels with the landing, so the server's broadcast can end the copy of
        -- this throw every other machine is flying and light the tile on the frame it arrives.
        -- A landing with no flight behind it -- the fallback that places an item directly when the
        -- arc could not be launched -- carries none, and is simply a landing nobody watched.
        local throwId = rest ~= nil and rest.record ~= nil and rest.record.throwId or nil
        if M.sendDrop(player, item, square, ox, oy, restPitch, restYaw, origin or inv, throwId) then
            M.debug(PART, string.format("asked the server to land %s at %d,%d,%d",
                tostring(item:getFullType()), square:getX(), square:getY(), square:getZ()))
            -- The noise is ours to make and replicates by itself; the light, the pose and the model
            -- all arrive with the object the server sends back to everyone.
            M.noiseAt(player, square:getX(), square:getY(), square:getZ(), M.cfg("ThrowNoise"))
            return true
        end
    end

    local placed = nil
    pcall(function()
        placed = square:AddWorldInventoryItem(item, ox, oy, 0.0, true)
    end)
    if placed == nil then
        M.defect(PART, "AddWorldInventoryItem returned nothing")
        return false
    end

    -- Says WHERE it went, once per throw.
    M.debug(PART, string.format("landed %s at %d,%d,%d (3D ground items: %s)",
        tostring(item:getFullType()), square:getX(), square:getY(), square:getZ(),
        tostring(getCore ~= nil and getCore():isOption3DGroundItem() or "unknown")))

    -- MINE TO LOOK AFTER, and only on a multiplayer client. Nothing Lua can call from a client puts
    -- a world item on the wire, so this object exists here and nowhere else: the authority will
    -- never see it and never burn it out. The mark is what lets the client sweep expire this one
    -- without going anywhere near an object the server owns. See M.markLocalOnly.
    if M.isMultiplayer() and M.markLocalOnly ~= nil then
        M.markLocalOnly(placed or item)
    end

    -- Vanilla's own drop does this. Without it the world-item cleanup sandbox option can sweep a
    -- burning stick away.
    local wo = nil
    pcall(function()
        wo = placed:getWorldItem()
        if wo ~= nil then wo:setIgnoreRemoveSandbox(true) end
    end)

    -- HOW IT LIES, applied to the object this machine just made. Same numbers the server path
    -- sends; worked out once, above.
    if M.poseFor ~= nil then
        local info0 = M.litInfo(placed) or M.litInfo(item)
        local fam = info0 ~= nil and info0.family or nil
        local pitch, yaw, name = M.poseFor(fam, rest or {})
        restPitch, restYaw = pitch, yaw
        -- Onto the record for THIS throw, which travelled here in `rest`, rather than onto
        -- whichever throw happens to be the most recent one.
        if rest ~= nil and rest.record ~= nil then
            rest.record.pose = name
            rest.record.pitch = pitch
            rest.record.yaw = yaw
        end
        if M.applyPose(placed, wo, pitch, yaw) then
            M.debug(PART, "resting pose: " .. tostring(name)
                        .. " pitch=" .. tostring(pitch) .. " yaw=" .. tostring(yaw))
        end
    end

    -- LIT ON THE FRAME IT LANDS, not on the next sweep pass.
    local info = M.litInfo(item)
    if info ~= nil and M.ensure ~= nil then
        local frac = M.fractionLeft(item) or 1.0
        pcall(function()
            M.ensure(square:getX(), square:getY(), square:getZ(), {
                family = info.family,
                colour = info.colour,
                r = info.r, g = info.g, b = info.b,
                sound = M.burnSoundFor(info.family),
                fx = M.worldPosOf(wo, "X", square:getX()),
                fy = M.worldPosOf(wo, "Y", square:getY()),
                fz = M.worldPosOf(wo, "Z", square:getZ()),
                -- THE POSE, ON THE FRAME IT LANDS. Same argument as the light itself: the sweep
                -- would supply these a second later, and a second is long enough to see.
                pitch = M.itemRotation(placed or item, "P") or restPitch,
                yaw = M.itemRotation(placed or item, "Z") or restYaw,
            }, frac)
        end)
    end

    M.noiseAt(player, square:getX(), square:getY(), square:getZ(), M.cfg("ThrowNoise"))
    return true
end

--- Throw it, and let it FLY there.
local function throwWithArc(player, item, square, info)
    if M.launchProjectile == nil then return false end

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local tx, ty = square:getX() + 0.5, square:getY() + 0.5
    local dx, dy = tx - px, ty - py
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Short throws are fast and flat, long ones hang. Both scale with distance so the arc always
    -- looks like the effort the character just made.
    local vary = M.rand
    -- FLAT AND FAST, because that is how a person throws a small object at something they can see.
    local flight = (0.38 + dist * 0.055) * vary(0.90, 1.12)
    local apex = (0.30 + dist * 0.060) * vary(0.85, 1.18)

    -- IT LEAVES THE INVENTORY HERE, on the frame it leaves the hand.
    pcall(function() player:removeFromHands(item) end)

    -- AND THE EMPTY HAND GOES ON THE WIRE. removeFromHands on a client only nulls the hand and
    -- raises a flag that the SERVER reads (IsoGameCharacter.java:3383, :8655); a client sends the
    -- Equip packet only when something calls updateHandEquips, which is exactly what the engine's
    -- own client-side drop does (:11323-11325). Without it the thrown item stays visible in this
    -- character's hand on every other player's screen for as long as they can see them. The
    -- authority empties its own copy of the hand when it takes the item (World.lua, onDrop); this
    -- is the half that cannot wait for the round trip.
    if M.isMultiplayer() then
        pcall(function() player:updateHandEquips() end)
    end

    local origin = nil
    pcall(function() origin = item:getContainer() end)
    if origin ~= nil then
        pcall(function() origin:Remove(item) end)
        local stuck = false
        pcall(function() stuck = origin:contains(item) end)
        if stuck then
            M.defect(PART, "could not take the thrown item out of its container; refusing the throw")
            return false
        end
    end
    M.markInFlight(item, true, player, origin)

    -- AND TELL EVERYBODY ELSE IT IS IN THE AIR. The landed item reaches them through the server's
    -- own placement; the flight would not, and a stick that appears on the ground out of nowhere
    -- is not the throw the other player just watched you wind up for. Net.lua relays the arc and
    -- the receivers fly a visual-only copy: no item, no landing, no inventory.
    -- The id it went out under is kept on the throw's own record below: the landing is a separate
    -- message, sent once the item is really on the ground, and it names this id so every machine
    -- ends the arc it is flying at the same moment rather than whenever its own copy stops.
    local throwId = nil
    if M.sendThrow ~= nil then
        throwId = M.sendThrow(player, item, px, py, pz, tx, ty, flight, apex)
    end

    -- The square is captured by COORDINATE, not by reference: a chunk can be disposed and rebuilt
    -- mid-flight, and placing onto an orphaned IsoGridSquare succeeds silently and puts the item
    -- nowhere.
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()

    -- DECLARED ABOVE onDone, and that position is the whole point.
    local rec = {
        family = info.family,
        colour = info.colour,
        throwId = throwId,
        aimDist = dist,
        range = M.throwRange ~= nil and M.throwRange(info.family) or nil,
        fromX = px, fromY = py, fromZ = pz,
        aimX = tx, aimY = ty,
        at = getTimestampMs ~= nil and getTimestampMs() or 0,
    }

    local landed = false

    --- Where it actually stopped, or the aim square if the physics put it somewhere illegal.
    local function restingSquare(rx, ry, rz)
        if getCell == nil then return nil end

        local function fetch(ix, iy, iz)
            local ok, sq = pcall(function() return getCell():getGridSquare(ix, iy, iz) end)
            if not ok then return nil end
            return sq
        end

        if type(rx) == "number" and type(ry) == "number" and type(rz) == "number" then
            local sq = fetch(math.floor(rx), math.floor(ry), math.floor(rz))
            if sq ~= nil and (M.landable == nil or M.landable(sq, player)) then return sq end
        end
        -- RE-RESOLVED BY COORDINATE, never from the captured reference. A chunk can be disposed
        -- and rebuilt mid-flight, and placing onto an orphaned IsoGridSquare succeeds silently and
        -- puts the item nowhere.
        return fetch(sx, sy, sz)
    end

    local function onDone(rx, ry, rz, p)
        if landed then return end
        landed = true
        M.markInFlight(item, false)
        local sq = restingSquare(rx, ry, rz)
        if sq == nil then
            -- No world left to land in, which is the teardown case. The item is out of every
            -- container by now and this mod is the only thing holding it, so it goes back.
            M.debug(PART, "landing square is gone; the item goes back to the inventory")
            M.restoreThrown(item, player, origin)
            return
        end

        -- WHAT THE FLIGHT ENDED IN, which is what decides how the object lies. A stick that was
        -- still sliding lies flat along its direction of travel; one that stopped against a wall
        -- leans on it; a flare that came down steeply and slowly stands on its base.
        local rest = nil
        if p ~= nil then
            rest = {
                x = rx, y = ry, z = rz,
                vx = p.vx, vy = p.vy, vz = p.vz,
                -- How it ARRIVED, which is what decides the pose. The resting velocity is zero.
                impactVX = p.impactVX, impactVY = p.impactVY, impactVZ = p.impactVZ,
                -- RECENT, not ever. hitWall is a latch that never clears, so a stick that clipped a
                -- doorframe early and then slid five tiles into open floor still
                hitWall = p.hitWall and p.wallAt ~= nil
                    and (p.elapsed - p.wallAt) < WALL_LEAN_WINDOW,
                wallX = p.wallX, wallY = p.wallY,
                heading = math.atan2(ty - py, tx - px),
                record = rec,
            }
        end
        -- The other half of the record: where it really stopped, and how it got there.
        do
            local lt = rec
            lt.landX, lt.landY, lt.landZ = rx, ry, rz
            if p ~= nil then
                lt.contacts = p.contacts
                -- THE ARC, IN SCREEN PIXELS. One z unit lifts a sprite about 192 of them, so this
                -- is what the eye actually judges "does that look like a throw or a lob" on --
                -- and it is the number two rounds of tuning by degrees failed to move.
                lt.risePx = p.peakZ ~= nil and (p.peakZ - lt.fromZ - 0.55) * 192.0 or nil
                lt.hitWall = p.hitWall
                -- THE THREE THINGS THAT CUT A THROW SHORT, and until now the log named only one.
                lt.ceilHits = p.ceilHits
                lt.stalled = p.stalled
                lt.peakZ = p.peakZ ~= nil and (p.peakZ - lt.fromZ) or nil
                lt.flightSeconds = p.elapsed
                lt.impactVZ = p.impactVZ
                local ddx = (rx or lt.fromX) - lt.fromX
                local ddy = (ry or lt.fromY) - lt.fromY
                lt.gotDist = math.sqrt(ddx * ddx + ddy * ddy)
                if lt.aimDist > 0.01 then
                    lt.errPct = (lt.gotDist / lt.aimDist - 1.0) * 100.0
                end
            end
            M.debug(PART, string.format(
                "%s aimed %.1f, landed %.1f (%+.0f%%) in %.2fs, peak %.2fz, %d contact(s)%s%s%s",
                tostring(lt.family), lt.aimDist, lt.gotDist or -1, lt.errPct or 0,
                lt.flightSeconds or 0, lt.peakZ or 0.0, lt.contacts or 0,
                lt.hitWall and ", hit a wall" or "",
                (lt.ceilHits or 0) > 0 and ", hit a ceiling" or "",
                lt.stalled and ", stalled on unloaded ground" or ""))
        end

        if not M.place(player, item, sq, rest, origin) then
            M.restoreThrown(item, player, origin)
        end
    end

    -- The family's own material. restitution and friction, authored as bounceE/bounceF.
    local fam = M.FAMILIES[info.family]
    -- restitution, the contact's tangential loss, and how freely it slides once it is down.
    local bounce = fam ~= nil and { fam.bounceE, fam.bounceF, fam.slide } or nil

    -- The item's own icon, so what flies through the air is the thing that was thrown. getTex is
    -- the same accessor the engine falls back to for a ground item that has no 3D model.
    local tex = nil
    pcall(function() tex = item:getTex() end)

    -- WHAT THIS THROW WAS, recorded for the debug read-out and for the log.

    local ok = M.launchProjectile(player, px, py, pz, tx, ty,
                                  flight, flight, apex, info.r, info.g, info.b,
                                  M.lightRadius(info.family), nil, onDone, true, bounce,
                                  M.windageFor ~= nil and M.windageFor(info.family) or 0.0,
                                  tex,
                                  -- THE ITEM'S OWN DECAY, carried into the flight. Without these a
                                  -- thrown light ignores its burn curve and flies at full
                                  info.family, M.fractionLeft(item) or 1.0)
    if not ok then
        -- Could not fly it: put it down rather than losing it, and CLEAR THE FLAG. Leaving it set
        -- would mark the item as permanently airborne -- unthrowable for the rest of the session,
        -- and invisible to the held light, which skips anything in flight.
        M.markInFlight(item, false)
        if not M.place(player, item, square, nil, origin) then
            M.restoreThrown(item, player, origin)
        end
    end
    return true
end

--- Where the throw is AIMED, made imperfect: the square throwWithArc launches at.
local function landingSquare(player, sq, info)
    if sq == nil then return sq end

    local px, py = player:getX(), player:getY()
    local tx, ty = sq:getX() + 0.5, sq:getY() + 0.5
    local dx, dy = tx - px, ty - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.5 then return sq end

    local function jitter() return M.jitter(1.0) end

    -- SCATTER IN TILES, NOT DEGREES, and that is what makes it exist at all.
    local maxr = M.throwRange(info.family)
    local reachFrac = 1.0
    if type(maxr) == "number" and maxr > 0 then reachFrac = math.min(1.0, dist / maxr) end
    local sigma = (M.spreadFor ~= nil and M.spreadFor(info.family) or 0.0) * reachFrac

    -- Two independent samples make a round-ish blob rather than a bias along one axis. Summing a
    -- pair of uniforms is the cheap approximation of a normal, and it is the right SHAPE here:
    -- most throws near the mark, a few well out, and none absurd.
    local ox = (jitter() + jitter()) * 0.5 * sigma
    local oy = (jitter() + jitter()) * 0.5 * sigma

    -- NO SLIDE EXTENSION ANY MORE, and removing it is a correction rather than a simplification.
    local rx = dx + ox
    local ry = dy + oy

    -- CLAMPED TO THE ITEM'S OWN RANGE.
    if type(maxr) == "number" and maxr > 0 then
        local out = math.sqrt(rx * rx + ry * ry)
        if out > maxr then
            local k = maxr / out
            rx, ry = rx * k, ry * k
        end
    end

    -- Falls back to the aimed square, which aimSquareDirect has already validated. That is the
    -- only case worth a fallback: scatter moved the point onto a tile that will not take an item.
    return M.directSquare(player, px + rx, py + ry, sq:getZ()) or sq
end

local function onSwing(character, weapon)
    if character == nil or weapon == nil then return end
    -- Ours only: the aim reads this machine's mouse and camera.
    if not M.isLocalPlayer(character) then return end

    local info = M.litInfo(weapon)
    if info == nil then return end
    -- Already arcing through the air: one swing, one throw.
    if M.isInFlight(weapon) then return end

    -- DIRECT, for the same reason the flare gun is, and one the rewrite created.
    local sq = M.aimSquareDirect(character, M.throwRange(info.family))
    if sq == nil then return end
    -- The aim is where you POINTED. This is where it lands.
    sq = landingSquare(character, sq, info)
    if sq == nil then return end
    -- OFF THE BELT THE INSTANT IT LEAVES, and this cannot wait for the landing.
    M.detachAttachment(weapon, character)

    if not throwWithArc(character, weapon, sq, info) then
        M.place(character, weapon, sq)
    end

    -- AND LET GO OF THE PLAYER.
    pcall(function() character:setAttackAnimThrowTimer(0) end)
end

-- THROWING IS THE ATTACK SWING, and only that.

local h = M.addHandler(PART, "OnWeaponSwingHitPoint", onSwing)

-- BEFORE THE WORLD IS WRITTEN, everything still in the air goes back into a container. This is the
-- one hook that runs early enough to matter; the reasoning is on M.stowInFlight.
M.addHandler(PART, "OnSave", function() M.stowInFlight() end)

-- A world change lands everything still in the air back into the inventory it never left, which
-- is the whole point of leaving it there.
M.addTeardown(PART, function() M.clearInFlight() end)
if h ~= nil then M.status(PART, true) end
