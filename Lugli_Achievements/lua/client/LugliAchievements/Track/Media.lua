require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Radio and TV"

-- GetName() returns the raw XML attribute in every language, so comparing against these is
-- stable.
local LIFE_AND_LIVING = "Life and Living TV"
local MILITARY = "Classified M1A1"

--- The channel list, or nil when this session has none. Walked one step at a time because BOTH
--- intermediates are nullable and neither failure is exceptional:
---
--- getZomboidRadio() is `hasInstance() ? getInstance() : null`, and ZomboidRadio.Reset() nulls
--- that instance on world exit. getScriptManager() is worse -- ZomboidRadio.Init() assigns it
--- null and returns early when the game mode is Client, so on a MULTIPLAYER CLIENT it is null
--- for the whole session and there is no channel list to read at all.
---
--- Chaining through either raises a Lua error, and pcall does not keep that out of the log: the
--- engine dumps the trace when the Java call throws, before pcall unwinds. An inner pcall also
--- hides the throw from addHandler, so the handler is never removed. Together that turned one
--- log line into one every ten game-minutes for the rest of the session.
local function channelsList()
    if getZomboidRadio == nil then return nil end
    local radio = getZomboidRadio()
    if radio == nil then return nil end
    local manager = radio:getScriptManager()
    if manager == nil then return nil end
    return manager:getChannelsList()
end

-- IsTv only says whether a channel is one particular category. Treating everything that is not
-- television as a radio station swept in the amateur and military frequencies, which a survivor
-- stumbles onto rather than tunes to.
local function isRadioStation(ch)
    if ChannelCategory == nil then return false end
    return ch:GetCategory() == ChannelCategory.Radio
end

-- No pcall around any of these: RadioChannel is on the engine's Lua whitelist and every member
-- read here is declared on it, so once the receiver is non-nil none of them can throw.
local function credit(ch)
    local name = ch:GetName()
    if type(name) ~= "string" then return end
    local isTv = ch:IsTv()
    local radio = isRadioStation(ch)
    M.forEachLocalPlayer(function(player)
        if isTv then
            M.addUnique(player, "tv_channels", name)
        elseif radio then
            M.addUnique(player, "radio_stations", name)
        end
        if name == MILITARY then
            M.setStat(player, "saw_military_freq", 1)
        end
        if name == LIFE_AND_LIVING then
            -- One credit per in-game day, so leaving a TV on does not run the counter up in a
            -- single afternoon.
            M.addUnique(player, "ll_days", math.floor(M.worldHours() / 24))
        end
    end)
end

-- Polled: there is no event for tuning a radio.
local function onEveryTenMinutes()
    local list = channelsList()
    if list == nil then return end
    for i = 0, list:size() - 1 do
        local ch = list:get(i)
        if ch ~= nil and ch:GetPlayerIsListening() then
            credit(ch)
        end
    end
end

M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)

-- Asked once a world exists rather than at load, and the answer holds for the session:
-- ZomboidRadio.Init runs during IsoWorld load, well before OnGameStart.
local h = M.addHandler(PART, "OnGameStart", function()
    if channelsList() == nil then
        -- A dependency, not a defect. The engine hands a multiplayer client no channel list, so
        -- the four radio and television achievements cannot be earned there by any means.
        M.status(PART, false, "the engine gives a multiplayer client no channel list", "dep")
    else
        M.status(PART, true)
    end
end)

if h ~= nil then M.status(PART, nil, "checked when you load a world", "pending") end
