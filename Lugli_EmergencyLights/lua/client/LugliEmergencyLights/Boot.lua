--[[
    Boot
    What loaded, what did not, and compatibility with other mods.
]]

require "LugliEmergencyLights/Light"
require "LugliEmergencyLights/Crack"
require "LugliEmergencyLights/Throw"
require "LugliEmergencyLights/Gun"
require "LugliEmergencyLights/Aiming"
require "LugliEmergencyLights/Fire"
require "LugliEmergencyLights/Expire"
require "LugliEmergencyLights/Items"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

-- ---- Boot --------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Boot"

    local function summary()
        local ok, bad, pending = 0, 0, 0
        for _, v in pairs(M.parts) do
            if v.ok == true then ok = ok + 1
            elseif v.ok == false then bad = bad + 1
            else pending = pending + 1 end
        end
        return ok, bad, pending
    end

    M.addHandler(PART, "OnGameStart", function()
        -- Before any part reads a number: sandbox values are fixed for a world's life, and this is
        -- the only moment they can change.
        M.resetConfig()
        local ok, bad, pending = summary()
        -- THE BUILD STAMP LEADS, because every other line here is worthless if the code that printed
        -- them is not the code that was just written. M.BUILD is written into the staged tree at
        -- build time; "unstamped" means this install predates the stamp or was copied by hand.
        M.log("boot", M.envName() .. ", " .. ok .. " part(s) ready, "
            .. bad .. " defective, " .. pending .. " pending"
            .. "  [build " .. tostring(M.BUILD or "unstamped") .. "]")
        -- WHAT THIS WORLD DISAGREES WITH THE BUILD ABOUT, if anything.
        if M.configDrift ~= nil then
            local n, drift = M.configDrift()
            if n ~= nil then
                M.log("boot", "this world overrides " .. tostring(n) .. " option(s): " .. drift)
            end
        end

        if bad > 0 then
            for k, v in pairs(M.parts) do
                if v.ok == false then
                    M.log("boot", "  " .. k .. ": " .. tostring(v.note))
                end
            end
        end
    end)

    -- SANDBOX EDITS IN A LIVE WORLD TAKE EFFECT, within a couple of seconds.
    M.addTicker(PART, 2.0, function()
        if M.refreshConfig ~= nil and M.refreshConfig() then
            M.debug("boot", "sandbox options changed; reloaded")
        end
    end)

    M.status(PART, true)
end

-- ---- Compat ------------------------------------------------------------------------------------
do
    local M = LugliEmergencyLights
    local PART = "Compat"

    local function blockSuicideWithFlareGun()
        if ImmersiveSuicide == nil or type(ImmersiveSuicide.startSuicide) ~= "function" then
            M.status(PART, true, "Immersive Suicide is not installed", "dep")
            return
        end
        if ImmersiveSuicide._lugliEL_guard then return end

        local original = ImmersiveSuicide.startSuicide
        ImmersiveSuicide.startSuicide = function(playerObj, item, ...)
            if item ~= nil then
                local ok, full = pcall(function() return item:getFullType() end)
                if ok and full == M.GUN.item then
                    -- A flare gun fires a signal cartridge. It is not a weapon and it is not a way
                    -- out, and offering it as one is a promise the mod cannot keep.
                    if playerObj ~= nil and playerObj.Say ~= nil then
                        pcall(function()
                            playerObj:Say(M.T("UI_LugliEL_NotAWeapon", "This is not a weapon."))
                        end)
                    end
                    return
                end
            end
            return original(playerObj, item, ...)
        end
        ImmersiveSuicide._lugliEL_guard = true
        M.status(PART, true, "Immersive Suicide: flare gun excluded")
    end

    -- After every other mod has defined its globals.
    M.addHandler(PART, "OnGameStart", blockSuicideWithFlareGun)

    M.status(PART, nil, "checked when you load a world", "pending")
end
