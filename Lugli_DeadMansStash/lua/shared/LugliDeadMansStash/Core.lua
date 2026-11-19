--[[
    Core
    Environment election, logging, the part registry with its boot line, the mod's one OnTick and
    the wire names. The shape is Lugli - Power Grid's Core, cut down to what this mod needs.
]]

LugliDeadMansStash = LugliDeadMansStash or {}
LugliDeadMansStash.parts = LugliDeadMansStash.parts or {}
LugliDeadMansStash.partOrder = LugliDeadMansStash.partOrder or {}

do
    local M = LugliDeadMansStash

    M.TAG = "Lugli/DeadMansStash"
    M.MOD_ID = "Lugli_DeadMansStash"
    M.SANDBOX_PAGE = "LugliDMS"
    M.MODDATA_KEY = "LugliDMS"
    -- The key every gated world object carries in its own modData.
    M.OBJ_KEY = "LugliDMS"

    -- THE WIRE NAMES. OnClientCommand/OnServerCommand fire for every mod; the module string is the
    -- only thing separating them.
    M.NET_MODULE  = "LugliDMS"
    M.NET_CLAIM   = "claim"    -- client -> authority: I start this route on this gate
    M.NET_RELEASE = "release"  -- client -> authority: I put it down unfinished, keep my progress
    M.NET_SUBMIT  = "submit"   -- client -> authority: my timed action finished, resolve the route
    M.NET_RESULT  = "result"   -- authority -> that client: what the route did
    M.NET_BUSY    = "busy"     -- authority -> that client: refused silently (rate limit, someone else)
    M.NET_OPENED  = "opened"   -- authority -> every client: this gate is open, redraw what shows it
    M.NET_ALARM   = "alarm"    -- authority -> clients near it: a safe's alarm went off at x, y, z
    M.NET_PLACED  = "placed"   -- authority -> every client: a box went in at x, y, z, check you have it
    M.NET_RESEND  = "resend"   -- client -> authority: x, y, z is loaded here and holds no box, send it again
    M.NET_SOUND   = "sound"    -- authority -> clients near a box but not its worker: how its answer sounded
    -- A resend is asked and honoured within this many tiles of the survivor on each axis: a client
    -- loads at most 19 chunks across (IsoChunkMap.java:120) centred on its own chunk
    -- (UdpConnection.isRelevantTo, :212), so 9 chunks and 7 tiles, 79, is the farthest it holds.
    M.RESEND_RANGE = 80

    local function boolCall(fn)
        if type(fn) ~= "function" then return false end
        local ok, v = pcall(fn)
        return ok and v == true
    end

    -- CACHED AT LOAD, AND THAT IS CORRECT. GameClient.client is set before the handshake, and the
    -- connect rebuilds the whole Lua VM with the flag already true, so an MP client re-reads it.
    local IS_SERVER = boolCall(isServer)
    local IS_CLIENT = boolCall(isClient)

    function M.isDedicatedServer() return IS_SERVER and not IS_CLIENT end
    function M.isMultiplayer()     return IS_SERVER or IS_CLIENT end

    --- Is this machine allowed to change the world? True on a dedicated server, on a co-op child
    --- server and in single player: exactly one process per world. isServer() is false in single
    --- player, so it cannot be the test.
    function M.isWorldAuthority() return not IS_CLIENT end

    function M.envName()
        if M.isDedicatedServer() then return "dedicated server" end
        if IS_CLIENT then return "multiplayer client" end
        return "single player"
    end

    --- Outcome of one part. The first report fixes the part's place in the boot line.
    function M.status(part, ok, note, kind)
        if M.parts[part] == nil then M.partOrder[#M.partOrder + 1] = part end
        M.parts[part] = { ok = ok, note = note, kind = kind }
    end

    function M.partText(p)
        if p == nil then return "never reported" end
        if p.ok == true then return "installed" end
        if p.kind == "skipped" then return "skipped: " .. tostring(p.note) end
        return "failed: " .. tostring(p.note)
    end

    function M.bootLine()
        local items = {}
        for i = 1, #M.partOrder do
            local name = M.partOrder[i]
            items[i] = name .. ": " .. M.partText(M.parts[name])
        end
        local line = "[" .. M.TAG .. "] loaded [build " .. tostring(M.BUILD or "unstamped") .. "] on "
            .. M.envName() .. ", " .. #items .. " part(s)"
        if #items > 0 then line = line .. ": " .. table.concat(items, "; ") end
        return line
    end

    function M.log(part, msg)
        print("[" .. M.TAG .. "/" .. tostring(part) .. "] " .. tostring(msg))
    end

    --- A diagnostic, printed only when the sandbox asks for them.
    function M.debug(part, msg)
        if M.cfg == nil or M.cfg("DebugLog") ~= true then return end
        M.log(part, msg)
    end

    --- A failure that should not have happened. The first M.DEFECT_PRINTS from one part print with
    --- their running count, then every M.DEFECT_EVERY-th, so a recurring failure stays visible
    --- without flooding the log. `always` prints past that limit.
    M.DEFECT_PRINTS, M.DEFECT_EVERY = 5, 100
    local reported = {}
    function M.defect(part, note, always)
        M.status(part, false, note, "bug")
        local n = (reported[part] or 0) + 1
        reported[part] = n
        if not always and n > M.DEFECT_PRINTS and n % M.DEFECT_EVERY ~= 0 then return end
        print("[" .. M.TAG .. "/" .. tostring(part) .. "] DEFECT" .. (n > 1 and (" #" .. n) or "")
            .. ": " .. tostring(note))
    end

    --- An event handler that fails ONCE and then goes quiet. pcall does not suppress the engine's
    --- on-screen error box, so a handler that keeps failing keeps shouting.
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

    -- ONE OnTick FOR THE WHOLE MOD. A ticker survives a failure: each one is a defect and a success
    -- resets the run. Only M.TICKER_GIVE_UP failures in a row drop it, because a ticker failing on
    -- every call would raise the engine's error box every period for the session.
    local tickers = {}
    local tickerHandler = nil
    M.TICKER_GIVE_UP = 20

    --- Run fn every `seconds` (a number, or a function returning one). Zero means every frame.
    function M.addTicker(part, seconds, fn)
        tickers[#tickers + 1] = { part = part, at = 0, every = seconds, fn = fn, streak = 0, failures = 0 }
        if tickerHandler == nil then
            tickerHandler = M.addHandler("Core", "OnTick", function()
                local now = getTimestampMs ~= nil and getTimestampMs() or 0
                for i = #tickers, 1, -1 do
                    local t = tickers[i]
                    local every = t.every
                    if type(every) == "function" then
                        local okE, v = pcall(every)
                        every = okE and v or 0
                    end
                    if type(every) ~= "number" or every < 0 then every = 0 end
                    if now >= t.at then
                        t.at = now + every * 1000
                        local ok, err = pcall(t.fn)
                        if ok then
                            t.streak = 0
                        else
                            t.streak = t.streak + 1
                            t.failures = t.failures + 1
                            if t.streak >= M.TICKER_GIVE_UP then
                                table.remove(tickers, i)
                                M.defect(t.part, "ticker removed after " .. t.streak .. " failures in a row: "
                                    .. tostring(err), true)
                            else
                                M.defect(t.part, "ticker failed (" .. t.streak .. " in a row, " .. t.failures
                                    .. " in all): " .. tostring(err))
                            end
                        end
                    end
                end
            end)
            if tickerHandler == nil then return nil end
        end
        return true
    end

    --- Translate with arguments, treating an echoed key as a miss. The engine stores every %N of a
    --- translation as %N$s when it loads the file (Translator.formatFixer, 42.22.2) and fills it only
    --- from getText's own arguments, so a placeholder is never substituted after the fact.
    function M.Tf(key, fallback, ...)
        local args = { ... }
        if type(key) == "string" and getText ~= nil then
            local ok, s = pcall(getText, key, ...)
            if ok and type(s) == "string" and s ~= key then return s end
        end
        local text = fallback or (type(key) == "string" and key or "")
        for k = #args, 1, -1 do text = string.gsub(text, "%%" .. k, (string.gsub(tostring(args[k]), "%%", "%%%%"))) end
        return text
    end

    --- Translate, treating an echoed key as a miss.
    function M.T(key, fallback)
        if type(key) ~= "string" then return fallback or "" end
        if getText == nil then return fallback or key end
        local ok, s = pcall(getText, key)
        if ok and type(s) == "string" and s ~= key then return s end
        return fallback or key
    end

    --- Release everything a part owns when the world goes away.
    function M.addTeardown(part, fn)
        M.addHandler(part, "OnDisconnect", fn)
        M.addHandler(part, "OnMainMenuEnter", fn)
    end

    --- A finite number, or nil.
    function M.finite(v)
        if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
        return v
    end

    function M.clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    --- Every player this process can see. getOnlinePlayers() is the connected list on a server and
    --- EMPTY in single player; the local walk is empty on a dedicated server. Both, so the
    --- authority reaches everybody everywhere.
    function M.forEachWorldPlayer(fn)
        local seen = false
        if getOnlinePlayers ~= nil then
            local ok, list = pcall(getOnlinePlayers)
            if ok and list ~= nil then
                local okN, n = pcall(function() return list:size() end)
                if okN and type(n) == "number" and n > 0 then
                    for i = 0, n - 1 do
                        local p = list:get(i)
                        if p ~= nil then seen = true; fn(p) end
                    end
                end
            end
        end
        if seen then return end
        if getNumActivePlayers == nil or getSpecificPlayer == nil then return end
        local okN, n = pcall(getNumActivePlayers)
        if not okN or type(n) ~= "number" then return end
        for i = 0, n - 1 do
            local p = getSpecificPlayer(i)
            if p ~= nil then fn(p) end
        end
    end

    -- THE BOOT LINE. Server files load at world load, after shared and client, so the line waits
    -- for the world: OnGameStart in a game with a screen, OnServerStarted on a dedicated server.
    -- Whichever fires first prints it, once per world.
    local printed = false
    local function printBoot()
        if printed then return end
        printed = true
        print(M.bootLine())
    end
    M.addHandler("Core", "OnGameStart", printBoot)
    M.addHandler("Core", "OnServerStarted", printBoot)
    M.addTeardown("Core", function() printed = false end)
end
