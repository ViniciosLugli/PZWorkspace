--[[
Item Details Panel: the vanilla tooltip rows it has no row for survive a hidden vanilla tooltip.

What happens today. Item Details Panel rebuilds most of the vanilla item tooltip from the item's
own getters, but not every row (DoTooltip of InventoryItem, Food, Literature, HandWeapon, Clothing,
AlarmClock and AlarmClockClothing on 42.22.2). With its Hide vanilla tooltip option on these are
gone: a clock's time and alarm, raw meat's "Dangerous uncooked" and tainted food's warning, what a
magazine teaches and whether it was read, a skill book's XP levels, a fishing rod's line, hook and
bait, an SCBA's tank, and the crafting notes (can research, favourite recipe input, flagged
unusable or unwanted). Captured in game: scratch/pztest/runs/20261118-134719-idp-player-new.

What this part changes. While the vanilla tooltip is hidden, Item Details Panel shows the same rows
in its main panel, under vanilla's conditions and in vanilla's words: warnings in its Attention
section, the rest in Clock, Reading, Teaches, Fishing and Crafting groups. It reads only; where vanilla's
tooltip writes a fishing rod's default line and hook into its mod data, this shows the defaults.
A book teaching more than eight recipes lists seven, a count and a tip naming the full list key
(Alt by default, rebindable on this mod's options page); held, the list is whole. Item Details
Panel reads its rows again at each information refresh (250 ms by default), which picks the key up.
]]
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.VanillaRows"
-- Rows a recipe list takes at most, the last one a count when it is longer: eight keep a
-- 32-recipe cooking magazine's panel on a 1080p screen.
local MAX_TEACHES = 8
-- With the full list key held: Item Details Panel reads 64 rows of a provider, and a book's other
-- rows here are at most eight. It flows a panel taller than the screen into columns.
local MAX_EXPANDED = 48

local OPTIONS_ID = "LugliModpackFixes"
local FULL_LIST_KEY = "IdpFullListKey"
local fullListOption = nil

-- Registered whatever the part's state: PZAPI.ModOptions save() writes a saved line whose option
-- is not registered with no terminator, so it fuses with the next one.
local function registerOptions()
    if fullListOption ~= nil or PZAPI == nil or PZAPI.ModOptions == nil or Keyboard == nil then return end
    local options = PZAPI.ModOptions:getOptions(OPTIONS_ID)
        or PZAPI.ModOptions:create(OPTIONS_ID, getText("IGUI_LugliMPF_OptionsTitle"))
    fullListOption = options:addKeyBind(FULL_LIST_KEY, getText("IGUI_LugliMPF_IdpFullListKey"),
        Keyboard.KEY_LMENU, getText("IGUI_LugliMPF_IdpFullListKeyTip"))
end
if Events ~= nil and Events.OnGameBoot ~= nil then Events.OnGameBoot.Add(registerOptions) end

-- A modifier's right-hand twin counts too, as Item Details Panel does for Shift.
local TWIN = { [56] = 184, [184] = 56, [29] = 157, [157] = 29, [42] = 54, [54] = 42 }
local KEY_TEXT = { [56] = "Alt", [184] = "Alt", [29] = "Ctrl", [157] = "Ctrl", [42] = "Shift", [54] = "Shift" }

local function fullListKey()
    local key = fullListOption ~= nil and fullListOption:getValue() or nil
    if type(key) ~= "number" or key <= 0 then return nil end
    return key
end

local function held(key)
    if isKeyDown(key) then return true end
    return TWIN[key] ~= nil and isKeyDown(TWIN[key])
end

local function keyText(key)
    return KEY_TEXT[key] or Keyboard.getKeyName(key)
end

-- Vanilla wording without its trailing colon or full stop, and with its line breaks as spaces.
local function plain(text)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "<br>", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "[%s:%.]+$", "")
    if text == "" then return nil end
    return text
end

local function vanilla(key, arg)
    if arg ~= nil then return plain(getText(key, arg)) end
    return plain(getText(key))
end

-- Vanilla's clock text: hours as they are, minutes in two digits (vanilla prints 7:5 as "7:5").
local function clock(hour, minutes)
    return string.format("%d:%02d", hour, minutes)
end

local function row(id, label, value, extra)
    local r = { id = id, label = label, value = value }
    if extra ~= nil then
        for k, v in pairs(extra) do r[k] = v end
    end
    return r
end

local function addClock(rows, item, enabled)
    if not (instanceof(item, "AlarmClock") or instanceof(item, "AlarmClockClothing")) then return end
    local gt = getGameTime()
    if enabled.CurrentTime ~= false then
        local minutes = math.floor(gt:getMinutes() / 10) * 10
        rows[#rows + 1] = row("CurrentTime", vanilla("IGUI_CurrentTime"), clock(gt:getHour(), minutes), { groupId = "Clock" })
    end
    if enabled.Alarm ~= false and item:isAlarmSet() then
        rows[#rows + 1] = row("Alarm", vanilla("IGUI_AlarmIsSetFor"), clock(item:getHour(), item:getMinute()), { groupId = "Clock" })
    end
end

local function addFood(rows, item, enabled)
    if not instanceof(item, "Food") then return end
    local label = getText("IGUI_LugliMPF_IdpFoodSafety")
    if enabled.Uncooked ~= false and item:isbDangerousUncooked() and not item:isCooked() and not item:isBurnt() then
        rows[#rows + 1] = row("Uncooked", label, vanilla("Tooltip_food_Dangerous_uncooked"),
            { section = "status", warning = true, role = "bad" })
    end
    if enabled.Tainted ~= false and item:isTainted() and SandboxVars.EnableTaintedWaterText ~= false then
        local key = item:hasMetal() and "Tooltip_item_TaintedWater_Plastic" or "Tooltip_item_TaintedWater"
        -- Vanilla's two lines (the danger, then how to sterilize) stay two rows, so the panel keeps its width.
        -- The translator turns the file's <br> into a line break; either can arrive.
        local text = getText(key)
        local cut, cutEnd = string.find(text, "<br>", 1, true)
        if cut == nil then cut, cutEnd = string.find(text, "[\r\n]+") end
        if cut == nil then
            rows[#rows + 1] = row("Tainted", label, plain(text), { section = "status", warning = true, role = "bad" })
        else
            rows[#rows + 1] = row("Tainted", label, plain(string.sub(text, 1, cut - 1)), { section = "status", warning = true, role = "bad" })
            local fix = plain(string.sub(text, cutEnd + 1))
            if fix ~= nil and enabled.TaintedFix ~= false then
                rows[#rows + 1] = row("TaintedFix", label, fix, { section = "status", role = "bad" })
            end
        end
    end
end

-- Whether the player's profession or a trait already grants one of these recipes (Literature.DoTooltip).
local function grantedByOrigin(player, recipes)
    local prof = CharacterProfessionDefinition.getCharacterProfessionDefinition(player:getDescriptor():getCharacterProfession())
    local traits = player:getCharacterTraits():getKnownTraits()
    for i = 0, recipes:size() - 1 do
        local recipe = recipes:get(i)
        if prof ~= nil and prof:isGrantedRecipe(recipe) then return true end
        for j = 0, traits:size() - 1 do
            local def = CharacterTraitDefinition.getCharacterTraitDefinition(traits:get(j))
            if def ~= nil and def:isGrantedRecipe(recipe) then return true end
        end
    end
    return false
end

local function addRecipes(rows, enabled, player, recipes, illiterate)
    local label = getText("IGUI_LugliMPF_IdpRecipes")
    if illiterate then
        if enabled.ReadState ~= false then
            rows[#rows + 1] = row("ReadState", label, vanilla("ContextMenu_Illiterate"), { groupId = "Reading", role = "bad" })
        end
        return
    end
    -- One row per recipe under a Teaches heading, named by the recipe and marked known or new, instead
    -- of vanilla's "Teaches: X" line repeated per recipe.
    local knownList = player:getKnownRecipes()
    local count = recipes:size()
    local key = fullListKey()
    local cut = count > MAX_TEACHES and enabled.TeachesMore ~= false
    local expanded = cut and key ~= nil and held(key)
    local limit = expanded and MAX_EXPANDED or MAX_TEACHES
    local shown = count > limit and limit - 1 or count
    for i = 0, shown - 1 do
        local id = "Teaches" .. (i + 1)
        if enabled[id] ~= false then
            local recipe = recipes:get(i)
            local has = knownList:contains(recipe)
            rows[#rows + 1] = row(id, getRecipeDisplayName(recipe),
                getText(has and "IGUI_LugliMPF_IdpKnown" or "IGUI_LugliMPF_IdpNew"),
                { groupId = "Teaches", role = has and "muted" or "good" })
        end
    end
    -- A long list (a cooking magazine) ends in a count, so the panel stays on screen.
    if count > shown and enabled.TeachesMore ~= false then
        local rest = 0
        for i = shown, count - 1 do
            if knownList:contains(recipes:get(i)) then rest = rest + 1 end
        end
        rows[#rows + 1] = row("TeachesMore", getText("IGUI_LugliMPF_IdpMore", tostring(count - shown)),
            getText("IGUI_LugliMPF_IdpKnownOf", tostring(rest), tostring(count - shown)),
            { groupId = "Teaches", role = "muted" })
    end
    -- A cut list says how to see it whole.
    if cut and not expanded and key ~= nil and enabled.TeachesHint ~= false then
        rows[#rows + 1] = row("TeachesHint", getText("IGUI_LugliMPF_IdpFullList"),
            getText("IGUI_LugliMPF_IdpHoldKey", keyText(key)), { groupId = "Teaches", role = "muted" })
    end
    local known = knownList:containsAll(recipes)
    if enabled.ReadState ~= false then
        rows[#rows + 1] = row("ReadState", label,
            vanilla(known and "Tooltip_literature_HasBeenRead" or "Tooltip_literature_NotBeenRead"),
            { groupId = "Reading", role = known and "good" or "value" })
    end
    if known and enabled.KnownFrom ~= false and grantedByOrigin(player, recipes) then
        rows[#rows + 1] = row("KnownFrom", label, vanilla("Tooltip_literature_AlreadyKnown"), { groupId = "Reading", role = "muted" })
    end
end

local function addReading(rows, item, player, enabled)
    if player == nil or not instanceof(item, "Literature") then return end
    local illiterate = player:hasTrait(CharacterTrait.ILLITERATE)
    local trained = item:getLvlSkillTrained()
    if trained ~= -1 and enabled.XpLevels ~= false then
        local levels = tostring(trained)
        if trained ~= item:getMaxLevelTrained() then levels = levels .. "-" .. tostring(item:getMaxLevelTrained()) end
        rows[#rows + 1] = row("XpLevels", getText("IGUI_LugliMPF_IdpXpMultiplier"),
            getText("IGUI_LugliMPF_IdpXpLevels", levels), { groupId = "Reading" })
    end
    local learned = item:getLearnedRecipes()
    if learned ~= nil then addRecipes(rows, enabled, player, learned, illiterate) end
    local modData = item:getModData()
    local single = modData.learnedRecipe
    if type(single) == "string" then
        local list = ArrayList.new()
        list:add(single)
        addRecipes(rows, enabled, player, list, illiterate)
    end
    local title = modData.literatureTitle
    if type(title) == "string" and enabled.RecentlyRead ~= false and player:isLiteratureRead(title) then
        local key = item:hasTag(ItemTag.PICTURE) and "ContextMenu_RecentlySeen" or "ContextMenu_RecentlyRead"
        rows[#rows + 1] = row("RecentlyRead", getText("IGUI_LugliMPF_IdpReadStatus"), vanilla(key), { groupId = "Reading" })
    end
end

local function displayName(fullType, fallbackKey)
    local script = type(fullType) == "string" and getScriptManager():FindItem(fullType) or nil
    if script ~= nil then return script:getDisplayName() end
    return getText(fallbackKey)
end

-- HandWeapon.DoTooltip's fishing rows, with the defaults it would store when the mod data is empty.
local function addFishing(rows, item, enabled)
    if not instanceof(item, "HandWeapon") or not item:hasTag(ItemTag.FISHING_ROD) then return end
    local modData = item:getModData()
    if enabled.Line ~= false then
        local condition = tonumber(modData.fishing_LineCondition) or 1
        rows[#rows + 1] = row("Line", vanilla("Tooltip_fishing_line"),
            displayName(modData.fishing_LineType or "Base.FishingLine", "Tooltip_fishing_line"),
            { groupId = "Fishing", progress = condition, tooltip = vanilla("Tooltip_fishing_line_Condition") })
    end
    if enabled.Hook ~= false then
        rows[#rows + 1] = row("Hook", vanilla("Tooltip_fishing_hook"),
            displayName(modData.fishing_HookType or "Base.FishingHook", "Tooltip_fishing_hook"), { groupId = "Fishing" })
    end
    if enabled.Bait ~= false then
        local lure = modData.fishing_Lure
        if lure == nil then
            rows[#rows + 1] = row("Bait", vanilla("Tooltip_fishing_bait"), getText("UI_None"), { groupId = "Fishing", role = "bad" })
        else
            rows[#rows + 1] = row("Bait", vanilla("Tooltip_fishing_bait"), displayName(lure, "Tooltip_fishing_bait"), { groupId = "Fishing" })
        end
    end
end

local function addTank(rows, item, enabled)
    if not instanceof(item, "Clothing") or enabled.Tank == false then return end
    local label = getText("IGUI_LugliMPF_IdpTank")
    if item:hasTag(ItemTag.SCBA) and item:hasTank() then
        local level = math.max(0, math.min(1, item:getUsedDelta()))
        rows[#rows + 1] = row("Tank", displayName(item:getTankType(), "IGUI_LugliMPF_IdpTank"),
            tostring(math.floor(level * 100 + 0.5)) .. "%", { progress = level })
    elseif item:hasTag(ItemTag.SCBA) or item:hasTag(ItemTag.SCBANO_TANK) then
        rows[#rows + 1] = row("Tank", label, vanilla("Tooltip_NoTank"), { section = "status", warning = true, role = "bad" })
    end
end

local function addCrafting(rows, item, player, enabled)
    if player == nil or item:getScriptItem() == nil then return end
    local label = getText("IGUI_LugliMPF_IdpCrafting")
    if enabled.CanResearch ~= false then
        local researchable = item:getResearchableRecipes(player)
        if researchable ~= nil and not researchable:isEmpty() then
            local key = researchable:size() == 1 and "Tooltip_item_CanResearch" or "Tooltip_item_CanResearchPlural"
            rows[#rows + 1] = row("CanResearch", label, vanilla(key), { groupId = "Crafting", role = "good" })
        end
    end
    if enabled.FavouriteInput ~= false and item:isFavouriteRecipeInput(player) then
        rows[#rows + 1] = row("FavouriteInput", label, vanilla("Tooltip_item_IsFavouriteInput"), { groupId = "Crafting", role = "good" })
    end
    if enabled.NoRecipes ~= false and item:isNoRecipes(player) then
        rows[#rows + 1] = row("NoRecipes", label, vanilla("Tooltip_NoRecipes_More"), { groupId = "Crafting", role = "bad" })
    end
    if enabled.Unwanted ~= false and item:isUnwanted(player) then
        rows[#rows + 1] = row("Unwanted", label, vanilla("Tooltip_Unwanted_More"), { groupId = "Crafting", role = "bad" })
    end
end

local function collect(item, player, context)
    player = player or getPlayer()
    local enabled = context and context.enabledFields or {}
    local rows = {}
    addClock(rows, item, enabled)
    addFood(rows, item, enabled)
    addReading(rows, item, player, enabled)
    addFishing(rows, item, enabled)
    addTank(rows, item, enabled)
    addCrafting(rows, item, player, enabled)
    for i = 1, #rows do rows[i].order = i end
    if #rows == 0 then return nil end
    return rows
end

local function fields()
    local list = {
        { id = "CurrentTime", label = "Current time", groupId = "Clock" },
        { id = "Alarm", label = "Alarm", groupId = "Clock" },
        { id = "Uncooked", label = "Dangerous uncooked", section = "status" },
        { id = "Tainted", label = "Tainted", section = "status" },
        { id = "TaintedFix", label = "How to sterilize", section = "status" },
        { id = "XpLevels", label = "Skill book XP levels", groupId = "Reading" },
    }
    for i = 1, MAX_TEACHES do
        list[#list + 1] = { id = "Teaches" .. i, label = "Recipe taught " .. i, groupId = "Teaches" }
    end
    local rest = {
        { id = "TeachesMore", label = "More recipes taught", groupId = "Teaches" },
        { id = "TeachesHint", label = "Key to hold for the full recipe list", groupId = "Teaches" },
        { id = "ReadState", label = "Recipes read", groupId = "Reading" },
        { id = "KnownFrom", label = "Recipes known from profession or traits", groupId = "Reading" },
        { id = "RecentlyRead", label = "Recently read", groupId = "Reading" },
        { id = "Line", label = "Fishing line", groupId = "Fishing" },
        { id = "Hook", label = "Fishing hook", groupId = "Fishing" },
        { id = "Bait", label = "Fishing bait", groupId = "Fishing" },
        { id = "Tank", label = "SCBA tank" },
        { id = "CanResearch", label = "Can research", groupId = "Crafting" },
        { id = "FavouriteInput", label = "Favourite recipe input", groupId = "Crafting" },
        { id = "NoRecipes", label = "Flagged unusable", groupId = "Crafting" },
        { id = "Unwanted", label = "Flagged unwanted", groupId = "Crafting" },
    }
    for i = 1, #rest do list[#list + 1] = rest[i] end
    return list
end

local function install(ctx)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Vanilla tooltip rows (Modpack Fixes)",
        description = "Rows of the vanilla tooltip that Item Details Panel has none for: a clock's time and alarm, food warnings, what a book or magazine teaches, a fishing rod's tackle, an SCBA's tank and crafting notes. Only while the vanilla tooltip is hidden.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "main", order = 20,
        groups = {
            { id = "Clock", labelKey = "IGUI_LugliMPF_IdpClock", label = "Clock", order = 10 },
            { id = "Reading", labelKey = "IGUI_LugliMPF_IdpReading", label = "Reading", order = 20 },
            { id = "Teaches", labelKey = "IGUI_LugliMPF_IdpTeaches", label = "Teaches", order = 25 },
            { id = "Fishing", labelKey = "IGUI_LugliMPF_IdpFishing", label = "Fishing", order = 30 },
            { id = "Crafting", labelKey = "IGUI_LugliMPF_IdpCrafting", label = "Crafting", order = 40 },
        },
        fields = fields(),
        supports = function(item)
            return item ~= nil and K.vanillaHidden()
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-vanilla",
    switch = "IdpVanilla",
    title = "Item Details Panel: vanilla tooltip rows it lacks",
    tip = "With Item Details Panel's Hide vanilla tooltip option on, some vanilla tooltip rows show nowhere: a clock's time and alarm, raw meat and tainted food warnings, what a magazine or book teaches and whether you read it, a fishing rod's line, hook and bait, an SCBA's tank, and crafting notes. This shows them in Item Details Panel. Only active with Item Details Panel.",
    kind = "compat",
    all = { "ItemDetailsPanel" },
    side = "client",
    phase = "boot",
    pins = { "idp.render", "idp.kinds" },
    check = K.check,
    install = install,
})
