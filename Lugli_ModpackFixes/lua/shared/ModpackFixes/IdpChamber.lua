--[[
Item Details Panel: a gun's chamber warning survives a hidden vanilla tooltip.

What happens today. The vanilla tooltip of a loaded gun with nothing chambered warns in red "No
round in chamber" (or that a spent round is in it), and a gun holding spent rounds shows how many
(HandWeapon.DoTooltip on 42.22.2). Item Details Panel folds the chamber into its ammo count
(5+0/5) and drops the warning (Providers/Firearms.lua sets its Chamber row to nil), and it never
shows spent rounds. With its Hide vanilla tooltip option on, both are gone.

What this part changes. While the vanilla tooltip is hidden, Item Details Panel's Attention section
shows the same warning, under vanilla's rule, worded by vanilla's own text.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.Chamber"

local function trimColon(text)
    return (string.gsub(text, "%s*:%s*$", ""))
end

-- HandWeapon.DoTooltip: a jam is shown instead (Item Details Panel shows it too); a gun with a
-- chamber, rounds in it and none chambered warns; otherwise spent rounds are counted.
local function collect(item, player, context)
    if not instanceof(item, "HandWeapon") or item:isJammed() then return nil end
    local enabled = context and context.enabledFields or {}
    if item:haveChamber() and not item:isRoundChambered() and item:getCurrentAmmoCount() > 0 then
        if enabled.Chamber == false then return nil end
        local key = item:isSpentRoundChambered() and "Tooltip_weapon_SpentRoundChambered" or "Tooltip_weapon_NoRoundChambered"
        return { { id = "Chamber", value = getText(key), section = "status", warning = true, role = "bad", order = 10 } }
    end
    local spent = item:getSpentRoundCount()
    if spent > 0 and enabled.SpentRounds ~= false then
        return { { id = "SpentRounds", label = trimColon(getText("Tooltip_weapon_SpentRounds")),
            value = tostring(spent) .. " / " .. tostring(item:getMaxAmmo()), section = "status", warning = true,
            role = "bad", order = 11 } }
    end
    return nil
end

local function install(ctx)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Chamber warning (Modpack Fixes)",
        description = "The vanilla tooltip's warning for a loaded gun with nothing chambered, and its spent round count. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "main", order = 10,
        fields = {
            { id = "Chamber", labelKey = "IGUI_LugliMPF_IdpChamber", label = "Chamber", section = "status", order = 10 },
            { id = "SpentRounds", label = "Spent rounds", section = "status", order = 11 },
        },
        supports = function(item)
            return item ~= nil and K.vanillaHidden() and instanceof(item, "HandWeapon") and item:isRanged()
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-chamber",
    switch = "IdpChamber",
    title = "Item Details Panel: chamber warning",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, a loaded gun with nothing chambered no longer warns that it needs racking, and spent rounds in a gun are not counted. This shows both in Item Details Panel. Only active with Item Details Panel.",
    kind = "compat",
    all = { "ItemDetailsPanel" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.chamber" },
    check = K.check,
    install = install,
})
