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

-- Position cache. Every Insert walks all four loot tables end to end, and the mod makes 230
-- Insert calls naming only 48 distinct base items, so remember where each was found.
--
-- Cached positions stay valid because Insert only ever APPENDS: it never removes or reorders,
-- so a recorded index still points at the same value. The one way to go stale is a later Insert
-- searching for a name an earlier one appended, so new positions are pushed into any matching
-- cache entry rather than trusting the caller's naming convention.

local cacheStore = {}
local indexStore = {}
local indexChecks = 0

--- -Dfastloading.gunidx=off falls back to the per-miss full walk. Also set automatically if the
--- index ever disagrees with that walk, so a wrong index degrades instead of corrupting loot.
--
-- The bridge is absent on a dedicated server (this mod's jar never loads there) and absent when
-- ZombieBuddy is not installed, so treat a missing bridge as "on" -- this file's whole saving is
-- what cuts server startup, and it must not switch itself off in the environment that needs it.
--
-- A SERVER CANNOT USE THE -D SWITCH. FastLoading_Switch is a @LuaMethod on this mod's jar, and
-- that jar never loads on a dedicated server (no ZombieBuddy there) -- so the bridge is nil in
-- exactly the environment these shared Lua parts matter most for. Without a second route the
-- kill switch would be dead where an admin is most likely to need it. So also honour a plain
-- global, which any server can set from its own Lua:
--     FastLoadingDisableGunIndex = true
local indexBroken = (FastLoadingDisableGunIndex == true)
        or ((type(FastLoading_Switch) == "function")
            and FastLoading_Switch("gunidx", "on") == "off")
        or false
--- Cross-check this many index lookups against the original full walk before trusting it.
local INDEX_VERIFY = 4

-- ---------------------------------------------------------------------------
-- One indexing walk instead of one walk per base item.
--
-- The per-base cache above still paid a FULL four-table walk on every miss, and
-- applyDistributionPass names 48 distinct base items -- so 48 walks of 531,557
-- values, about 25.5 M iterations, which is the bulk of what the pass still
-- costs after the hoist fix.
--
-- buildIndex walks ONCE and records every string it sees under its own name.
-- A global sequence number is stamped on each position so that merging the two
-- buckets for getName() and getFullName() reproduces the original emission
-- order exactly: (table, container, index). That order is observable in the
-- finished loot tables, so it is not a detail.
-- ---------------------------------------------------------------------------
local function buildIndex(tables)
    local II, WI, seq = {}, {}, 0
    for _, lootTable in pairs(tables) do
        for _, data in pairs(lootTable) do
            local items = data.items
            if items then
                for i = 1, #items do
                    local v = items[i]
                    -- Only strings can ever equal a name; weights are numbers.
                    if type(v) == "string" then
                        seq = seq + 1
                        local b = II[v]
                        if b == nil then b = { d = {}, i = {}, s = {}, n = 0 }; II[v] = b end
                        local n = b.n + 1
                        b.n = n; b.d[n] = data; b.i[n] = i; b.s[n] = seq
                    end
                end
            end
            local weapons = data.weapons
            if weapons then
                for i = 1, #weapons do
                    local v = weapons[i]
                    if type(v) == "string" then
                        seq = seq + 1
                        local b = WI[v]
                        if b == nil then b = { d = {}, i = {}, s = {}, n = 0 }; WI[v] = b end
                        local n = b.n + 1
                        b.n = n; b.d[n] = data; b.i[n] = i; b.s[n] = seq
                    end
                end
            end
        end
    end
    return { items = II, weapons = WI, appended = {} }
end

-- Merge two buckets by sequence number. nameA == nameB must not double-count:
-- the original tests `v == nameA or v == nameB`, which matches an index once.
local function mergeBucket(bA, bB, outD, outI)
    local n = 0
    if bA == nil and bB == nil then return 0 end
    if bB == nil or bA == bB then
        if bA == nil then return 0 end
        for k = 1, bA.n do n = n + 1; outD[n] = bA.d[k]; outI[n] = bA.i[k] end
        return n
    end
    if bA == nil then
        for k = 1, bB.n do n = n + 1; outD[n] = bB.d[k]; outI[n] = bB.i[k] end
        return n
    end
    local ka, kb = 1, 1
    while ka <= bA.n and kb <= bB.n do
        if bA.s[ka] < bB.s[kb] then
            n = n + 1; outD[n] = bA.d[ka]; outI[n] = bA.i[ka]; ka = ka + 1
        else
            n = n + 1; outD[n] = bB.d[kb]; outI[n] = bB.i[kb]; kb = kb + 1
        end
    end
    while ka <= bA.n do n = n + 1; outD[n] = bA.d[ka]; outI[n] = bA.i[ka]; ka = ka + 1 end
    while kb <= bB.n do n = n + 1; outD[n] = bB.d[kb]; outI[n] = bB.i[kb]; kb = kb + 1 end
    return n
end

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
    if pos == nil and indexBroken then
        -- The index disagreed with the full walk once; never trust it again this session.
        pos = buildPositions(tables, nameA, nameB)
        cache[baseItem] = pos
    end
    if pos == nil then
        local index = indexStore[tables]
        -- Rebuild if a name we are about to look up was APPENDED since the index
        -- was built: its positions would be missing, and the original -- which
        -- rescans the live table every call -- would have found them.
        if index ~= nil and (index.appended[nameA] or index.appended[nameB]) then
            index = nil
        end
        if index == nil then
            index = buildIndex(tables)
            indexStore[tables] = index
        end
        local iD, iI = {}, {}
        local iN = mergeBucket(index.items[nameA], index.items[nameB], iD, iI)
        local wD, wI = {}, {}
        local wN = mergeBucket(index.weapons[nameA], index.weapons[nameB], wD, wI)
        pos = { nameA = nameA, nameB = nameB,
                iD = iD, iI = iI, iN = iN,
                wD = wD, wI = wI, wN = wN }

        -- DIFFERENTIAL GATE, same standard as ScriptParse's tokenizer.
        --
        -- The index must reproduce buildPositions exactly -- same positions, same ORDER --
        -- because the order in which matches are emitted is observable in the finished loot
        -- tables. A wrong order does not crash; it silently changes what spawns. So the first
        -- few misses run the original full walk too and compare. Any disagreement disables the
        -- index permanently and the walk takes over, which is merely the previous version.
        --
        -- Only the first few: the point is to catch a wrong ALGORITHM, and paying two walks
        -- forever would give back the saving this exists to produce.
        if indexChecks < INDEX_VERIFY then
            indexChecks = indexChecks + 1
            local ref = buildPositions(tables, nameA, nameB)
            local same = (ref.iN == iN and ref.wN == wN)
            if same then
                for k = 1, iN do
                    if ref.iD[k] ~= iD[k] or ref.iI[k] ~= iI[k] then same = false; break end
                end
            end
            if same then
                for k = 1, wN do
                    if ref.wD[k] ~= wD[k] or ref.wI[k] ~= wI[k] then same = false; break end
                end
            end
            if not same then
                indexBroken = true
                indexStore[tables] = nil
                print("[FastLoading/gunworks] index DISARMED: disagreed with the full walk on "
                      .. tostring(baseItem) .. "; using the walk")
                pos = ref
            end
        end
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
    local index = indexStore[tables]
    if index ~= nil then index.appended[newItem] = true end

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
-- The offline fixture proves the patch against a COPY of the framework's
-- Insert. If the framework mod is updated and its Insert changes meaning, that
-- proof silently stops applying -- so re-prove it here against whatever Insert
-- is actually loaded, and refuse to install on disagreement. A slow correct
-- load beats a fast wrong one.
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
    -- Drop the caches at the START of every merge, not just the first.
    --
    -- `applyPatch` self-guards with `patched`, so on the SECOND world load of a session it does
    -- nothing -- and both stores would survive, keyed by the same table objects. That is only safe
    -- while Insert is the sole mutator of those tables, and it is not: SapphCooking pushes ~1,090
    -- `table.insert` calls from `addSandboxLoot()` on OnInitGlobalModData. An append by anyone
    -- else leaves a cached position list incomplete, where the original's live re-walk would have
    -- found it -- a silently different loot table on the second load, which is exactly the failure
    -- this file's own header warns about. Rebuilding costs one walk per world load.
    cacheStore = {}
    indexStore = {}
    indexChecks = 0

    local ok, err = pcall(applyPatch)
    if not ok then
        patched = true -- fail once, then stay quiet
        gwStatus(false, "patch failed: " .. tostring(err), "bug")
        print("[FastLoading/gunworks] Marz/Gunworks distribution patch FAILED: " .. tostring(err))
    end
end)
