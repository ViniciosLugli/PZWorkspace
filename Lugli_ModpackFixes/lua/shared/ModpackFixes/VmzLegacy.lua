--[[
Vehicle Military Zones: its leftover zone script stops throwing an error at every world load.

What happens today. VMZ (VMZNEW) still ships its old server/VMZ/ChangeZones.lua beside the newer
shared/VMZ/Zones/Change.lua. The old file's OnLoadedMapZones handler calls VZUtils.changeName,
which Yet Another PZ Library dropped when it moved to VehicleZone.change, so the handler throws on
its first line once per world load (an MP client log of 2026-11-13 shows it at ChangeZones.lua:5).
No zone edit is lost to it: the new file sends the same parking-stall changes through
VehicleZone.change (145 of the old file's 149 coordinates; the other 4 belong to EchoCreek
MilitaryBase), and YAPZLib applies them when vanilla's doMapZones reads each map's objects.lua.

What this part changes. When ChangeZones.lua registers that handler, it is kept out of the event,
unless YAPZLib has changeName again, in which case the old handler works and is registered as
without this mod. Switched off or failed, the handler is registered unchanged.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local LEGACY_FILE = "ChangeZones.lua"
local LEGACY_DIR = "VMZ"
local dropped = nil

local function fromLegacyScript(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string"
        and string.find(name, LEGACY_FILE, 1, true) ~= nil
        and string.find(name, LEGACY_DIR, 1, true) ~= nil
end

local function legacyApiBack()
    local ok, zoneUtils = pcall(require, "YAPZLib/VehicleZone")
    return ok and type(zoneUtils) == "table" and type(zoneUtils.changeName) == "function"
end

local function install(ctx)
    ctx.wrap(Events.OnLoadedMapZones, "Add", function(add)
        return function(fn)
            if dropped ~= nil or not fromLegacyScript(fn) or legacyApiBack() then return add(fn) end
            dropped = fn
        end
    end)
    ctx.undo(function()
        if dropped == nil then return end
        Events.OnLoadedMapZones.Add(dropped)
        dropped = nil
    end)
end

M.addPart({
    name = "vmz-legacy",
    switch = "VmzLegacy",
    title = "Vehicle Military Zones: no error from its old zone script",
    tip = "Vehicle Military Zones still ships an old zone script that calls library functions which no longer exist, so it throws an error every time a world loads. Its zone changes already come from the mod's newer script, so this stops only the old one. Only active with Vehicle Military Zones.",
    kind = "fix",
    all = { "VMZNEW", "YAPZLib" },
    side = "both",
    phase = "load",
    pins = { "vmz.legacy", "vmz.register", "vmz.change", "yapz.change" },
    install = install,
})
