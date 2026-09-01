require "LugliAchievements/Registry"

local M = LugliAchievements

M.countActions("Farming and foraging", {
    { "ISHarvestPlantAction", "crops_harvested" },
    { "ISSeedActionNew", "seeds_planted" },
    { "ISWaterPlantAction", "plants_watered" },
    { "ISAddCompost", "compost_added" },
    { "ISScything", "scythings" },
    { "ISChopTreeAction", "trees_chopped" },
    { "ISCheckFishingNetAction", "nets_checked" },
})
