require "LugliAchievements/Registry"

local M = LugliAchievements

M.countActions("Gear and upkeep", {
    { "ISUpgradeWeapon", "weapon_upgrades" },
    { "ISConsolidateDrainable", "consolidations" },
    { "ISDumpContentsAction", "containers_dumped" },
    { "ISAddFuel", "refuels" },
    { "ISConnectCarBatteryToChargerAction", "batteries_charged" },
    { "ISDrinkFluidAction", "drinks" },
    { "ISGetOnBedAction", "sleeps" },
    { "ISRestAction", "rests" },
    { "ISResearchRecipe", "recipes_researched" },
    { "ISReadWorldMap", "maps_read" },
    { "ISClimbThroughWindow", "windows_climbed" },
    { "ISClimbOverFence", "fences_climbed" },
    { "ISAddSheetRope", "sheet_ropes_tied" },
    { "ISSmashWindow", "windows_smashed" },
    { "ISPlaceTrap", "traps_placed" },
})
