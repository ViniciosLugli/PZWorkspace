--[[
    Lamp
    Every world light this mod makes, with no jar under it.

    The mod used to reach zombie.iso.LightingJNI through a ZombieBuddy bridge, because LightingJNI
    is not on LuaManager's exposer whitelist. IsoCell IS on it (LuaManager.java:2170) and so is
    IsoLightSource (:2176), so getCell():addLamppost(...) is reachable from here and the jar is not
    needed. What that costs, and why each cost is paid rather than worked around, is below.

    WHY THE LAMPPOST PATH AND NOT THE TEMP-LIGHT PATH. LightingJNI.checkLights forks on `life`
    (:298-331). A source with life ~= -1 goes to addTempLight with its radius and colour passed
    RAW, which is the only way past the 20-tile cap. It is reachable: IsoLightSource's two 8-arg
    constructors differ in a primitive vs a non-primitive, which Kahlua separates cleanly
    (LuaJavaInvoker.java:271-292). It is still the wrong choice HERE, and the reason is the shape
    of this mod rather than the engine:

      * the engine DROPS a temp source from lamppostPositions the same pass it submits it, so the
        colour can never be changed again -- only re-submitted;
      * and this mod restates every light's colour EVERY FRAME, because a burning flare decays,
        breathes and flickers.

    Re-adding at frame rate is roughly 60 global relights per second per light, and about 20 per
    second already pins a relight on every lighting tick. The permanent arm instead lets a colour
    change go out as a bare setLightColor with no relight at all, which is exactly the cost model
    the old jar had. So: permanent lamppost, and the 20-tile cap is accepted.

    THE THREE THINGS THE LAMPPOST PATH DOES TO A LIGHT, and what is done about each:

      radius  PZMath.min(r, 20)          accepted. The families are 5, 10 and 15; only the aerial
                                         flare wanted more, and a smaller flare is a fair price for
                                         needing no dependency.
      colour  PZMath.clamp(c * 2, 0, 1)  CANCELLED EXACTLY by halving on the way in. Every channel
                                         this mod sends is already 0..1, so c/2 doubled is c, and
                                         the whole decay curve survives. This is not an
                                         approximation.
      relight Core.dirtyGlobalLightsCount++  paid on add and on remove, so a MOVE costs two. A
                                         colour change costs none, which is why moves are the only
                                         thing worth rationing here.
]]

require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

do
    local M = LugliEmergencyLights
    local PART = "Lamp"

    --- The engine doubles what it is given, so give it half. See the header.
    local COLOUR_PRESCALE = 0.5

    --- LightingJNI.java:325. Sending more is not an error, it is silently ignored.
    local MAX_RADIUS = 20

    local function now()
        if getTimestampMs == nil then return 0 end
        local ok, t = pcall(getTimestampMs)
        return (ok and type(t) == "number") and t or 0
    end

    --- HOW LONG A FRESHLY BUILT SOURCE IS HELD BEFORE IT MAY BE REBUILT, in ms.
    ---
    --- IsoCell.addLamppost only queues the source. The native id is assigned inside
    --- LightingJNI.checkLights, which runs on LightingThread at PerformanceSettings.lightingFps
    --- (LightingThread.java:63, :88; 15 by default, an options-screen setting from 5 to 60). And
    --- removeLamppost removes nothing: it sets life = 0, and a source that reaches checkLights with
    --- life == 0 and no id yet is dropped unlit (LightingJNI.java:315-318). So a light rebuilt twice
    --- between two passes loses the first build entirely.
    ---
    --- Nothing carried on foot crosses a tile that fast, so a walking light never waits here. A
    --- fired flare does: Gun.lua flies it at up to 25 tiles a second, which is a tile every 40 ms
    --- against a 67 ms pass, and without this floor it would climb dark. One pass, plus half a pass
    --- for whatever phase of the pass the source happened to land in.
    local function holdMs()
        local fps = 15
        if getPerformance ~= nil then
            local ok, v = pcall(function() return getPerformance():getLightingFPS() end)
            if ok and type(v) == "number" and v >= 1 then fps = v end
        end
        return 1500 / fps
    end

    --- Records by handle. A handle is an integer, and a negative one is the failure the callers
    --- already test for.
    local live = {}
    local owners = {}
    local freed = {}
    local nextHandle = 0

    local function finite(v)
        return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
    end

    local function clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local function cell()
        if getCell == nil then return nil end
        local ok, c = pcall(getCell)
        if not ok then return nil end
        return c
    end

    --- Take one light out of the world. The OBJECT form on purpose: removeLamppost(x,y,z) also
    --- runs clearInfluence, a (2r)^2 x 8 square walk, and the JNI removal that actually matters
    --- happens in checkLights either way.
    local function unplace(rec)
        if rec.light == nil then return end
        local c = cell()
        if c ~= nil then pcall(function() c:removeLamppost(rec.light) end) end
        rec.light = nil
    end

    --- Put one light into the world at the record's current numbers.
    ---
    --- CONSTRUCT THEN ADD, rather than the seven-argument addLamppost that builds its own source.
    --- Both overloads exist, but this is the pair shipping Workshop mods actually use -- see
    --- Explosives' FlareHandler.lua and LanternsOnTheFloorFix's FloorLamps.lua, which light a
    --- flare in flight and a dropped lamp respectively by exactly this route. Standing on a path
    --- other people's players already exercise beats standing on one only read out of a decompile.
    local function place(rec)
        local c = cell()
        if c == nil then return false end
        local ok, light = pcall(function()
            local src = IsoLightSource.new(rec.x, rec.y, rec.z,
                                           rec.r * COLOUR_PRESCALE,
                                           rec.g * COLOUR_PRESCALE,
                                           rec.b * COLOUR_PRESCALE,
                                           rec.radius)
            c:addLamppost(src)
            return src
        end)
        if not ok or light == nil then
            rec.light = nil
            return false
        end
        rec.light = light
        rec.dropped = false
        rec.holdUntil = now() + holdMs()
        return true
    end

    --- Restate one light's colour with no rebuild and no relight.
    ---
    --- checkLights compares r/g/b against rJni/gJni/bJni and emits a bare setLightColor for the
    --- difference. That is why the permanent arm was chosen over the uncapped temp one: this mod
    --- restates every colour every frame, and only this arm makes that free.
    local function colourNow(rec)
        if rec.light == nil then return false end
        local ok = pcall(function()
            rec.light:setR(rec.r * COLOUR_PRESCALE)
            rec.light:setG(rec.g * COLOUR_PRESCALE)
            rec.light:setB(rec.b * COLOUR_PRESCALE)
        end)
        return ok
    end

    --- Reserve a handle. No light exists yet: the caller has not said where it goes.
    ---
    --- NO READINESS GATE, DELIBERATELY. This used to refuse every handle until its own
    --- OnGameStart had run, and since handlers fire in registration order and nothing requires
    --- this file, it registered LAST. A consumer that asked during world entry got -1, latched
    --- its own "pool exhausted" flag, and lost every ground light for the rest of the session.
    --- A handle is only a table entry. Whether a world exists is lampSet's problem, and it
    --- already checks.
    function M.lampAcquire(owner)
        if type(owner) ~= "string" or owner == "" then return -1 end
        local h
        if #freed > 0 then
            h = table.remove(freed)
        else
            h = nextHandle
            nextHandle = nextHandle + 1
        end
        live[h] = { x = 0, y = 0, z = 0, r = 0, g = 0, b = 0, radius = 0,
                    light = nil, dropped = false }
        owners[h] = owner
        return h
    end

    --- State one light. Called EVERY FRAME for every light in the mod, so the cheap path has to be
    --- the common one: nothing changed, or only the colour did.
    function M.lampSet(h, x, y, z, r, g, b, radius)
        local rec = live[h]
        if rec == nil then return false end
        if not finite(x) or not finite(y) or not finite(z) or not finite(radius) then return false end
        if not finite(r) or not finite(g) or not finite(b) then return false end

        local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
        local ir = math.floor(clamp(radius, 1, MAX_RADIUS))
        -- NOT CLAMPED TO 0..1 HERE, deliberately. checkLights sends clamp(c * 2, 0, 1), so an
        -- out-of-range channel lands on the same colour whether this rounds it first or not, and a
        -- guard whose effect no test can observe is a guard that will rot. The radius above is a
        -- different case: it is capped here so a sandbox value can be reported honestly rather
        -- than appearing to take effect.
        local cr, cg, cb = r, g, b

        -- THE ENGINE TAKES OUR LIGHT AWAY when it leaves the loaded chunk map: checkLights drops
        -- any source failing isInBounds() and our reference goes stale silently. Noticing the
        -- return is the whole of the bookkeeping the old jar's reassert() used to do.
        --
        -- AND WHILE IT IS OUT THERE, DO NOTHING. Rebuilding a light the engine is about to drop
        -- again buys nothing and costs a global relight every frame the carrier stands off the
        -- edge of the loaded map. Record the numbers and wait for it to come back.
        if rec.light ~= nil then
            local okB, inB = pcall(function() return rec.light:isInBounds() end)
            if okB and inB == false then
                rec.dropped = true
                rec.x, rec.y, rec.z, rec.radius = ix, iy, iz, ir
                rec.r, rec.g, rec.b = cr, cg, cb
                return true
            end
        end

        local moved = rec.light == nil or rec.dropped
            or rec.x ~= ix or rec.y ~= iy or rec.z ~= iz or rec.radius ~= ir
        local recoloured = rec.r ~= cr or rec.g ~= cg or rec.b ~= cb

        -- The colour is free either way, so it always applies.
        rec.r, rec.g, rec.b = cr, cg, cb

        if moved then
            -- STILL INSIDE THE HOLD, so the source has not been through a lighting pass yet. Leave
            -- the light where it is, and leave rec's geometry alone as well, so the move is still
            -- pending and is made on a later call rather than silently dropped. See holdMs.
            if rec.light ~= nil and now() < (rec.holdUntil or 0) then
                if recoloured then colourNow(rec) end
                return true
            end
            rec.x, rec.y, rec.z, rec.radius = ix, iy, iz, ir
            unplace(rec)
            return place(rec)
        end

        if recoloured then return colourNow(rec) end
        return true
    end

    --- Give a handle back and put its light out.
    function M.lampRelease(h)
        local rec = live[h]
        if rec == nil then return end
        unplace(rec)
        live[h] = nil
        owners[h] = nil
        freed[#freed + 1] = h
    end

    --- Put out everything one owner holds. Returns how many.
    function M.lampReleaseOwner(owner)
        if type(owner) ~= "string" then return 0 end
        local n = 0
        for h, o in pairs(owners) do
            if o == owner then
                M.lampRelease(h)
                n = n + 1
            end
        end
        return n
    end

    --- How many lights this module currently holds, for the parts that budget them.
    function M.lampCount()
        local n = 0
        for _ in pairs(live) do n = n + 1 end
        return n
    end

    M.addHandler(PART, "OnGameStart", function()
        -- NOTHING IS RESET HERE, AND THAT IS THE POINT. Handlers fire in registration order, and
        -- Boot.lua requires Light.lua while nothing requires this file, so every consumer's
        -- OnGameStart runs before this one -- including the sweep, which lights everything already
        -- burning in the loaded world and takes a handle for each. This handler used to reset the
        -- registry, which reissued those handles: the next carried light and the next flare in
        -- flight were handed a handle a ground light still held, two records drove one source to
        -- two positions every frame, and the light was either never given a native id (dark) or
        -- jumped between the two (blinking). A world change is the teardown's job, below.
        M.log(PART, "world lights ready, radius capped at " .. MAX_RADIUS .. " tiles")
    end)

    -- A NEW WORLD IS A NEW CELL. IsoCell.lamppostPositions is cleared on world teardown, so
    -- nothing survives to be reclaimed. Every consumer's own teardown has already run by the time
    -- this one does, so what is left here is only what something forgot.
    M.addTeardown(PART, function()
        for h in pairs(live) do M.lampRelease(h) end
        live, owners, freed, nextHandle = {}, {}, {}, 0
    end)
end
