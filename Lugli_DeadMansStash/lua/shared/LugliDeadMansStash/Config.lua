--[[
    Config
    The sandbox options, read through one function with a typed default for each.

    THE CACHE IS FILLED ONCE AND RE-READ ONLY ON DEMAND. A read taken before SandboxOptions.load()
    is deliberately not remembered: on a loaded save the distribution-merge events fire while the
    page is still the main menu's, so pageLoaded() decides whether an answer is worth caching.
    World.lua's ticker calls M.refreshConfig(), so an admin's change applies without a restart.
]]

require "LugliDeadMansStash/Core"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Config"

    -- THE ONE TABLE media/sandbox-options.txt mirrors. Name, kind, default, range.
    -- An enum reaches Lua as its 1-based index, never as its label.
    M.SANDBOX = {
        Enabled         = { kind = "boolean", default = true },
        -- Percent of buildings that hide a stash box, judged once per building (Spots.hostsStash).
        StashChance     = { kind = "number",  default = 7,   min = 0,    max = 100 },
        -- The most stash boxes one building hides; a house never holds more than one.
        MaxPerBuilding  = { kind = "number",  default = 2,   min = 1,    max = 10 },
        -- Extra sets of payout rolls: a box rolls tier x (1 + this) lists (Payout.payout).
        PayoutRolls     = { kind = "number",  default = 0,   min = 0,    max = 10 },
        -- 1 Off, 2 Light, 3 Normal, 4 Heavy: what brute force does to the payout.
        BruteDamage     = { kind = "number",  default = 3,   min = 1,    max = 4 },
        -- Multiplier on every route's noise radius. 0 is silent.
        NoiseScale      = { kind = "number",  default = 1,   min = 0,    max = 3 },
        -- Multiplier on every route's duration.
        TimeScale       = { kind = "number",  default = 1,   min = 0.25, max = 4 },
        -- Percent of buildings that hide a safe, on its own draw (Spots.hostsSafe).
        SafeChance      = { kind = "number",  default = 10,  min = 0,    max = 100 },
        -- Percent of buildings with a bank, police or jeweller's room that hide a keypad safe. Only
        -- 43 buildings on the vanilla map qualify, so at SafeChance they held under one a world.
        VaultSafeChance = { kind = "number",  default = 60,  min = 0,    max = 100 },
        -- Wrong codes a safe takes before it locks out.
        SafeTries       = { kind = "number",  default = 5,   min = 1,    max = 20 },
        -- Game hours a keypad locks out for; a dial locks out for half of it. 0: no lockout.
        SafeLockoutHours = { kind = "number", default = 2,   min = 0,    max = 48 },
        -- A keypad lockout or a failed bypass sounds the alarm.
        SafeAlarm       = { kind = "boolean", default = true },
        -- Paper clues to a safe's code, dropped like a key (Codes.lua).
        CluesPerSafe    = { kind = "number",  default = 2,   min = 0,    max = 3 },
        DebugLog        = { kind = "boolean", default = false },
    }

    local cache = nil

    local function typeOk(kind, v)
        if kind == "boolean" then return type(v) == "boolean" end
        return type(v) == "number"
    end

    local function readAll()
        local out = {}
        local vars = nil
        if SandboxVars ~= nil then
            local ok, t = pcall(function() return SandboxVars[M.SANDBOX_PAGE] end)
            if ok then vars = t end
        end
        local bad = 0
        for name, spec in pairs(M.SANDBOX) do
            local v = nil
            if vars ~= nil then
                local ok, got = pcall(function() return vars[name] end)
                if ok then v = got end
            end
            -- A present but wrong-shaped value is worse than a missing one: it reaches arithmetic
            -- and throws somewhere unrelated.
            if v ~= nil and not typeOk(spec.kind, v) then
                bad = bad + 1
                v = nil
            end
            if v == nil then v = spec.default end
            if spec.kind == "number" and spec.min ~= nil then v = M.clamp(v, spec.min, spec.max) end
            out[name] = v
        end
        if bad > 0 then
            M.log(PART, bad .. " sandbox value(s) had the wrong type, used the default")
        end
        return out
    end

    local function pageLoaded()
        return SandboxVars ~= nil and type(SandboxVars[M.SANDBOX_PAGE]) == "table"
    end

    function M.config()
        if cache ~= nil then return cache end
        local fresh = readAll()
        if pageLoaded() then cache = fresh end
        return fresh
    end

    --- One option, by name.
    function M.cfg(name)
        return M.config()[name]
    end

    --- Re-read the sandbox and adopt anything that changed. Returns true when something did.
    function M.refreshConfig()
        local fresh = readAll()
        if cache == nil then
            cache = fresh
            return true
        end
        local moved = false
        for name, v in pairs(fresh) do
            if cache[name] ~= v then moved = true break end
        end
        if not moved then return false end
        cache = fresh
        M.debug(PART, "sandbox options changed, adopted")
        return true
    end

    M.addTeardown(PART, function() cache = nil end)
end
