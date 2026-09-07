-- FasterLootInit: coalesces redundant ItemPickerJava.Parse() calls during world load.
FastLoading = FastLoading or {}

local realParse = nil
local deferred = 0
local broken = false

local function deferParse()
    deferred = deferred + 1
end

-- Kill switch (-Dfastloading.lootinit=off or global FastLoadingDisableLootInit = true).
local function partDisabled()
    if FastLoadingDisableLootInit == true then return true end
    if type(FastLoading_Switch) == "function" then
        return FastLoading_Switch("lootinit", "on") == "off"
    end
    return false
end

local function install()
    if broken or realParse ~= nil then return end
    if partDisabled() then
        broken = true
        return
    end

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
        print("[FastLoading/loot] flush FAILED: " .. tostring(err))
        return
    end

    if n > 0 then
        print("[FastLoading/loot] coalesced " .. n .. " Parse() calls into 1")
    end
end

Events.OnInitGlobalModData.Add(install)
Events.OnInitGlobalModData.Add(flush)

-- Ensure flush runs after all mod handlers are registered.
Events.OnPreDistributionMerge.Add(function()
    local ok, err = pcall(function()
        Events.OnInitGlobalModData.Remove(flush)
        Events.OnInitGlobalModData.Add(flush)
    end)
    if not ok then
        broken = true
        print("[FastLoading/loot] ordering failed: " .. tostring(err))
    end
end)
