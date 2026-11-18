--[[
Item Details Panel: an item's description and its mod survive a hidden vanilla tooltip.

What happens today. The vanilla tooltip ends with the item's Tooltip text (a translation key, or a
sentence another mod sets at run time, such as Emergency Lights' burn time left on a lit flare) and,
with the game's Show item mod info option on, the "Mod: <name>" line (InventoryItem.DoTooltip on
42.22.2); a weapon part's also shows its slot and the guns it fits (WeaponPart.DoTooltip). Item
Details Panel shows none of these, so with its Hide vanilla tooltip option on they are gone.

What this part changes. While the vanilla tooltip is hidden, Item Details Panel shows them in a
Details block of its own, read the way the vanilla tooltip reads them.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.Description"
local MAX_LINES = 12
-- Item Details Panel drops any row text over 1024 characters (APIFormatting.lua F.text).
local MAX_TEXT = 1000
local TEXT_COLOR = { 1, 1, 0.8, 1 }
local MOD_COLOR = { 0.392, 0.584, 0.929, 1 }

local function tooltipKey(item)
    for i = 1, #K.tooltipKeyHooks do
        local key = K.tooltipKeyHooks[i](item)
        if key ~= nil then return key end
    end
    return item:getTooltip()
end

local function descriptionLines(item)
    local key = tooltipKey(item)
    if type(key) ~= "string" or key == "" then return nil end
    return K.splitLines(getText(key), MAX_LINES)
end

local function modLine(item)
    if not getCore():getOptionShowItemModInfo() or item:isVanilla() then return nil end
    local name = item:getModName()
    if type(name) ~= "string" or name == "" then return nil end
    return "Mod: " .. name
end

-- WeaponPart.DoTooltip's two rows: the part's slot, and the guns it fits (by display name).
local function partRows(item, enabled)
    if not instanceof(item, "WeaponPart") then return {} end
    local rows = {}
    local partType = item:getPartType()
    if enabled.PartType ~= false and type(partType) == "string" and partType ~= "" then
        rows[#rows + 1] = { id = "PartType", label = getText("Tooltip_weapon_Type"), value = getText("Tooltip_weapon_" .. partType),
            order = 0.2, presentation = { kind = "keyvalue", labelColor = TEXT_COLOR, valueColor = TEXT_COLOR } }
    end
    local mountOn = item:getMountOn()
    if enabled.MountOn ~= false and mountOn ~= nil and mountOn:size() > 0 then
        local names = {}
        for i = 0, mountOn:size() - 1 do
            local script = getScriptManager():FindItem(mountOn:get(i))
            if script ~= nil then names[#names + 1] = script:getDisplayName() end
        end
        if #names > 0 then
            local text = getText("Tooltip_weapon_CanBeMountOn") .. ": " .. table.concat(names, ", ")
            if #text > MAX_TEXT then text = string.sub(text, 1, MAX_TEXT - 3) .. "..." end
            rows[#rows + 1] = { id = "MountOn", label = text, value = text, order = 0.4,
                presentation = { kind = "label", labelColor = TEXT_COLOR } }
        end
    end
    return rows
end

local function collect(item, player, context)
    local enabled = context and context.enabledFields or {}
    local rows = K.textRows(getText("IGUI_LugliMPF_IdpDescription"), nil, descriptionLines(item) or {}, context, TEXT_COLOR)
    local heading = (rows[1] ~= nil and rows[1].id == "Heading") and 1 or 0
    local parts = partRows(item, enabled)
    for i = 1, #parts do
        table.insert(rows, heading + i, parts[i])
    end
    local mod = modLine(item)
    if mod ~= nil and enabled.Mod ~= false then
        rows[#rows + 1] = { id = "Mod", label = mod, value = mod,
            presentation = { kind = "label", labelColor = MOD_COLOR }, order = MAX_LINES + 1 }
    end
    if #rows <= heading then return nil end
    return rows
end

local function install(ctx)
    local fields = K.lineFields(MAX_LINES)
    fields[#fields + 1] = { id = "PartType", label = "Weapon part type", order = 0.2 }
    fields[#fields + 1] = { id = "MountOn", label = "Can be mounted on", order = 0.4 }
    fields[#fields + 1] = { id = "Mod", label = "Mod", order = MAX_LINES + 1 }
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Item details (Modpack Fixes)",
        description = "The item's description, its mod and a weapon part's slot and guns, as the vanilla tooltip shows them. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "independent", order = 90,
        fields = fields,
        supports = function(item)
            return item ~= nil and K.vanillaHidden()
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-text",
    switch = "IdpText",
    title = "Item Details Panel: item description and mod",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, an item's description (and, if the game's Show item mod info option is on, the mod it comes from) shows nowhere. This shows both in Item Details Panel. Only active with Item Details Panel.",
    kind = "compat",
    all = { "ItemDetailsPanel" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.kinds" },
    check = K.check,
    install = install,
})
