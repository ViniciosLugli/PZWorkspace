--[[
    FX
]]

require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "FX"

local BASE = "media/textures/"

--- Textures, fetched once.
local cache = {}

function M.fxTex(name)
    local t = cache[name]
    if t ~= nil then return t end
    if getTexture == nil then return nil end
    local ok, tex = pcall(getTexture, BASE .. name .. ".png")
    if not ok or tex == nil then return nil end
    cache[name] = tex
    return tex
end

--- The four variant names, built once.
local SMOKE = {
    "LugliEL_FXSmoke1", "LugliEL_FXSmoke2", "LugliEL_FXSmoke3", "LugliEL_FXSmoke4",
}

--- One of the four smoke variants, chosen deterministically.
function M.fxSmoke(a, b)
    local n = (a * 12.9898 + b * 78.233) * 43758.5453
    local f = n - math.floor(n)
    local i = math.floor(f * 4.0) + 1
    if i > 4 then i = 4 elseif i < 1 then i = 1 end
    return M.fxTex(SMOKE[i])
end

-- ---- PROJECT VIEWPOINT (Workshop 3809306528) -------------------------------------------------------
-- Its first- and third-person camera replaces the iso one, so isoToScreen puts every sprite in the
-- wrong place. The camera is readable from Lua: Viewpoint.Addons.viewState() gives the eye and the
-- crosshair ray in world units (x and y in tiles, z in floors) and the vertical field of view in
-- degrees (viewpoint.ViewFeed.state, viewpoint.input.WorldPose).

--- One floor in Viewpoint's render units, which are tiles across (WorldPose.world).
M.FX_VP_FLOOR = 2.4494896

--- World-frame pixels per tile across in the iso view: every sprite size here was authored at it.
M.FX_ISO_PX_PER_TILE = 128.0 / math.sqrt(2.0)

--- Nearer than this to the eye, in render units, a point is not drawn: it would fill the screen.
M.FX_NEAR = 0.05

--- How far a perspective pass looks for things to draw, in tiles. The iso reach is a screen's worth.
M.FX_PERSPECTIVE_REACH = 60.0

--- Off every screen, for a point that has no projection.
local OFF = -1.0e6

--- A camera nothing projects through: every point drawn with it is behind its eye, at scale 0.
--- For a thing the player cannot see in perspective, so its whole draw costs nothing.
M.FX_UNSEEN = { idx = 0, w = 0.0, h = 0.0, ex = 0.0, ey = 0.0, ez = 0.0, fx = 0.0, fy = 0.0, fz = 0.0,
                rx = 0.0, ry = 0.0, ux = 0.0, uy = 0.0, uz = 0.0, focal = 0.0 }

local vpBroken = false
local cam = { idx = 0, w = 0.0, h = 0.0 }

-- viewState is the last 3D frame Viewpoint drew, and it stops drawing them in the iso view, so on
-- the way back to iso it still says on. Its live switch is Viewpoint.Loot.viewOn (View.enabled).
local function viewState()
    if Viewpoint.Loot.viewOn() ~= true then return nil end
    return Viewpoint.Addons.viewState()
end

--- The perspective camera for this pass, or nil when the iso projection applies.
local function perspective(idx, zoom)
    if vpBroken or Viewpoint == nil or Viewpoint.Addons == nil or Viewpoint.Addons.viewState == nil
        or Viewpoint.Loot == nil or Viewpoint.Loot.viewOn == nil then
        return nil
    end
    local ok, st = pcall(viewState)
    if not ok then
        vpBroken = true
        M.defect(PART, "Viewpoint.Addons.viewState threw, flares keep the iso projection: " .. tostring(st))
        return nil
    end
    if type(st) ~= "table" or st.on ~= true or type(st.eye) ~= "table" or type(st.crosshair) ~= "table"
        or type(st.fov) ~= "number" then
        return nil
    end
    local w, h = M.fxViewBounds(idx, zoom)
    if w == nil then return nil end

    local c = st.crosshair
    local fx, fy, fz = c.dx, c.dy, c.dz * M.FX_VP_FLOOR
    local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
    -- right = up x forward, with up = +z. Straight up or down there is no basis for one frame:
    -- nothing is drawn, since the iso positions would be wrong on a 3D screen.
    local rl = math.sqrt(fx * fx + fy * fy)
    if fl < 1.0e-6 or rl / fl < 1.0e-4 or st.fov <= 0.0 then return M.FX_UNSEEN end
    fx, fy, fz = fx / fl, fy / fl, fz / fl
    rl = rl / fl
    local rx, ry = -fy / rl, fx / rl

    cam.idx = idx
    cam.w, cam.h = w, h
    cam.tx, cam.ty, cam.tz = math.floor(st.eye.x), math.floor(st.eye.y), math.floor(st.eye.z)
    cam.ex, cam.ey, cam.ez = st.eye.x, st.eye.y, st.eye.z * M.FX_VP_FLOOR
    cam.fx, cam.fy, cam.fz = fx, fy, fz
    cam.rx, cam.ry = rx, ry
    -- up = forward x right
    cam.ux, cam.uy, cam.uz = -fz * ry, fz * rx, fx * ry - fy * rx
    cam.focal = (h * 0.5) / math.tan(math.rad(st.fov) * 0.5)
    return cam
end

--- WORLD TO THE WORLD FRAME, WITH THE CORRECTION THE MODELS GET. The third value is the
--- perspective camera under Viewpoint's 3D view, nil for the iso view; fxScreen takes it back.
function M.fxViewport(player)
    local idx = 0
    if player ~= nil then
        local oki, n = pcall(function() return player:getPlayerNum() end)
        if oki and type(n) == "number" and n >= 0 then idx = n end
    end

    local zoom = 1.0
    local okz, z = pcall(function() return getCore():getZoom(idx) end)
    if okz and type(z) == "number" and z > 0.01 then zoom = z end

    return idx, zoom, perspective(idx, zoom)
end

--- THE PROJECTION ITSELF, hoisted out of fxScreen so it can be pcall'd WITHOUT a closure.
local function project(idx, zoom, x, y, z)
    return (isoToScreenX(idx, x, y, z) - IsoCamera.getScreenLeft(idx)) * zoom,
           (isoToScreenY(idx, x, y, z) - IsoCamera.getScreenTop(idx)) * zoom
end

--- A world point through the perspective camera: screen x, y and the sprite scale, which is 0
--- (and the point off every screen) behind the eye.
local function projectPerspective(c, x, y, z)
    local dx, dy, dz = x - c.ex, y - c.ey, z * M.FX_VP_FLOOR - c.ez
    local depth = dx * c.fx + dy * c.fy + dz * c.fz
    if depth < M.FX_NEAR then return OFF, OFF, 0.0 end
    local k = c.focal / depth
    return c.w * 0.5 + (dx * c.rx + dy * c.ry) * k,
           c.h * 0.5 - (dx * c.ux + dy * c.uy + dz * c.uz) * k,
           k / M.FX_ISO_PX_PER_TILE
end

--- Set the renderer's blend mode, guarded, without allocating.
local function setAdditive(r, on) r:setDoAdditive(on) end

function M.fxAdditive(r, on)
    if r == nil then return end
    pcall(setAdditive, r, on)
end

--- World to screen, plus the scale every authored sprite size is multiplied by: 1 in the iso view,
--- the size at that depth in perspective, 0 for a point that cannot be drawn.
function M.fxScreen(idx, zoom, x, y, z, persp)
    if persp ~= nil then return projectPerspective(persp, x, y, z) end

    local ok, sx, sy = pcall(project, idx, zoom, x, y, z)
    if ok and type(sx) == "number" then return sx, sy, 1.0 end

    -- The uncorrected projection, which is what the mod used everywhere before. Half a tile out at
    -- worst, and only if one of the two statics above ever stops being reachable.
    local ux, uy = ISCoordConversion.ToScreen(x, y, z)
    return ux, uy, 1.0
end

--- The unit screen direction of a world direction at a world point, or nil when it has none on
--- screen. Perspective only: the iso callers keep their own screen-space directions.
function M.fxScreenDir(persp, x, y, z, wx, wy, wz)
    local ax, ay, as = projectPerspective(persp, x, y, z)
    local e = 0.05
    local bx, by, bs = projectPerspective(persp, x + wx * e, y + wy * e, z + wz * e)
    if as <= 0.0 or bs <= 0.0 then return nil end
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1.0e-6 then return nil end
    return dx / len, dy / len
end

local losBroken = false

local function lineClear(c, x, y, z)
    return tostring(LosUtil.lineClear(getCell(), c.tx, c.ty, c.tz, x, y, z, false))
end

local function couldSee(sq, idx) return sq:isCouldSee(idx) end

--- Does the camera see this tile? Always in the iso view, where the mod has always drawn through
--- walls the way the engine's own overlays do. In perspective a 2D sprite has no depth test, so a
--- flare behind a wall would shine through it: the engine's line of sight decides, cast from the
--- camera's eye rather than the survivor, who stands on the other side of a wall from a third-person
--- camera often enough (LosUtil.lineClear: walls, closed doors, curtains, floors).
function M.fxSees(persp, x, y, z)
    if persp == nil then return true end
    if persp.tx == nil then return false end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    if not losBroken and LosUtil ~= nil then
        local ok, r = pcall(lineClear, persp, x, y, z)
        if ok then return r ~= "Blocked" end
        losBroken = true
        M.defect(PART, "LosUtil.lineClear threw, flares use the survivor's line of sight: " .. tostring(r))
    end
    local sq = getCell():getGridSquare(x, y, z)
    if sq == nil then return false end
    local ok, seen = pcall(couldSee, sq, persp.idx)
    return ok and seen == true
end

local function outside(x, y, z)
    local sq = getCell():getGridSquare(x, y, z)
    return sq ~= nil and sq:isOutside()
end

--- Does the camera see a flare high in the sky above (x, y)? A ray up there crosses squares the
--- world never built, which block nothing, so it would see through any roof. Instead: from outdoors,
--- the sky is in view; from indoors, only through a window or a doorway onto open ground below it.
function M.fxSeesSky(persp, x, y)
    if persp == nil then return true end
    if persp.tx == nil then return false end
    local ok, out = pcall(outside, persp.tx, persp.ty, persp.tz)
    if ok and out == true then return true end
    x, y = math.floor(x), math.floor(y)
    local okb, below = pcall(outside, x, y, persp.tz)
    return okb and below == true and M.fxSees(persp, x, y, persp.tz)
end

--- THE VIEWPORT, in the same world frame fxScreen projects into.
function M.fxViewBounds(idx, zoom)
    local w, h = 0.0, 0.0
    local ok = pcall(function()
        w = IsoCamera.getScreenWidth(idx) * zoom
        h = IsoCamera.getScreenHeight(idx) * zoom
    end)
    if not ok or w <= 0.0 or h <= 0.0 then return nil, nil end
    return w, h
end

--- Is this world-frame point on screen, allowing `margin` world-frame pixels of overhang?
function M.fxOnScreen(sx, sy, w, h, margin)
    if w == nil or h == nil then return true end
    local m = margin or 0.0
    return sx >= -m and sx <= w + m and sy >= -m and sy <= h + m
end

--- The greatest distance, in TILES, at which a point could still land inside `w` x `h`.
function M.fxReachTiles(w, h, persp)
    if persp ~= nil then return M.FX_PERSPECTIVE_REACH end
    if w == nil or h == nil then return nil end
    return w / 128.0 + h / 64.0 + 4.0
end

--- A circle lying on the ground, as a ring of tapered segments through the projection. A segment
--- with an end behind the eye is skipped rather than drawn to the far side of the screen.
function M.fxGroundCircle(R, tex, idx, zoom, persp, cx, cy, cz, radius, segments, width, r, g, b, a)
    local px, py, ps, fx, fy, fs
    for i = 0, segments do
        local t = (i / segments) * 6.2831853
        local sx, sy, s = M.fxScreen(idx, zoom, cx + math.cos(t) * radius, cy + math.sin(t) * radius, cz, persp)
        if ps ~= nil then
            if ps > 0.0 and s > 0.0 then
                M.fxTaper(R, tex, px, py, sx, sy, width * ps, width * s, r, g, b, a)
            end
        else
            fx, fy, fs = sx, sy, s
        end
        px, py, ps = sx, sy, s
    end
    if fs ~= nil and fs > 0.0 and ps > 0.0 then
        M.fxTaper(R, tex, px, py, fx, fy, width * ps, width * fs, r, g, b, a)
    end
end

--- A textured quad centred on a screen point, rotated, at an arbitrary size.
function M.fxQuad(R, tex, cx, cy, w, h, angle, r, g, b, a)
    if tex == nil or type(a) ~= "number" or a <= 0.0 or w <= 0.0 or h <= 0.0 then return end
    local hw, hh = w * 0.5, h * 0.5
    local c = math.cos(angle or 0.0)
    local s = math.sin(angle or 0.0)

    -- The two half-axes of the quad, rotated once.
    local ux, uy = c * hw, s * hw
    local vx, vy = -s * hh, c * hh

    R:render(tex,
             cx - ux - vx, cy - uy - vy,
             cx + ux - vx, cy + uy - vy,
             cx + ux + vx, cy + uy + vy,
             cx - ux + vx, cy - uy + vy,
             r, g, b, a, nil)
end

--- An axis-aligned quad centred on a screen point.
function M.fxRect(R, tex, cx, cy, w, h, r, g, b, a)
    M.fxQuad(R, tex, cx, cy, w, h, 0.0, r, g, b, a)
end

--- A quad stretched between two screen points, of a given width. For anything with a direction:
function M.fxBeam(R, tex, x1, y1, x2, y2, w, r, g, b, a)
    if tex == nil or type(a) ~= "number" or a <= 0.0 or w <= 0.0 then return end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.0001 then return end

    -- Perpendicular, scaled to half the width.
    local px = -dy / len * w * 0.5
    local py = dx / len * w * 0.5

    R:render(tex,
             x1 - px, y1 - py,
             x2 - px, y2 - py,
             x2 + px, y2 + py,
             x1 + px, y1 + py,
             r, g, b, a, nil)
end

--- A tapered line, using the engine's own primitive rather than a quad.
function M.fxTaper(R, tex, x1, y1, x2, y2, w0, w1, r, g, b, a)
    if tex == nil or type(a) ~= "number" or a <= 0.0 or (w0 <= 0.0 and w1 <= 0.0) then return end
    pcall(function()
        R:renderlinef(tex, x1, y1, x2, y2, r, g, b, a, w0, w1)
    end)
end

M.status(PART, true)
