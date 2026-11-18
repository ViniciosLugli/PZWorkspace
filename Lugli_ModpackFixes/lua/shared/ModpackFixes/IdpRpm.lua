--[[
Item Details Panel and Gunworks: a Gunworks gun shows its rate of fire.

What happens today. Gunworks (SWMG, the framework behind Guns of Marz) fires each registered gun
at its own rate (WeaponSystems/Utils/RateOfFire.lua: one rate, or several the player switches
between), but no tooltip shows that rate, the vanilla one or Item Details Panel's.

What this part changes. Item Details Panel's Common section shows the gun's current rate of fire
in rounds per minute, read from Gunworks' own getWeaponRPM, and which of its rates is selected when
it has more than one. It is shown whether or not the vanilla tooltip is hidden, since neither shows
it otherwise.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.RateOfFire"

local rof

local function registered(item)
    return instanceof(item, "HandWeapon") and rof.IsWeaponRegistered(item) == true
end

local function collect(item, player, context)
    if not registered(item) then return nil end
    local enabled = context and context.enabledFields or {}
    if enabled.RateOfFire == false then return nil end
    local rpm = rof.getWeaponRPM(item)
    if type(rpm) ~= "number" or rpm <= 0 or rpm ~= rpm or rpm == math.huge then return nil end
    local text = tostring(math.floor(rpm + 0.5)) .. " RPM"
    local stages = rof.GetRpmStages(item)
    if type(stages) == "table" and #stages > 1 then
        text = text .. " (" .. tostring(rof.GetRpmStageIndex(item)) .. " of " .. tostring(#stages) .. ")"
    end
    return { { id = "RateOfFire", value = text, section = "properties", order = 50 } }
end

local function check()
    local why = K.check()
    if why ~= nil then return why end
    local ok, lib = pcall(require, "WeaponSystems/Utils/RateOfFire")
    if not ok or type(lib) ~= "table" then return "Gunworks' RateOfFire module is not loaded" end
    for _, name in ipairs({ "IsWeaponRegistered", "getWeaponRPM", "GetRpmStages", "GetRpmStageIndex" }) do
        if type(lib[name]) ~= "function" then return "Gunworks' RateOfFire has no " .. name end
    end
    rof = lib
    return nil
end

local function install(ctx)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Gunworks rate of fire (Modpack Fixes)",
        description = "A Gunworks gun's current rate of fire, and which of its rates is selected.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "main", order = 50,
        fields = { { id = "RateOfFire", label = "Rate of fire", section = "properties", order = 50 } },
        supports = function(item)
            return item ~= nil and registered(item)
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-rpm",
    switch = "IdpRpm",
    title = "Item Details Panel and Gunworks: rate of fire",
    tip = "Gunworks guns (Guns of Marz and its add-ons) fire at their own rate, which no tooltip shows. This adds the current rate of fire, in rounds per minute, to Item Details Panel. Only active with both mods.",
    kind = "compat",
    all = { "ItemDetailsPanel", "SWMG" },
    side = "client",
    phase = "boot",
    pins = { "idp.kinds", "gw.rpm" },
    check = check,
    install = install,
})
