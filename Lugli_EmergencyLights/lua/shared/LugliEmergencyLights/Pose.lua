--[[
    Pose
]]

require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Pose"

--- Yaw quantisation, in degrees.
local YAW_STEP = 30

--- Pitch in degrees away from standing.
local PITCH_FLAT = 90
local PITCH_LEAN = 62
local PITCH_UP = 0

--- Below this HORIZONTAL speed at the moment of impact, an object that came down steeply can settle
--- on its base rather than skidding. Tiles per second.
local UPRIGHT_SPEED = 1.4

--- And it has to have arrived steeply: the descent must be at least this many times the remaining
--- horizontal speed. A shallow fast arrival skids and lies down however heavy the object is.
local UPRIGHT_STEEP = 1.5

--- How often an object that reached the ground WITHOUT being thrown stands up, when its family can
--- stand at all.
local UPRIGHT_CHANCE = 0.25

--- Which families can stand up at all.
local CAN_STAND = { RoadFlare = true }

--- Snap a heading in radians to a whole number of YAW_STEP degrees, in 0..359.
function M.poseYaw(radians)
    local deg = 0
    if type(radians) == "number" then deg = math.deg(radians) end
    local snapped = math.floor(deg / YAW_STEP + 0.5) * YAW_STEP
    snapped = snapped % 360
    if snapped < 0 then snapped = snapped + 360 end
    return snapped
end

--- Choose a resting pose. Returns pitch, yaw, and the name of the pose for the log.
function M.poseFor(family, ctx)
    ctx = ctx or {}

    -- The IMPACT velocity where there is one, falling back to whatever was given. An object at
    -- rest has no velocity to read a pose from.
    local vx = ctx.impactVX or ctx.vx or 0.0
    local vy = ctx.impactVY or ctx.vy or 0.0
    local vz = ctx.impactVZ or ctx.vz or 0.0
    local speed = math.sqrt(vx * vx + vy * vy)

    -- Heading from the last motion, falling back to the throw's own bearing: an object that
    -- stopped dead against a wall has no velocity left to read a direction from.
    local heading = ctx.heading or 0.0
    if speed > 0.05 then heading = math.atan2(vy, vx) end

    -- LEANING, when the last thing it touched was upright. Yaw points INTO the surface, which is
    -- what makes it read as propped against the wall rather than as having fallen next to it.
    if ctx.hitWall and (ctx.wallX ~= nil) and (ctx.wallX ~= 0 or ctx.wallY ~= 0) then
        return PITCH_LEAN, M.poseYaw(math.atan2(ctx.wallY or 0, ctx.wallX or 0)), "leaning"
    end

    -- STANDING, for a flare that came down steeply and slowly onto its base. Both conditions
    -- matter: slow alone would stand anything that had stopped, and steep alone would stand one
    -- that arrived like a dart and skidded.
    if CAN_STAND[family] and speed < UPRIGHT_SPEED
        and math.abs(vz) > speed * UPRIGHT_STEEP then
        return PITCH_UP, M.poseYaw(heading), "upright"
    end

    -- LYING FLAT, which is what almost everything does and what a glow stick on a floor has
    -- always looked like everywhere except in this game.
    return PITCH_FLAT, M.poseYaw(heading), "flat"
end

--- The ModData key that says "this item has been posed".
local POSED_KEY = "lugliELPosed"

--- Has this item ever been given a pose?
local function isPosed(item)
    local ok, v = pcall(function() return item:getModData()[POSED_KEY] end)
    return ok and v == true
end

local function markPosed(item)
    pcall(function() item:getModData()[POSED_KEY] = true end)
end

--- Write a pose onto a placed item.
function M.applyPose(item, worldObj, pitch, yaw)
    if item == nil then return false end
    markPosed(item)
    local ok = pcall(function()
        -- THE PITCH. Applied first, so the heading below still has a tipped tube to swing.
        item:setWorldYRotation(pitch)
        -- Zero rather than left alone. IsoWorldInventoryObject zeroes pitch and roll at
        -- construction but the LOAD path resets only worldZRotation and worldScale
        item:setWorldXRotation(0)
        -- THE HEADING. Also the one axis vanilla sets: it randomises it ONLY when it is negative
        -- (IsoWorldInventoryObject.java:75-76), so an explicit value is kept.
        item:setWorldZRotation(yaw)
    end)
    if not ok then return false end

    -- REPLICATED, so other players see the same object lying the same way. Without this a thrown
    -- stick appears on every other client standing upright at a random yaw -- which was true of
    -- every item this mod has ever dropped, and is a gap the pose work closes rather than opens.
    if worldObj ~= nil then
        pcall(function() worldObj:syncExtendedPlacement() end)
    end
    return true
end

--- Give an item a pose if it has never had one.
function M.poseIfUnposed(item, worldObj, family)
    if item == nil or isPosed(item) then return false end

    -- A random heading, because an item that arrived without being thrown has no heading to
    -- inherit and a row of identically aligned sticks in a crate looks worse than a random one.
    local heading = 0.0
    if ZombRandFloat ~= nil then
        local okr, v = pcall(ZombRandFloat, 0.0, math.pi * 2.0)
        if okr and type(v) == "number" then heading = v end
    end

    -- A ROLL, not a rule. An item that arrived without being thrown has no impact to read, and
    -- the honest answer to "how did this land" is that nobody knows -- so it lies flat like almost
    -- everything does, and occasionally, if it is the sort of thing that can, it stands.
    local ctx = { heading = heading }
    if CAN_STAND[family] and ZombRandFloat ~= nil then
        local okc, roll = pcall(ZombRandFloat, 0.0, 1.0)
        if okc and type(roll) == "number" and roll < UPRIGHT_CHANCE then
            -- Steep and slow: the shape of an arrival that settles on its base.
            ctx.impactVX, ctx.impactVY, ctx.impactVZ = 0.0, 0.0, -2.0
        else
            -- Shallow and quick: it lies down.
            ctx.impactVX, ctx.impactVY, ctx.impactVZ = math.cos(heading) * 2.0,
                                                        math.sin(heading) * 2.0, -0.8
        end
    end

    local p, y = M.poseFor(family, ctx)
    return M.applyPose(item, worldObj, p, y)
end

M.status(PART, true)
