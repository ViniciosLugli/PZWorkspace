--[[
Item Details Panel and Dynamic Backpack Upgrades: a bag's upgrade slots and bonuses survive a hidden
vanilla tooltip.

What happens today. Dynamic Backpack Upgrades (LazoloDynamicBackpackUpgrades) draws extra lines into
the vanilla tooltip (ToolTipInvOverride.lua): on a bag, the free upgrade slots and the capacity and
weight reduction its upgrades add; on an upgrade item, what it adds. Each time that tooltip draws it
also sets up a bag it has not seen and puts back its upgraded stats, which the game does not save.
With Item Details Panel's Hide vanilla tooltip option on, the lines are gone and the setup and
restore no longer run when a bag is looked at (its once a minute check covers only the player's main
inventory).

What this part changes. While the vanilla tooltip is hidden, Item Details Panel shows the same
lines in the same colours, worked out as Dynamic Backpack Upgrades works them out, and looking at a
bag sets it up and restores its stats as the vanilla tooltip did.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.BackpackUpgrades"
local BAG_COLOR = { 0.68, 0.64, 0.96, 1 }
local UPGRADE_COLOR = { 0.95, 0.95, 0.2, 1 }
local SANDBOX_BONUS = {
    UpgradeCapacityCloth = "ClothCapacityBonus",
    UpgradeCapacityJean = "JeanCapacityBonus",
    UpgradeCapacityLeather = "LeatherCapacityBonus",
    UpgradeCapacityMilitary = "MilitaryCapacityBonus",
}

local function isUpgrade(item)
    return not item:IsInventoryContainer() and DBU.getUpgradeItemValue(item:getType()) ~= nil
end

local function bagLines(item, player)
    if not item:getModData().LDynamicBackpacksInit then DBU.InitBackpack(item) end
    DBU.RestoreBagStats(item)
    local imd = item:getModData()
    local upgrades = imd.LUpgrades or {}
    local bonusCapacity, bonusReduction = false, false
    for _, v in pairs(upgrades) do
        local value = DBU.getUpgradeItemValue(v)
        if value ~= nil and value >= 1 then bonusCapacity = true
        elseif value ~= nil then bonusReduction = true end
    end
    local lines = {}
    if (imd.LMaxUpgrades or 0) > 0 then
        local modifier = DBU.TailoringModifier
        if modifier == nil or modifier == 0 then modifier = 11 end
        local tailoring = player and player:getPerkLevel(Perks.Tailoring) or 0
        local slots = imd.LMaxUpgrades + math.floor(tailoring / modifier)
        lines[#lines + 1] = getText("UI_LazoloUpgradeSlots") .. ": " .. math.max(0, slots - #upgrades)
    end
    if bonusCapacity then
        lines[#lines + 1] = "+" .. (item:getCapacity() - imd.LCapacity) .. " " .. getText("UI_LazoloCapacity")
    end
    if bonusReduction then
        lines[#lines + 1] = "+" .. (item:getWeightReduction() - imd.LWeightReduction) .. "% " .. getText("UI_LazoloWeightReduction")
    end
    return lines
end

local function upgradeLine(item)
    local itemType = item:getType()
    local value = DBU.getUpgradeItemValue(itemType)
    if value < 1 then
        return getText("UI_UpgradeWeightReduction") .. math.floor(0.5 + (1 - value) * 100) .. "%"
    end
    local text = getText("UI_UpgradeCapacity")
    local option = SANDBOX_BONUS[itemType]
    local bonus = option and SandboxVars.DynamicBackpacks and SandboxVars.DynamicBackpacks[option]
    if type(bonus) == "number" and bonus > 0 then text = text .. bonus .. " " end
    if value > 1 then text = text .. "+" .. math.floor(0.5 + (value - 1) * 100) .. "%" end
    return text
end

local function collect(item, player, context)
    if item:IsInventoryContainer() then
        local lines = bagLines(item, player or getPlayer())
        if #lines == 0 then return nil end
        return K.textRows(getText("IGUI_LugliMPF_IdpBagUpgrades"), nil, lines, context, BAG_COLOR)
    end
    if isUpgrade(item) then
        return K.textRows(getText("IGUI_LugliMPF_IdpBagUpgrades"), nil, { upgradeLine(item) }, context, UPGRADE_COLOR)
    end
    return nil
end

local function check()
    local why = K.check()
    if why ~= nil then return why end
    if type(DBU) ~= "table" then return "Dynamic Backpack Upgrades' DBU table is missing" end
    for _, name in ipairs({ "getUpgradeItemValue", "InitBackpack", "RestoreBagStats" }) do
        if type(DBU[name]) ~= "function" then return "Dynamic Backpack Upgrades has no DBU." .. name end
    end
    return nil
end

local function install(ctx)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Dynamic Backpack Upgrades (Modpack Fixes)",
        description = "A bag's free upgrade slots and the bonuses its upgrades add, and what an upgrade item adds. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "independent", order = 75,
        fields = K.lineFields(3),
        supports = function(item)
            return item ~= nil and K.vanillaHidden() and (item:IsInventoryContainer() or isUpgrade(item))
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-bags",
    switch = "IdpBags",
    title = "Item Details Panel and Dynamic Backpack Upgrades: upgrade slots",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, Dynamic Backpack Upgrades' lines (free upgrade slots, the capacity and weight reduction upgrades add, what an upgrade item adds) are gone, and looking at a bag no longer restores its upgraded stats. This shows the lines in Item Details Panel and restores the stats as before. Only active with both mods.",
    kind = "compat",
    all = { "ItemDetailsPanel", "LazoloDynamicBackpackUpgrades" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.kinds", "dbu.tooltip", "dbu.init" },
    check = check,
    install = install,
})
