--[[
    Gun
    The flare gun: firing it, the flare it leaves in the sky, and the map mark.
]]

require "LugliEmergencyLights/Aim"
require "LugliEmergencyLights/Light"
require "LugliEmergencyLights/Projectile"
require "LugliEmergencyLights/Config"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- FlareGun ----------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Flare gun"

    -- How far a shot can reach, from the sandbox option. Roughly the visible screen by default: the
    -- aim point is where the player pointed rather than where a ballistic solution would land, so the
    -- clamp is about keeping the flare somewhere you can see it come down.
    local function aimRange()
        local v = M.cfg("AerialShotRange")
        if type(v) ~= "number" or v <= 0 then return 30 end
        return v
    end

    local function anyCartridge()
        for _, c in pairs(M.CARTRIDGES) do return c end
        return nil
    end

    local function onShot(character, weapon)
        if character == nil or weapon == nil then return end
        if weapon:getFullType() ~= M.GUN.item then return end
        -- OURS ONLY. The aim point comes from getMouseX/Y through this machine's camera, so running
        -- this for another player's shot would land their flare wherever we happen to be pointing,
        -- taking the light cluster, the zombie draw and the map mark with it.
        if not M.isLocalPlayer(character) then return end

        local cart = anyCartridge()
        if cart == nil then
            M.defect(PART, "no cartridge record")
            return
        end

        -- FIRED OVER THE SCENERY, so the ground path between here and there does not get a vote.
        local sq = M.skySquare(character, aimRange())
        if sq == nil then return end
        local x, y = sq:getX() + 0.5, sq:getY() + 0.5

        -- THE SHOT LEANS DOWNWIND, and it does so HERE, before anything else reads x or y.
        local windLean = 0.0
        if M.windVector ~= nil then
            local wx, wy, kph = M.windVector()
            windLean = kph * 0.012 * 1.4
            x = x + wx * windLean
            y = y + wy * windLean
        end

        local range = M.cfg("AerialRange")
        if type(range) ~= "number" then range = cart.rangeTiles end
        -- Through M.positive, not M.cfg: zero or negative reaches launchProjectile, which refuses the
        -- flight, which drops the whole shot onto the no-projectile fallback.
        local secs = M.positive("AerialSeconds", cart.aloftSeconds)

        -- THE FLARE HANGS. It climbs, then burns in the air for its whole life while drifting down.
        local z = math.floor(character:getZ())
        local radius = M.cfg("AerialLightRadius")
        if type(radius) ~= "number" then radius = 20 end

        -- The report and the recoil are now, whatever the flare does afterwards.
        local sq = character:getCurrentSquare()
        if sq ~= nil then
            M.noiseAt(character, sq:getX(), sq:getY(), sq:getZ(), M.cfg("FlareGunNoise"))
        end

        local px, py, pz = character:getX(), character:getY(), character:getZ()
        local dx, dy = x - px, y - py
        local dist = math.sqrt(dx * dx + dy * dy)
        -- APEX IS IN Z UNITS, AND ONE Z UNIT LIFTS THE SPRITE 192 SCREEN PIXELS.
        local apex = 2.6 + dist * 0.045

        -- IT LEAVES THE MUZZLE, NOT THE BOOTS.
        local mx, my, mz = px, py, pz
        if dist > 0.001 then
            local ux, uy = dx / dist, dy / dist
            mx = px + ux * 0.42 - uy * 0.11
            my = py + uy * 0.42 + ux * 0.11
            mz = pz + 0.55
        end

        -- THE BOOST IS SECONDS; THE LIFE IS MINUTES.
        local travel = 0.55 + dist * 0.022

        -- Fires once, when the composition ignites: the sky wash, the zombie draw and the map mark all
        -- begin here rather than at a landing that, for a flare that reaches altitude, never happens.
        --
        -- DECLARED BELOW THE MUZZLE SOLVE, and that position is load-bearing: a closure written above
        -- `local mx` would bind the GLOBAL mx, which is nil, and the packet would carry nothing.
        local function onLit(aloft)
            -- Guarded like every other cross-file call in this mod: these two live in Net.lua, and
            -- a shot that threw here would take the projectile ticker down with it rather than
            -- costing one flare.
            if M.aerialComposition == nil then
                M.defect(PART, "Net.lua did not load; a fired flare will not light")
                return
            end
            M.aerialComposition(x, y, z, secs, range, cart.r, cart.g, cart.b,
                                character, aloft ~= false)
        end

        -- AND TELL EVERYONE ELSE, NOW, NOT AT IGNITION. Nothing about a fired flare is derivable
        -- from replicated state: it leaves no item behind and the aim point existed only on this
        -- machine. It is sent here rather than from onLit because onLit fires when the flare
        -- IGNITES, a second or more into the flight, while the muzzle below was captured at the
        -- trigger -- and the server checks that muzzle against where the shooter is standing when
        -- the packet arrives. Anyone who kept walking after firing had their flare silently
        -- refused, which is most people, most of the time.
        --
        -- The receiver replays the whole flight from these numbers, so nothing is gained by waiting.
        if M.sendFlare ~= nil then
            M.sendFlare(character, x, y, z, secs, range, mx, my, mz, travel, apex, cart)
        end

        local launched = false
        if M.launchProjectile ~= nil then
            launched = M.launchProjectile(character, mx, my, mz, x, y,
                                          secs, travel, apex, cart.r, cart.g, cart.b,
                                          radius, onLit, nil, false,
                                          -- No bounce table: it never touches the ground, and full windage, because a
                                          -- flare under a canopy is the most wind-affected thing this mod has.
                                          nil, 1.0)
        end

        -- ONE LINE PER SHOT, the way the throw reports itself.
        M.debug(PART, string.format(
            "fired %.1f tiles, apex %.2fz in %.2fs, wind lean %.2f, wash %d tiles for %ds%s",
            dist, apex, travel, windLean, math.floor(range), math.floor(secs),
            launched and "" or "  DEFECT: no projectile part, the flare did not fly"))
    end

    --- The trigger was pulled.
    local function onSwing(character, weapon)
        if character == nil or weapon == nil then return end
        if weapon:getFullType() ~= M.GUN.item then return end
        local ok, ammo = pcall(function() return weapon:getCurrentAmmoCount() end)
        if not ok or type(ammo) ~= "number" or ammo > 0 then return end

        M.playOn(character, M.SND_FLAREGUN_DRY)

        -- And cancel the swing, so an empty gun clicks instead of miming a shot it did not fire.
        pcall(function()
            character:setAttackStarted(false)
            character:setRecoilDelay(0.0)
        end)
    end

    --- Break the action and load a cartridge.
    local function hookReload()
        if ISReloadWeaponAction == nil or type(ISReloadWeaponAction.perform) ~= "function" then
            M.status(PART, false, "ISReloadWeaponAction is not on this build", "dep")
            return
        end
        if ISReloadWeaponAction._lugliEL_reload then return end
        local original = ISReloadWeaponAction.perform
        ISReloadWeaponAction.perform = function(self, ...)
            pcall(function()
                -- `gun`, not `item`. ISReloadWeaponAction:new stores the weapon as o.gun and there is
                -- no self.item on it anywhere, so the guard was never true and the shipped
                -- LugliEL_FlareGunReload.ogg was never once heard.
                if self.gun ~= nil and self.gun:getFullType() == M.GUN.item then
                    M.playOn(self.character, M.SND_FLAREGUN_RELOAD)
                end
            end)
            return original(self, ...)
        end
        ISReloadWeaponAction._lugliEL_reload = true
    end

    local h = M.addHandler(PART, "OnWeaponSwingHitPoint", onShot)
    M.addHandler(PART, "OnWeaponSwing", onSwing)

    -- After every other mod has had its turn at the class.
    M.addHandler(PART, "OnGameStart", hookReload)

    if h ~= nil then M.status(PART, true) end
end

-- ---- Flare -------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Flare"

    local nextWash = 0
    local nextNoise = 0
    local nextAerial = 0
    local phase = 0

    -- WorldFlares.launchFlare takes accumulated GameTime.getMultiplier, which advances about 48 per
    -- REAL second. The engine's own ClimateManager passes 7200, which is 150 seconds.
    local MULT_PER_SECOND = 48

    -- Re-launched rather than launched once: a Flare has no setters, its list caps at 101 and evicts
    -- the oldest, and it is cleared on world init. A short lifetime refreshed on a timer is
    -- self-limiting and survives a reload.
    --- How far away a burning flare can be and still be worth washing the sky for, in tiles.
    local WASH_CULL = 80

    local WASH_SECONDS = 25
    local WASH_EVERY_MS = 20000

    -- A burning flare KEEPS calling.
    local NOISE_EVERY_MS = 1000

    -- Four times a second. The swap only happens when you cross the boundary, but the DISTANCE
    -- check walks every live light, and a fired flare does not move.
    local AERIAL_EVERY_MS = 250

    --- Is this record a FLARE, of any kind?
    local function isFlare(rec)
        return rec.flare == true
            or rec.sound == M.SND_FLARE_BURN
            or rec.sound == M.SND_FLARE_BURN_AERIAL
            or rec.sound == M.SND_FLARE_BURN_AERIAL_NEAR
    end

    --- Every wash this mod has launched that is still worth driving, keyed by the engine's own flare
    --- id.
    local washes = {}
    local washN = 0

    local function launch(x, y, range, seconds, r, g, b)
        if WorldFlares == nil then return false end
        local id = nil
        local ok = pcall(function()
            id = WorldFlares.nextId
            WorldFlares.launchFlare(
                seconds * MULT_PER_SECOND,
                math.floor(x), math.floor(y), math.floor(range),
                0.0,
                r, g, b,
                r, g, b)
        end)
        if ok and type(id) == "number" then
            washes[id] = { born = getTimestampMs ~= nil and getTimestampMs() or 0,
                           life = seconds * 1000.0, r = r, g = g, b = b }
            washN = washN + 1
        end
        return ok
    end
    M.launchWash = launch

    --- Drive the colour of every live wash across its life.
    local function washColour()
        if WorldFlares == nil or washN == 0 or getTimestampMs == nil then return end
        local now = getTimestampMs()
        for id, w in pairs(washes) do
            local k = w.life > 0 and (now - w.born) / w.life or 1.0
            if k >= 1.0 then
                washes[id] = nil
                washN = washN - 1
            else
                -- White-hot for the first tenth, then down through its own colour, ending deep and
                -- dim. Squared on the way out so most of the life is spent at the flare's real hue
                -- rather than sliding continuously.
                local hot = k < 0.10 and (1.0 - k / 0.10) or 0.0
                local fade = 1.0 - 0.45 * k * k
                local r = (w.r + (1.0 - w.r) * hot) * fade
                local g = (w.g + (1.0 - w.g) * hot) * fade
                local b = (w.b + (1.0 - w.b) * hot) * fade
                pcall(function()
                    local f = WorldFlares.getFlareID(id)
                    if f ~= nil then f:getColor():setExterior(r, g, b, 1.0) end
                end)
            end
        end
    end

    --- One flicker step across every burning flare light.
    local function flicker(dt)
        -- BY TIME, NOT BY FRAME.
        phase = phase + (dt or (1.0 / 60.0)) * 60.0

        -- ONE, NOT ZERO, WHEN THE OPTION IS OFF.
        local k = 1.0
        if M.cfg("LightFlicker") == true then
            -- A cheap deterministic wobble. Two periods that do not divide each other, so it never
            -- settles into a visible pulse.
            k = 0.88 + 0.12 * math.abs(math.sin(phase * 0.31) * math.cos(phase * 0.17))
        end
        M.eachLight(function(_, rec)
            -- rec.cd is the whole test now. There is no rec.light any more: the lamppost path this
            -- registry used to fall back to is gone, and every live record holds a world-light handle.
            if isFlare(rec) and rec.cd ~= nil then
                -- CONTRIBUTED, NOT WRITTEN.
                rec.flick = k
            end
        end)
    end

    --- Forget every wash.
    local function washForget()
        washes = {}
        washN = 0
    end

    local function washPass()
        if getTimestampMs == nil then return end
        local now = getTimestampMs()
        if now < nextWash then return end
        nextWash = now + WASH_EVERY_MS

        -- THROUGH M.lightRadius, so one option means one thing to both of its readers.
        local groundRange = M.lightRadius("RoadFlare")
        if type(groundRange) ~= "number" then groundRange = 9 end
        -- ONE WASH, FOR THE NEAREST FLARE ONLY.
        local px, py = nil, nil
        if getPlayer ~= nil then
            local okp, pl = pcall(getPlayer)
            if okp and pl ~= nil then
                pcall(function() px, py = pl:getX(), pl:getY() end)
            end
        end

        local best, bestD = nil, nil
        M.eachLight(function(_, rec)
            if not isFlare(rec) or rec.sound == nil then return end
            local d = 0.0
            if px ~= nil then
                local dx, dy = rec.x - px, rec.y - py
                d = dx * dx + dy * dy
            end
            if bestD == nil or d < bestD then best, bestD = rec, d end
        end)

        -- And only if it is close enough to be worth a sky effect at all. Beyond this the wash is
        -- invisible anyway: applyFlaresForPlayer scales it by distance.
        if best ~= nil and (bestD == nil or bestD <= WASH_CULL * WASH_CULL) then
            local wr = best.washR or best.baseR
            local wg = best.washG or best.baseG
            local wb = best.washB or best.baseB
            local wrange = best.washRange
            if type(wrange) ~= "number" then wrange = groundRange * 2 end
            launch(best.x, best.y, wrange, WASH_SECONDS, wr, wg, wb)
        end
    end

    --- Draw zombies to every burning flare, ground and aerial alike.
    local function noisePass()
        if getTimestampMs == nil then return end
        local now = getTimestampMs()
        if now < nextNoise then return end
        nextNoise = now + NOISE_EVERY_MS

        local radius = M.cfg("FlareNoise")
        if type(radius) ~= "number" or radius <= 0 then return end

        -- NO isServer() GATE HERE, AND THAT IS DELIBERATE. It was tried and it broke the feature.

        M.eachLight(function(_, rec)
            -- Only the sounding one. A cluster's ring lights are the same flare, and drawing zombies
            -- seven times over would make a fired flare seven times the beacon a dropped one is.
            if isFlare(rec) and rec.sound ~= nil then
                -- The light is the source. A flare draws zombies to ITSELF, not to whoever lit it,
                -- which is what makes throwing one a way to send them somewhere else.
                M.noiseRepeatingAt(rec.light or rec.emitter, rec.x, rec.y, rec.z, radius)
            end
        end)

        -- AND THE ONE IN YOUR HAND, which is the first thing a player will try.
        M.forEachLocalPlayer(function(player)
            local item = player:getPrimaryHandItem()
            local info = item ~= nil and M.litInfo(item) or nil
            if info == nil then
                item = player:getSecondaryHandItem()
                info = item ~= nil and M.litInfo(item) or nil
            end
            if info == nil or M.isExpired(item) then return end
            if M.burnSoundFor(info.family) == nil then return end
            local sq = player:getCurrentSquare()
            if sq ~= nil then
                M.noiseRepeatingAt(player, sq:getX(), sq:getY(), sq:getZ(), radius)
            end
        end)

        -- AND THE ONE IN THE AIR, which is the third of the three states and was the only one missing.
        if M.eachProjectile ~= nil then
            M.eachProjectile(function(x, y, z, family, slot)
                if M.burnSoundFor(family) == nil then return end
                M.noiseRepeatingAt(slot, math.floor(x), math.floor(y), z, radius)
            end)
        end
    end

    --- A fired flare burns ABOVE its landing point, so how it should be heard depends on where you are
    --- standing rather than on where it is.
    -- Reused across passes: at most one entry per local player.
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

    local function aerialPass()
        if getTimestampMs == nil then return end
        local now = getTimestampMs()
        if now < nextAerial then return end
        nextAerial = now + AERIAL_EVERY_MS

        local near = M.AERIAL_NEAR_TILES
        if type(near) ~= "number" or near <= 0 then near = 12 end

        -- HYSTERESIS, because the swap is not free: it stops one loop and starts another, so a player
        -- standing exactly on the boundary would restart the burn every time this ran. Crossing OUT
        -- costs a tile more than crossing in, which is enough that ordinary walking never oscillates.
        local inner2 = near * near
        local outer2 = (near + 1.0) * (near + 1.0)

        -- THE PLAYERS ONCE, not once per record. forEachLocalPlayer costs two engine calls per player
        -- and a fresh closure, and it was inside the per-record walk answering a question that is the
        -- same for every record in the pass.
        local pn = collectPlayers()
        if pn == 0 then return end

        M.eachLight(function(_, rec)
            local isNear = rec.sound == M.SND_FLARE_BURN_AERIAL_NEAR
            if not isNear and rec.sound ~= M.SND_FLARE_BURN_AERIAL then return end

            -- Nearest local player, so split screen does not let one view decide for the other.
            local best = nil
            for i = 1, pn do
                local dx = playerX[i] - rec.x
                local dy = playerY[i] - rec.y
                local d2 = dx * dx + dy * dy
                if best == nil or d2 < best then best = d2 end
            end
            if best == nil then return end

            if isNear then
                if best > outer2 then M.reSound(rec, M.SND_FLARE_BURN_AERIAL) end
            elseif best < inner2 then
                M.reSound(rec, M.SND_FLARE_BURN_AERIAL_NEAR)
            end
        end)
    end

    local function tick()
        -- Drives the shared, subtle wobble every light uses. Time-based, so it looks the same at 30
        -- and 144 fps, unlike the flare's own flicker which is deliberately phase-stepped.
        local dt = M.frameDelta()
        M.stepIncidence(dt)

        -- flicker() pairs-walks EVERY live light to find flares, so with forty dropped sticks and no
        -- flare at all that was 2,400 closure calls a second to animate nothing. The registry knows
        if M.flareLightCount() > 0 then flicker(dt) end
        if M.cfg("FlareWash") == true then
            washPass()
            -- Every frame, and cheap: it skips on a counter when no wash is live, and a live one is
            -- three lerps and one setter. The wash lasts 25 seconds and is re-issued every 20, so
            -- there are rarely more than two.
            washColour()
        end
        noisePass()
        aerialPass()
    end

    -- PER FRAME, but only the flicker needs it, and only when there is a flare to flicker. The other
    -- three passes throttle themselves on their own clocks.
    local h = M.addTicker(PART, 0, tick)

    -- The engine clears its own flare list on world init (ClimateManager.init -> WorldFlares.Clear),
    -- so a record surviving a world change would be driving an id that now belongs to someone else's
    -- flare -- or to nothing.
    M.addTeardown(PART, washForget)

    if h ~= nil then M.status(PART, true) end
end

-- ---- Map ---------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Map"

    -- { marker, until }
    local marks = {}

    -- Kept small so a distant flare is still a visible dot rather than a sub-pixel speck.
    local MIN_SCREEN_RADIUS = 6
    local DOT_RADIUS = 10

    -- Marks asked for before the map existed. See markersAPI.
    local pending = {}

    local function markersAPI()
        -- ISWorldMap_instance is created lazily the FIRST TIME THE MAP IS OPENED. A flare fired
        -- before that got no marker at all, and every later one did, which reads as the feature
        -- randomly working. Requests are queued instead and placed once the API appears.
        if ISWorldMap_instance == nil then return nil end
        local ok, api = pcall(function()
            return ISWorldMap_instance.javaObject:getAPIv3():getMarkersAPI()
        end)
        if not ok then return nil end
        return api
    end

    --- Mark a flare at a world point for `seconds`.
    function M.markFlare(x, y, range, seconds, r, g, b)
        if M.cfg("MapMarker") ~= true then return end
        local api = markersAPI()
        if api == nil then
            pending[#pending + 1] = { x = x, y = y, range = range, r = r, g = g, b = b,
                                      expires = M.worldHours() + (seconds or 60) / 3600.0 }
            return
        end

        -- Off by default: at a long range the true circle covers most of the visible map.
        local radius = DOT_RADIUS
        if M.cfg("MapRangeCircle") == true and type(range) == "number" then
            radius = range
        end

        local ok, marker = pcall(function()
            return api:addGridSquareMarker(math.floor(x), math.floor(y),
                                           math.floor(radius), r, g, b, 1.0)
        end)
        if not ok or marker == nil then return end

        pcall(function()
            marker:setBlink(true)
            marker:setMinScreenRadius(MIN_SCREEN_RADIUS)
        end)

        marks[#marks + 1] = {
            marker = marker,
            -- Game clock, matching the light it marks. On the wall clock, opening the map to look at
            -- the marker paused the world while the marker's own timer kept running.
            expires = M.worldHours() + (seconds or 60) / 3600.0,
        }
    end

    --- Place anything that was asked for before the map existed, dropping what has since expired.
    local function flushPending()
        if #pending == 0 then return end

        -- EXPIRE FIRST, WHETHER OR NOT THE MAP IS UP. This list is the mod's own bookkeeping and does
        -- not need the world map to forget a flare that has burned out.
        local now = M.worldHours()
        if now ~= nil then
            local kept, n = {}, 0
            for i = 1, #pending do
                local p = pending[i]
                if now < p.expires then
                    n = n + 1
                    kept[n] = p
                end
            end
            pending = kept
            if n == 0 then return end
        end

        local api = markersAPI()
        if api == nil then return end
        if now == nil then return end

        local queued = pending
        pending = {}
        for i = 1, #queued do
            local p = queued[i]
            if now < p.expires then
                M.markFlare(p.x, p.y, p.range, (p.expires - now) * 3600.0, p.r, p.g, p.b)
            end
        end
    end

    local function reap()
        if M.worldHours == nil then return end
        flushPending()
        local now = M.worldHours()
        local api = markersAPI()
        local keep = {}
        for i = 1, #marks do
            local m = marks[i]
            if now < m.expires then
                keep[#keep + 1] = m
            elseif api == nil then
                -- EXPIRED BUT NOT REMOVABLE: the map has gone away since this was placed, so there is
                -- no API to remove it through.
                keep[#keep + 1] = m
            else
                pcall(function() api:removeMarker(m.marker) end)
            end
        end
        marks = keep
    end

    local h = M.addHandler(PART, "EveryOneMinute", reap)
    if h == nil then h = M.addTicker(PART, M.scanInterval, reap) end

    -- FLUSHED ON ITS OWN CLOCK, once a second.
    M.addTicker(PART, 1.0, flushPending)

    M.addTeardown(PART, function() marks, pending = {}, {} end)

    if h ~= nil then M.status(PART, true) end
end
