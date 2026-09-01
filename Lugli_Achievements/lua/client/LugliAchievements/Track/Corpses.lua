require "LugliAchievements/Registry"

local M = LugliAchievements

M.countActions("Corpse handling", {
    { "ISBuryCorpse", "corpses_buried" },
    { "ISBurnCorpseAction", "corpses_burned" },
    { "ISThrowCorpseThroughWindow", "corpses_windowed" },
    { "ISThrowCorpseOverFence", "corpses_fenced" },
    { "ISGrabCorpseAction", "corpses_moved" },
    { "ISDropCorpseIntoContainer", "corpses_binned" },
})
