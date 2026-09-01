require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Radio and TV"

-- GetName() returns the raw XML attribute in every language, so comparing against these is
-- stable. The method names are irregularly capitalised and a wrong case throws rather than
-- returning nil, so every call is guarded.
local LIFE_AND_LIVING = "Life and Living TV"
local MILITARY = "Classified M1A1"

-- IsTv only says whether a channel is one particular category. Treating everything that is not
-- television as a radio station swept in the amateur and military frequencies, which a survivor
-- stumbles onto rather than tunes to.
local function isRadioStation(ch)
    if ChannelCategory == nil then return false end
    local ok, cat = pcall(function() return ch:GetCategory() end)
    return ok and cat == ChannelCategory.Radio
end

-- Polled: there is no event for tuning a radio.
local function onEveryTenMinutes()
    if getZomboidRadio == nil then return end
    local ok, list = pcall(function()
        return getZomboidRadio():getScriptManager():getChannelsList()
    end)
    if not ok or list == nil then return end

    local okN, n = pcall(function() return list:size() end)
    if not okN or type(n) ~= "number" then return end

    for i = 0, n - 1 do
        local ch = list:get(i)
        if ch ~= nil then
            local okL, listening = pcall(function() return ch:GetPlayerIsListening() end)
            if okL and listening == true then
                local okName, name = pcall(function() return ch:GetName() end)
                if okName and type(name) == "string" then
                    local okTv, isTv = pcall(function() return ch:IsTv() end)
                    local radio = isRadioStation(ch)
                    M.forEachLocalPlayer(function(player)
                        if okTv and isTv then
                            M.addUnique(player, "tv_channels", name)
                        elseif radio then
                            M.addUnique(player, "radio_stations", name)
                        end
                        if name == MILITARY then
                            M.setStat(player, "saw_military_freq", 1)
                        end
                        if name == LIFE_AND_LIVING then
                            -- One credit per in-game day, so leaving a TV on does not run the
                            -- counter up in a single afternoon.
                            local day = 0
                            local okD, d = pcall(function()
                                return math.floor(getGameTime():getWorldAgeHours() / 24)
                            end)
                            if okD and type(d) == "number" then day = d end
                            M.addUnique(player, "ll_days", day)
                        end
                    end)
                end
            end
        end
    end
end

M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)
M.status(PART, true)
