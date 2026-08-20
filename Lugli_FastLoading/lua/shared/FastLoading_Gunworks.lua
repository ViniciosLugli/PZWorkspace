--[[
    GunworksLootSpeedup
    Makes the Gunworks loot-table insert pass fast.

    Distribution.Insert (Gunworks framework, Distribution/Functions.lua) evaluated
    script:getName() and script:getFullName(), two Lua to Java calls, inside its
    innermost loop, once per value of every loot table. With Guns of Marz calling
    Insert 230 times over ~531,000 values that is ~244 million calls. Measured on a
    large mod list: 78,308 ms of world load, cut to 8,078 ms. The sibling functions
    in the same file already hoist those calls; only Insert did not.

    Hoists the two calls, scans with a numeric for, and caches per-base positions,
    invalidating a cached entry when a later insert appends a name it searched for.

    Loot output is identical. A self-test runs both the original and the fast
    version against a fixture at install time and REFUSES to install on any
    mismatch, leaving the original Insert in place.
]]

FastLoading = FastLoading or {}
FastLoading.parts = FastLoading.parts or {}
-- kind: "dep"  a dependency you chose not to install, nothing is wrong
--       "bug"  this should have worked; worth reporting
local function gwStatus(ok, note, kind)
    FastLoading.parts["Gunworks loot insert"] = { ok = ok, note = note, kind = kind }
end

gwStatus(nil, "checked when you load a world", "pending")

local MODULE = "Distribution/Functions.lua"
local patched = false

-- ---------------------------------------------------------------------------
-- Position cache.
--
-- Measured after the hoist fix (run 15-28): applyDistributionPass fell
-- 78.3 s -> 25.8 s. What remains is that every Insert still walks all four
-- loot tables end to end, 531,557 values, confirmed by the checksum output:
--
--   ProceduralDistributions  83,305   SuburbsDistributions  27,198
--   VehicleDistributions    407,272   BagsAndContainers     13,782
--
-- applyDistributionPass makes 230 Insert calls but names only 48 DISTINCT base
-- items; "Base.AssaultRifle" alone is searched 46 times and the answer is the
-- same every time. So remember where each base item was found and reuse it.
--
-- Why the cached positions stay valid: Insert only ever APPENDS. It never
-- removes or reorders, so an index recorded earlier still points at the same
-- value. Appended entries land past the recorded range and are picked up by
-- any later full scan for a different name.
--
-- The one case that could go stale is a later Insert searching for a name that
-- an earlier Insert appended. In this mod that never happens (bases are all
-- "Base.*", inserted items are all "MarzGuns.*"), but the framework is shared,
-- so newly appended positions are pushed into any cache entry matching that
-- name rather than relying on the caller's naming convention.
-- ---------------------------------------------------------------------------

local cacheStore = {}

local function buildPositions(tables, nameA, nameB)
    local iD, iI, iN = {}, {}, 0
    local wD, wI, wN = {}, {}, 0
    -- Traversal order must match the original exactly: appends happen in the
    -- order matches are encountered, and that order is observable in the
    -- finished table (the checksum hashes item lists in order).
    for _, lootTable in pairs(tables) do
        for _, data in pairs(lootTable) do
            local items = data.items
            if items then
                for i = 1, #items do
                    local v = items[i]
                    if v == nameA or v == nameB then
                        iN = iN + 1; iD[iN] = data; iI[iN] = i
                    end
                end
            end
            local weapons = data.weapons
            if weapons then
                for i = 1, #weapons do
                    local v = weapons[i]
                    if v == nameA or v == nameB then
                        wN = wN + 1; wD[wN] = data; wI[wN] = i
                    end
                end
            end
        end
    end
    return { nameA = nameA, nameB = nameB,
             iD = iD, iI = iI, iN = iN,
             wD = wD, wI = wI, wN = wN }
end

local function fastInsert(baseItem, chance, tables, newItem)
    local script = ScriptManager.instance:getItem(baseItem)
    if not script then return end

    -- Two Java calls per Insert, not two per value scanned.
    local nameA = script:getName()
    local nameB = script:getFullName()
    local mult  = chance or 1

    local cache = cacheStore[tables]
    if cache == nil then cache = {}; cacheStore[tables] = cache end
    local pos = cache[baseItem]
    if pos == nil then
        pos = buildPositions(tables, nameA, nameB)
        cache[baseItem] = pos
    end

    local iD, iI, iN = pos.iD, pos.iI, pos.iN
    local k = 1
    while k <= iN do
        local data  = iD[k]
        local items = data.items
        local m = #items
        -- The original appended while walking a single container, so all
        -- matches within one container are emitted before moving on.
        while k <= iN and iD[k] == data do
            local w = items[iI[k] + 1] * mult
            items[m + 1] = newItem
            items[m + 2] = w
            m = m + 2
            k = k + 1
        end
    end

    local wD, wI, wN = pos.wD, pos.wI, pos.wN
    k = 1
    while k <= wN do
        local data    = wD[k]
        local weapons = data.weapons
        local m = #weapons
        while k <= wN and wD[k] == data do
            m = m + 1
            weapons[m] = newItem
            k = k + 1
        end
    end

    -- If we just appended a value that some cached entry searches for, that
    -- entry is now incomplete. Patching the new positions into its flat list
    -- is NOT safe: the list is ordered by (table, container, index) and the
    -- traversal emits all matches of one container together, so appending at
    -- the end reorders the output. The equivalence test caught exactly that.
    -- Drop the entry instead and let the next call rebuild it.
    local stale = nil
    for kbase, e in pairs(cache) do
        if e.nameA == newItem or e.nameB == newItem then
            if stale == nil then stale = {} end
            stale[#stale + 1] = kbase
        end
    end
    if stale ~= nil then
        -- collected first: removing during pairs() traversal is not safe
        for j = 1, #stale do cache[stale[j]] = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Regression gate.
--
-- The fixture proof lives in the workspace, but it proves the patch against a
-- COPY of the framework's Insert. If the framework mod is ever updated and its
-- Insert changes meaning, that proof silently stops applying. So re-prove it
-- here, in the live game, against whatever Insert is actually loaded, and
-- refuse to install if the two disagree. A slow correct load beats a fast
-- wrong one.
-- ---------------------------------------------------------------------------

local function deepcopy(o)
    if type(o) ~= "table" then return o end
    local c = {}
    for k, v in pairs(o) do c[k] = deepcopy(v) end
    return c
end

local function ser(o)
    if type(o) ~= "table" then return tostring(o) end
    local keys = {}
    for k in pairs(o) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local out = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = nil
        for kk, vv in pairs(o) do if tostring(kk) == k then v = vv end end
        out[#out + 1] = k .. "=" .. ser(v)
    end
    return "{" .. table.concat(out, ",") .. "}"
end

-- Returns true only if fastInsert reproduces originalInsert exactly on a
-- fixture built from a REAL script item, so getName/getFullName return the
-- same strings the real pass will see.
local function selfTestPasses(originalInsert)
    local probe = "Base.AssaultRifle"
    local script = ScriptManager.instance:getItem(probe)
    if not script then return false, "probe item " .. probe .. " not found" end
    local shortName, fullName = script:getName(), script:getFullName()

    local function fixture()
        local list = {}
        for t = 1, 4 do
            local items = {}
            for k = 1, 12 do
                if k % 5 == 2 then items[#items + 1] = shortName
                elseif k % 7 == 3 then items[#items + 1] = fullName
                else items[#items + 1] = "Base.Filler" .. k end
                items[#items + 1] = (k % 4) + 1
            end
            local data = { rolls = 4, items = items }
            if t % 2 == 0 then data.weapons = { shortName, "Base.Axe", fullName } end
            if t == 3 then data.items = nil end
            list["c" .. t] = data
        end
        return { list }
    end

    local a, b = fixture(), fixture()

    -- Exercise every path the real pass uses, including the two that the
    -- position cache makes non-trivial:
    --   * the same base repeated  -> cache-hit path
    --   * inserting a value that is itself searched later -> invalidation path
    local steps = {
        { probe,    0.3, "PZFixPack.SelfTest"  },  -- cold: builds the cache
        { probe,    0.3, "PZFixPack.SelfTest"  },  -- warm: cache hit
        { probe,    nil, "PZFixPack.SelfTest2" },  -- nil chance
        { probe,    0.5, fullName              },  -- appends a searched name
        { probe,    0.7, "PZFixPack.SelfTest3" },  -- must see the appended one
    }
    for i = 1, #steps do
        local st = steps[i]
        local okA = pcall(originalInsert, st[1], st[2], a, st[3])
        local okB = pcall(fastInsert,     st[1], st[2], b, st[3])
        if not okA or not okB then return false, "step " .. i .. " errored" end
        if ser(a) ~= ser(b) then return false, "outputs differ at step " .. i end
    end
    return true, nil
end

local function applyPatch()
    if patched then return end
    patched = true

    -- require() raises when the framework is absent, which is a normal
    -- condition here: FastLoading declares no hard dependency on it.
    local found, mod = pcall(require, MODULE)
    if not found or type(mod) ~= "table" or type(mod.Insert) ~= "function" then
        gwStatus(false, "needs the Gunworks framework (SWMG)", "dep")
        print("[FastLoading/gunworks] Gunworks framework (SWMG) not present, skipping")
        return
    end

    local ok, why = selfTestPasses(mod.Insert)
    if not ok then
        gwStatus(false, "self-test disagreed with the original, not installed", "bug")
        print("[FastLoading/gunworks] Marz/Gunworks distribution: SELF-TEST FAILED (" .. tostring(why)
              .. ") - leaving the original Insert in place")
        return
    end

    mod.FastLoading_originalInsert = mod.Insert
    mod.Insert = fastInsert
    gwStatus(true)
    print("[FastLoading/gunworks] Marz/Gunworks distribution: Insert() replaced, self-test passed")
end

Events.OnPreDistributionMerge.Add(function()
    local ok, err = pcall(applyPatch)
    if not ok then
        patched = true -- fail once, then stay quiet
        gwStatus(false, "patch failed: " .. tostring(err), "bug")
        print("[FastLoading/gunworks] Marz/Gunworks distribution patch FAILED: " .. tostring(err))
    end
end)
