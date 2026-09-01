require "LugliAchievements/Registry"

local M = LugliAchievements

M.countActions("Building and crafting", {
    { "ISBuildAction", "objects_built" },
    { "ISDismantleAction", "things_dismantled" },
    { "ISPadlockAction", "padlocks_fitted" },
    { "ISDigStairsAction", "stairs_dug" },
    { "ISPlumbItem", "things_plumbed" },
    { "ISHandcraftAction", "items_crafted" },
    { "ISActivateGenerator", "generators_started" },
})
