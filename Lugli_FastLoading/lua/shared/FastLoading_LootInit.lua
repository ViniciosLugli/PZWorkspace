--[[
    FasterLootInit
    Collapses redundant ItemPickerJava.Parse() calls at world load.

    ItemPickerJava.Parse() clears its tables and re-walks every distribution
    table. On a large mod list that is ~531,000 values, roughly 800 ms per call.
    Many mods call it from their OnInitGlobalModData handler, so the full parse
    runs ~9 times and only the last result survives, because each Parse() discards the
    previous one. Measured: GlobalModData.init() 7.56 s -> 2.16 s.

    Safe because Parse() is idempotent and rebuilds from whatever the Lua tables
    currently hold, and these handlers only insert. None of them read parsed state back.
    One parse after all handlers sees exactly the same inserts as the last parse
    does today, so the resulting Java state is identical.

    Ordering: install runs first (registered at file load); flush is moved to the
    end of the callback list at OnPreDistributionMerge, by which point every mod
    handler is registered.

    If ItemPickerJava.Parse cannot be replaced, this disables itself and leaves
    stock behaviour.
]]

FastLoading = FastLoading or {}
FastLoading.parts = FastLoading.parts or {}
-- kind: "dep"  a dependency you chose not to install, nothing is wrong
--       "bug"  this should have worked; worth reporting
local function gwStatus(ok, note, kind)
    FastLoading.parts["Loot table init"] = { ok = ok, note = note, kind = kind }
end

gwStatus(nil, "checked when you load a world", "pending")

local realParse = nil
local deferred = 0
local broken = false

local function deferParse()
    deferred = deferred + 1
end

local function install()
    if broken or realParse ~= nil then return end

    local ok, err = pcall(function()
        local p = ItemPickerJava.Parse
        if type(p) ~= "function" then
            broken = true
            return
        end

        ItemPickerJava.Parse = deferParse
        if ItemPickerJava.Parse == p then
            -- assignment silently did not take; leave everything alone
            broken = true
            return
        end

        realParse = p
        deferred = 0
    end)

    if not ok then
        broken = true
        gwStatus(false, "ItemPickerJava.Parse could not be replaced", "bug")
        print("[FastLoading/loot] disabled: " .. tostring(err))
    end
end

local function flush()
    if realParse == nil then return end

    local saved, n = realParse, deferred
    realParse, deferred = nil, 0

    local ok, err = pcall(function()
        ItemPickerJava.Parse = saved
        if n > 0 then
            saved()
        end
    end)

    if not ok then
        broken = true
        gwStatus(false, "parse flush failed", "bug")
        print("[FastLoading/loot] flush FAILED: " .. tostring(err))
        return
    end

    if n > 0 then
        gwStatus(true)
        print("[FastLoading/loot] coalesced " .. n .. " Parse() calls into 1")
    end
end

Events.OnInitGlobalModData.Add(install)
Events.OnInitGlobalModData.Add(flush)

-- Move flush to the end of the callback list, after every mod has registered.
Events.OnPreDistributionMerge.Add(function()
    local ok, err = pcall(function()
        Events.OnInitGlobalModData.Remove(flush)
        Events.OnInitGlobalModData.Add(flush)
    end)
    if not ok then
        broken = true
        gwStatus(false, "could not order its handler last", "bug")
        print("[FastLoading/loot] ordering failed: " .. tostring(err))
    end
end)
