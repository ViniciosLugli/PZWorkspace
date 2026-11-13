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
--- null when the game mode is Client (ZomboidRadio.java:216-224), so on a MULTIPLAYER CLIENT it
--- is null for the whole session and the devices below are read instead.
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

local function credit(name, isTv, radio)
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

-- No pcall around any of these: RadioChannel is on the engine's Lua whitelist and every member
-- read here is declared on it, so once the receiver is non-nil none of them can throw.
local function creditChannels(list)
    for i = 0, list:size() - 1 do
        local ch = list:get(i)
        if ch ~= nil and ch:GetPlayerIsListening() then
            local name = ch:GetName()
            if type(name) == "string" then credit(name, ch:IsTv(), isRadioStation(ch)) end
        end
    end
end

-- A multiplayer client has no channels, but it does have the devices and their names. The
-- server answers RadioServerData with every channel's name, frequency and category, which
-- addChannelName files under ChannelCategory.name() (GameClient.java:2289-2300,
-- RadioScriptManager.java:104). The test for "listening" is the engine's own on a client,
-- a device turned on with a player in range (ZomboidRadio.java:443-449); a held radio is the
-- one device that is never registered, and counts while equipped (Radio.java:177-191).
local function creditDevice(radio, data)
    if data == nil or not data:getIsTurnedOn() then return end
    -- nil until RadioServerData lands, and then in no category, so it is never credited.
    local name = radio:getChannelName(data:getChannel())
    local isTv = data:getIsTelevision()
    -- RadioScriptManager.PlayerListensChannel only matches a channel whose IsTv agrees with the
    -- device, so a television counts only television and a radio only the Radio category.
    local category = radio:GetChannelList(isTv and "Television" or "Radio")
    local listed = category ~= nil and category:containsValue(name)
    credit(name, isTv and listed, (not isTv) and listed)
end

local function creditDevices(radio)
    local devices = radio:getDevices()
    for i = 0, devices:size() - 1 do
        local device = devices:get(i)
        if device ~= nil and device:HasPlayerInRange() then
            creditDevice(radio, device:getDeviceData())
        end
    end
    M.forEachLocalPlayer(function(player)
        local held = player:getEquipedRadio()
        if held ~= nil then creditDevice(radio, held:getDeviceData()) end
    end)
end

--- The radio a multiplayer client reads its devices from, or nil when this session is not one.
local function deviceRadio()
    if not M.isMpClient() or getZomboidRadio == nil then return nil end
    return getZomboidRadio()
end

-- Polled: there is no event for tuning a radio.
local function onEveryTenMinutes()
    local list = channelsList()
    if list ~= nil then
        creditChannels(list)
        return
    end
    local radio = deviceRadio()
    if radio ~= nil then creditDevices(radio) end
end

M.addHandler(PART, "EveryTenMinutes", onEveryTenMinutes)

-- Asked once a world exists rather than at load, and the answer holds for the session:
-- ZomboidRadio.Init runs during IsoWorld load, well before OnGameStart.
local h = M.addHandler(PART, "OnGameStart", function()
    if channelsList() ~= nil then
        M.status(PART, true)
    elseif deviceRadio() ~= nil then
        M.status(PART, true, "read from the radios and televisions around you")
    else
        M.status(PART, false, "the engine gives this session no channel list", "dep")
    end
end)

if h ~= nil then M.status(PART, nil, "checked when you load a world", "pending") end
