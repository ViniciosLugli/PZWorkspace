--[[
    EmergencyLightsItems
    GENERATED FILE. Edit the generator that writes it, never this.

    The same table the item scripts, the meshes and the icons came from, so the
    burn time Lua enforces cannot drift from the one the script advertises and the
    light colour cannot drift from the icon.

    Colours are 0-1 here because IsoLightSource takes floats, while the script
    writes the same values as 0-255. Note the engine doubles a persistent light's
    colour and clamps it (LightingJNI.java:299-313), so anything above 0.5
    saturates.
]]

require "LugliEmergencyLights/Core"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Items"

--- lit fullType -> the dead item it becomes. One per FAMILY, not one overall:
--- a burnt road flare must not turn into a glow stick.
M.SPENT_OF = {
    ["LugliEmergencyLights.GlowStick_Green_Lit"] = "LugliEmergencyLights.GlowStick_Spent",
    ["LugliEmergencyLights.GlowStick_Blue_Lit"] = "LugliEmergencyLights.GlowStick_Spent",
    ["LugliEmergencyLights.GlowStick_Pink_Lit"] = "LugliEmergencyLights.GlowStick_Spent",
    ["LugliEmergencyLights.GlowStick_Orange_Lit"] = "LugliEmergencyLights.GlowStick_Spent",
    ["LugliEmergencyLights.ChemLight_Green_Lit"] = "LugliEmergencyLights.ChemLight_Spent",
    ["LugliEmergencyLights.ChemLight_Red_Lit"] = "LugliEmergencyLights.ChemLight_Spent",
    ["LugliEmergencyLights.ChemLight_Yellow_Lit"] = "LugliEmergencyLights.ChemLight_Spent",
    ["LugliEmergencyLights.ChemLight_Cyan_Lit"] = "LugliEmergencyLights.ChemLight_Spent",
    ["LugliEmergencyLights.RoadFlare_Red_Lit"] = "LugliEmergencyLights.RoadFlare_Spent",
}

--- every dead item, for the loot and junk passes. A dead item is lighter than the
--- live one: what is left is the case, and the chemistry that made up the
--- difference has gone.
M.SPENT = {
    ["LugliEmergencyLights.GlowStick_Spent"] = { family = "GlowStick", weight = 0.04 },
    ["LugliEmergencyLights.ChemLight_Spent"] = { family = "ChemLight", weight = 0.05 },
    ["LugliEmergencyLights.RoadFlare_Spent"] = { family = "RoadFlare", weight = 0.07 },
}

--- sealed fullType -> lit fullType.
M.LIT_OF = {
    ["LugliEmergencyLights.GlowStick_Green"] = "LugliEmergencyLights.GlowStick_Green_Lit",
    ["LugliEmergencyLights.GlowStick_Blue"] = "LugliEmergencyLights.GlowStick_Blue_Lit",
    ["LugliEmergencyLights.GlowStick_Pink"] = "LugliEmergencyLights.GlowStick_Pink_Lit",
    ["LugliEmergencyLights.GlowStick_Orange"] = "LugliEmergencyLights.GlowStick_Orange_Lit",
    ["LugliEmergencyLights.ChemLight_Green"] = "LugliEmergencyLights.ChemLight_Green_Lit",
    ["LugliEmergencyLights.ChemLight_Red"] = "LugliEmergencyLights.ChemLight_Red_Lit",
    ["LugliEmergencyLights.ChemLight_Yellow"] = "LugliEmergencyLights.ChemLight_Yellow_Lit",
    ["LugliEmergencyLights.ChemLight_Cyan"] = "LugliEmergencyLights.ChemLight_Cyan_Lit",
    ["LugliEmergencyLights.RoadFlare_Red"] = "LugliEmergencyLights.RoadFlare_Red_Lit",
}

--- lit fullType -> everything the sweep and the tooltip need.
M.LIT = {
    ["LugliEmergencyLights.GlowStick_Green_Lit"] = {
        family = "GlowStick", colour = "Green",
        burnHours = 4.00, radius = 5,
        r = 0.1569, g = 1.0000, b = 0.3529,
        throwRange = 18.2,
        slide = 0.26,
        spread = 1.35,
        windage = 1.00,
        bounceE = 0.46,
        bounceF = 0.62,
    },
    ["LugliEmergencyLights.GlowStick_Blue_Lit"] = {
        family = "GlowStick", colour = "Blue",
        burnHours = 4.00, radius = 5,
        r = 0.2353, g = 0.5490, b = 1.0000,
        throwRange = 18.2,
        slide = 0.26,
        spread = 1.35,
        windage = 1.00,
        bounceE = 0.46,
        bounceF = 0.62,
    },
    ["LugliEmergencyLights.GlowStick_Pink_Lit"] = {
        family = "GlowStick", colour = "Pink",
        burnHours = 4.00, radius = 5,
        r = 1.0000, g = 0.3137, b = 0.7059,
        throwRange = 18.2,
        slide = 0.26,
        spread = 1.35,
        windage = 1.00,
        bounceE = 0.46,
        bounceF = 0.62,
    },
    ["LugliEmergencyLights.GlowStick_Orange_Lit"] = {
        family = "GlowStick", colour = "Orange",
        burnHours = 4.00, radius = 5,
        r = 1.0000, g = 0.5490, b = 0.1569,
        throwRange = 18.2,
        slide = 0.26,
        spread = 1.35,
        windage = 1.00,
        bounceE = 0.46,
        bounceF = 0.62,
    },
    ["LugliEmergencyLights.ChemLight_Green_Lit"] = {
        family = "ChemLight", colour = "Green",
        burnHours = 8.00, radius = 10,
        r = 0.1569, g = 1.0000, b = 0.3529,
        throwRange = 16.2,
        slide = 0.16,
        spread = 1.05,
        windage = 0.72,
        bounceE = 0.36,
        bounceF = 0.48,
    },
    ["LugliEmergencyLights.ChemLight_Red_Lit"] = {
        family = "ChemLight", colour = "Red",
        burnHours = 8.00, radius = 10,
        r = 1.0000, g = 0.1765, b = 0.1373,
        throwRange = 16.2,
        slide = 0.16,
        spread = 1.05,
        windage = 0.72,
        bounceE = 0.36,
        bounceF = 0.48,
    },
    ["LugliEmergencyLights.ChemLight_Yellow_Lit"] = {
        family = "ChemLight", colour = "Yellow",
        burnHours = 8.00, radius = 10,
        r = 1.0000, g = 0.9020, b = 0.2353,
        throwRange = 16.2,
        slide = 0.16,
        spread = 1.05,
        windage = 0.72,
        bounceE = 0.36,
        bounceF = 0.48,
    },
    ["LugliEmergencyLights.ChemLight_Cyan_Lit"] = {
        family = "ChemLight", colour = "Cyan",
        burnHours = 8.00, radius = 10,
        r = 0.2157, g = 0.9216, b = 0.9020,
        throwRange = 16.2,
        slide = 0.16,
        spread = 1.05,
        windage = 0.72,
        bounceE = 0.36,
        bounceF = 0.48,
    },
    ["LugliEmergencyLights.RoadFlare_Red_Lit"] = {
        family = "RoadFlare", colour = "Red",
        burnHours = 0.50, radius = 15,
        r = 1.0000, g = 0.1765, b = 0.1373,
        throwRange = 10.5,
        slide = 0.07,
        spread = 0.70,
        windage = 0.45,
        bounceE = 0.18,
        bounceF = 0.28,
        tintByValue = true,
    },
}

--- family id -> defaults, for the sandbox options and the listing.
M.FAMILIES = {
    ["GlowStick"] = { label = "Glow Stick", burnHours = 4.00, radius = 5, throwRange = 18.2, slide = 0.26, spread = 1.35, bounceE = 0.46, bounceF = 0.62, windage = 1.00 },
    ["ChemLight"] = { label = "Chem Light", burnHours = 8.00, radius = 10, throwRange = 16.2, slide = 0.16, spread = 1.05, bounceE = 0.36, bounceF = 0.48, windage = 0.72 },
    ["RoadFlare"] = { label = "Road Flare", burnHours = 0.50, radius = 15, throwRange = 10.5, slide = 0.07, spread = 0.70, bounceE = 0.18, bounceF = 0.28, windage = 0.45 },
}

--- family id -> how far ABOVE the object its light actually comes from, in world
--- levels. Derived here rather than tuned in Lua, because it is a fact about the
--- mesh and the engine, and both live in this file.
---
--- A light is not at the middle of the object, it is at the part that is burning.
--- A glow stick is a tube whose whole body glows but whose moulded eyelet does not,
--- so its light comes from just under half way up; a road flare is dark along its
--- length and incandescent at the tip, so its light comes from just above the top.
---
--- THE MESH STANDS UPRIGHT, which is what makes this a purely vertical offset.
--- ItemModelRenderer.java:484 resets the transform to identity, and the lay-down
--- rotation at :486-488 is guarded on bWeaponFix, which is false on the
--- WorldStaticModel path (:265). Nothing else rotates it, and these blocks declare
--- no `attachment world`. So the mesh's local +Y is world +Z, straight up.
---
--- levels = y_units * groundScale * 0.61237, where 0.61237 is 1.5 / 2.44949: the
--- engine's model scale (Core.java:2616) over its frame-units-per-level
--- (Core.java:2612).
M.EMISSIVE = {
    ["GlowStick"] = { 0.0, 0.0, 0.0413 },   -- 0.150 m * 1.00 scale * 0.45 of its height
    ["ChemLight"] = { 0.0, 0.0, 0.0441 },   -- 0.160 m * 1.00 scale * 0.45 of its height
    ["RoadFlare"] = { 0.0, 0.0, 0.1187 },   -- 0.190 m * 1.00 scale * 1.02 of its height
}

--- Sandbox option names and their defaults, generated from the same table that
--- wrote media/sandbox-options.txt, so the fallback used when a world has no value
--- for an option cannot disagree with what the sandbox screen showed.
--- Read these through LugliEmergencyLights/Config, never directly.
M.SANDBOX_PAGE = "LugliEL"
M.SANDBOX = {
    ["GlowStickHours"] = { kind = "double", default = 4 },
    ["ChemLightHours"] = { kind = "double", default = 8 },
    ["RoadFlareHours"] = { kind = "double", default = 0.5 },
    ["GlowStickRadius"] = { kind = "integer", default = 5 },
    ["ChemLightRadius"] = { kind = "integer", default = 10 },
    ["RoadFlareRadius"] = { kind = "integer", default = 15 },
    ["LightIntensity"] = { kind = "double", default = 1 },
    ["LightSaturation"] = { kind = "double", default = 0.45 },
    ["LightFlicker"] = { kind = "boolean", default = true },
    ["LightIncidence"] = { kind = "boolean", default = true },
    ["ThrowRangeMult"] = { kind = "double", default = 1 },
    ["CrackNoise"] = { kind = "integer", default = 3 },
    ["ThrowNoise"] = { kind = "integer", default = 5 },
    ["FlareNoise"] = { kind = "integer", default = 12 },
    ["FlareGunNoise"] = { kind = "integer", default = 30 },
    ["AerialNoise"] = { kind = "integer", default = 20 },
    ["AerialShotRange"] = { kind = "integer", default = 30 },
    ["AerialSeconds"] = { kind = "integer", default = 300 },
    ["AerialLightRadius"] = { kind = "integer", default = 20 },
    ["AerialRange"] = { kind = "integer", default = 150 },
    ["FlareWash"] = { kind = "boolean", default = true },
    ["FlareFire"] = { kind = "boolean", default = true },
    ["CarriedFlareSound"] = { kind = "boolean", default = true },
    ["MapMarker"] = { kind = "boolean", default = true },
    ["MapRangeCircle"] = { kind = "boolean", default = false },
    ["LootMultiplier"] = { kind = "double", default = 1 },
    ["SweepRadius"] = { kind = "integer", default = 10 },
    ["SweepSeconds"] = { kind = "double", default = 1 },
    ["DebugLog"] = { kind = "boolean", default = false },
    ["DebugRanges"] = { kind = "boolean", default = false },
}

--- The flare gun.
M.GUN = {
    item = "LugliEmergencyLights.FlareGun",
    ammo = "lugli:flare_cartridge",
}

--- The aerial signal cartridge, keyed by fullType. A table with one row rather
--- than a single record, so a second colour, if the reload path ever grows one, is
--- a row here instead of a rewrite of everything that reads it.
--- flareLife is what WorldFlares.launchFlare wants: its lifetime argument is
--- accumulated GameTime.getMultiplier, which advances about 48 per REAL second, so
--- it is seconds * 48 and not seconds. The engine's own ClimateManager passes 7200,
--- which is 150 seconds, and the debug UI's lifeTime * 60 is off by 1.25x from the
--- label above it.
M.CARTRIDGES = {
    ["LugliEmergencyLights.FlareCartridge"] = {
        colour = "Red", ammo = "lugli:flare_cartridge",
        r = 1.0000, g = 0.1765, b = 0.1373,
        rangeTiles = 150, aloftSeconds = 300.0, flareLife = 14400.0,
        -- Fired, not spent. Unlike the three light families it leaves NO
        -- item behind: the whole cartridge goes up, so the firing code
        -- removes it and puts nothing in its place.
        consumed = true,
    },
}

--- The cartridge record for an item, or nil.
function M.cartridgeInfo(item)
    if item == nil then return nil end
    return M.CARTRIDGES[item:getFullType()]
end

--- The burning-light record for an item, or nil.
function M.litInfo(item)
    if item == nil then return nil end
    return M.LIT[item:getFullType()]
end

--- The family of a SEALED item, from the lit form it becomes. nil if not crackable.
---
--- ONE lookup, shared by the context menu, the double click and the timed action, so
--- the label, the animation and the swap cannot disagree about what is being cracked.
function M.sealedFamily(item)
    if item == nil then return nil end
    local lit = M.LIT_OF[item:getFullType()]
    if lit == nil then return nil end
    local info = M.LIT[lit]
    return info ~= nil and info.family or nil
end

M.status(PART, true)
