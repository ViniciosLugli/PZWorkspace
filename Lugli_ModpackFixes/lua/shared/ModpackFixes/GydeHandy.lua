--[[
Gyde's Trait Magazines Extended takes over the Handy magazine of the base mod, so that reading
it also gives +1 Carpentry, Carving, Maintenance and Masonry. To hand it over it clears the base
mod's entry for that magazine, but it does that while its own shared file loads. With the base
mod later in the list, the base mod then builds a fresh table with the entry back in it, and its
read hook, which is the outer one, answers first: the trait is granted with no skill levels.

This part clears the base mod's entry once a world starts, which is what Extended meant to do.
Every other magazine of the base mod is left alone.
]]
require "ModpackFixes_Status"

local M = LugliModpackFixes
local MAGAZINE = "Base.HandyMag"

local function install(ctx)
    local extended, base = GydeTraitMagsExtended, GydeTraitMags
    if type(extended) ~= "table" or type(extended.magazineTraits) ~= "table"
        or type(extended.magazineStats) ~= "table" then
        error("Extended's magazine tables are missing")
    end
    if type(base) ~= "table" or type(base.magazineTraits) ~= "table" then
        error("the base mod's magazine table is missing")
    end
    if extended.magazineTraits[MAGAZINE] == nil or extended.magazineStats[MAGAZINE] == nil then
        error("Extended does not handle the Handy magazine")
    end
    local traits = base.magazineTraits
    local saved = traits[MAGAZINE]
    if saved == nil then return end
    traits[MAGAZINE] = nil
    if traits[MAGAZINE] ~= nil then error("the base mod's table rejected the change") end
    ctx.undo(function()
        if traits[MAGAZINE] == nil then traits[MAGAZINE] = saved end
    end)
end

M.addPart({
    name = "gyde-handy",
    switch = "GydeHandy",
    title = "Trait Magazines: Handy magazine skill levels",
    tip = "With Gyde's Trait Magazines and its Extended add-on both active, reading the Handy magazine gives the trait but not the four skill levels Extended adds. This lets Extended handle that magazine, as it intends.",
    kind = "compat",
    all = { "GydesTraitMagazinesExtended", "GydeTraitMags" },
    side = "client",
    pins = { "gyde.base", "gyde.read", "gyde.handover" },
    install = install,
})
