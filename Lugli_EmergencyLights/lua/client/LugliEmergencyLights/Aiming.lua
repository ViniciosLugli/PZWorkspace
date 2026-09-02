--[[
    Aiming
    The aim pose, the landing marker, and the debug range overlay.
]]

require "LugliEmergencyLights/FX"
require "LugliEmergencyLights/Aim"
require "LugliEmergencyLights/Light"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- Aiming ------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Aiming"

    -- Degrees above horizontal. The animset blends Bob_IdleAimHandgun_Up45 and _Up75 off this scalar,
    -- so 60 is a real interpolation between two shipped poses rather than an extrapolation past one.
    local PITCH = 60.0

    -- playerIndex -> true while we are holding that player's pitch up, so it is released exactly once.
    local raised = {}

    --- The flare gun, in hand, or nil.
    local function gunInHand(player)
        if M.GUN == nil then return nil end
        local item = player:getPrimaryHandItem()
        if item == nil then return nil end
        local ok, ft = pcall(function() return item:getFullType() end)
        if not ok or ft ~= M.GUN.item then return nil end
        return item
    end

    local function aimingWithGun(player)
        if player == nil then return nil end
        local ok, aiming = pcall(function() return player:isAiming() end)
        if not ok or aiming ~= true then return nil end
        return gunInHand(player)
    end

    --- A lit, throwable light in the primary hand, and its family info, or nil.
    local function throwableInHand(player)
        local item = player:getPrimaryHandItem()
        if item == nil then return nil end
        local info = M.litInfo(item)
        if info == nil then return nil end
        if M.isInFlight ~= nil and M.isInFlight(item) then return nil end
        return info
    end

    local function aimingWithThrowable(player)
        if player == nil then return nil end
        local ok, aiming = pcall(function() return player:isAiming() end)
        if not ok or aiming ~= true then return nil end
        return throwableInHand(player)
    end

    -- The square the shot would use, recomputed on the pose ticker and only DRAWN per frame.
    local marked = nil

    -- One sigma of throw scatter at the current aim distance, in tiles.
    -- Zero for the flare gun, whose shot has no scatter and whose marker is a point.
    local spreadTiles = 0.0

    -- THE RETICLE IS NEUTRAL, DELIBERATELY, and it used to be the item's own colour.
    --- THE RETICLE PALETTE, and it is built on CONTRAST rather than on brightness.
    local RING_R, RING_G, RING_B = 0.90, 0.93, 0.97
    local EDGE_R, EDGE_G, EDGE_B = 0.04, 0.05, 0.08

    --- How wide the landing ring is, in tiles. Just inside one tile, so it reads as "this square".
    local RING_TILES = 0.92

    --- Below this the spread is not worth drawing as its own ring: the flare gun is precise enough
    --- that a second circle on top of the first is noise.
    local SPREAD_MIN = 0.30

    --- Raise the muzzle while aiming, lower it the moment that stops.
    local function pose()
        marked = nil
        spreadTiles = 0.0
        M.forEachLocalPlayer(function(player, idx)
            local up = aimingWithGun(player) ~= nil

            -- Resolved here rather than in the draw. Only for the player whose viewport this is; a
            -- second player aiming would need its own entry, and split screen does not have a mouse
            -- each anyway, which is the same reason the aim helper is single-cursor throughout.
            if up and idx == 0 then
                local range = M.positive("AerialShotRange", 30)
                -- THE SAME CALL THE SHOT MAKES.
                local ok, sq = pcall(M.skySquare, player, range)
                if ok then marked = sq end
                spreadTiles = 0.0
            end

            -- THE THROW GETS A RING TOO, and it shows the real distribution rather than a decoration.
            if idx == 0 and not up then
                local info = aimingWithThrowable(player)
                if info ~= nil then
                    local range = M.throwRange(info.family)
                    local ok, sq = pcall(M.aimSquareDirect, player, range)
                    if ok and sq ~= nil then
                        marked = sq
                        local dx = sq:getX() + 0.5 - player:getX()
                        local dy = sq:getY() + 0.5 - player:getY()
                        local d = math.sqrt(dx * dx + dy * dy)
                        local frac = 1.0
                        if type(range) == "number" and range > 0 then
                            frac = math.min(1.0, d / range)
                        end
                        spreadTiles = (M.spreadFor ~= nil and M.spreadFor(info.family) or 0.0) * frac
                    end
                end
            end

            -- Nothing to do in the common case: not aiming, and not holding anything up.
            if not up and not raised[idx] then return end

            -- RE-ASSERTED WHILE AIMING, not set once on the transition.
            -- ---- THE GRIP -------------------------------------------------------------------
            -- WHY THE LEFT HAND LETS GO, and it is not the pitch and not IsAimedFirearm.
            if up then
                pcall(function()
                    -- Immune to a leaked overrideWeaponType and to the two-second "throwing" latch
                    -- CombatManager sets after any throw, which would otherwise pick aim_throwing.
                    player:setVariable("Weapon", "handgun")

                    -- The action latch, released ONLY when the character genuinely has no action
                    -- queued -- otherwise this would cancel a real one out from under the player.
                    local acts = player:getCharacterActions()
                    local busy = acts ~= nil and acts:size() > 0
                    if not busy and player:getVariableString("IsPerformingAnAction") == "true" then
                        player:setVariable("IsPerformingAnAction", false)
                    end

                    -- And the left-arm mask, which owns the whole arm when it is set. Only when the
                    -- off hand is genuinely empty: with a bag equipped vanilla WANTS the masked pose,
                    -- and clearing it would push the bag model through the character's hand.
                    local mask = player:getVariableString("LeftHandMask")
                    if mask ~= nil and mask ~= "" and player:getSecondaryHandItem() == nil then
                        player:clearVariable("LeftHandMask")
                    end
                end)
            end

            local ok = pcall(function()
                player:setTargetVerticalAimAngle(up and PITCH or 0.0)
            end)
            if not ok then
                -- The build does not have the method. Say so once and stop trying: this is cosmetic,
                -- and the gun still fires perfectly well pointed straight ahead.
                M.defect(PART, "no setTargetVerticalAimAngle on this build; the gun aims level")
                raised[idx] = up
                return
            end
            raised[idx] = up or nil
        end)
    end

    --- Put every raised muzzle back down. A world change must not leave a character frozen mid-aim.
    function M.lowerAim()
        marked = nil
        M.forEachLocalPlayer(function(player, idx)
            if raised[idx] then
                pcall(function() player:setTargetVerticalAimAngle(0.0) end)
            end
        end)
        raised = {}
    end

    --- The ring where the flare will land.
    local function draw()
        if ISCoordConversion == nil or getRenderer == nil or getTexture == nil then return end

        -- THE SAME SQUARE THE SHOT WILL USE, resolved on the ticker above.
        local sq = marked
        if sq == nil then return end

        local player = getPlayer ~= nil and getPlayer() or nil
        if player == nil then return end

        local ring = M.fxTex("LugliEL_FXRing")
        local band = M.fxTex("LugliEL_FXRibbon")
        if ring == nil or band == nil then return end

        -- Only on the floor the player is standing on. The ring is a ground mark, and one drawn for a
        -- square on another level would sit over the roof between them.
        if sq:getZ() ~= math.floor(player:getZ()) then return end

        local aIdx, aZoom = M.fxViewport(player)
        local sx, sy = M.fxScreen(aIdx, aZoom, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())

        local R = getRenderer()

        -- NOT ADDITIVE. See the palette note: this is an overlay, not a light. Additive was what made
        -- it a white smear on pale ground with no edge to read.
        local ok = pcall(function()
            -- 64 world-frame pixels to the tile across and 32 down: that 2:1 is the iso projection,
            -- and it is what makes a circle read as lying flat on the ground rather than standing up
            -- facing the camera.
            local rw = 64.0 * RING_TILES
            local rh = rw * 0.5

            -- ---- THE SPREAD, first and faintest -------------------------------------------------
            -- Where it can actually land, at one sigma. Only for a throw, and only when it is wider
            -- than the landing ring itself -- a second circle inside the first says nothing.
            if spreadTiles > SPREAD_MIN then
                local sw = 64.0 * spreadTiles * 2.0
                local sh = sw * 0.5
                M.fxQuad(R, ring, sx, sy, sw + 3.0, sh + 3.0, 0.0,
                         EDGE_R, EDGE_G, EDGE_B, 0.30)
                M.fxQuad(R, ring, sx, sy, sw, sh, 0.0, RING_R, RING_G, RING_B, 0.22)
            end

            -- ---- THE LANDING RING ----------------------------------------------------------------
            -- Dark first, a little larger, then the light ring inside it. Two draws and the mark is
            -- legible on concrete, on grass, on tarmac and on blood.
            M.fxQuad(R, ring, sx, sy, rw + 4.0, rh + 4.0, 0.0, EDGE_R, EDGE_G, EDGE_B, 0.55)
            M.fxQuad(R, ring, sx, sy, rw, rh, 0.0, RING_R, RING_G, RING_B, 0.85)

            -- ---- THE AIM POINT ---------------------------------------------------------------------
            -- A CROSS, not a dot.
            local arm, gap, t = 9.0, 3.0, 1.6
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local ax = sx + d[1] * gap
                local ay = sy + d[2] * gap * 0.5
                local bx = sx + d[1] * arm
                local by = sy + d[2] * arm * 0.5
                M.fxBeam(R, band, ax, ay, bx, by, t + 2.0, EDGE_R, EDGE_G, EDGE_B, 0.55)
                M.fxBeam(R, band, ax, ay, bx, by, t, RING_R, RING_G, RING_B, 0.90)
            end
        end)

        if not ok then
            M.defect(PART, "the aim reticle threw and has been skipped this frame")
        end
    end

    -- 0.05s, not per frame: this resolves the landing square as well as setting the pose, and
    -- neither needs a frame's resolution. See the note on `marked`.
    local h = M.addTicker(PART, 0.05, pose)
    M.addHandler(PART, "OnPostRender", draw)

    -- Aiming is a live pose, not a saved one, so it must not survive the world that set it.
    M.addTeardown(PART, function() M.lowerAim() end)

    if h ~= nil then M.status(PART, true) end
end

-- ---- Debug -------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Debug ranges"

    --- Segments in a ring. Enough that a forty-tile circle has no visible corners.
    local SEGMENTS = 72

    --- How thick the line is, in world-frame pixels. A measuring line, not a beam.
    local RING_W = 2.0

    --- Beyond this there is no point drawing: the sky wash is 150 tiles and its ring would be a line
    --- across the whole screen with nothing to compare it to.
    local MAX_DRAW = 64

    --- Colour per KIND of thing, so the legend is the colour rather than a wall of text.
    local C_NOISE = { 1.00, 0.25, 0.20 }
    local C_LIGHT = { 1.00, 0.85, 0.30 }
    local C_REACH = { 0.35, 0.85, 1.00 }

    --- One world circle, drawn as a ring of dots through the iso projection.
    local function ring(R, tex, vpIdx, vpZoom, cx, cy, cz, radius, col, alpha)
        if radius <= 0.0 or radius > MAX_DRAW then return end

        local px, py, fx, fy
        for i = 0, SEGMENTS do
            local a = (i / SEGMENTS) * 6.2831853
            local sx, sy = M.fxScreen(vpIdx, vpZoom,
                                      cx + math.cos(a) * radius,
                                      cy + math.sin(a) * radius, cz)
            if px ~= nil then
                M.fxTaper(R, tex, px, py, sx, sy, RING_W, RING_W, col[1], col[2], col[3], alpha)
            else
                fx, fy = sx, sy
            end
            px, py = sx, sy
        end
        if fx ~= nil then
            M.fxTaper(R, tex, px, py, fx, fy, RING_W, RING_W, col[1], col[2], col[3], alpha)
        end
    end

    --- The ring's label, at its northern edge so several concentric rings do not stack their text.
    local function drawString(sx, sy, text, col)
        getTextManager():DrawString(UIFont.Small, sx, sy, text, col[1], col[2], col[3], 0.95)
    end

    local function label(vpIdx, vpZoom, cx, cy, cz, radius, text, col)
        if radius <= 0.0 or radius > MAX_DRAW then return end
        if getTextManager == nil then return end
        local sx, sy = M.fxScreen(vpIdx, vpZoom, cx, cy - radius, cz)
        pcall(drawString, sx + 3, sy - 8, text, col)
    end

    local function ringAndLabel(R, tex, vpIdx, vpZoom, cx, cy, cz, radius, col, text)
        if type(radius) ~= "number" then return end
        ring(R, tex, vpIdx, vpZoom, cx, cy, cz, radius, col, 0.90)
        label(vpIdx, vpZoom, cx, cy, cz, radius, text .. "  " .. tostring(math.floor(radius)), col)
    end

    local function draw()
        if M.cfg("DebugRanges") ~= true then return end
        if getRenderer == nil or getTextManager == nil then return end

        local viewer = getPlayer ~= nil and getPlayer() or nil
        if viewer == nil then return end

        -- The RIBBON, not the core. See ring(): a flat band draws a line, a radial glow draws a smear.
        local tex = M.fxTex("LugliEL_FXRibbon")
        if tex == nil then return end

        local vpIdx, vpZoom = M.fxViewport(viewer)
        local R = getRenderer()

        -- NOT additive. These are measuring lines, not light, and additive rings over a dark floor
        -- wash out exactly where they need to be readable.
        M.fxAdditive(R, false)

        local ok = pcall(function()
            local px, py = viewer:getX(), viewer:getY()
            local pz = viewer:getZ()

            -- ---- WHAT YOU DO, drawn around you ------------------------------------------------
            -- These are the one-shot noises and the reaches. They have no position of their own until
            -- you act, so your own feet are the only honest place to show them.
            ringAndLabel(R, tex, vpIdx, vpZoom, px, py, pz, M.cfg("CrackNoise"), C_NOISE, "crack")
            ringAndLabel(R, tex, vpIdx, vpZoom, px, py, pz, M.cfg("ThrowNoise"), C_NOISE, "landing")
            ringAndLabel(R, tex, vpIdx, vpZoom, px, py, pz, M.cfg("FlareGunNoise"), C_NOISE, "gun shot")
            ringAndLabel(R, tex, vpIdx, vpZoom, px, py, pz, M.cfg("AerialNoise"), C_NOISE, "sky flare")
            ringAndLabel(R, tex, vpIdx, vpZoom, px, py, pz,
                         M.cfg("AerialShotRange"), C_REACH, "gun range")
            ringAndLabel(R, tex, vpIdx, vpZoom, px, py, pz,
                         M.cfg("AerialLightRadius"), C_LIGHT, "sky flare light")

            -- How far the thing in your hand would actually go, which is the family's own range and
            -- the multiplier together rather than either on its own.
            if M.eachCarried ~= nil and M.throwRange ~= nil then
                M.eachCarried(function(player, key, item, info, remote)
                    -- These rings are drawn at the VIEWER's feet, so they describe what the viewer
                    -- is holding. Another player's stick would put a second ring here labelled with
                    -- their reach, which is a number about somebody else drawn around you.
                    if remote then return end
                    ringAndLabel(R, tex, vpIdx, vpZoom, px, py, pz,
                                 M.throwRange(info.family), C_REACH, "throw")
                end)
            end

            -- ---- WHAT IS ALREADY BURNING, drawn where it is ------------------------------------
            local flareNoise = M.cfg("FlareNoise")
            M.eachLight(function(_, rec)
                local cx = rec.fx or (rec.x + 0.5)
                local cy = rec.fy or (rec.y + 0.5)
                local cz = rec.fz or rec.z
                local dx, dy = cx - px, cy - py
                if dx * dx + dy * dy > MAX_DRAW * MAX_DRAW then return end

                ringAndLabel(R, tex, vpIdx, vpZoom, cx, cy, cz, rec.radius, C_LIGHT, "light")
                -- Only a road flare makes the repeating noise; a glow stick is silent on the ground.
                if rec.family == "RoadFlare" then
                    ringAndLabel(R, tex, vpIdx, vpZoom, cx, cy, cz, flareNoise, C_NOISE, "flare noise")
                end
            end)
        end)

        M.fxAdditive(R, true)
        if not ok then
            M.defect(PART, "the range overlay threw; additive blend has been restored")
        end
    end

    local h = M.addHandler(PART, "OnPostRender", draw)
    if h ~= nil then M.status(PART, true) end
end
