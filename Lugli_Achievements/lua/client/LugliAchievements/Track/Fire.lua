require "LugliAchievements/Registry"

local M = LugliAchievements

-- A class appears on more than one row where one action feeds two counters. A fire is a fire
-- however it was started: only the kindling action used to raise fires_lit, so a survivor whose
-- first fire came off a lighter and a phone book had lit none.
M.countActions("Fire and light", {
    { "ISBBQLightFromKindle", "fires_lit" },
    { "ISBBQLightFromLiterature", "fires_lit" },
    { "ISBBQLightFromLiterature", "fires_from_books" },
    { "ISBBQLightFromPetrol", "fires_lit" },
    { "ISBBQLightFromPetrol", "fires_from_petrol" },
    { "ISPutOutFire", "fires_extinguished" },
    { "ISLitCandleExtinguish", "candles_snuffed" },
    { "ISClearAshes", "ashes_cleared" },
    { "ISBBQToggle", "bbq_uses" },
    { "ISBBQAddFuel", "bbq_uses" },
})
