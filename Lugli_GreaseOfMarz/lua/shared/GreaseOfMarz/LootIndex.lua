--[[
Gunworks loot insert, indexed. Guns of Marz adds its guns to the loot tables through Gunworks'
Distribution.Insert, which walks every table and asks every script item its name on each call,
so its cost grows with the size of the mod list.

The work is shared/FastLoading_Gunworks.lua, which Fast Loading ships byte for byte at the same
game path, so exactly one copy runs whichever of the two mods is active. It installs itself at
the loot merge and reports there; this part only checks at boot that the file loaded.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

M.addPart("LootIndex", { "SWMG" }, function()
    if type(LugliGunworksLoot) ~= "table" then
        error("shared/FastLoading_Gunworks.lua did not load")
    end
end)
