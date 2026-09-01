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

--- WHERE THE FLAME SITS RELATIVE TO THE CHARACTER, when the flare is in their hand.
M.flameOffset = M.flameOffset or { fwd = 0.10, side = 0.11, up = 0.42 }

local phase = 0.0

--- A cheap deterministic hash in 0..1, so every particle has its own rhythm without storing state.
local function playerLook(player)
    return player:getLookDirectionX(), player:getLookDirectionY()
end

local function hash01(a, b)
    local n = (a * 12.9898 + b * 78.233) * 43758.5453
    return n - math.floor(n)
end

--- DECLARED ABOVE ITS WRITER, and that is the whole reason it sits here rather than beside the
--- other reporting state further down.
local anchorFromBridge = false

--- Where a held flare's burning tip is, in WORLD coordinates, and which way it points on screen.
local function heldAnchor(player, fx, fy)
    if LugliELHeldPointResolve ~= nil and LugliELHeldPointResolve(player) == true then
        local wx, wy, wz = LugliELHeldPointX(), LugliELHeldPointY(), LugliELHeldPointZ()
        anchorFromBridge = true
        -- The flare's own axis, tip minus base, so the flame leaves the burning end along the tube
        -- exactly as it does for a flare lying on the ground.
        local hjx, hjy = M.jetFromWorld(wx - LugliELHeldPointBaseX(),
                                        wy - LugliELHeldPointBaseY(),
                                        wz - LugliELHeldPointBaseZ())
        return wx, wy, wz, hjx, hjy
    end

    anchorFromBridge = false
    local o = M.flameOffset
    -- The right-hand normal of the look vector, which is where the primary hand is.
    local px, py = -fy, fx
    return player:getX() + fx * o.fwd + px * o.side,
           player:getY() + fy * o.fwd + py * o.side,
           player:getZ() + o.up, nil, nil
end

--- The look vector, or straight ahead when it cannot be had.
local function lookVector(player)
    local ok, lx, ly = pcall(playerLook, player)
    if ok and type(lx) == "number" and (lx ~= 0.0 or ly ~= 0.0) then return lx, ly end
    return 0.0, 1.0
end

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

--- Which route produced the held anchor, said once when it changes. If the bridge is answering
--- and the flame still sits wrong, the error is downstream of here.
local anchorSaid = nil

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

        -- ---- FLARES IN THE HAND ------------------------------------------------------------
        -- NOT CULLED, and it does not need to be: there is at most one per local player and the
        -- character carrying it is at the centre of their own viewport by construction.
        if M.eachCarried ~= nil then
            M.eachCarried(function(player, idx, item, info)
                if info.family ~= "RoadFlare" then return end

                local fx, fy = lookVector(player)

                -- ASK THE ENGINE WHERE THE HAND IS, and only guess if it will not say.
                local wx, wy, wz, hjx, hjy = heldAnchor(player, fx, fy)

                -- THIS PLAYER'S viewport, not the pass's. In split screen the two characters are
                -- drawn into different halves of the window with their own zoom, and a held flame
                -- belongs to whichever one is carrying it.
                local hIdx, hZoom = M.fxViewport(player)
                local sx, sy = M.fxScreen(hIdx, hZoom, wx, wy, wz)

                -- SAID ONCE, WHEN THE ROUTE CHANGES, never per frame.
                if anchorSaid ~= anchorFromBridge then
                    anchorSaid = anchorFromBridge
                    M.debug(PART, string.format(
                        "held flame anchored via %s at %.2f,%.2f,%.2f",
                        anchorFromBridge and "the hand bone" or "the fallback offset",
                        wx, wy, wz))
                end

                local frac = M.fractionLeft(item) or 1.0
                local life = 0.55 + 0.45 * frac
                -- Seeded on the player rather than on a tile, so the flame is stable as they walk
                -- and two players carrying flares do not burn in lockstep.
                drawFlame(R, sx, sy, idx * 977, idx * 131,
                          info.r, info.g, info.b,
                          life, windX, windY, core, glow, streak, corona, hjx, hjy)
            end)
        end
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
