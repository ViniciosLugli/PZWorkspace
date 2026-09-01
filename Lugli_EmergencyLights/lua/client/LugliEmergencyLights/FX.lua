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

--- WORLD TO THE WORLD FRAME, WITH THE CORRECTION THE MODELS GET.
function M.fxViewport(player)
    local idx = 0
    if player ~= nil then
        local oki, n = pcall(function() return player:getPlayerNum() end)
        if oki and type(n) == "number" and n >= 0 then idx = n end
    end

    local zoom = 1.0
    local okz, z = pcall(function() return getCore():getZoom(idx) end)
    if okz and type(z) == "number" and z > 0.01 then zoom = z end

    return idx, zoom
end

--- THE PROJECTION ITSELF, hoisted out of fxScreen so it can be pcall'd WITHOUT a closure.
local function project(idx, zoom, x, y, z)
    return (isoToScreenX(idx, x, y, z) - IsoCamera.getScreenLeft(idx)) * zoom,
           (isoToScreenY(idx, x, y, z) - IsoCamera.getScreenTop(idx)) * zoom
end

--- Set the renderer's blend mode, guarded, without allocating.
local function setAdditive(r, on) r:setDoAdditive(on) end

function M.fxAdditive(r, on)
    if r == nil then return end
    pcall(setAdditive, r, on)
end

function M.fxScreen(idx, zoom, x, y, z)
    local ok, sx, sy = pcall(project, idx, zoom, x, y, z)
    if ok and type(sx) == "number" then return sx, sy end

    -- The uncorrected projection, which is what the mod used everywhere before. Half a tile out at
    -- worst, and only if one of the two statics above ever stops being reachable.
    return ISCoordConversion.ToScreen(x, y, z)
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
function M.fxReachTiles(w, h)
    if w == nil or h == nil then return nil end
    return w / 128.0 + h / 64.0 + 4.0
end

--- A textured quad centred on a screen point, rotated, at an arbitrary size.
function M.fxQuad(R, tex, cx, cy, w, h, angle, r, g, b, a)
    if tex == nil or type(a) ~= "number" or a <= 0.0 then return end
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
    if tex == nil or type(a) ~= "number" or a <= 0.0 then return end
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
    if tex == nil or type(a) ~= "number" or a <= 0.0 then return end
    pcall(function()
        R:renderlinef(tex, x1, y1, x2, y2, r, g, b, a, w0, w1)
    end)
end

M.status(PART, true)
