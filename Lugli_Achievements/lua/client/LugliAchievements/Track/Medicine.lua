require "LugliAchievements/Registry"

local M = LugliAchievements

M.countActions("Field medicine", {
    { "ISApplyBandage", "bandages_applied" },
    { "ISStitch", "stitches" },
    { "ISSplint", "splints" },
    { "ISRemoveBullet", "bullets_removed" },
    { "ISRemoveGlass", "glass_removed" },
    { "ISTakePillAction", "pills_taken" },
    { "ISMedicalCheckAction", "medical_checks" },
    { "ISComfreyCataplasm", "cataplasms" },
    { "ISGarlicCataplasm", "cataplasms" },
    { "ISPlantainCataplasm", "cataplasms" },
})
