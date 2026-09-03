--[[
    Light
    Every light this mod puts in the world: on the ground, in a hand, and the upkeep sweep.
]]

require "LugliEmergencyLights/Core"
require "LugliEmergencyLights/FX"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- GroundLight -------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Ground light"

    -- ============================================================================ WHICH PRIMITIVE, and
    -- it is the one decision the whole file rests on.
    local OWNER = "Lugli_EmergencyLights/ground"

    -- FULL SATURATION IS 1.0 HERE, not the lamppost's 0.5.
    local CEILING = 1.0

    -- IS THERE STILL A WORLD.
    local worldUp = false

    -- A ceiling on how many ground lights may hold a slot at once.
    local MAX_LIGHTS = 128
    local lightN = 0

    -- A LIGHT IS NOT AT THE MIDDLE OF THE OBJECT, it is at the part that is burning, and on these
    -- objects those are not the same point.
    --- Where this family's light actually comes from, relative to the item's origin, in world units.
    function M.emissiveOffset(familyId, pitchDeg, yawDeg)
        local o = M.EMISSIVE ~= nil and M.EMISSIVE[familyId] or nil
        if o == nil then return 0.0, 0.0, 0.0 end

        -- The authored offset is a length along the axis. The first two components stay available for
        -- a family whose lit part is genuinely off-axis; none is today, and both are zero.
        local len = o[3]
        if type(pitchDeg) ~= "number" then return o[1], o[2], len end

        local p = math.rad(pitchDeg)

        -- NO HORIZONTAL DISPLACEMENT, AND THIS IS MEASURED RATHER THAN DERIVED.
        return o[1], o[2], len * math.cos(p)
    end

    -- key -> { light, emitter, x, y, z, radius, ident, sound, expiresAt }
    local live = {}
    local liveN = 0

    local function keyOf(x, y, z)
        return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    end

    function M.liveLightCount() return liveN end

    --- Will the registry accept a light yet?
    function M.lightsReady() return worldUp end

    -- How many live records are flares. Maintained rather than counted, so the per-frame flicker can
    -- ask "is there anything to do" in O(1) instead of walking every light in the world to find out
    -- there is not.
    local flareN = 0
    function M.flareLightCount() return flareN end

    --- ONE shading function, for a light in your hand and a light on the floor alike.
    local function shade(v, frac, sat, intensity)
        local mixed = v * sat + (1.0 - sat)
        local c = mixed * intensity * CEILING * frac
        if c < 0.0 then return 0.0 end
        if c > CEILING then return CEILING end
        return c
    end

    -- THE THREE OPTIONS M.shade READS, RESOLVED ONCE PER WORLD.
    local cfgGen = -1
    local satC, intenC, wobbleOnC = 0.45, 1.0, false

    local function refreshShadeOptions()
        cfgGen = M.configGen or 0

        local v = M.cfg("LightSaturation")
        satC = (type(v) == "number" and v >= 0.0 and v <= 1.0) and v or 0.45

        v = M.cfg("LightIntensity")
        intenC = (type(v) == "number" and v > 0.0) and v or 1.0

        wobbleOnC = M.cfg("LightIncidence") == true
    end

    local function shadeOptions()
        if cfgGen ~= (M.configGen or 0) then refreshShadeOptions() end
        return satC, intenC, wobbleOnC
    end

    --- THE one entry point.
    local DECAY = {
        GlowStick = { at = 0.30, floor = 0.75 },
        ChemLight = { at = 0.15, floor = 0.85 },
        RoadFlare = { at = 0.20, floor = 0.70 },
        -- A FIRED flare, which is not the same object as one in your hand and should not fade like one.
        AerialFlare = { at = 0.30, floor = 0.55 },
    }

    function M.decayFor(familyId, frac)
        if type(frac) ~= "number" then return 1.0 end
        local d = DECAY[familyId]
        if d == nil or frac >= d.at then return 1.0 end
        -- Linear from full power at the threshold to the floor at expiry.
        local k = frac / d.at
        return d.floor + (1.0 - d.floor) * k
    end

    --- A small, constant wobble so a chemical light is not mathematically steady.
    local incidence = 1.0

    function M.stepIncidence(dt)
        -- NOT WRAPPED.
        incidence = incidence + dt
    end

    local function wobble(on)
        if not on then return 1.0 end
        local t = incidence
        return 1.0 + 0.04 * math.sin(t * 2.3) * math.cos(t * 0.71)
    end

    --- ONE function, for every light in the mod: held, dropped, in flight, fired.
    function M.shade(v, frac, familyId)
        local f = frac or 1.0
        local sat, inten, wobbleOn = shadeOptions()
        -- The decay multiplies the light's POWER, not its remaining life: a stick at 10% left is not
        -- at 10% brightness, it is at its family's floor.
        local power = M.decayFor(familyId, f) * wobble(wobbleOn)
        return shade(v, power, sat, inten)
    end

    --- A world-light slot, or nil when this part is already holding its budget.
    ---
    --- A REFUSAL IS NEVER LATCHED. It used to be: one failed acquire set an `exhausted` flag that
    --- only a release could clear, so a single refusal during world entry silently killed every
    --- ground light for the rest of the session -- which is exactly what happened, because the
    --- light pool's own OnGameStart handler ran after this one and refused until it had.
    --- MAX_LIGHTS is the only real ceiling now, and it is checked without latching anything.
    local function acquireSlot()
        if lightN >= MAX_LIGHTS then return nil end
        local ok, h = pcall(M.lampAcquire, OWNER)
        if not ok or type(h) ~= "number" or h < 0 then
            -- Said once per part by M.defect's own dedupe, and the next sweep tries again.
            M.defect(PART, "the world light refused a slot; ground lights will keep retrying")
            return nil
        end
        lightN = lightN + 1
        return h
    end

    --- RELEASE ONLY. Release calls remove itself, so calling both fired removeLight twice for every
    --- light this mod ever put out: harmless, and twice the JNI for nothing.
    local function releaseSlot(h)
        if h == nil then return end
        pcall(M.lampRelease, h)
        lightN = lightN - 1
    end

    --- Register one ground light. Returns its handle, or nil.
    local function place(x, y, z, r, g, b, radius, label)
        local h = acquireSlot()
        if h == nil then return nil end
        local ok, set = pcall(M.lampSet, h,
                              math.floor(x), math.floor(y), z, r, g, b, radius)
        if not ok or set == false then
            releaseSlot(h)
            M.defect(PART, label .. " light refused: " .. tostring(set))
            return nil
        end
        return h
    end

    -- ONE PRIMITIVE, RE-STATED EVERY FRAME.

    --- Start this record's burn loop, if it has one.
    local function arm(rec, x, y, z, sound)
        if sound == nil then return end
        if rec.emitter == nil then rec.emitter = M.emitterAt(x, y, z) end
        if rec.emitter == nil or getCell == nil then return end
        local sq = getCell():getGridSquare(x, y, z)
        if sq ~= nil then M.loopOn(rec.emitter, sound, sq) end
    end

    --- Create or update the light and emitter for one square. frac is 1 at full life, 0 at expiry.
    function M.ensure(x, y, z, info, frac)
        if info == nil or not worldUp then return end
        if type(frac) ~= "number" then frac = 1.0 end
        if frac < 0.0 then frac = 0.0 end

        local key = keyOf(x, y, z)
        local rec = live[key]

        -- A TIMED LIGHT OUTRANKS AN ITEM'S.
        if rec ~= nil and rec.expiresAt ~= nil then return end

        -- THE FAMILY'S OWN NUMBERS, WITH NOTHING APPLIED ON TOP.
        local radius = M.lightRadius(info.family)
        local r = M.shade(info.r, frac, info.family)
        local g = M.shade(info.g, frac, info.family)
        local b = M.shade(info.b, frac, info.family)

        -- Keyed on WHICH ITEM, not just which square.
        local ident = tostring(info.family) .. "/" .. tostring(info.colour)
        if rec ~= nil and rec.ident ~= ident then
            M.drop(key)
            rec = nil
        end

        -- WHERE THE LIGHT SITS. The item's own sub-tile position, plus the offset to whatever part of
        -- it is actually burning. Falls back to the middle of the tile, which is all the lamppost path
        -- can express anyway.
        local ex, ey, ez = M.emissiveOffset(info.family, info.pitch, info.yaw)
        local fx = (info.fx or (x + 0.5)) + ex
        local fy = (info.fy or (y + 0.5)) + ey
        local fz = (info.fz or z) + ez

        if rec == nil then
            -- OUT OF SLOTS, BUT STILL BURNING.
            local cd = place(fx, fy, fz, r, g, b, radius, "ground")
            rec = { cd = cd, x = x, y = y, z = z,
                    fx = fx, fy = fy, fz = fz, radius = radius, ident = ident,
                    -- Kept on the record so anything DRAWING the object can size itself from the
                    -- mesh: the pin needs to know a flare's glow is a blob at the tip and a glow
                    -- stick's is a bar down its whole body.
                    family = info.family,
                    -- HOW THE ITEM IS LYING, kept so anything DRAWING it can follow the model.
                    pitch = info.pitch, yaw = info.yaw,
                    baseR = r, baseG = g, baseB = b, curR = r, curG = g, curB = b }
            live[key] = rec
            liveN = liveN + 1
        else
            -- UPDATE IN PLACE.
            --
            -- AND TRY AGAIN IF IT NEVER GOT A LIGHT. A record is created whether or not a slot was
            -- free, so an item that landed during a moment when none was is otherwise dark for as
            -- long as it burns, with a record that looks healthy. The sweep passes through here
            -- every scan, which is exactly the right place to notice and retry.
            if rec.cd == nil then
                rec.cd = place(fx, fy, fz, r, g, b, radius, "ground")
            end
            rec.fx, rec.fy, rec.fz = fx, fy, fz
            rec.radius = radius
            -- Re-read every pass, not just at creation: an item that is knocked over, picked up and
            -- dropped again, or re-posed by another client keeps its light but changes how it lies.
            rec.pitch, rec.yaw = info.pitch, info.yaw
            rec.curR, rec.curG, rec.curB = r, g, b
        end

        -- THE COLOUR THIS LIGHT SHOULD REST AT.
        rec.frac = frac

        rec.baseR, rec.baseG, rec.baseB = r, g, b
        -- And the CURRENT colour, which is what the per-frame submit actually sends. Without this a
        -- A light created this pass had no curR until the first flicker frame wrote one, so a
        -- non-flickering stick submitted its base and a flickering one submitted nil.
        if rec.curR == nil then rec.curR, rec.curG, rec.curB = r, g, b end
        -- The ITEM's colour, kept alongside the light's. baseR/G/B are post-shade: mixed toward white
        -- and scaled to the 0.5 ceiling, so renormalising them recovers the brightness but not the
        -- hue. Anything drawing the item rather than its light wants these.
        rec.rawR, rec.rawG, rec.rawB = info.r, info.g, info.b
        rec.sound = info.sound
        if info.sound == M.SND_FLARE_BURN and not rec.flare then
            rec.flare = true
            flareN = flareN + 1
        end
        arm(rec, x, y, z, info.sound)
    end

    --- Count a timed light as a flare, so the flicker pass knows there is something to animate.
    local function markFlareLight(x, y, z)
        local rec = live[keyOf(x, y, z)]
        if rec ~= nil and not rec.flare then
            rec.flare = true
            flareN = flareN + 1
        end
    end

    --- A light with no item under it, alive until a GAME-CLOCK deadline.
    local function addTimedLight(x, y, z, r, g, b, radius, seconds, sound)
        if M.worldHours == nil or not worldUp then return false end
        M.drop(keyOf(x, y, z))

        local cd = place(x, y, z, r, g, b, radius, "timed")
        if cd == nil then return false end

        local rec = { cd = cd, x = x, y = y, z = z,
                      fx = x + 0.5, fy = y + 0.5, fz = z,
                      radius = radius, ident = "timed",
                      baseR = r, baseG = g, baseB = b,
                      curR = r, curG = g, curB = b,
                      sound = sound, expiresAt = M.worldHours() + seconds / 3600.0 }
        live[keyOf(x, y, z)] = rec
        liveN = liveN + 1
        arm(rec, x, y, z, sound)
        return true
    end

    --- One light of whatever size was asked for.
    function M.addTimedCluster(x, y, z, r, g, b, radius, seconds, sound)
        local ok = addTimedLight(x, y, z, r, g, b, radius, seconds, sound)
        if ok then markFlareLight(x, y, z) end
        return ok
    end

    --- nil for an item's light, true or false for a timed one. The sweep reaps by asking whether a
    --- burning item is still on the square, which is never true for a fired flare.
    function M.timedAlive(rec)
        if rec == nil or rec.expiresAt == nil then return nil end
        if M.worldHours == nil then return false end
        return M.worldHours() < rec.expiresAt
    end

    --- Swap which sound a live light is playing, keeping the light itself.
    function M.reSound(rec, name)
        if rec == nil or rec.sound == name then return end
        M.stopEmitter(rec.emitter)
        rec.emitter = nil
        rec.sound = name
        if name ~= nil then arm(rec, rec.x, rec.y, rec.z, name) end
    end

    function M.drop(key)
        local rec = live[key]
        if rec == nil then return end
        live[key] = nil
        liveN = liveN - 1
        if rec.flare then flareN = flareN - 1 end
        -- Flagged rather than searched for. A dropped record can still be sitting in the dirty list,
        -- and its handle is about to belong to something else; submitting it then would have moved
        -- another part's light to this one's position for a frame.
        rec.dead = true
        M.stopEmitter(rec.emitter)
        releaseSlot(rec.cd)
        rec.cd = nil
    end

    function M.dropAt(x, y, z)
        M.drop(keyOf(x, y, z))
    end

    function M.hasLight(x, y, z)
        return live[keyOf(x, y, z)] ~= nil
    end

    --- Walk every live light. The callback gets (key, record) and the record is NEVER nil.
    function M.eachLight(fn)
        for key, rec in pairs(live) do
            if rec ~= nil then fn(key, rec) end
        end
    end

    --- Nothing may outlive the world: a stranded light has no source, and a stranded looping emitter
    --- is ticked forever at a fixed point.
    function M.dropAll()
        for key, _ in pairs(live) do M.drop(key) end
        live = {}
        liveN = 0
        flareN = 0
        -- Counted back to zero rather than decremented to it. Every drop above releases its own slot,
        -- so this should already be 0; asserting it means a record that somehow escaped cannot leave
        -- the cap permanently short and silently starve every future light.
        lightN = 0

        -- And by owner, so a record that somehow escaped the walk above costs nothing permanently.
        -- The carried light does not share this owner string, so its slot is untouched.
        pcall(function() M.lampReleaseOwner(OWNER) end)
    end

    -- NO TICKER. A registered world light persists until something removes it, so there is nothing
    -- to re-state; see the note where the submitter used to be. The part's status is gated on the
    -- OnGameStart handler instead, which is the thing it genuinely cannot run without.
    --- THE SUBMITTER. Every live ground light, re-stated every frame.
    local SUBMIT_CULL = 52

    -- Reused across frames by submit(). Never longer than the number of local players, which is at
    -- most four, so there is nothing to trim.
    local playerX, playerY = {}, {}
    local playerN = 0

    local function notePlayer(player)
        playerN = playerN + 1
        playerX[playerN], playerY[playerN] = player:getX(), player:getY()
    end

    local function collectPlayers()
        playerN = 0
        M.forEachLocalPlayer(notePlayer)
        return playerN
    end

    local function submit()
        if liveN == 0 then return end

        -- The players, once, rather than once per light -- and into arrays that OUTLIVE the frame.
        local pn = collectPlayers()
        if pn == 0 then return end
        local px, py = playerX, playerY

        for _, rec in pairs(live) do
            if rec ~= nil and rec.cd ~= nil and not rec.dead then
                local near = false
                for i = 1, pn do
                    local dx, dy = rec.fx - px[i], rec.fy - py[i]
                    if dx * dx + dy * dy <= SUBMIT_CULL * SUBMIT_CULL then
                        near = true
                        break
                    end
                end

                if near then
                    local r, g, b

                    if rec.rawR ~= nil then
                        -- AN ITEM'S LIGHT. Shaded from the raw authored colour and the life left, so
                        -- it decays and breathes exactly as the same item does in the player's hand.
                        local frac = rec.frac or 1.0
                        r = M.shade(rec.rawR, frac, rec.family)
                        g = M.shade(rec.rawG, frac, rec.family)
                        b = M.shade(rec.rawB, frac, rec.family)

                        -- The flare's own flicker, CONTRIBUTED by the Flare block in Gun.lua rather than
                        -- written by it. Two writers on one light fought each other frame by frame;
                        -- one writer with several contributors does not.
                        local k = rec.flick
                        if k ~= nil then r, g, b = r * k, g * k, b * k end
                    else
                        -- A TIMED LIGHT, submitted EXACTLY AS AUTHORED. addTimedLight and
                        -- addTimedCluster build a record with baseR/G/B and no rawR: there is no item
                        r, g, b = rec.baseR, rec.baseG, rec.baseB
                    end

                    if r ~= nil then
                        rec.curR, rec.curG, rec.curB = r, g, b
                        -- Lamp sends a bare setLightColor unless the position or radius actually
                        -- moved, so a stationary light costs one native call and NO global relight.
                        -- That difference is why the permanent lamppost arm was chosen over the
                        -- uncapped temp one, which cannot be recoloured at all.
                        pcall(M.lampSet, rec.cd,
                              math.floor(rec.fx), math.floor(rec.fy), rec.fz,
                              r, g, b, rec.radius)
                    end
                end
            end
        end
    end

    -- Per frame, because a torch stated once and left alone goes out.
    M.addTicker(PART, 0, submit)

    local h = M.addHandler(PART, "OnGameStart", function()
        lightN = 0
        worldUp = true

        -- A NEW WORLD STARTS A NEW CLOCK. M.worldHours clamps to the highest value it has seen, so a
        -- high-water mark carried over from the last world would freeze every burn time in this one
        -- at the old world's age.
        if M.resetWorldClock ~= nil then M.resetWorldClock() end

        -- NOTHING TO RECLAIM ANY MORE. The old bridge kept its registry in Java, which survived the
        -- Lua VM teardown, so every world entry had to hand the last world's slots back or the pool
        -- ran dry after a few reloads. Lamp's registry is Lua and dies with it, and the engine
        -- clears lamppostPositions on world teardown, so both halves are gone by themselves.
        M.log(PART, "ground lights ready, up to " .. tostring(MAX_LIGHTS) .. " at once")
    end)

    M.addTeardown(PART, function()
        -- CLOSED FIRST. Everything after this point in the teardown order is landing things, and
        -- anything it asks to be lit must be refused rather than registered into a world that is
        -- already going away.
        worldUp = false
        M.dropAll()
        pcall(M.lampReleaseOwner, OWNER)
    end)

    -- Gated on the handler, as every other part is gated on the thing it cannot run without.
    -- Reporting healthy when that hook failed is the one failure the status panel exists to catch.
    if h ~= nil then M.status(PART, true) end
end

-- ---- HeldLight ---------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Held light"

    local OWNER = "Lugli_EmergencyLights/held"

    -- ONE KEY SPACE FOR BOTH KINDS OF CARRIER. A local player is keyed by their player number, so
    -- split screen still gets one light each; another player on the server is keyed by "@username".
    -- Keeping them in one table is what lets the slot pool, the teardown and the flame pass stay
    -- single-path rather than growing a second copy of each.
    local function localKey(idx) return idx end
    local function remoteKey(who) return "@" .. tostring(who) end

    -- key -> world-light handle
    local slots = {}

    -- key -> { player, item, info, remote } resolved on the slow pass, reused by the fast one.
    local carried = {}
    local carriedN = 0

    --- How many OTHER players' lights this client will carry at once. The pool is 256 slots, of
    --- which the ground takes up to 128 and split screen up to 4; this leaves room for the
    --- projectiles. Without a ceiling, a full server where everyone cracked a stick would starve
    --- every ground light on the map.
    local MAX_REMOTE = 24

    --- And how far away another player's light is still worth carrying, in tiles. The ground
    --- submitter's own cull, for the same reason: past this it is not on anybody's screen.
    local REMOTE_CULL = 52

    --- When the remote walk may run again. It walks every online player, so it goes on the scan
    --- interval rather than on the 10 Hz resolve: nobody can light a stick faster than that.
    local remoteAt = 0

    local function setCarried(key, rec)
        local had = carried[key] ~= nil
        carried[key] = rec
        if rec ~= nil and not had then carriedN = carriedN + 1
        elseif rec == nil and had then carriedN = carriedN - 1 end
    end

    -- DECLARED HERE, ABOVE drop(), and that position is the whole point.
    local exhausted = false

    local function drop(key)
        local s = slots[key]
        if s ~= nil then
            -- RELEASED, NOT JUST REMOVED, and cleared from the table.
            slots[key] = nil
            -- NOT ALSO CLEARING `exhausted` HERE. Clearing it only on a release was the bug: it
            -- assumed this block already held a slot, which is exactly not the case when the ground
            -- lights have taken the pool. resolve() clears it every pass instead, which covers this
            -- case and every other one.
            pcall(M.lampRelease, s)
        end
        setCarried(key, nil)
    end

    local function usable(item)
        if item == nil then return false end
        -- A thrown item stays in the inventory for its whole flight so a world exit cannot destroy it,
        -- so it must be excluded here or it would light the player from inside a bag while visibly
        -- arcing across the street.
        if M.isInFlight ~= nil and M.isInFlight(item) then return false end
        -- ON ANOTHER PLAYER'S ITEM, isExpired IS ALWAYS FALSE, and that is the honest limit of doing
        -- this without a packet: a held item is stamped on its owner's machine and the stamp only
        -- travels when the item does. So a remote carrier's light lingers a little past the burn-out
        -- rather than never appearing, which is the right direction to be wrong in.
        return M.litInfo(item) ~= nil and not M.isExpired(item)
    end

    --- The lit item in either hand or clipped to the belt, or nil. Asked of remote players too:
    --- every call here is on IsoGameCharacter, which a replicated player fully is.
    local function heldLit(player)
        if usable(player:getPrimaryHandItem()) then return player:getPrimaryHandItem() end
        if usable(player:getSecondaryHandItem()) then return player:getSecondaryHandItem() end
        local ok, attached = pcall(function() return player:getAttachedItems() end)
        if ok and attached ~= nil then
            for i = 0, attached:size() - 1 do
                local item = attached:getItemByIndex(i)
                if usable(item) then return item end
            end
        end
        return nil
    end

    --- ONE slot per carrier, taken once and kept for as long as they carry something lit.
    local function slotFor(key)
        local s = slots[key]
        if s ~= nil or exhausted then return s end

        local h = M.lampAcquire(OWNER)
        if type(h) == "number" and h >= 0 then
            slots[key] = h
            return h
        end

        exhausted = true
        M.defect(PART, "no free light slots; a carried light will not be lit")
        return nil
    end

    --- One light, re-stated every frame on the tile nearest the player.
    local function update(player, key, item, info)
        local h = slotFor(key)
        if h == nil then return end

        local frac = M.fractionLeft(item) or 1.0
        local r = M.shade(info.r, frac, info.family)
        local g = M.shade(info.g, frac, info.family)
        local b = M.shade(info.b, frac, info.family)

        -- THE SAME RADIUS THE FLOOR GETS. Not 0.75x for a pool and 1.15x for a cone: one light, the
        -- family's own number, so putting a burning flare down changes where the light is and nothing
        -- else about it.
        local radius = M.lightRadius(info.family)

        -- ROUNDED TO THE NEAREST TILE.
        M.lampSet(h, M.lightTile(player:getX()), M.lightTile(player:getY()),
                  player:getZ(), r, g, b, radius)
    end

    --- WHICH item is lit, for the players sharing this screen.
    local function resolveLocal()
        M.forEachLocalPlayer(function(player, idx)
            local key = localKey(idx)
            local item = heldLit(player)
            if item == nil then
                if carried[key] ~= nil then drop(key) end
                return
            end
            setCarried(key, { player = player, item = item, info = M.litInfo(item) })
        end)
    end

    --- How far the nearest local player is from this one, squared, or nil when nobody is loaded.
    local function nearestLocalDist2(other)
        local ox, oy = other:getX(), other:getY()
        local best = nil
        M.forEachLocalPlayer(function(p)
            local dx, dy = p:getX() - ox, p:getY() - oy
            local d2 = dx * dx + dy * dy
            if best == nil or d2 < best then best = d2 end
        end)
        return best
    end

    --- AND THE OTHER PLAYERS ON THE SERVER, which is the whole reason a carried light is worth
    --- anything to anybody but the carrier. Their held item type is replicated by the engine, so
    --- this needs no packet of its own: only a walk.
    local function resolveRemote()
        if getOnlinePlayers == nil then return end
        local players = getOnlinePlayers()
        if players == nil then return end

        local cull2 = REMOTE_CULL * REMOTE_CULL
        local seen, taken = {}, 0
        for i = 0, players:size() - 1 do
            local other = players:get(i)
            if other ~= nil and not other:isLocalPlayer() then
                local item = heldLit(other)
                if item ~= nil then
                    local d2 = nearestLocalDist2(other)
                    -- Bounded twice: by distance, because past the cull it is on nobody's screen,
                    -- and by count, because the slot pool is shared with every ground light and a
                    -- full server would otherwise take all of it.
                    if d2 ~= nil and d2 <= cull2 and taken < MAX_REMOTE then
                        taken = taken + 1
                        local key = remoteKey(other:getUsername())
                        seen[key] = true
                        setCarried(key, { player = other, item = item,
                                          info = M.litInfo(item), remote = true })
                    end
                end
            end
        end

        -- Anyone who logged out, walked off, or put it away gives their slot back.
        local stale = {}
        for key, c in pairs(carried) do
            if c.remote and not seen[key] then stale[#stale + 1] = key end
        end
        for i = 1, #stale do drop(stale[i]) end
    end

    local function resolve()
        -- THE LATCH IS CLEARED HERE, not only when one of OUR slots comes back.
        --
        -- `exhausted` exists to stop slotFor asking the bridge on every frame once the pool is
        -- spent. Clearing it only in drop() assumed this block already held a slot -- but the pool
        -- is shared with the ground lights, which can take all of it while nobody is carrying
        -- anything. Then the first person to crack a stick latched it and NOTHING could clear it,
        -- because there was no held slot to release: carried lights were dead for the rest of the
        -- session, with one defect line, and the code's own comment said otherwise.
        --
        -- Retrying once per resolve rather than per frame is what the latch was really for: this is
        -- ten attempts a second in the worst case instead of sixty, and it recovers by itself the
        -- moment a ground light goes out.
        exhausted = false
        resolveLocal()
        if not M.isMultiplayer() then return end
        -- On its own clock: this walks every online player, and nothing it looks at can change
        -- faster than somebody can crack a stick.
        local now = getTimestampMs ~= nil and getTimestampMs() or 0
        if now < remoteAt then return end
        remoteAt = now + M.scanInterval() * 1000
        pcall(resolveRemote)
    end

    --- WHERE the light goes, every frame. This is what makes it glide rather than step.
    local function place()
        -- Nothing lit in anybody's hands: the whole pass is one integer compare.
        if carriedN == 0 then return end
        local stale = nil

        --- YOUR OWN LIGHT FIRST, and a stranger's second.
        ---
        --- Slots are taken lazily, here, and `pairs` walks a hash table in whatever order it likes.
        --- With the pool nearly spent that decided by coin toss whose light survived, so your own
        --- held flare could go dark while somebody you can barely see stayed lit. Two passes over
        --- the same table costs nothing and makes the answer "yours".
        local function pass(wantRemote)
            for key, c in pairs(carried) do
                if (c.remote == true) == wantRemote then
                    local ok, err = pcall(update, c.player, key, c.item, c.info)
                    if not ok then
                        -- Not dropped inside the walk: removing from a table while iterating it
                        -- skips entries, and a remote player's object goes stale the moment they
                        -- disconnect.
                        stale = stale or {}
                        stale[#stale + 1] = key
                        M.defect(PART, tostring(err))
                    end
                end
            end
        end

        pass(false)
        pass(true)

        if stale ~= nil then
            for i = 1, #stale do drop(stale[i]) end
        end
    end

    --- Every player currently carrying a lit item, local or remote, with the item and its family
    --- record. `remote` says which, because a remote carrier is drawn into the VIEWER's viewport
    --- rather than their own -- they do not have one on this machine.
    function M.eachCarried(fn)
        if carriedN == 0 then return end
        for key, c in pairs(carried) do
            if c.player ~= nil and c.item ~= nil and c.info ~= nil then
                fn(c.player, key, c.item, c.info, c.remote == true)
            end
        end
    end

    function M.dropHeldLights()
        for key, _ in pairs(carried) do drop(key) end
        for key, _ in pairs(slots) do drop(key) end
        carried, slots = {}, {}
        carriedN = 0
        remoteAt = 0
    end

    -- TWO RATES ON PURPOSE.
    M.addTicker(PART, 0.1, resolve)
    local h = M.addTicker(PART, 0, place)

    M.addTeardown(PART, function() M.dropHeldLights() end)

    M.addHandler(PART, "OnGameStart", function()
        slots = {}
        exhausted = false
        M.log(PART, "carried light ready, one per player at the family's own radius")
    end)

    if h ~= nil then M.status(PART, true) end
end

-- ---- Sweep -------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Sweep"

    -- Guards a pathological case rather than a normal one: without it, walking into a room someone
    -- filled with burning sticks would build every light in a single frame.
    local MAX_NEW_PER_PASS = 24

    --- How many steps the burn is quantised into before it reaches the item's tint.
    local TINT_STEPS = 12

    --- Tint a burning item to match the light it casts, at a bounded number of distinct values.
    ---
    --- CLIENT-SIDE, and it stays that way now its neighbours have gone to the server. setColorRed
    --- and friends do not transmit, and this is a pure function of fractionLeft, which every machine
    --- computes identically from the replicated stamp -- so no two clients can disagree, and having
    --- the authority write it too would mark a burning stick dirty on the world save every tick.
    local function tintItem(item, info, frac)
        local q = math.floor((frac or 1.0) * TINT_STEPS + 0.5) / TINT_STEPS
        local r, g, b = info.r * q, info.g * q, info.b * q
        -- A family whose lit skin is painted in colour ships its lit item WHITE, so that a held
        -- one's flame keeps its own colours (the engine re-tints a held weapon's whole texture by
        -- the item colour). Burning down still dims it, by value alone.
        if info.tintByValue then r, g, b = q, q, q end
        pcall(function()
            -- Half a step of the coarsest channel, well under the byte the atlas key quantises to and
            -- well over any float noise from the round trip.
            if math.abs(item:getColorRed() - r) < 0.002
                and math.abs(item:getColorGreen() - g) < 0.002
                and math.abs(item:getColorBlue() - b) < 0.002 then
                return
            end
            item:setColorRed(r)
            item:setColorGreen(g)
            item:setColorBlue(b)
        end)
    end

    --- Burn out an item that ONLY THIS MACHINE CAN SEE.
    ---
    --- The one exception to "the authority owns ground items", and it is not a loophole: an object
    --- a multiplayer client dropped or threw never reached the server (see M.markLocalOnly), so the
    --- authority cannot burn it out and no other client can be racing us for it. Without this the
    --- stick you threw stayed lit forever on your own screen -- which is what removing the old
    --- client-side expire cost, before this put it back for exactly the objects it is safe for.
    local function expireLocalOnly(square, worldObj, item)
        local spentType = M.SPENT_OF[item:getFullType()]
        if spentType == nil or instanceItem == nil then return end
        local ok, err = pcall(function()
            local spent = instanceItem(spentType)
            -- swapItem throws if the incoming item already belongs to a world object, so a freshly
            -- instanced one is the only safe thing to hand it. It does not transmit from a client,
            -- which is precisely why this is confined to objects nobody else has.
            if spent ~= nil then
                M.markLocalOnly(spent)
                worldObj:swapItem(spent)
            end
        end)
        if not ok then
            M.defect(PART, "could not burn out a locally dropped item: " .. tostring(err))
        end
    end

    -- NO GENERAL expire() HERE ANY MORE, and no stamping and no posing: they live in
    -- server/LugliEmergencyLights/World.lua, which exactly one machine per world runs.
    --
    -- swapItem sends IsoObjectChange.SWAP_ITEM only inside `if (GameServer.server)`, so the swap
    -- this file used to make was purely local on a multiplayer client: the server never heard it,
    -- the save kept the lit item, and every client redid the swap on every chunk load. The fallback
    -- branch was worse, because THAT one does replicate -- two clients in range minted two spent
    -- items. What is left here is what a viewer may legitimately decide for itself.

    local function sweepSquare(square, budget)
        local objs = square:getWorldObjects()
        if objs == nil then return budget end
        local n = objs:size()
        if n == 0 then return budget end

        -- COLLECTED FIRST, THEN ACTED ON. `dead` is now only a flag: this file no longer touches a
        -- burnt-out item, it only stops lighting the tile once nothing on it is still burning.
        local dead, live, mine = false, nil, nil
        for i = 0, n - 1 do
            local wo = objs:get(i)
            local item = wo ~= nil and wo:getItem() or nil
            local info = item ~= nil and M.litInfo(item) or nil
            if info ~= nil then
                if M.isExpired(item) then
                    dead = true
                    -- Ours alone, so ours to burn out. Anything else on this tile is the
                    -- authority's and is left strictly alone.
                    if M.isLocalOnly ~= nil and M.isLocalOnly(item) then
                        mine = mine or {}
                        mine[#mine + 1] = { wo = wo, item = item }
                    end
                elseif live == nil then
                    -- The first burning item on the tile owns the light. Several on one square is one
                    -- light, which is both cheaper and what looks right.
                    live = { item = item, info = info, wo = wo }
                end
            end
        end

        if not dead and live == nil then return budget end
        local x, y, z = square:getX(), square:getY(), square:getZ()

        -- THE AUTHORITY GETS THIS SQUARE FIRST, and only in single player, where it is this same
        -- process and has no walk of its own. It stamps, poses and swaps here so the record built
        -- below reads a posed item's rotation in the same visit -- and so the two of us do not walk
        -- every tile in the world twice a second between us. On a multiplayer client this global
        -- does not exist at all; on a dedicated server this file never runs.
        if M.worldActOnSquare ~= nil then M.worldActOnSquare(square) end

        if live ~= nil then
            local info, item = live.info, live.item
            -- ON THE GROUND, LIT, AND NOT STAMPED. Light it at full strength rather than refuse to
            -- light it at all.
            --
            -- AND ON A MULTIPLAYER CLIENT THAT IS PERMANENT, not a pass or two: item ModData is not
            -- replicated by anything. SyncExtendedPlacementPacket carries offsets and rotations
            -- only, and SWAP_ITEM re-serialises the replacement. So the authority's stamp is real,
            -- and it decides when the item burns out and swaps, but this client never reads the
            -- number -- it sees full brightness and then the spent item arriving. In single player
            -- the authority is this process and the stamp is landed before this line runs.
            local frac = M.fractionLeft(item) or 1.0

            local isNew = not M.hasLight(x, y, z)
            if not isNew or budget > 0 then
                if isNew then budget = budget - 1 end
                M.ensure(x, y, z, {
                    family = info.family,
                    -- WHICH ITEM, not just which family.
                    colour = info.colour,
                    r = info.r, g = info.g, b = info.b,
                    sound = M.burnSoundFor(info.family),
                    -- WHERE THE OBJECT ACTUALLY IS, not the middle of its tile.
                    fx = M.worldPosOf(live.wo, "X", x),
                    fy = M.worldPosOf(live.wo, "Y", y),
                    fz = M.worldPosOf(live.wo, "Z", z),
                    -- HOW IT IS LYING, so the burning tip is placed along the item's own axis rather
                    -- than assumed to be straight up. Public getters (InventoryItem.java:4243, 4259),
                    -- unlike the fields behind them.
                    pitch = M.itemRotation(item, "P"),
                    yaw = M.itemRotation(item, "Z"),
                }, frac)
                -- The item's own model dims with the pool of light it casts, from one value.
                tintItem(item, info, frac)
                -- And its burn line and gauge stay honest on the ground, not only once it is picked
                -- up. Guarded rather than required: the tooltip part is client-only and may not have
                -- loaded when this file first runs.
                if M.refreshBurnDisplay ~= nil then M.refreshBurnDisplay(item) end
            end
        elseif dead then
            -- Only when nothing is left burning here. Dropping unconditionally darkened a tile that
            -- still had a live stick on it for a full pass.
            M.dropAt(x, y, z)
        end

        -- `dead` is read only to decide whether this tile still deserves a light. Turning the burnt
        -- item into its spent form is the authority's job and arrives over the wire -- except for
        -- the ones the authority has never heard of, which are ours.
        if mine ~= nil then
            for i = 1, #mine do expireLocalOnly(square, mine[i].wo, mine[i].item) end
        end
        return budget
    end

    -- ---- DISCOVERY IS CHUNK-DRIVEN, NOT RADIAL ---------------------------------------------------
    -- A burning item on the ground used to be found only by the radial pass below, so anything outside
    -- SweepRadius was simply dark until you walked to it.
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
                        -- Caught per square, for the reason given on the radial pass: one bad tile must
                        -- not take the whole handler with it.
                        local ok, res = pcall(sweepSquare, sq, budget)
                        if ok then budget = res end
                    end
                end
            end
        end
        return budget
    end

    --- One chunk has streamed in. Light whatever is burning on it.
    local function onLoadChunk(chunk)
        -- The registry refuses work before OnGameStart, and LoadChunk fires for the initial window
        -- before that. Those chunks are covered by the sweep at boot instead.
        if not M.lightsReady() then return end
        sweepChunk(chunk, MAX_NEW_PER_PASS)
    end

    --- Everything already loaded when the world came up.
    function M.sweepLoadedWorld()
        if getWorld == nil then return 0 end

        local okCell, cell = pcall(function() return getWorld():getCell() end)
        if not okCell or cell == nil then return 0 end

        local found = 0
        M.forEachLocalPlayer(function(player, idx)
            local okMap, map = pcall(function() return cell:getChunkMap(idx) end)
            if not okMap or map == nil then return end

            local okW, wide = pcall(function() return map:getWidthInTiles() end)
            if not okW or type(wide) ~= "number" then return end
            local chunks = math.floor(wide / 8)

            for cx = 0, chunks - 1 do
                for cy = 0, chunks - 1 do
                    local okC, chunk = pcall(function() return map:getChunk(cx, cy) end)
                    if okC and chunk ~= nil then
                        local before = M.liveLightCount()
                        sweepChunk(chunk, MAX_NEW_PER_PASS)
                        found = found + (M.liveLightCount() - before)
                    end
                end
            end
        end)
        return found
    end

    --- True while that square still carries a burning item.
    function M.squareBurning(sq)
        if sq == nil then return false end
        local objs = sq:getWorldObjects()
        if objs == nil then return false end
        for i = 0, objs:size() - 1 do
            local wo = objs:get(i)
            local item = wo ~= nil and wo:getItem() or nil
            if item ~= nil and M.litInfo(item) ~= nil and not M.isExpired(item) then
                return true
            end
        end
        return false
    end

    -- ONE SQUARE LOOKUP PER RECORD PER REAP, memoised across the two branches that need it.
    local reapRec, reapSq = nil, nil

    local function reapSquare(rec)
        if rec == nil or getCell == nil then return nil end
        if rec ~= reapRec then
            reapRec = rec
            local cell = getCell()
            reapSq = cell ~= nil and cell:getGridSquare(rec.x, rec.y, rec.z) or nil
        end
        return reapSq
    end

    local function pass()
        if getCell == nil then return end
        local cell = getCell()
        if cell == nil then return end

        -- MAINTENANCE, NOT DISCOVERY, and that is what makes a small radius correct now.
        local radius = M.cfg("SweepRadius")
        if type(radius) ~= "number" or radius < 1 then radius = 10 end
        -- Clamped to what the sandbox can actually produce. This said 48, which no setting could reach.
        if radius > 32 then radius = 32 end
        local budget = MAX_NEW_PER_PASS

        M.forEachLocalPlayer(function(player)
            local px = math.floor(player:getX())
            local py = math.floor(player:getY())
            local pz = math.floor(player:getZ())
            -- A CIRCLE, NOT A SQUARE.
            local r2 = radius * radius
            for dy = -radius, radius do
                local room = r2 - dy * dy
                for dx = -radius, radius do
                    local sq = nil
                    if dx * dx <= room then sq = cell:getGridSquare(px + dx, py + dy, pz) end
                    if sq ~= nil then
                        -- CAUGHT PER SQUARE.
                        local okSq, res = pcall(sweepSquare, sq, budget)
                        if okSq then
                            budget = res
                        else
                            M.defect(PART, "square skipped after: " .. tostring(res))
                        end
                    end
                end
            end
        end)

        -- Reap ONLY on evidence: a square we can actually read that no longer has anything burning on
        -- it.
        local stale = {}
        M.eachLight(function(key, rec)
            local timed = M.timedAlive(rec)
            if timed ~= nil then
                -- A fired flare has no item under it and is reaped by its own clock, not by the
                -- square. It also survives being walked away from, which is the entire point of
                -- firing one: a signal you cannot leave behind is not a signal.
                if not timed then stale[#stale + 1] = key end
            elseif reapSquare(rec) == nil then
                -- OUT OF THE CHUNK WINDOW IS EVIDENCE, and this is the opposite of what it looks like.
                stale[#stale + 1] = key
            elseif not M.squareBurning(reapSquare(rec)) then
                stale[#stale + 1] = key
            end
        end)
        for i = 1, #stale do M.drop(stale[i]) end
    end

    -- DISCOVERY: one handler for chunks that stream in, one sweep for the window already open.
    M.addHandler(PART, "LoadChunk", onLoadChunk)

    M.addHandler(PART, "OnGameStart", function()
        local found = M.sweepLoadedWorld()
        if found > 0 then
            M.debug(PART, "lit " .. tostring(found) .. " item(s) already burning in the loaded world")
        end
    end)

    -- MAINTENANCE: colour refresh, the pose catch-up and reaping, near the player only. Expiry and
    -- the burnt-out swap are NOT here any more; they belong to the authority, in server/World.lua.
    local h = M.addTicker(PART, M.scanInterval, pass)

    -- NO TEARDOWN HERE. The GroundLight block owns the registry and already registers dropAll,
    -- closing its own worldUp gate first so nothing can re-register during the pass. A second
    -- registration simply ran the whole drop twice on every world exit.

    if h ~= nil then M.status(PART, true) end
end

-- ---- Source ------------------------------------------------------------------------------------
-- REMOVED. This drew a findability marker on every ground light -- FXGlow in the item colour with
-- FXCore white at 0.34 of it -- which on screen is a flat disc with a smaller white disc punched
-- into it, reading as a decal rather than as light. Moving it onto the item did not help: the
-- shape was the problem, not the position. The light, the model tint and the flare's own flame
-- are unaffected.
