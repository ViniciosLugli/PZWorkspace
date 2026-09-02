--[[
    Fire
]]

require "LugliEmergencyLights/Light"
require "LugliEmergencyLights/FX"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Fire"

--- How far past its own tip a flame is drawn, in world-frame pixels.
local FLAME_MARGIN = 96.0

--- How many tongues of flame.
local TONGUES = 7

--- How far the jet reaches from the tip, in world-frame pixels.
local JET_REACH = 20.0

--- WHERE THE JET POINTS, AND IT FOLLOWS THE FLARE.
function M.jetFromWorld(wx, wy, wz)
    local sx = (wx - wy) * 64.0
    local sy = (wx + wy) * 32.0 - wz * 192.0
    local len = math.sqrt(sx * sx + sy * sy)
    if len < 1.0e-6 then return 0.0, -1.0 end
    return sx / len, sy / len
end

--- Which way a posed item points, as a unit vector in WORLD units.
function M.axisWorld(pitchDeg, yawDeg)
    -- No pose: upright, which is what a flare in a hand and a flare with no recorded rotation both
    -- look like, and what every caller assumed before.
    if type(pitchDeg) ~= "number" then return 0.0, 0.0, 1.0 end

    local p = math.rad(pitchDeg)
    local y = math.rad(yawDeg or 0.0)
    local s = math.sin(p)
    local flat = 1.5 / 0.61237234

    local wx = s * math.cos(y) * flat
    local wy = s * math.sin(y) * flat
    local wz = math.cos(p)

    -- Normalised in world space, so a caller multiplying by a speed gets that speed.
    local len = math.sqrt(wx * wx + wy * wy + wz * wz)
    if len < 1.0e-6 then return 0.0, 0.0, 1.0 end
    return wx / len, wy / len, wz / len
end

function M.jetDirection(pitchDeg, yawDeg)
    if type(pitchDeg) ~= "number" then return 0.0, -1.0 end
    return M.jetFromWorld(M.axisWorld(pitchDeg, yawDeg))
end

local phase = 0.0


local function hash01(a, b)
    local n = (a * 12.9898 + b * 78.233) * 43758.5453
    return n - math.floor(n)
end

--- THE FLAME OF A FLARE IN THE HAND IS NOT DRAWN HERE. It is geometry in the held mesh
--- (tools/emlights-gen.py, profile_flame_plume): the engine keeps a held model on the
--- Bip01_Prop1 bone through every animation, and nothing Lua can read follows that bone. Two
--- anchors were tried from here, a measured constant and a live evaluation of the animation
--- blend, and both sat visibly off the rod. What this file draws is the flame of a flare ON
--- THE GROUND, where the rod's pose is the mod's own number and the sprite fits it exactly.

--- Draw one complete flare flame at a screen point.
local function drawFlame(R, sx, sy, seedA, seedB, cr, cg, cb, life, windX, windY,
                         core, glow, streak, corona, jx, jy)
    -- The jet axis for THIS flare. Defaulted so a caller with no pose still gets the old upward
    -- plume rather than a zero-length vector and a division by nothing.
    jx = jx or 0.0
    jy = jy or -1.0
    -- ---- THE JET --------------------------------------------------------------------------
    -- Tongues as oriented STREAKS along the jet axis rather than round blobs. A flame has a
    -- direction: it is thrown out of the tube and it tapers as it goes. Round sprites stacked up
    -- an axis read as a column of bubbles, which is what this used to look like.
    for i = 1, TONGUES do
        local seed = hash01(seedA + i * 7, seedB + i * 13)
        local k = (phase * (1.6 + seed * 1.5) + seed) % 1.0
        -- Spread across the jet, widening as it travels.
        local fan = (seed - 0.5) * 1.5
        local reach = JET_REACH * (0.35 + 0.65 * k) * life
        local tipX = sx + (jx + fan * 0.55 + windX * 0.5) * reach
        local tipY = sy + (jy + windY * 0.5) * reach
        local w = (11.0 - 6.0 * k) * life
        if w > 0.5 then
            -- Cools along its length: white where it leaves the tube, the flare's own colour by
            -- the time it is spent.
            local hot = 1.0 - k
            local tr = cr + (1.0 - cr) * hot
            local tg = cg + (1.0 - cg) * hot
            local tb = cb + (1.0 - cb) * hot
            M.fxBeam(R, streak, sx, sy, tipX, tipY, w, tr, tg, tb, (1.0 - k) * 0.52 * life)
        end
    end

    -- ---- THE CORONA AND THE CORE, last, so they sit on top ---------------------------------
    -- Fast, shallow flicker. A big slow pulse reads as a lamp being dimmed; a real flame shivers.
    -- Two frequencies so it never settles into an obvious beat.
    local f = 0.86 + 0.14 * math.sin(phase * 41.0)
                  + 0.06 * math.sin(phase * 97.0 + 1.7)
    local cw = 6.0 * f * life

    -- THE BLOOM IS THE BIGGEST THING HERE AND IT STILL HAS TO FIT THE SCENE. At ten times the core
    -- it was an 85-pixel disc before the glow was added on top, which on a 100-pixel character
    -- reads as a force field rather than as a light. Six is a bloom; ten was a backdrop.
    if corona ~= nil then
        M.fxQuad(R, corona, sx, sy, cw * 6.0, cw * 6.0, phase * 0.21, cr, cg, cb, 0.26 * life)
    end
    M.fxRect(R, glow, sx, sy, cw * 3.0, cw * 3.0, cr, cg, cb, 0.40 * life)
    -- Near white, and small. The one part of a flare that has no colour of its own.
    M.fxRect(R, core, sx, sy, cw * 1.1, cw * 1.1, 1.0, 0.96, 0.90, 0.95 * life)
end

local function draw()
    if M.cfg("FlareFire") ~= true then return end
    if ISCoordConversion == nil or getRenderer == nil or getTexture == nil then return end

    local viewer = getPlayer ~= nil and getPlayer() or nil
    if viewer == nil then return end

    local core = M.fxTex("LugliEL_FXCore")
    local glow = M.fxTex("LugliEL_FXGlow")
    if core == nil or glow == nil then return end
    local streak = M.fxTex("LugliEL_FXStreak")
    local corona = M.fxTex("LugliEL_FXFlare")

    local vx, vy = viewer:getX(), viewer:getY()
    local vz = math.floor(viewer:getZ())

    -- The viewport this pass draws into, and the size divisor that goes with it. See fxViewport.
    local vpIdx, vpZoom = M.fxViewport(viewer)

    -- THE CULL, read once per frame from the camera rather than authored as a tile count.
    local vw, vh = M.fxViewBounds(vpIdx, vpZoom)
    local reach = M.fxReachTiles(vw, vh)
    local reach2 = reach ~= nil and reach * reach or nil

    local R = getRenderer()

    -- Read ONCE. The wind is identical for every flare in the frame, and fetching it per record
    -- cost a closure, a pcall and three engine calls each.
    local windX, windY = 0.0, 0.0
    if M.windVector ~= nil then
        local okw, ax, ay, kph = pcall(M.windVector)
        if okw and type(ax) == "number" then
            windX, windY = ax * (kph or 0.0) * 0.010, ay * (kph or 0.0) * 0.010
        end
    end

    -- THE WHOLE PASS IS BRACKETED.
    M.fxAdditive(R, true)

    local ok = pcall(function()
        -- ---- FLARES ON THE GROUND ----------------------------------------------------------
        M.eachLight(function(key, rec)
            -- Road flares only. A glow stick is a cold chemical reaction: it has no flame, and
            -- giving it one would be the single most obviously wrong thing in the mod. Its own
            -- visible source is drawn by the Source block in Light.lua instead.
            if rec.family ~= "RoadFlare" then return end
            -- A fired flare's ground record is a near-black carrier that owns the sound; the
            -- burning thing itself is up in the sky and draws its own fire.
            if rec.expiresAt ~= nil then return end
            if rec.z ~= vz then return end

            local px = rec.fx or (rec.x + 0.5)
            local py = rec.fy or (rec.y + 0.5)
            local dx, dy = px - vx, py - vy
            if reach2 ~= nil and dx * dx + dy * dy > reach2 then return end

            local sx, sy = M.fxScreen(vpIdx, vpZoom, px, py, rec.fz or rec.z)
            if not M.fxOnScreen(sx, sy, vw, vh, FLAME_MARGIN) then return end

            -- Dimmer as it burns down, but never out: a nearly spent flare is a smaller flame,
            -- not a dark one.
            local life = 0.55 + 0.45 * (rec.frac or 1.0)
            -- FOLLOWS THE FLARE ON THE GROUND. rec.pitch/rec.yaw are the item's own world
            -- rotations, so a flare that came to rest on its side burns out of its side.
            local jx, jy = M.jetDirection(rec.pitch, rec.yaw)
            drawFlame(R, sx, sy, rec.x, rec.y,
                      rec.rawR or 1.0, rec.rawG or 0.3, rec.rawB or 0.2,
                      life, windX, windY, core, glow, streak, corona, jx, jy)
        end)
    end)

    M.fxAdditive(R, false)
    if not ok then
        M.defect(PART, "the flame pass threw; additive blend has been cleared")
    end
end

local function tick()
    if M.cfg("FlareFire") ~= true then return end

    -- Advanced here rather than in the draw, because OnPostRender runs once per PLAYER and would
    -- make every flame burn twice as fast in split screen.
    phase = phase + M.frameDelta()
end

M.addHandler(PART, "OnPostRender", draw)
local h = M.addTicker(PART, 0, tick)

if h ~= nil then M.status(PART, true) end
