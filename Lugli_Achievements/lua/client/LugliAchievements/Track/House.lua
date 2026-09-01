require "LugliAchievements/Registry"

local M = LugliAchievements

M.countActions("Housekeeping", {
    { "ISCleanBlood", "blood_cleaned" },
    { "ISCleanGraffiti", "graffiti_cleaned" },
    { "ISWashYourself", "washes" },
    { "ISWashClothing", "clothes_washed" },
    { "ISRepairClothing", "clothes_repaired" },
    { "ISCutHair", "haircuts" },
    { "ISDyeHair", "hair_dyed" },
    { "ISTrimBeard", "beard_trims" },
    { "ISApplyMakeUp", "makeup_applied" },
    { "ISOpenCloseCurtain", "curtains_used" },
    { "ISToggleLightAction", "lights_toggled" },
    { "ISWriteSomething", "notes_written" },
})
