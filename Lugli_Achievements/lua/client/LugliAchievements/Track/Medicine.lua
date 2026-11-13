require "LugliAchievements/Registry"

local M = LugliAchievements
local PART = "Field medicine"

M.countActions(PART, {
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

--- ISApplyBandage is also the action that takes a bandage OFF, with doIt false, so counting every
--- perform credited each removal as an application.
local function onBandage(self)
    if self == nil or self.character == nil or not self.doIt then return end
    M.incStat(self.character, "bandages_applied", 1)
end

-- Added after countActions, so a missing class reported here is not overwritten by its "ok".
M.addHandler(PART, "OnGameStart", function()
    M.onAction(PART, "ISApplyBandage", onBandage)
end)
