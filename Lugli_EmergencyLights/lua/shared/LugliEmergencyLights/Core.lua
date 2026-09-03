--[[
    Core
    Environment, items, sound and the part registry.
]]

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- Core --------------------------------------------------------------------------------------
do
    --- Every item the player is carrying, INCLUDING inside bags, as a flat array.
    function LugliEmergencyLights.allCarried(player, depth)
        local out = {}
        if player == nil then return out end

        local function walk(container, d)
            if container == nil or d > 3 then return end
            local items = container:getItems()
            if items == nil then return end
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item ~= nil then
                    out[#out + 1] = item
                    if item:IsInventoryContainer() then
                        local inner = item:getInventory()
                        if inner ~= nil and inner ~= container then walk(inner, d + 1) end
                    end
                end
            end
        end

        pcall(function() walk(player:getInventory(), depth or 1) end)
        return out
    end

    --- One world-object coordinate, or the tile centre when it cannot be had.
    function LugliEmergencyLights.worldPosOf(wo, axis, tile)
        local mid = (axis == "Z") and tile or (tile + 0.5)
        if wo == nil then return mid end
        local ok, v = pcall(function()
            if axis == "X" then return wo:getWorldPosX() end
            if axis == "Y" then return wo:getWorldPosY() end
            return wo:getWorldPosZ()
        end)
        if not ok or type(v) ~= "number" or v ~= v then return mid end
        return v
    end

    --- How the item is lying, in degrees, or nil if it cannot be asked.
    function LugliEmergencyLights.itemRotation(item, axis)
        if item == nil then return nil end
        local ok, v = pcall(function()
            if axis == "P" then return item:getWorldYRotation() end
            return item:getWorldZRotation()
        end)
        if not ok or type(v) ~= "number" or v ~= v then return nil end
        return v
    end

    --- The tile a MOVING light should sit on: the nearest one, not the one it is inside.
    function LugliEmergencyLights.lightTile(v)
        if type(v) ~= "number" then return v end
        return math.floor(v + 0.5)
    end

    --- Put a replacement item onto the belt, the back or the holster at a named attachment
    --- location, in the hotbar slot that serves that location.
    ---
    --- BY LOCATION, NOT BY THE OLD ITEM. The item being replaced is gone by the time this runs
    --- on a multiplayer client: the server swapped it and the engine's own inventory packets took
    --- it out of every container, so its slot index cannot be read off it any more. What survives
    --- the round trip is the attachment location string ("Belt Left"), which is what the
    --- character indexes its attached items by and what the authority read before the swap.
    --- The hotbar slot is found from that: each slot's definition names the location it attaches
    --- an item of this attachment type to. Client-only: getPlayerHotbar is a UI global.
    function LugliEmergencyLights.reattachAt(player, newItem, location)
        if player == nil or newItem == nil or location == nil or location == "" then return false end
        if getPlayerHotbar == nil then return false end

        local ok, done = pcall(function()
            local hotbar = getPlayerHotbar(player:getPlayerNum())
            if hotbar == nil or type(hotbar.availableSlot) ~= "table" then return false end
            local kind = newItem:getAttachmentType()
            if kind == nil then return false end
            for idx, slot in pairs(hotbar.availableSlot) do
                local def = slot.def
                if type(def) == "table" and type(def.attachments) == "table"
                    and def.attachments[kind] == location then
                    hotbar:attachItem(newItem, location, idx, def, false)
                    return true
                end
            end
            return false
        end)
        return ok and done == true
    end

    --- Take an item off the belt, the back or the holster, and off the character's model with it.
    function LugliEmergencyLights.detachAttachment(item, player)
        if item == nil or player == nil then return false end
        if getPlayerHotbar == nil then return false end

        local ok, gone = pcall(function()
            local idx = item:getAttachedSlot()
            if type(idx) ~= "number" or idx < 0 then return false end

            local hotbar = getPlayerHotbar(player:getPlayerNum())
            if hotbar == nil then return false end

            hotbar:removeItem(item, false)
            return true
        end)
        return ok and gone == true
    end

    --- Seconds of GAME time since the last frame, defaulting to 1/60.
    local function readDelta() return getGameTime():getTimeDelta() end

    function LugliEmergencyLights.frameDelta()
        if getGameTime == nil then return 1.0 / 60.0 end
        local ok, d = pcall(readDelta)
        if ok and type(d) == "number" and d > 0.0 then return d end
        return 1.0 / 60.0
    end

    local M = LugliEmergencyLights

    M.TAG = "EmergencyLights"

    -- THE WIRE NAMES. Namespaced, because OnClientCommand/OnServerCommand fire for every mod on
    -- the server and the module string is the only thing separating them.
    M.NET_MODULE     = "LugliEmergencyLights"
    M.NET_FLARE      = "flare"      -- client -> server: I fired one
    M.NET_FLARE_ECHO = "flareAt"    -- server -> everyone: somebody fired one
    M.NET_DROP       = "drop"       -- client -> server: put this on the ground for me
    M.NET_DROP_ECHO  = "dropped"    -- server -> the thrower: it is on the ground now, or not
    M.NET_CRACK      = "crack"      -- client -> server: crack this sealed item of mine
    M.NET_CRACK_ECHO = "cracked"    -- server -> that client: swapped, with the new item's id
    M.NET_THROW      = "throw"      -- client -> server: I threw one, here is its flight
    M.NET_THROW_ECHO = "thrown"     -- server -> everyone: somebody threw one
    M.NET_EXPIRE_ECHO = "burntOut"  -- server -> that client: one of yours burnt out and was swapped
    M.NET_LAND_ECHO  = "landed"     -- server -> everyone: a throw ended HERE, light this tile

    --- ZombRandFloat, guarded. The engine's own generator, so this follows the world seed rather than
    --- a second unseeded one; the midpoint is the fallback when it is absent.
    function M.rand(lo, hi)
        if ZombRandFloat == nil then return (lo + hi) * 0.5 end
        local ok, v = pcall(ZombRandFloat, lo, hi)
        if not ok or type(v) ~= "number" then return (lo + hi) * 0.5 end
        return v
    end

    --- Symmetric noise in [-amount, amount], zero when the generator is absent.
    function M.jitter(amount)
        if ZombRandFloat == nil then return 0.0 end
        local ok, v = pcall(ZombRandFloat, -amount, amount)
        if not ok or type(v) ~= "number" then return 0.0 end
        return v
    end

    -- WHERE ARE WE RUNNING.
    local function boolCall(fn)
        if type(fn) ~= "function" then return false end
        local ok, v = pcall(fn)
        return ok and v == true
    end

    -- CACHED AT LOAD, AND THAT IS CORRECT. GameClient.client is set in
    -- ConnectionManager.doServerConnect BEFORE the handshake, and ConnectToServerState then calls
    -- Core.ResetLua, which rebuilds the whole Lua VM and re-runs LoadDirBase with the flag already
    -- true. So this file is re-executed as a multiplayer client and these read true.
    local IS_SERVER = boolCall(isServer)
    local IS_CLIENT = boolCall(isClient)

    function M.isDedicatedServer() return IS_SERVER and not IS_CLIENT end
    function M.isMultiplayer()     return IS_SERVER or IS_CLIENT end

    --- Is this the co-op HOST's client process? Read live, never cached: GameClient.connection is
    --- nil while this file first loads, so a value captured here would latch false forever.
    --- IS_SERVER and IS_CLIENT was the old test and it is never true on any process -- the co-op
    --- host's server runs in a CHILD JVM, so the host itself is an ordinary multiplayer client.
    function M.isCoopHost()
        if not IS_CLIENT then return false end
        return boolCall(isCoopHost)
    end

    --- IS THIS MACHINE ALLOWED TO CHANGE THE WORLD?
    --- True on a dedicated server, on a co-op child server, and in single player: exactly one
    --- process per world. isServer() cannot answer this -- it is false in single player, where the
    --- work still has to happen -- which is why electing on it was tried and failed.
    function M.isWorldAuthority() return not IS_CLIENT end

    function M.envName()
        if M.isCoopHost() then return "co-op host" end
        if M.isDedicatedServer() then return "dedicated server" end
        if IS_CLIENT then return "multiplayer client" end
        return "single player"
    end

    --- Outcome of one part, rendered by the main-menu panel.
    function M.status(key, ok, note, kind)
        M.parts[key] = { ok = ok, note = note, kind = kind }
    end

    function M.log(part, msg)
        print("[" .. M.TAG .. "/" .. tostring(part) .. "] " .. tostring(msg))
    end

    --- A DIAGNOSTIC, printed only when the player has asked for them.
    function M.debug(part, msg)
        if M.cfg == nil or M.cfg("DebugLog") ~= true then return end
        M.log(part, msg)
    end

    --- A failure that should not have happened.
    local reported = {}
    function M.defect(part, note)
        M.status(part, false, note, "bug")
        if reported[part] then return end
        reported[part] = true
        print("[" .. M.TAG .. "/" .. tostring(part) .. "] DEFECT: " .. tostring(note))
    end

    --- Register an event handler that fails ONCE and then goes quiet.
    function M.addHandler(part, eventName, fn)
        if Events == nil or Events[eventName] == nil then
            M.defect(part, "Events." .. tostring(eventName) .. " does not exist on this build")
            return nil
        end
        local wrapped
        wrapped = function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                Events[eventName].Remove(wrapped)
                M.defect(part, eventName .. " handler removed after: " .. tostring(err))
            end
        end
        Events[eventName].Add(wrapped)
        return wrapped
    end

    -- ONE OnTick FOR THE WHOLE MOD.
    local tickers = {}
    local tickerHandler = nil

    --- Run fn every `seconds`. seconds may be a number, or a function returning one when the
    --- interval is a sandbox option that can change under us. Zero means every frame.
    function M.addTicker(part, seconds, fn)
        tickers[#tickers + 1] = { part = part, at = 0, every = seconds, fn = fn }

        if tickerHandler == nil then
            tickerHandler = M.addHandler("Core", "OnTick", function()
                local now = getTimestampMs ~= nil and getTimestampMs() or 0
                for i = #tickers, 1, -1 do
                    local t = tickers[i]
                    local every = t.every
                    if type(every) == "function" then every = every() end
                    if type(every) ~= "number" or every < 0 then every = 0 end
                    if now >= t.at then
                        t.at = now + every * 1000
                        local ok, err = pcall(t.fn)
                        if not ok then
                            table.remove(tickers, i)
                            M.defect(t.part, "ticker removed after: " .. tostring(err))
                        end
                    end
                end
            end)
            if tickerHandler == nil then return nil end
        end
        return true
    end

    --- How often the scanning parts run, from the one sandbox option that governs it.
    function M.scanInterval()
        local secs = M.cfg ~= nil and M.cfg("SweepSeconds") or nil
        if type(secs) ~= "number" or secs <= 0 then return 1.0 end
        return secs
    end

    --- Translate, treating an echoed key as a miss.
    function M.T(key, fallback)
        if type(key) ~= "string" then return fallback or "" end
        if getText == nil then return fallback or key end
        local ok, s = pcall(getText, key)
        if ok and type(s) == "string" and s ~= key then return s end
        return fallback or key
    end

    --- Release everything this part owns when the world goes away.
    function M.addTeardown(part, fn)
        M.addHandler(part, "OnDisconnect", fn)
        M.addHandler(part, "OnMainMenuEnter", fn)
    end

    --- Is this character one THIS machine controls?
    ---
    --- FAILS CLOSED, and the class test comes first. isLocalPlayer() is declared on IsoPlayer, not
    --- on IsoGameCharacter, and OnWeaponSwingHitPoint hands us the latter: a zombie swinging a lit
    --- stick used to pass this check, reach the aim resolver, and throw its stick at THIS machine's
    --- mouse cursor. Answering "yes" when the question could not be asked is the wrong default in
    --- every caller here.
    function M.isLocalPlayer(character)
        if character == nil then return false end
        if instanceof ~= nil and not instanceof(character, "IsoPlayer") then return false end
        local ok, v = pcall(function() return character:isLocalPlayer() end)
        return ok and v == true
    end

    --- Flatten a context-menu selection into real InventoryItems.
    function M.selectedItems(items)
        if items == nil then return {} end
        if ISInventoryPane ~= nil and type(ISInventoryPane.getActualItems) == "function" then
            local ok, actual = pcall(ISInventoryPane.getActualItems, items)
            if ok and type(actual) == "table" then return actual end
        end
        local out = {}
        for _, v in ipairs(items) do
            if instanceof ~= nil and instanceof(v, "InventoryItem") then
                out[#out + 1] = v
            elseif type(v) == "table" and type(v.items) == "table" then
                for i = 2, #v.items do out[#out + 1] = v.items[i] end
            end
        end
        return out
    end

    --- Every local player, so split screen works rather than only player one.
    --- RENDERING AND INPUT ONLY. On a dedicated server getNumActivePlayers() is 0, so this yields
    --- nothing there; anything the world authority has to walk wants forEachWorldPlayer.
    function M.forEachLocalPlayer(fn)
        if getNumActivePlayers == nil or getSpecificPlayer == nil then return end
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p ~= nil then fn(p, i) end
        end
    end

    --- Every player whose surroundings this process is responsible for.
    ---
    --- Two drivers, because neither covers both worlds this runs in: getOnlinePlayers() is
    --- GameServer.getPlayers() on a dedicated server and an EMPTY list in single player, while
    --- getNumActivePlayers() is 0 on a dedicated server. The index passed to fn is a position in
    --- the walk, not a player number -- do not use it for a viewport.
    function M.forEachWorldPlayer(fn)
        if getOnlinePlayers ~= nil then
            local ok, list = pcall(getOnlinePlayers)
            if ok and list ~= nil then
                local okN, n = pcall(function() return list:size() end)
                if okN and type(n) == "number" and n > 0 then
                    for i = 0, n - 1 do
                        local p = list:get(i)
                        if p ~= nil then fn(p, i) end
                    end
                    return
                end
            end
        end
        M.forEachLocalPlayer(fn)
    end

    M.status("Core", true)
end

-- ---- Sound -------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Sound"

    -- Prefixed: GameSounds keys one flat map on the bare name and ignores the module, so an
    -- unprefixed name is replaced by any later-loading mod that picks the same one.
    M.SND_CRACK = "LugliEL_StickCrack"
    M.SND_FLARE_BURN = "LugliEL_FlareBurn"
    -- One clip, five entries, because volume and 3D-ness are SCRIPT properties: every field on
    -- FMODSoundEmitter is a public instance field, so Kahlua can neither read a playing instance's
    -- handle nor set its volume. Which one plays is decided by where the flare is.
    M.SND_FLARE_BURN_HELD    = "LugliEL_FlareBurnHeld"      -- your own hand: mono, and twice as loud
    M.SND_FLARE_BURN_CARRIED = "LugliEL_FlareBurnCarried"   -- your own bag: mono, world volume
    M.SND_FLARE_BURN_REMOTE  = "LugliEL_FlareBurnRemote"    -- someone else's hand: positional
    M.SND_FLARE_BURN_AERIAL  = "LugliEL_FlareBurnAerial"    -- fired and burning: louder, carries further
    M.SND_FLARE_BURN_AERIAL_NEAR = "LugliEL_FlareBurnAerialNear"  -- standing under it: mono, no direction

    --- Beyond this many tiles a fired flare is a thing over there; inside it, it is overhead.
    M.AERIAL_NEAR_TILES = 8
    M.SND_FLAREGUN_RELOAD    = "LugliEL_FlareGunReload"
    M.SND_FLAREGUN_DRY       = "LugliEL_FlareGunDry"

    -- THE SHOT ITSELF IS NOT PLAYED FROM HERE. The gun's item script sets SwingSound to
    -- LugliEL_FlareGunShot and ClickSound to LugliEL_FlareGunDry, so the engine plays both by itself;
    -- playing the shot from Lua as well gave two reports for one trigger pull.

    --- Which looping burn sound a family makes, or nil for the ones that burn silently.
    function M.burnSoundFor(familyId)
        if familyId == "RoadFlare" then return M.SND_FLARE_BURN end
        return nil
    end

    --- One-shot at a square. Replicates, so other players hear it.
    local function playAt(square, name)
        if square == nil or name == nil or M.isDedicatedServer() then return end
        pcall(function() square:playSound(name) end)
    end

    --- One-shot on a character.
    function M.playOn(character, name)
        if character == nil then return end
        local sq = character:getCurrentSquare()
        if sq ~= nil then playAt(sq, name) end
    end

    --- A free emitter at a world point, or nil.
    function M.emitterAt(x, y, z)
        if getWorld == nil or x == nil or y == nil then return nil end
        -- An emitter at exactly (0,0) is forced to 2D and would follow the listener around.
        if x == 0 and y == 0 then return nil end
        local ok, e = pcall(function()
            return getWorld():getFreeEmitter(x + 0.5, y + 0.5, z or 0)
        end)
        return ok and e or nil
    end

    --- Start or re-arm a loop. Looping comes from `loop = true` in the sound script, not from here.
    function M.loopOn(emitter, name, square)
        if emitter == nil or name == nil or square == nil then return false end
        -- Poll rather than cache a channel handle, as IsoGenerator does: self-healing across a
        -- chunk reload that dropped the channel.
        local ok, playing = pcall(function() return emitter:isPlaying(name) end)
        if ok and playing then return true end
        -- playSoundImpl, not playSound: every client derives this loop from the item it can already
        -- see, so replicating it would stack one copy per player in range.
        return pcall(function() emitter:playSoundImpl(name, square) end)
    end

    --- Stop an emitter. Every path that drops a light must call this: a loop never reports
    --- isEmpty(), so an abandoned emitter is ticked forever at a fixed position.
    function M.stopEmitter(emitter)
        if emitter == nil then return end
        pcall(function() emitter:stopAll() end)
    end

    --- Attract zombies.
    function M.noiseAt(source, x, y, z, radius)
        if radius == nil or radius <= 0 or getWorldSoundManager == nil then return end
        pcall(function()
            getWorldSoundManager():addSound(source, x, y, z or 0, radius, radius)
        end)
    end

    --- A noise that is ONGOING, re-asserted by its caller for as long as the source is alive.
    function M.noiseRepeatingAt(source, x, y, z, radius)
        if radius == nil or radius <= 0 or getWorldSoundManager == nil then return end
        pcall(function()
            getWorldSoundManager():addSoundRepeating(
                source, x, y, z or 0, radius, radius, false, false)
        end)
    end

    M.status(PART, true)
end
