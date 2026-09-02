require "LugliAchievements/Prefs"

local M = LugliAchievements
local PART = "Unlock sound"

-- Index 1 is Off, so the dropdown reads the way a player expects. Everything after it is a name
-- achievements_sounds.txt declares.
local OFF = "off"
local SOUNDS = {
    OFF,
    "LugliAch_Steam",
    "LugliAch_Xbox",
    "LugliAch_SteamDeck",
    "LugliAch_Witcher",
    "LugliAch_Skyrim",
    "LugliAch_DST",
    "LugliAch_Scribblenauts",
}

-- The cfg stores the NAME, never the dropdown position. An index would mean a clip added or
-- reordered here silently changes what every existing player hears.
local INDEX_OF = {}
for i = 1, #SOUNDS do INDEX_OF[SOUNDS[i]] = i end

local LABELS = {
    "UI_LugliAch_opt_sound_off",
    "UI_LugliAch_opt_sound_steam",
    "UI_LugliAch_opt_sound_xbox",
    "UI_LugliAch_opt_sound_steamdeck",
    "UI_LugliAch_opt_sound_witcher",
    "UI_LugliAch_opt_sound_skyrim",
    "UI_LugliAch_opt_sound_dst",
    "UI_LugliAch_opt_sound_scribblenauts",
}

local DEFAULT_NAME = "LugliAch_Steam"

-- 0..10, matching ISVolumeControl, which is the widget the settings panel draws, and where 0 is
-- a real position rather than a floor. Stored as the notch rather than a fraction so the cfg
-- holds the number the control shows.
local NOTCHES = 10
local DEFAULT_NOTCH = 7

M.SOUND_LABELS = LABELS
M.SOUND_NOTCHES = NOTCHES

--- The dropdown position of the saved choice. An unreadable or retired name falls back to the
--- default rather than to Off, so a bad cfg line never silently mutes the mod.
function M.soundIndex()
    return INDEX_OF[M.pref("sound", DEFAULT_NAME)] or INDEX_OF[DEFAULT_NAME]
end

--- 0..10, the notch. The settings panel speaks this; everything else wants soundGain.
function M.soundNotch()
    local n = M.pref("volume", DEFAULT_NOTCH)
    if type(n) ~= "number" then return DEFAULT_NOTCH end
    n = math.floor(n)
    if n < 0 then return 0 end
    if n > NOTCHES then return NOTCHES end
    return n
end

function M.soundGain() return M.soundNotch() / NOTCHES end

--- The sound an unlock should play, or nil for none.
function M.unlockSoundName()
    local name = SOUNDS[M.soundIndex()]
    if name == OFF then return nil end
    return name
end

--- Play a UI sound at this mod's own volume.
---
--- The gain is applied AFTER the play because no volume argument exists on this path:
--- playUISound takes only a name, and PlaySound's maxGain is accepted and never read. What works
--- is the handle it returns, scaled on the UI emitter and ticked out to FMOD. Not setUserVolume,
--- which is the game's own audio-options value and not a mod's to rewrite.
---
--- Every step past the play is guarded and degrades to full volume: getUIEmitter exists on
--- SoundManager but not on DummySoundManager.
function M.playAtVolume(name)
    if name == nil or getSoundManager == nil then return false end
    local ok, sm = pcall(getSoundManager)
    if not ok or sm == nil then return false end

    -- Zero is silence, and silence is cheaper not to start than to start and mute.
    local gain = M.soundGain()
    if gain <= 0 then return false end

    local okRef, ref = pcall(function() return sm:playUISound(name) end)
    if not okRef or type(ref) ~= "number" or ref == 0 then return false end

    if gain >= 1 then return true end
    pcall(function()
        local em = sm:getUIEmitter()
        if em == nil then return end
        em:setVolume(ref, gain)
        em:tick()
    end)
    return true
end

function M.setSoundIndex(i)
    if type(i) ~= "number" then return end
    i = math.floor(i)
    if i < 1 then i = 1 elseif i > #SOUNDS then i = #SOUNDS end
    M.setPref("sound", SOUNDS[i])
    M.savePrefs()
end

function M.setSoundNotch(n)
    if type(n) ~= "number" then return end
    n = math.floor(n)
    if n < 0 then n = 0 elseif n > NOTCHES then n = NOTCHES end
    M.setPref("volume", n)
    M.savePrefs()
end

--- Play the current choice, for the settings panel. Silent on Off, which is the honest preview
--- of Off rather than a sound announcing that sound is disabled.
function M.previewSound() return M.playAtVolume(M.unlockSoundName()) end

M.status(PART, true, "chosen in the achievements window, with its own volume")
