--[[
Clear Driver View Fix with KI5's seat UI: the seat diagram is not drawn while driving.

What happens today. Clear Driver View Fix closes the seat diagram once you drive, and also stops
it drawing in the frames before that close lands, by wrapping the diagram's render. KI5's Vehicle
Seat UI loads later and defines its own render for every vehicle, so that frame guard is gone and
the diagram can flash on screen when you start driving.

What this part changes. KI5's render is skipped while the viewer sits in the vehicle with the
engine running, the condition Clear Driver View Fix closes the diagram on.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local KI5_FILE = "ISVehicleSeatUI_KI5.lua"

local function fromKI5(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, KI5_FILE, 1, true) ~= nil
end

local function driving(character)
    local vehicle = character ~= nil and character:getVehicle() or nil
    return vehicle ~= nil and vehicle:isEngineRunning() and vehicle:getSeat(character) ~= -1
end

local function install(ctx)
    if type(ISVehicleSeatUI) ~= "table" or not fromKI5(ISVehicleSeatUI.render) then
        error("ISVehicleSeatUI.render is not KI5's")
    end
    ctx.wrap(ISVehicleSeatUI, "render", function(callOriginal)
        return function(self, ...)
            if driving(self.character) then return end
            return callOriginal(self, ...)
        end
    end)
end

M.addPart({
    name = "seat-view",
    switch = "SeatView",
    title = "Clear Driver View Fix: no seat diagram flash with KI5's seat UI",
    tip = "KI5's seat UI replaces the seat diagram's drawing and drops Clear Driver View Fix's guard, so the diagram can flash when you start driving. This keeps it hidden while you drive with the engine on. Only active with both mods.",
    kind = "compat",
    all = { "ClearDriverViewFix", "VSUIKI5" },
    side = "client",
    phase = "boot",
    pins = { "cdvf.render", "ki5.render" },
    install = install,
})
