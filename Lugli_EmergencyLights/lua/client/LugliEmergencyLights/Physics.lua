--[[
    Physics
]]

require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Physics"

-- ---------------------------------------------------------------------------------------------
-- Constants. Every one of these is either derived or a measured property of a material, and the
-- comment says which, because a number nobody can re-derive is a number nobody dares change.
-- ---------------------------------------------------------------------------------------------

--- Metres per z unit. A Project Zomboid storey. Used only to derive gravity, but stated
--- separately so the derivation is legible rather than a magic 4.09.
local METRES_PER_LEVEL = 2.4

--- z units per second squared. 9.81 m/s^2 expressed in floors.
local GRAVITY = 9.81 / METRES_PER_LEVEL

--- The fixed simulation step. 120 Hz rather than 60 because a thrown stick crosses a tile in about
--- 55 ms and a step longer than that can tunnel straight through a wall between two samples.
local SUBSTEP = 1.0 / 120.0

--- How many substeps one frame may run.
local MAX_SUBSTEPS = 8

--- Below this speed, in tiles per second, a contact counts as still.
local REST_SPEED = 0.30

--- And it has to stay still for this many consecutive substeps. One frame of slowness is a stick
--- at the top of a bounce, not a stick at rest.
local REST_STEPS = 8

--- Air drag, per second, as a fraction of speed. Small: these are light objects thrown a few
--- tiles, not projectiles, and heavy drag makes a throw look like it is happening underwater.
local DRAG = 0.22

--- Heights, in z units, at which a barrier stops mattering.
local WALL_HEIGHT = 1.0e9

--- A tall fence is one you CLIMB: chain link, a high garden fence, a wrought-iron railing. About
--- a storey, so clearing it takes a deliberate lob rather than an ordinary flat throw.
local TALL_HOP_HEIGHT = 1.00

--- A low fence is one you VAULT: a picket, a low wall, a hedge. Under a metre, so any throw with
--- an arc on it goes over and only something rolling along the ground is stopped.
local LOW_HOP_HEIGHT = 0.35

--- Surface-offset units per z level. The engine's own conversion for FURNITURE HEIGHTS:
local SURFACE_UNITS_PER_LEVEL = 96.0

--- How far below a ceiling an object is placed when it strikes one, in z units.
local CEILING_GAP = 0.02

--- How much of the vertical speed survives hitting a ceiling.
local CEILING_BOUNCE = 0.25

--- Below this closing speed, an object is not arriving, it is lying there. The line between a
--- bounce and a slide, in z units per second.
local IMPACT_SPEED = 0.45

--- A bounce that would come back slower than this is not a bounce. Without a floor here an object
--- jitters against the ground forever at a millimetre a step and never reaches rest.
local BOUNCE_FLOOR = 0.35

--- How fast sliding friction bleeds speed, per second, per unit of the family's friction.
local SLIDE_RATE = 3.2

--- How strongly moving air couples to an object, per second, per unit of windage.
local WIND_COUPLE = 0.9

--- How much of a contact's energy goes into a random direction.
local CONTACT_SCATTER = 0.16

-- ---------------------------------------------------------------------------------------------
-- Engine access. Every call is wrapped, because the offline suite runs this file against a stubbed
-- world and because a square can vanish under a projectile mid-flight.
-- ---------------------------------------------------------------------------------------------

--- The square at these integer coordinates, or nil.
local function gridSquare(x, y, z)
    return getCell():getGridSquare(x, y, z)
end

local function squareAt(x, y, z)
    if getCell == nil then return nil end
    local ok, sq = pcall(gridSquare, x, y, z)
    if not ok then return nil end
    return sq
end

--- Call a method on a Java object and return nil rather than throwing.
local function call0(obj, name) local f = obj[name] if f == nil then return nil end return f(obj) end
local function call1(obj, name, a) local f = obj[name] if f == nil then return nil end return f(obj, a) end
local function call2(obj, name, a, b) local f = obj[name] if f == nil then return nil end return f(obj, a, b) end
local function call4(obj, name, a, b, c, d)
    local f = obj[name]
    if f == nil then return nil end
    return f(obj, a, b, c, d)
end

local function try0(obj, name)
    if obj == nil then return nil end
    local ok, v = pcall(call0, obj, name)
    if not ok then return nil end
    return v
end

local function try1(obj, name, a)
    if obj == nil then return nil end
    local ok, v = pcall(call1, obj, name, a)
    if not ok then return nil end
    return v
end

local function try2(obj, name, a, b)
    if obj == nil then return nil end
    local ok, v = pcall(call2, obj, name, a, b)
    if not ok then return nil end
    return v
end

local function try4(obj, name, a, b, c, d)
    if obj == nil then return nil end
    local ok, v = pcall(call4, obj, name, a, b, c, d)
    if not ok then return nil end
    return v
end

--- Is there something to land on here? The engine's own test, and the one IsoPhysicsObject uses.
--- solidfloor, or stairs, or a sloped surface. Cached inside the engine, so this is nearly free.
local function hasFloor(sq)
    if sq == nil then return false end
    return try0(sq, "TreatAsSolidFloor") == true
end

--- The height of the surface at a point inside a square, in z units above the square's own level.
local function surfaceZ(sq, z, fx, fy)
    if sq == nil then return z end
    local best = z

    local ap = try2(sq, "getApparentZ", fx, fy)
    if type(ap) == "number" and ap > best then best = ap end

    -- FURNITURE. getSurfaceOffsetNoTable is in PIXELS at 1x texture scale, and 96 of them make one
    -- level -- the engine converts exactly this way when it snaps a dropped item to a surface.
    local objs = try0(sq, "getObjects")
    local n = objs ~= nil and try0(objs, "size") or 0
    if type(n) == "number" then
        for i = 0, n - 1 do
            local o = try1(objs, "get", i)
            if o ~= nil and try0(o, "isTableSurface") == true then
                local px = try0(o, "getSurfaceOffsetNoTable")
                if type(px) == "number" and px > 0 then
                    local h = z + px / SURFACE_UNITS_PER_LEVEL
                    if h > best then best = h end
                end
            end
        end
    end
    return best
end

--- Is an object an OPEN or broken window, which is not an obstacle at all?
local function windowIsOpen(obj)
    if obj == nil then return false end
    if try0(obj, "isDestroyed") == true then return true end
    if instanceof == nil then return false end
    if not instanceof(obj, "IsoWindow") and not instanceof(obj, "IsoThumpable") then return false end
    return try0(obj, "IsOpen") == true
end

--- The height above which a projectile clears the edge between two adjacent squares.
local function barrierHeight(a, b)
    if a == nil or b == nil then return WALL_HEIGHT end

    local obj = try1(a, "getHoppableTo", b)
    if obj == nil then obj = try1(b, "getHoppableTo", a) end
    if obj ~= nil then
        if windowIsOpen(obj) then return 0.0 end
        if try0(obj, "isTallHoppable") == true then return TALL_HOP_HEIGHT end
        if try0(obj, "isHoppable") == true then return LOW_HOP_HEIGHT end
        -- A window that is neither open nor hoppable is glass, and glass stops a glow stick.
        return WALL_HEIGHT
    end
    return WALL_HEIGHT
end

--- Is the step from square `a` into the square at (dx, dy) blocked at all?
local function edgeBlocked(a, dx, dy)
    if a == nil then return true end
    local v = try4(a, "testCollideAdjacentAdvanced", dx, dy, 0, false)
    if v == nil then return true end
    return v == true
end

--- What is under the object: the nearest square AT OR BELOW its level that has a floor.
local function support(cx, cy, fromLevel)
    local loaded = false
    -- CLAMPED AT GROUND LEVEL, and this is not defensive tidying.
    local l = fromLevel
    if l < 0 then l = 0 end
    while l >= 0 do
        local sq = squareAt(cx, cy, l)
        if sq ~= nil then
            loaded = true
            if hasFloor(sq) then return sq, l, true end
        end
        l = l - 1
    end
    return nil, nil, loaded
end

--- Is there a CEILING over this column, at or above `fromLevel + 1`? Returns the level it sits at,
--- or nil for open sky.
local function ceilingAbove(cx, cy, fromLevel)
    local l = math.floor(fromLevel) + 1
    if l < 0 then l = 0 end
    while l <= 31 do
        local sq = squareAt(cx, cy, l)
        if sq ~= nil then
            if try0(sq, "hasRainBlockingTile") == true or hasFloor(sq) then return l end
        end
        l = l + 1
    end
    return nil
end

--- The vehicle occupying a square, or nil. Single level: isIntersectingSquare bails when the
--- vehicle is not on the same floor, so the caller must floor its z before asking.
local function vehicleAt(sq)
    if sq == nil then return nil end
    return try0(sq, "getVehicleContainer")
end

M.physGravity = GRAVITY
M.physSubstep = SUBSTEP

-- PROMOTED, because the flare gun needs it too.
M.physCeilingAbove = ceilingAbove

-- ---------------------------------------------------------------------------------------------
-- The integrator
-- ---------------------------------------------------------------------------------------------

--- A small random multiplier around 1, or exactly 1 when no RNG is available.
local function contact(p, surface, h)
    p.z = surface

    local arriving = p.vz < -IMPACT_SPEED
    if arriving then
        p.contacts = (p.contacts or 0) + 1
        -- WHAT THE IMPACT WAS LIKE, kept for the resting pose.
        p.impactVX, p.impactVY, p.impactVZ = p.vx, p.vy, p.vz
        p.vz = -p.vz * p.restitution
        -- A bounce too small to see is a bounce that should not happen: without this the object
        -- jitters against the floor forever at a millimetre a step and never reaches rest.
        if p.vz < BOUNCE_FLOOR then p.vz = 0.0 end

        local keep = 1.0 - p.friction
        p.vx = p.vx * keep
        p.vy = p.vy * keep

        -- AND A REAL OBJECT IS NOT A SPHERE.
        local s = math.sqrt(p.vx * p.vx + p.vy * p.vy) * CONTACT_SCATTER
        if s > 0.0 then
            p.vx = p.vx + M.jitter(s)
            p.vy = p.vy + M.jitter(s)
        end
    else
        -- Resting on it. Kill the residual downward speed and slide.
        if p.vz < 0.0 then p.vz = 0.0 end
        local keep = 1.0 - p.friction * SLIDE_RATE * h
        if keep < 0.0 then keep = 0.0 end
        p.vx = p.vx * keep
        p.vy = p.vy * keep
    end
end

--- One fixed step. Everything about where the object goes is decided here.
local function substep(p, h)
    -- ---- forces ---------------------------------------------------------------------------
    p.vz = p.vz - GRAVITY * h

    -- ---- the air, and it acts ONCE ----------------------------------------------------------
    -- THIS USED TO BRAKE EVERY THROW TWICE.
    local d = 1.0 - DRAG * h
    if d < 0.0 then d = 0.0 end
    p.vz = p.vz * d

    local k = DRAG * h
    if k > 1.0 then k = 1.0 end

    local airX, airY = 0.0, 0.0
    if p.windX ~= nil and p.windage ~= nil and p.windage > 0.0 then
        airX = p.windX * p.windage * WIND_COUPLE
        airY = p.windY * p.windage * WIND_COUPLE
    end

    p.vx = p.vx + (airX - p.vx) * k
    p.vy = p.vy + (airY - p.vy) * k

    -- ---- where it wants to go ---------------------------------------------------------------
    local nx = p.x + p.vx * h
    local ny = p.y + p.vy * h
    local nz = p.z + p.vz * h

    local cx, cy = math.floor(p.x), math.floor(p.y)

    -- ---- what it is standing over -----------------------------------------------------------
    -- COLLISION IS RESOLVED AGAINST THE SUPPORT, not against the square at floor(z), and that is
    -- the difference between a wall you can throw over and one you cannot.
    local floorSq, floorLvl = support(cx, cy, math.floor(p.z))
    local base = floorLvl or math.floor(p.z)
    local here = floorSq or squareAt(cx, cy, base)
    local heightAbove = p.z - base

    -- ---- horizontal, one axis at a time -----------------------------------------------------
    -- SEPARATELY, and that is deliberate rather than lazy.
    local tx, ty = math.floor(nx), math.floor(ny)

    if tx ~= cx then
        local step = tx > cx and 1 or -1
        local nextSq = squareAt(cx + step, cy, base)
        if here ~= nil and edgeBlocked(here, step, 0)
            and heightAbove < barrierHeight(here, nextSq) then
            nx = cx + (step > 0 and 0.999 or 0.001)
            p.vx = -p.vx * p.restitution
            -- WHEN, as well as whether.
            p.hitWall = true
            p.wallAt = p.elapsed
            p.wallX, p.wallY = step, 0
        else
            cx = cx + step
            if nextSq ~= nil then here = nextSq end
        end
    end

    if ty ~= cy then
        local step = ty > cy and 1 or -1
        local nextSq = squareAt(cx, cy + step, base)
        if here ~= nil and edgeBlocked(here, 0, step)
            and heightAbove < barrierHeight(here, nextSq) then
            ny = cy + (step > 0 and 0.999 or 0.001)
            p.vy = -p.vy * p.restitution
            p.hitWall = true
            p.wallAt = p.elapsed
            p.wallX, p.wallY = 0, step
        else
            cy = cy + step
            if nextSq ~= nil then here = nextSq end
        end
    end

    p.x, p.y = nx, ny

    -- ---- vehicles ---------------------------------------------------------------------------
    -- A car is the one obstacle with no tile representation at all: it sits ON squares without
    -- blocking them, so every test above passes straight through it. BaseVehicle.getIntersectPoint
    if p.vehTileX ~= cx or p.vehTileY ~= cy or p.vehTileZ ~= base then
        p.vehTileX, p.vehTileY, p.vehTileZ = cx, cy, base
        p.veh = vehicleAt(squareAt(cx, cy, base))
    end
    local veh = p.veh
    if veh ~= nil and Vector3f ~= nil then
        local hit = nil
        local ok = pcall(function()
            local a = Vector3f.new(p.px or p.x, p.py or p.y, p.pz or p.z)
            local b = Vector3f.new(p.x, p.y, nz)
            hit = veh:getIntersectPoint(a, b, Vector3f.new())
        end)
        if ok and hit ~= nil then
            -- Landed on it or bounced off it. The distinction is the one the floor makes: coming
            -- down means resting, coming across means deflecting.
            local hz = try0(hit, "z")
            if type(hz) == "number" and p.vz < 0 and hz > p.z - 0.5 then
                nz = hz
                contact(p, hz, h)
            else
                p.vx = -p.vx * p.restitution
                p.vy = -p.vy * p.restitution
                -- DELIBERATELY NOT hitWall.
            end
        end
    end

    -- ---- vertical ---------------------------------------------------------------------------
    -- UPWARD FIRST, because this loop only ever looked down.
    if nz > p.z and p.vz > 0.0 then
        local ceil = ceilingAbove(cx, cy, math.floor(p.z))
        if ceil ~= nil and nz >= ceil then
            -- Just under it, not level with it: resting exactly on the boundary reads as inside
            -- the tile above and the next support() call would find that tile's floor instead.
            p.ceilHits = (p.ceilHits or 0) + 1
            nz = ceil - CEILING_GAP
            -- Damped, not reflected in full. A ceiling is masonry or plasterboard and takes most
            -- of what hits it; the horizontal component is untouched, so the object carries on
            -- along its path and drops, which is what a thrown thing striking a roof does.
            p.vz = -p.vz * CEILING_BOUNCE
            if p.z > nz then nz = p.z end
        end
    end

    p.z = nz

    -- Re-resolved after the horizontal move: it may have crossed onto a tile with a different
    -- floor, or off the edge of one entirely.
    local fSq, fLvl, fLoaded = support(cx, cy, math.floor(p.z))
    local floorZ = -1.0

    if not fLoaded then
        -- UNLOADED, not empty. Stop where it is rather than dropping it out of the world.
        p.vx, p.vy, p.vz = 0.0, 0.0, 0.0
        floorZ = p.z
        contact(p, p.z, h)
        p.stalled = true
    elseif fSq ~= nil then
        floorZ = surfaceZ(fSq, fLvl, p.x - cx, p.y - cy)
        if p.z <= floorZ then
            contact(p, floorZ, h)
        end
    else
        -- A real hole, all the way down. Zero is the hard bottom of the world, which is where
        -- IsoPhysicsObject stops one too.
        floorZ = 0.0
        if p.z <= 0.0 then
            contact(p, 0.0, h)
        end
    end

    -- ---- rest -------------------------------------------------------------------------------
    local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy + p.vz * p.vz)
    if speed < REST_SPEED and p.z <= floorZ + 0.02 then
        p.restSteps = (p.restSteps or 0) + 1
    else
        p.restSteps = 0
    end
end

--- Advance a projectile by `dt` real seconds. Returns true once it has come to rest.
function M.physAdvance(p, dt)
    if p.rested then return true end

    p.acc = (p.acc or 0.0) + dt
    local n = 0
    while p.acc >= SUBSTEP and n < MAX_SUBSTEPS do
        p.px, p.py, p.pz = p.x, p.y, p.z
        substep(p, SUBSTEP)
        p.acc = p.acc - SUBSTEP
        n = n + 1
        if (p.restSteps or 0) >= REST_STEPS then
            p.rested = true
            p.acc = 0.0
            return true
        end
    end

    -- LOST, NOT BANKED. Past the cap the remaining time is discarded rather than carried, because
    -- carrying it means the next frame owes even more and the sim never catches up -- it just runs
    -- MAX_SUBSTEPS every frame from then on while falling further behind.
    if n >= MAX_SUBSTEPS then p.acc = 0.0 end

    p.alpha = SUBSTEP > 0 and (p.acc / SUBSTEP) or 0.0
    return false
end

--- Where to draw it: the simulated state, interpolated across the leftover of the accumulator.
function M.physRenderPos(p)
    local a = p.alpha or 0.0
    local px, py, pz = p.px or p.x, p.py or p.y, p.pz or p.z
    return px + (p.x - px) * a, py + (p.y - py) * a, pz + (p.z - pz) * a
end

--- Launch velocity for a throw that should carry `dist` tiles from a release height of `h0`.
function M.physLaunch(dist, angleDeg, h0)
    local a = math.rad(angleDeg or 12.0)
    local c = math.cos(a)
    local s = math.sin(a)
    if c < 0.05 then c = 0.05 end

    local r = dist
    if r < 0.5 then r = 0.5 end
    local drop = h0 or 0.0
    if drop < 0.0 then drop = 0.0 end

    local k = r * GRAVITY / c
    local denom = 2.0 * GRAVITY * drop + 2.0 * k * s
    -- Degenerate only if both the release height and the angle are zero, which is a throw with no
    -- way to travel at all. Fall back to the flat-ground form rather than dividing by nothing.
    if denom < 1.0e-6 then
        local sin2 = math.sin(2.0 * a)
        if sin2 < 0.05 then sin2 = 0.05 end
        local v0 = math.sqrt(r * GRAVITY / sin2)
        return v0 * c, v0 * s
    end

    local v = k / math.sqrt(denom)
    return v * c, v * s
end

--- How far an object launched with (vh, vv) from height h0 will travel in TOTAL: the first arc,
--- every bounce after it, and the slide at the end.
local function travelled(vh, t)
    if DRAG < 1.0e-6 then return vh * t end
    return vh * (1.0 - math.exp(-DRAG * t)) / DRAG
end

local function carryOf(vh, vv, h0, restitution, friction)
    if vh <= 0.0 then return 0.0 end

    -- The first arc, from h0 down to the ground: time up plus time down.
    local vz = math.sqrt(vv * vv + 2.0 * GRAVITY * h0)
    local flight = (vv + vz) / GRAVITY
    local total = travelled(vh, flight)
    vh = vh * math.exp(-DRAG * flight)

    -- Then it hops, losing restitution off the vertical, friction off the horizontal at each
    -- contact, and drag off both throughout. Six is well past where BOUNCE_FLOOR ends it for
    -- every material this mod ships.
    for _ = 1, 6 do
        -- AN ARRIVAL IS ONLY AN IMPACT ABOVE IMPACT_SPEED, exactly as the integrator decides it.
        if vz <= IMPACT_SPEED then break end
        vz = vz * restitution
        vh = vh * (1.0 - friction)
        if vz < BOUNCE_FLOOR then break end
        local hop = 2.0 * vz / GRAVITY
        total = total + travelled(vh, hop)
        vh = vh * math.exp(-DRAG * hop)
        vz = vz * math.exp(-DRAG * hop)
    end

    -- And slides to a stop. Both friction and drag act per unit of time, so they simply add, and
    -- the distance is the remaining speed over their combined rate.
    local rate = friction * SLIDE_RATE + DRAG
    if rate > 0.01 then total = total + vh / rate end
    return total
end

--- The carry model, exposed so it can be held to the simulation it models.
function M.physCarryEstimate(vh, vv, h0, restitution, friction)
    return carryOf(vh, vv, h0, restitution, friction)
end

--- THE LAUNCH ANGLE, in degrees, for a throw of `dist` tiles.
local PX_PER_Z = 192.0

--- Screen pixels of travel per tile of ground travel, for a direction given in tiles.
function M.physScreenPxPerTile(dx, dy)
    local len = math.sqrt((dx or 0.0) * (dx or 0.0) + (dy or 0.0) * (dy or 0.0))
    if len < 1.0e-6 then return 71.554 end
    local ux, uy = dx / len, dy / len
    local sx = 64.0 * (ux - uy)
    local sy = 32.0 * (ux + uy)
    return math.sqrt(sx * sx + sy * sy)
end

--- The angle the throw should APPEAR to leave at, in screen degrees.
local SCREEN_ANGLE_BASE = 7.0
local SCREEN_ANGLE_PER_TILE = 0.22
local SCREEN_ANGLE_MAX = 12.0

--- The PHYSICAL launch angle, in degrees, that makes a throw of this length in this direction leave
--- the hand at the intended SCREEN angle.
function M.physThrowAngle(dist, pxPerTile)
    local screen = SCREEN_ANGLE_BASE + (dist or 0.0) * SCREEN_ANGLE_PER_TILE
    if screen > SCREEN_ANGLE_MAX then screen = SCREEN_ANGLE_MAX end

    local px = pxPerTile
    if type(px) ~= "number" or px <= 0.0 then px = 71.554 end

    return math.deg(math.atan(math.tan(math.rad(screen)) * px / PX_PER_Z))
end

--- Launch velocity for a throw whose TOTAL distance -- arc, bounces and slide together -- should be
--- `dist`.
function M.physSolveThrow(dist, angleDeg, h0, restitution, friction)
    local arc = dist * 0.7
    for _ = 1, 4 do
        local vh, vv = M.physLaunch(arc, angleDeg, h0)
        local got = carryOf(vh, vv, h0, restitution, friction)
        if got < 0.05 then break end
        arc = arc * (dist / got)
        -- BOUNDED BELOW ONLY. An arc at zero is not a throw.
        if arc < 0.4 then arc = 0.4 end
    end
    return M.physLaunch(arc, angleDeg, h0)
end

M.status(PART, true)
