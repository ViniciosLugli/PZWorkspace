--[[
    Projectile
]]

require "LugliEmergencyLights/Light"
require "LugliEmergencyLights/Physics"
require "LugliEmergencyLights/FX"
require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Projectile"

-- Lamp owns the moving light.
local OWNER = "Lugli_EmergencyLights/projectile"

local live = {}

-- Sampled on a fixed TIME interval rather than per frame, so the trail's density is the same at
-- 30 fps and 144.
local TRAIL_EVERY = 0.028
-- How long a sample lives, and it differs by what is flying.
local TRAIL_THROWN  = 1.3
local TRAIL_AERIAL  = 2.6
-- Enough samples for the LONGEST trail any projectile asks for: an aerial flare's plume lasts
-- 2.6 s at one sample every 0.028 s. A thrown stick only ever fills the first third of it.
local TRAIL_MAX = 96

-- How far an aerial flare travels along its shot vector while it hangs, in tiles, over its whole
-- life.
local DRIFT_TILES = 48.0

-- PARTICLE COUNTS AND LIFETIMES, declared UP HERE because Lua binds a name at the point it is READ,
-- not at the point the enclosing function runs.
local BURST_PUFFS = 9
local BURST_LIFE = 2.2

local SPARK_MAX = 14
local SPARK_LIFE = 1.6

-- Hand height, in world z. A thrown object leaves the hand at about 1.4 m and one z unit is a
-- whole storey, so this is a bit over half of one. It is what makes the arc asymmetric -- see
-- firstArc -- and it is also why a thrown stick no longer appears to come up out of the floor.
local RELEASE_Z = 0.55

--- Height over the WHOLE life of the flare, as a fraction of apex.
local CLIMB_EASE = 3

local function climb(k)
    if k < 0.0 then k = 0.0 elseif k > 1.0 then k = 1.0 end
    local inv = 1.0 - k
    return 1.0 - inv ^ CLIMB_EASE
end

--- How big the item's own icon is drawn in flight, in world-frame pixels. Close to the size the
--- engine draws a ground item at, because it IS the same picture.
local THROWN_SPRITE = 30.0

--- Where the canopy sits above the flare, in z, and how wide it is drawn.
local CHUTE_LIFT = 0.38

--- WIDE ENOUGH TO READ AS A CANOPY. At 62 it was a small disc with a clear gap above a much
--- larger glow, which is a balloon; a parachute is wider than the thing it is carrying.
local CHUTE_SIZE = 96.0

--- The parachute's swing: how fast, and how far. Radians per second and tiles.
local SWING_RATE = 0.55
local SWING_TILES = 0.85

--- How far up a fired flare still is when it burns out, in z units.
local BURNOUT_HEIGHT = 1.9

--- The height profile of a fired flare, as a fraction of its apex.
local function heightAt(p, t)
    local tr = p.travelFrac
    if t < tr then
        return climb(t / tr)
    end
    local k = (t - tr) / (1.0 - tr)
    if k > 1.0 then k = 1.0 end
    local e = p.endFrac or 0.15
    return 1.0 - (1.0 - e) * (k ^ 1.15)
end

--- How far the flare has swung out from under its canopy, in tiles.
local function swingAt(p, t)
    if t < p.travelFrac then return 0.0, 0.0 end
    local since = p.elapsed - p.travelFrac * p.flight
    if since < 0.0 then since = 0.0 end
    local k = (t - p.travelFrac) / (1.0 - p.travelFrac)
    local decay = 0.35 + 0.65 * math.exp(-k * 2.2)
    local a = math.sin(since * SWING_RATE * (p.swingRate or 1.0))
              * SWING_TILES * decay * (p.swingDir or 1.0)
    -- Perpendicular to the shot, so the swing crosses the direction of travel rather than
    -- fighting the wind drift along it.
    return p.perpX * a, p.perpY * a
end

--- A THROWN object, which does land -- and then bounces, twice, losing most of its energy each time
--- before settling.
-- The four-hop closed-form profile that used to live here -- firstArc, ballistic, HOPS, KICKS and
-- rollKicks -- is gone with the throw it served.

--- The launch angle of a throw, in degrees: a base, and how much it opens up with distance.
local THROW_SPEED_NOISE = 0.055
local THROW_ANGLE_NOISE = 0.035

--- A thrown object that has not settled by now is wedged in geometry the collision tests disagree
--- about, and must be landed rather than left flying.
local THROW_TIMEOUT = 12.0

--- How much a contact varies from throw to throw.
local BOUNCE_NOISE = 0.15

--- One correction for the one thing the launch solver does not model: air drag.
local DRAG_MAKEUP = 1.02

--- Trail sampling for a thrown item: one sample per this many tiles travelled.
local THROW_TRAIL_STEP = 0.30

--- A symmetric random offset, or zero when no RNG is available.
local function rollBurst()
    local rnd = M.rand
    return {
        -- Staggered over the first third of a second: a burst is not instantaneous, it billows.
        born = rnd(0.0, 0.30),
        vx = rnd(-0.5, 0.5),
        vy = rnd(-0.5, 0.5),
        -- Mostly upward. Hot gas rises, and a puff that only spread sideways read as a dust ring.
        vz = rnd(0.10, 0.42),
        size = rnd(9.0, 17.0),
        spin = rnd(0.6, 1.5),
    }
end

--- @param bounce  optional { restitution, forwardRetention } for a thrown item. Omitted for a
---                 fired flare, which never touches the ground.
--- @param tag     optional name for this flight, so something else can end it: only a relayed
---                 throw carries one, and only the landing broadcast uses it. See M.endProjectile.
function M.launchProjectile(player, x0, y0, z0, x1, y1, seconds, travel, apex, r, g, b,
                            radius, onLit, onDone, thrown, bounce, windage, tex,
                            decayFamily, decayFrac, tag)
    if type(seconds) ~= "number" or seconds <= 0 then return false end

    local p = {
        x0 = x0, y0 = y0, z0 = z0,
        -- THE FLOOR THE SHOT WAS FIRED FROM, which is NOT z0 any more.
        lightZ = math.floor(z0), x1 = x1, y1 = y1,
        x = x0, y = y0, z = z0,
        r = r, g = g, b = b,
        elapsed = 0.0, flight = seconds, apex = apex,
        -- BOOST CLAMPED IN SECONDS, not as a fraction.
        travelFrac = math.max(0.2, math.min(seconds * 0.9, travel or seconds)) / seconds,
        radius = radius or 20.0,
        -- How far it slides along the shot vector over the hang, in tiles. A fifth of the shot's
        -- own length, so a long shot drifts further than a short one and the motion always looks
        -- like the throw that produced it. Zero for a thrown item, which has no hang.
        driftX = 0.0, driftY = 0.0,
        windPull = 0.0,
        -- Where the descent ENDS, as a fraction of apex: the flare burns out about two storeys
        -- up. Derived rather than authored, so a higher shot still finishes at the same height
        -- above the ground rather than at the same fraction of a taller arc.
        endFrac = 0.15,
        -- Every canopy swings differently, and two flares in the sky must not swing in step.
        -- Varied in RATE and DIRECTION rather than in phase: a phase offset is a non-zero
        -- displacement at t=0, which is exactly the jump at deployment that swingAt exists to avoid.
        swingRate = 1.0, swingDir = 1.0,
        -- Turns over the flight, scaled by how hard it was thrown: a hard throw tumbles faster
        -- than a lob. Damped away through the bounces as it loses energy.
        spin = 9.0 + math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) * 1.6,
        tumble = 1.0,
        -- Perpendicular to the throw, so a kick reads as a deflection rather than as the object
        -- arriving early or late. Filled in below once the direction is known.
        perpX = 0.0, perpY = 0.0,
        -- Where the air is going, and how much this object cares. Sampled once: a gust changing
        -- mid-flight would be more physics than anyone asked for, and re-reading the climate every
        -- frame for every projectile is not free.
        windX = 0.0, windY = 0.0, windDirX = 0.0, windDirY = 0.0, windage = 0.0,
        trail = {}, head = 0, lastSample = -1.0,
        sparks = nil,                   -- born at apex; a thrown item never gets any
        -- Which decay curve this projectile's light follows, or nil for none. Only a fired flare
        -- lives long enough for burning down to mean anything.
        decayFamily = decayFamily or (thrown and nil or "AerialFlare"),
        decayFrac = decayFrac,
        burst = nil,                    -- the launch cloud; set below for a fired flare only
        -- Where the last trail sample was taken, so the next one can be gated on having actually
        -- moved. Seeded to the launch point rather than to nil: the first sample is then measured
        -- from the muzzle instead of being accepted unconditionally.
        lastX = x0, lastY = y0,
        onLit = onLit, onDone = onDone, fired = false,
        thrown = thrown == true,
        -- WHO THIS FLIGHT IS, for the one thing that can end a flight from outside: a relayed
        -- throw, ended by the landing that this machine could not have worked out for itself.
        tag = type(tag) == "string" and tag or nil,
        slot = -1,
        -- THE ITEM'S OWN PICTURE, for drawing it in flight.
        tex = tex,
        -- ---- the integrator's state, for a thrown item ----------------------------------
        -- Velocity in tiles (and floors) per second, the accumulator, and the previous state the
        -- renderer interpolates from. A fired flare uses none of this: it is not a thrown object,
        -- it is a rocket on a scripted climb followed by a parachute descent.
        vx = 0.0, vy = 0.0, vz = 0.0, acc = 0.0, alpha = 0.0,
        px = x0, py = y0, pz = z0,
        restSteps = 0, contacts = 0, rested = false,
        -- Genuine material properties.
        restitution = 0.34, friction = 0.55,
    }
    do
        local dx, dy = x1 - x0, y1 - y0
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 0.001 then p.perpX, p.perpY = -dy / d, dx / d end

        -- Wind in TILES PER SECOND.
        local wx, wy, kph = 0.0, 0.0, 0.0
        if M.windVector ~= nil then wx, wy, kph = M.windVector() end
        local speed = kph * 0.012
        p.windX, p.windY = wx * speed, wy * speed
        -- THE BARE DIRECTION, KEPT, because the two consumers want different quantities and mixing
        -- them is a units error.
        p.windDirX, p.windDirY = wx, wy
        p.windage = windage or 0.0

        -- How many TILES of lean the wind is worth over the whole hang, for the aerial path.
        local pull = speed * 90.0 * (windage or 0.0)
        local cap = DRIFT_TILES * 0.33
        if pull > cap then pull = cap end
        p.windPull = pull
    end

    if not p.thrown then
        -- Only a LAUNCH has a muzzle burst. A thrown stick leaves the hand silently.
        p.burst = {}
        for i = 1, BURST_PUFFS do p.burst[i] = rollBurst() end
    end

    if not p.thrown then
        -- IT KEEPS TRAVELLING, and by a FIXED distance rather than a fraction of the shot.
        local dx, dy = x1 - x0, y1 - y0
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 0.001 then
            p.driftX = dx / d * DRIFT_TILES
            p.driftY = dy / d * DRIFT_TILES
        end
    end

    if not p.thrown and apex ~= nil and apex > 0.1 then
        local e = BURNOUT_HEIGHT / apex
        if e < 0.06 then e = 0.06 elseif e > 0.55 then e = 0.55 end
        p.endFrac = e
        if ZombRandFloat ~= nil then
            local okr, rate = pcall(ZombRandFloat, 0.80, 1.30)
            if okr and type(rate) == "number" then p.swingRate = rate end
            local okd, dir = pcall(ZombRandFloat, -1.0, 1.0)
            if okd and type(dir) == "number" and dir < 0.0 then p.swingDir = -1.0 end
        end
    end

    -- ---- THE THROW ITSELF, and this is where the old system and the new one differ most.
    -- The old one solved for a curve that ARRIVED at a pre-validated square at exactly t = 1.
    if p.thrown then
        local dx, dy = x1 - x0, y1 - y0
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 0.001 then dx, dy, dist = 0.0, 1.0, 1.0 end

        -- THE FIRST ARC IS AIMED SHORT, because the object keeps going after it lands.
        local ang = M.physThrowAngle(dist, M.physScreenPxPerTile(dx, dy))

        -- SOLVED FOR THE TOTAL, not for the arc.
        local rest = 0.34
        local fric = 0.55
        if bounce ~= nil then
            rest = bounce[1]
            fric = (1.0 - bounce[2]) / (1.0 + (bounce[3] or 0.0))
            if fric < 0.02 then fric = 0.02 elseif fric > 0.95 then fric = 0.95 end
        end
        -- FROM THE HAND, NOT FROM THE FLOOR.
        p.z = z0 + RELEASE_Z
        p.pz = p.z
        local vh, vv = M.physSolveThrow(dist * DRAG_MAKEUP, ang, RELEASE_Z, rest, fric)

        local vary = 1.0 + M.jitter(THROW_SPEED_NOISE)
        local bearing = math.atan2(dy, dx) + M.jitter(THROW_ANGLE_NOISE)
        p.vx = math.cos(bearing) * vh * vary
        p.vy = math.sin(bearing) * vh * vary
        p.vz = vv * vary

        if bounce ~= nil then
            p.restitution = bounce[1]
            -- bounceF was authored as how much horizontal speed SURVIVES a contact, so the friction
            -- the integrator wants is its complement.
            p.friction = (1.0 - bounce[2]) / (1.0 + (bounce[3] or 0.0))
        end
        p.restitution = p.restitution * (1.0 + M.jitter(BOUNCE_NOISE))
        p.friction = p.friction * (1.0 + M.jitter(BOUNCE_NOISE))
        -- Bounded so a family keeps its character: a flare stays dead, a glow stick stays lively.
        if p.restitution < 0.05 then p.restitution = 0.05
        elseif p.restitution > 0.75 then p.restitution = 0.75 end
        if p.friction < 0.02 then p.friction = 0.02 end
        if p.friction > 0.95 then p.friction = 0.95 end
    end

    -- ---- THE TRAVELLING LIGHT ------------------------------------------------------------------
    -- The same world light the hand and the floor use, so a thrown item does not change
    -- renderer in mid-air and the two handovers are nothing at all.
    p.slot = M.lampAcquire(OWNER)
    if p.slot < 0 then
        M.defect(PART, "no free light slot; flare flies without its own light")
    end
    live[#live + 1] = p
    return true
end

--- SPARKS, ONCE IT IS HANGING.
-- THE MUZZLE BURST.

--- One ember.
local function rollSpark(p, stagger)
    local rnd = M.rand
    return {
        born = p.elapsed + (stagger and rnd(0.0, SPARK_LIFE) or rnd(0.0, SPARK_LIFE * 0.12)),
        vx = rnd(-0.28, 0.28),
        vy = rnd(-0.28, 0.28),
        -- Always downward: an ember that has left the flame is falling.
        vz = rnd(-0.55, -0.22),
        size = rnd(2.0, 4.5),
    }
end

local function pushTrail(p)
    p.head = p.head + 1
    local i = ((p.head - 1) % TRAIL_MAX) + 1
    local s = p.trail[i]
    if s == nil then
        s = {}
        p.trail[i] = s
    end
    s.x, s.y, s.z, s.at = p.x, p.y, p.z, p.elapsed
end

local function release(p)
    if p.slot >= 0 then
        pcall(M.lampRelease, p.slot)
        p.slot = -1
    end
end

--- How far below a ceiling the flare is stopped, in z units.
local CEILING_CLEAR = 0.15

--- Restitution and friction for a flare that has struck a roof and is coming back down.
local RICOCHET_BOUNCE = 0.22
local RICOCHET_FRICTION = 0.62

--- How fast it is still travelling along the shot's bearing when it strikes, in tiles per second,
--- and how hard the roof throws it back down, in z per second. Deliberately modest.
local RICOCHET_SPEED = 2.4
local RICOCHET_DROP = 1.6

--- Fired UP, hit a roof, now falling. Hands the flare to the real integrator.
local function ricochet(p, ceilLevel)
    p.ricochet = true
    p.thrown = true

    p.z = ceilLevel - CEILING_CLEAR
    p.px, p.py, p.pz = p.x, p.y, p.z
    p.acc = 0.0
    p.alpha = 0.0

    local dx, dy = (p.x1 or p.x) - p.x0, (p.y1 or p.y) - p.y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1.0e-6 then dx, dy, len = 0.0, 1.0, 1.0 end
    local speed = RICOCHET_SPEED
    p.vx, p.vy = dx / len * speed, dy / len * speed
    p.vz = -RICOCHET_DROP

    p.restitution = RICOCHET_BOUNCE
    p.friction = RICOCHET_FRICTION
    p.contacts = 0
    p.restSteps = 0
    p.lastX, p.lastY = p.x, p.y

    -- THE PAYLOAD IS DELIVERED HERE, and it has to be, because this is the last moment anything
    -- can.
    if not p.fired and type(p.onLit) == "function" then pcall(p.onLit, false) end

    -- The canopy never deployed and never will: it was struck on the way up. Clearing the embers
    -- too, because they are authored as a shower falling AWAY from a flare hanging above the map.
    p.fired = true
    p.sparks = nil

    M.debug(PART, "flare struck a ceiling at level " .. tostring(ceilLevel)
                .. " over " .. string.format("%.1f,%.1f", p.x, p.y)
                .. "; falling and will burn where it lands")
end

--- A ricocheted flare has stopped moving. Burn where it lies, for whatever life it has left.
local function landRicochet(p)
    if not p.ricochet or M.addTimedCluster == nil then return end

    local left = (p.flight or 0.0) - p.elapsed
    if left <= 0.25 then return end

    -- SHADED, AND MARKED AS A FLARE, so the frame it comes to rest looks like the frame before it.
    local frac = 1.0 - p.elapsed / p.flight
    if frac < 0.0 then frac = 0.0 elseif frac > 1.0 then frac = 1.0 end
    local fam = p.decayFamily
    local x, y, z = math.floor(p.x), math.floor(p.y), math.floor(p.z)
    pcall(M.addTimedCluster, x, y, z,
          M.shade(p.r, frac, fam), M.shade(p.g, frac, fam), M.shade(p.b, frac, fam),
          p.radius, left, M.SND_FLARE_BURN or nil)

    M.debug(PART, "ricocheted flare came to rest at " .. tostring(x) .. "," .. tostring(y)
                .. "," .. tostring(z) .. " with " .. string.format("%.1f", left) .. "s left")
end

--- A fired flare's drawn position, interpolated between the tick that set it and the next.
function M.aerialRenderPos(p)
    if p.px == nil or p.stepAt == nil or type(p.stepDt) ~= "number" or p.stepDt <= 0.0 then
        return p.x, p.y, p.z
    end

    local now = getTimestampMs ~= nil and getTimestampMs() or nil
    if now == nil then return p.x, p.y, p.z end

    local a = ((now - p.stepAt) / 1000.0) / p.stepDt
    if a < 0.0 then a = 0.0 elseif a > 1.0 then a = 1.0 end

    return p.px + (p.x - p.px) * a,
           p.py + (p.y - p.py) * a,
           p.pz + (p.z - p.pz) * a
end

--- One projectile, one step. Returns true when it has finished and should be removed.
local function step(p, dt)
    p.elapsed = p.elapsed + dt

    -- ---- A THROWN OBJECT IS SIMULATED, NOT ANIMATED --------------------------------------
    -- It finishes when the world stops it rather than when a clock runs out, so there is no `t` in
    -- this branch at all.
    if p.thrown then
        local done = M.physAdvance(p, dt)
        if p.peakZ == nil or p.z > p.peakZ then p.peakZ = p.z end

        -- THE LIGHT FOLLOWS THE OBJECT'S STOREY on this branch, unlike the scripted climb.
        p.lightZ = math.floor(p.z)

        -- The tumble is driven by real contacts now.
        local damp = p.restitution ^ (p.contacts or 0)
        p.tumble = 1.0 - (0.28 * damp) * math.abs(math.cos(p.spin * p.elapsed))

        local dx = p.x - p.lastX
        local dy = p.y - p.lastY
        if dx * dx + dy * dy >= THROW_TRAIL_STEP * THROW_TRAIL_STEP then
            p.lastX, p.lastY = p.x, p.y
            pushTrail(p)
        end

        if done or p.elapsed > THROW_TIMEOUT then return true end
        return false
    end

    local t = p.elapsed / p.flight

    if t >= 1.0 then
        return true
    else
        -- THE PAYLOAD FIRES AT THE TOP OF THE CLIMB, once.
        if not p.fired and t >= p.travelFrac then
            p.fired = true
            -- The embers start when the climb ends, for the same reason the trail stops there.
            if not p.thrown then
                p.sparks = {}
                for i = 1, SPARK_MAX do p.sparks[i] = rollSpark(p, true) end
            end
            -- TRUE: it reached altitude. ricochet passes false for the one that did not.
            if type(p.onLit) == "function" then pcall(p.onLit, true) end
        end
        -- Evaluated fresh from `elapsed` rather than integrated per frame: immune to float drift
        -- and to an irregular frame, and correct after a stall.
        p.px, p.py, p.pz = p.x, p.y, p.z
        p.stepDt = dt
        p.stepAt = getTimestampMs ~= nil and getTimestampMs() or nil

        local travel = climb(t / p.travelFrac)
        p.x = p.x0 + (p.x1 - p.x0) * travel
        p.y = p.y0 + (p.y1 - p.y0) * travel
        p.z = p.z0 + p.apex * heightAt(p, t)

        -- THE CEILING, and it is asked about from the flare's own level rather than the shooter's.
        if not p.thrown and not p.ricochet and p.z > (p.zPrev or p.z0) then
            local was = p.zPrev or p.z0
            local ceil = M.physCeilingAbove(math.floor(p.x), math.floor(p.y), math.floor(was))
            if ceil ~= nil and was < ceil and p.z >= ceil - CEILING_CLEAR then
                ricochet(p, ceil)
            end
        end
        p.zPrev = p.z

        -- AND IT KEEPS DRIFTING, along the direction it was fired.
        if not p.thrown and t > p.travelFrac then
            -- IT LEAVES THE CLIMB AT SPEED AND SLOWS, rather than crawling at a constant rate.
            local d = climb((t - p.travelFrac) / (1.0 - p.travelFrac))
            -- The shot's own momentum, plus the air.
            local wpull = p.windPull
            p.x = p.x + (p.driftX + p.windDirX * wpull) * d
            p.y = p.y + (p.driftY + p.windDirY * wpull) * d

            -- AND IT SWINGS UNDER ITS CANOPY.
            local sx, sy = swingAt(p, t)
            p.x = p.x + sx
            p.y = p.y + sy
        end

        -- THE EMBERS ARE RECYCLED HERE, not in draw.
        if p.sparks ~= nil then
            for i = 1, SPARK_MAX do
                local sp = p.sparks[i]
                if sp ~= nil and p.elapsed - sp.born >= SPARK_LIFE then
                    p.sparks[i] = rollSpark(p, false)
                end
            end
        end

        -- THE LAUNCH CLOUD IS OVER. Dropped rather than left in place: every puff is born within
        -- BURST_LIFE of the shot, so past that the table can only ever produce nine no-op iterations
        -- a frame -- for the remaining five minutes of a flare's life.
        if p.burst ~= nil and p.elapsed > BURST_LIFE * 2.0 then p.burst = nil end

        -- SAMPLED BY DISTANCE, NOT ONLY BY TIME.
        if p.elapsed - p.lastSample >= TRAIL_EVERY then
            local mdx, mdy = p.x - p.lastX, p.y - p.lastY
            local moved2 = mdx * mdx + mdy * mdy
            -- A thrown stick covers its whole arc in about a second and must not be gated as hard
            -- as a flare that hangs for minutes.
            local need = p.thrown and 0.0009 or 0.0025
            local trailing = p.thrown or t < p.travelFrac
            if not p.thrown and t < p.travelFrac * 0.5 then need = need * 0.25 end
            if trailing and moved2 >= need then
                p.lastSample = p.elapsed
                p.lastX, p.lastY = p.x, p.y
                pushTrail(p)
            end
        end

        -- ONE LIGHT, AND IT IS BIG.
    end
    return false
end

--- Move every live projectile's light. On OnTick, so a paused game does not move it.
local function submitLights()
    if #live == 0 then return end
    for i = 1, #live do
        local p = live[i]
        if p.slot ~= nil and p.slot >= 0 then
            -- p.lightZ, not p.z0: see the note where it is set.
            local frac = p.decayFrac
            if frac == nil then
                frac = 1.0 - p.elapsed / p.flight
                if frac < 0.0 then frac = 0.0 elseif frac > 1.0 then frac = 1.0 end
            end
            local fam = p.decayFamily
            -- THE SAME NUMBERS THE GROUND LIGHT WILL USE the instant it lands, through the same
            -- shading function, so the handover is invisible by construction rather than by two
            -- sets of constants happening to agree.
            local cr = M.shade(p.r, frac, fam)
            local cg = M.shade(p.g, frac, fam)
            local cb = M.shade(p.b, frac, fam)
            -- ROUNDED TO THE NEAREST TILE, not the one it happens to be inside.
            M.lampSet(p.slot, M.lightTile(p.x), M.lightTile(p.y), p.lightZ,
                      cr, cg, cb, p.radius)
        end
    end
end

--- Advance every flare. OnTick, so a paused game does not fly them.
local function advance()
    if #live == 0 then return end

    -- Belt and braces.
    if isGamePaused ~= nil and isGamePaused() then return end

    -- getTimeDelta is 1/60 at normal speed and scales with the game's own speed controls, so a
    -- fast-forwarded flare flies faster, as it should. It is framerate-independent by
    -- construction. NOT the wall clock, which would ignore game speed entirely.
    local dt = M.frameDelta()

    for i = #live, 1, -1 do
        -- CAUGHT PER PROJECTILE, so one bad flare cannot take the whole system with it.
        local p = live[i]
        local okp, doneOrErr = pcall(step, p, dt)
        if not okp then
            table.remove(live, i)
            -- LANDED FIRST, RELEASED SECOND, exactly as the success path below, and with the
            -- position it actually reached.
            landRicochet(p)
            if type(p.onDone) == "function" then
                pcall(p.onDone, p.x, p.y, p.z, p)
            end
            release(p)
            M.defect(PART, "projectile dropped after: " .. tostring(doneOrErr))
        elseif doneOrErr == true then
            table.remove(live, i)

            -- THE HANDOVER, AND ITS ORDER IS THE POINT.
            landRicochet(p)
            if type(p.onDone) == "function" then
                -- The record goes with the position, because the RESTING POSE is read off the
                -- contact that ended the flight -- how fast it was still going, and whether the
                -- last thing it touched was a wall. That is information only the integrator has.
                pcall(p.onDone, p.x, p.y, p.z, p)
            end
            release(p)
        end
    end
end

--- Draw every flare. OnPostRender, and NOTHING here may change state.
local function draw()
    if #live == 0 then return end
    if ISCoordConversion == nil or getRenderer == nil or getTexture == nil then return end

    local core = M.fxTex("LugliEL_FXCore")
    local glow = M.fxTex("LugliEL_FXGlow")
    -- The rest of the vocabulary, cached by the FX part. Each may be nil if the world is not up
    -- yet, and every draw below is guarded, so a missing one costs a feature rather than the pass.
    local streak = M.fxTex("LugliEL_FXStreak")
    local ribbon = M.fxTex("LugliEL_FXRibbon")
    local corona = M.fxTex("LugliEL_FXFlare")
    local chute = M.fxTex("LugliEL_FXChute")
    local ring = M.fxTex("LugliEL_FXRing")
    if core == nil or glow == nil then return end
    local R = getRenderer()

    -- ADDITIVE, or none of this is a glow.
    M.fxAdditive(R, true)

    -- THE WHOLE BODY IS GUARDED, and the reason is the line after it rather than the body itself.
    local vpIdx, vpZoom = M.fxViewport(getPlayer ~= nil and getPlayer() or nil)

    pcall(function()
    for n = 1, #live do
        local p = live[n]

        -- WHERE THIS PROJECTILE IS DRAWN, resolved ONCE and used by everything below it.
        local dx, dy, dz = p.x, p.y, p.z
        if p.thrown then
            dx, dy, dz = M.physRenderPos(p)
        else
            dx, dy, dz = M.aerialRenderPos(p)
        end
        local hx, hy = M.fxScreen(vpIdx, vpZoom, dx, dy, dz)

        -- THE TRAIL IS FIRE TURNING INTO SMOKE, and it is one draw per sample rather than two
        -- passes, because the whole difference between them is colour, size and where they sit.
        local nTrail = p.head
        if nTrail > TRAIL_MAX then nTrail = TRAIL_MAX end
        for i = 1, nTrail do
            local s = p.trail[i]
            if s ~= nil then
                local age = p.elapsed - s.at
                local k = 1.0 - age / (p.thrown and TRAIL_THROWN or TRAIL_AERIAL)
                if k > 0.0 then
                    -- Smoke rises, faster for a flare in open air than for a stick tumbling along
                    -- the ground. In z units, so it is a world offset rather than a screen one.
                    local rise = age * (p.thrown and 0.05 or 0.16)
                    local blow = age * 1.4
                    local sx, sy = M.fxScreen(vpIdx, vpZoom, s.x + p.windX * blow,
                                                              s.y + p.windY * blow,
                                                              s.z + rise)

                    -- No zoom division. OnPostRender draws in the WORLD frame, whose space is
                    -- already screen*zoom, so a fixed size scales with the world the way a world
                    local base = p.thrown and 12.0 or 26.0
                    local grow = p.thrown and 1.15 or 2.30
                    local w = base * (0.55 + grow * (1.0 - k))

                    -- hot -> the flare's own colour -> grey. Two straight lerps either side of
                    -- k = 0.72, which is about a third of a second of "still burning" at the
                    -- head before it starts cooling.
                    local cr, cg, cb
                    if k > 0.72 then
                        local h = (k - 0.72) / 0.28          -- 1 at the head, 0 at the knee
                        cr = p.r + (1.0 - p.r) * h
                        cg = p.g + (1.0 - p.g) * h
                        cb = p.b + (1.0 - p.b) * h
                    else
                        local h = k / 0.72                   -- 1 at the knee, 0 at the tail
                        local grey = 0.42
                        cr = grey + (p.r - grey) * h
                        cg = grey + (p.g - grey) * h
                        cb = grey + (p.b - grey) * h
                    end

                    -- Smoke is dimmer than fire on an ADDITIVE pass, or the tail reads as a
                    -- second light source hanging in the air behind the flare.
                    local a = k * k * (0.35 + 0.65 * k)

                    -- THE HEAD IS FIRE AND THE TAIL IS SMOKE, so they are drawn with different
                    -- textures: a soft glow at the hot end, because fire has no edges.
                    if k > 0.72 then
                        M.fxRect(R, glow, sx, sy, w, w, cr, cg, cb, a)
                    else
                        local puff = M.fxSmoke(i, math.floor(s.at * 7.0))
                        local spin = (i * 0.7 + s.at * 0.55) * (1.0 - k) * 1.4
                        M.fxQuad(R, puff, sx, sy, w * 1.25, w * 1.25, spin, cr, cg, cb, a * 0.85)
                    end
                end
            end
        end

        -- THE LAUNCH CLOUD, drawn FIRST so the flare and its trail sit over it.
        if p.burst ~= nil then
            for i = 1, BURST_PUFFS do
                local pf = p.burst[i]
                local age = p.elapsed - pf.born
                if age > 0.0 and age < BURST_LIFE then
                    local k = age / BURST_LIFE
                    -- Expands fast and then slows, the way a gas cloud does: most of the growth
                    -- happens in the first moments and it merely drifts after that.
                    local grow = 1.0 - (1.0 - k) * (1.0 - k)
                    local bx = p.x0 + pf.vx * grow * pf.spin + p.windX * age * 1.2
                    local by = p.y0 + pf.vy * grow * pf.spin + p.windY * age * 1.2
                    local bz = p.z0 + pf.vz * grow
                    local sx, sy = M.fxScreen(vpIdx, vpZoom, bx, by, bz)
                    local w = pf.size * (0.45 + 1.55 * grow)
                    -- Lit by the launch at first, then plain grey smoke. Alpha falls off fast so
                    -- the cloud thins rather than fading as one flat shape.
                    local hot = (1.0 - k) * (1.0 - k)
                    local grey = 0.40
                    local cr = grey + (p.r - grey) * hot
                    local cg = grey + (p.g - grey) * hot
                    local cb = grey + (p.b - grey) * hot
                    local a = (1.0 - k) * (1.0 - k) * 0.40
                    M.fxRect(R, glow, sx, sy, w, w, cr, cg, cb, a)
                end
            end
        end

        -- THE EMBERS.
        if p.sparks ~= nil then
            for i = 1, SPARK_MAX do
                local sp = p.sparks[i]
                if sp ~= nil then
                    local age = p.elapsed - sp.born
                    if age >= 0.0 and age < SPARK_LIFE then
                        local k = age / SPARK_LIFE
                        -- Gravity on the fall, so an ember accelerates downward rather than
                        -- sliding along a line.
                        local ex = dx + sp.vx * age
                        local ey = dy + sp.vy * age
                        local ez = dz + sp.vz * age - 0.35 * age * age
                        local sx, sy = M.fxScreen(vpIdx, vpZoom, ex, ey, ez)
                        -- Hot at birth, cooling to the flare's own colour as it falls out.
                        local hot = 1.0 - k
                        local cr = p.r + (1.0 - p.r) * hot
                        local cg = p.g + (1.0 - p.g) * hot
                        local cb = p.b + (1.0 - p.b) * hot
                        local w = sp.size * (1.0 - 0.45 * k)
                        local a = (1.0 - k) * (1.0 - k)

                        -- A STREAK, POINTED ALONG ITS OWN VELOCITY. An ember drawn as a dot is a
                        -- dot however fast it is falling; drawn as a tapered streak along the way
                        local bx = dx + sp.vx * (age - 0.09)
                        local by = dy + sp.vy * (age - 0.09)
                        local bz = dz + sp.vz * (age - 0.09) - 0.35 * (age - 0.09) * (age - 0.09)
                        local tx2, ty2 = M.fxScreen(vpIdx, vpZoom, bx, by, bz)
                        M.fxBeam(R, streak, sx, sy, tx2, ty2, w * 1.5, cr, cg, cb, a)
                        M.fxRect(R, core, sx, sy, w * 0.8, w * 0.8, cr, cg, cb, a)
                    end
                end
            end
        end

        -- A thrown stick is a small object a few tiles away; a flare is a burning charge in the
        -- sky. Drawing them at one size made whichever was wrong look absurd.
        local halo = p.thrown and 30.0 or 88.0
        local head = p.thrown and 11.0 or 26.0
        if p.thrown then
            halo = halo * p.tumble
            head = head * p.tumble
        end
        -- AND THE SPRITE DIMS WITH THE LIGHT. A flare whose pool of light is fading while the
        -- flare itself stays blinding reads as a bug in the lighting rather than as a flare going
        -- out. Only the fired one: a thrown item is in the air for a second and cannot fade.
        local dim = 1.0
        if not p.thrown and p.decayFamily ~= nil and M.decayFor ~= nil then
            local fr = 1.0 - p.elapsed / p.flight
            if fr < 0.0 then fr = 0.0 elseif fr > 1.0 then fr = 1.0 end
            dim = M.decayFor(p.decayFamily, fr)
        end

        if p.thrown then
            -- ---- A THROWN OBJECT IS A THING, NOT A LIGHT --------------------------------------
            -- It used to be a white dot inside a coloured halo, and at any size that reads as
            -- a bright circle rather than as the object you threw.
            local damp = p.restitution ^ (p.contacts or 0)
            local spin = p.elapsed * p.spin * 0.5 * damp

            -- A soft pool of its own colour first, well under the sprite, so it reads as lit
            -- rather than as a lamp with an item stuck to it.
            M.fxRect(R, glow, hx, hy, halo, halo, p.r, p.g, p.b, 0.30)

            if p.tex ~= nil then
                M.fxAdditive(R, false)
                M.fxQuad(R, p.tex, hx, hy, THROWN_SPRITE, THROWN_SPRITE, spin, 1.0, 1.0, 1.0, 1.0)
                M.fxAdditive(R, true)
            else
                -- No icon: a small coloured point rather than the old white one, so a missing
                -- texture degrades to something the right colour instead of the wrong shape.
                M.fxRect(R, core, hx, hy, head, head, p.r, p.g, p.b, 0.9)
            end
        else
            -- ---- THE CANOPY ------------------------------------------------------------------
            -- Only once the charge has deployed: during the boost the flare is still a rocket.
            if p.fired and chute ~= nil then
                local since = p.elapsed - p.travelFrac * p.flight
                local open = since / 1.1
                if open > 1.0 then open = 1.0 end
                if open > 0.0 then
                    local ease = open * open * (3.0 - 2.0 * open)
                    -- THE SAME CLOCK AND THE SAME PENDULUM AS THE FLARE UNDERNEATH.
                    local lean = math.sin(since * SWING_RATE * (p.swingRate or 1.0) + 0.6)
                                 * 0.10 * (p.swingDir or 1.0) * ease
                    local cxw, cyw = M.fxScreen(vpIdx, vpZoom, dx + p.perpX * lean,
                                                                dy + p.perpY * lean,
                                                                dz + CHUTE_LIFT)
                    local cw = CHUTE_SIZE * ease

                    -- NOT ADDITIVE, and that is the whole fix.
                    M.fxAdditive(R, false)
                    M.fxQuad(R, chute, cxw, cyw, cw, cw * 0.92, lean * 1.6,
                             0.20 + p.r * 0.80, 0.20 + p.g * 0.80, 0.20 + p.b * 0.80,
                             0.72 * dim * ease)

                    -- The shroud lines, as one thin tapered band. Four would be more correct and,
                    -- at this zoom, would be noise. On the same pass as the canopy: a bright line
                    -- is what made the two read as a balloon on a string.
                    M.fxTaper(R, ribbon, cxw, cyw, hx, hy, 1.4, 0.7,
                              0.30 + p.r * 0.55, 0.30 + p.g * 0.55, 0.30 + p.b * 0.55,
                              0.45 * dim * ease)
                    M.fxAdditive(R, true)

                    -- The deployment snap: one expanding ring, because the flare goes from
                    -- climbing to hanging in about a frame and without a punctuation mark that
                    -- change reads as a hitch.
                    if open < 0.45 then
                        local rk = open / 0.45
                        local rw = 40.0 + 110.0 * rk
                        M.fxQuad(R, ring, cxw, cyw, rw, rw * 0.62, 0.0,
                                 1.0, 1.0, 1.0, (1.0 - rk) * 0.40)
                    end
                end
            end

            -- ---- THE FLARE ITSELF ------------------------------------------------------------
            -- THE CORONA IS THE BODY OF IT, not a garnish on top of a disc.
            if corona ~= nil then
                M.fxQuad(R, corona, hx, hy, halo * 1.9, halo * 1.9, p.elapsed * 0.13,
                         p.r, p.g, p.b, 0.55 * dim)
            end
            M.fxRect(R, glow, hx, hy, halo * 0.44, halo * 0.44, p.r, p.g, p.b, 0.30 * dim)
            M.fxRect(R, core, hx, hy, head * 0.4, head * 0.4, 1.0, 1.0, 1.0, 0.9 * dim)
        end
    end
    end)

    M.fxAdditive(R, false)
end

--- End the flight carrying this tag, wherever it has got to. True when one was ended.
---
--- ONLY A RELAYED THROW HAS A TAG, and that is the whole safety of this: a replay is
--- visual-only, with no owner, no item and NO onDone, so ending it releases a light and nothing
--- else. onDone is deliberately not called -- it is what LANDS AN ITEM, and the only projectile
--- that has one is the thrower's own, which has already run it and retired by the time any
--- landing message could arrive. Calling it here could only ever put a second item on the ground.
function M.endProjectile(tag)
    if type(tag) ~= "string" then return false end
    for i = #live, 1, -1 do
        local p = live[i]
        if p ~= nil and p.tag == tag then
            table.remove(live, i)
            release(p)
            return true
        end
    end
    return false
end

--- Every projectile currently in the air, with its family and where it is.
function M.eachProjectile(fn)
    for i = 1, #live do
        local p = live[i]
        if p ~= nil then fn(p.x, p.y, p.lightZ, p.decayFamily, p.slot) end
    end
end

function M.dropProjectiles()
    -- onDone IS CALLED, not skipped.
    local dying = live
    live = {}
    for i = 1, #dying do
        local p = dying[i]
        -- Same order as every other exit, and with the position it actually reached: a teardown
        -- landing is still a landing, and the pose and the sub-tile offset are read from these.
        if type(p.onDone) == "function" then
            pcall(p.onDone, p.x, p.y, p.z, p)
        end
        release(p)
    end
end

-- Both on OnTick. A paused game must not fly a flare forward, and neither light minds the pause:
M.addTicker(PART, 0, submitLights)
local h = M.addTicker(PART, 0, advance)
M.addHandler(PART, "OnPostRender", draw)
M.addTeardown(PART, function() M.dropProjectiles() end)

-- A MOVING LIGHT IS THE EXPENSIVE ONE. Every tile step is a remove and an add, and each of those
-- bumps Core.dirtyGlobalLightsCount, so a flare in flight is the only thing in this mod that
-- rebuilds its light rather than merely recolouring it. The position is already quantised to tiles
-- by M.lightTile, which is what keeps that to a handful a second rather than one per frame.
M.addHandler(PART, "OnGameStart", function()
    M.log(PART, "thrown and fired lights travel with the object")
end)

if h ~= nil then M.status(PART, true) end
