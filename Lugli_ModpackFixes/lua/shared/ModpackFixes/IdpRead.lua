--[[
Item Details Panel: a book shows its reading time, not the time it would burn for.

What happens today. Item Details Panel adds a "Burn time" row to anything the campfire accepts as
fuel or tinder (Providers/Equipment.lua, from ISCampingMenu.getFuelDurationForItem), and a book or
magazine is both: a quarter of its weight in hours. So the only time on a book's panel is the
campfire's, under a name that reads like the thing a player came to see. How long the book takes to
read (ISReadABook:getDuration) is shown nowhere, by Item Details Panel or by the vanilla tooltip.

What this part changes. For a book, magazine or other literature Item Details Panel drops its
Burn time and Tinder burn time rows and shows a Reading time row in the Common section. The time
is what the Read action will take if started now: ISReadABook.getDuration itself, run on a stand-in
for the action, so the skill, traits, reading glasses, sitting, the MinutesPerPage sandbox option
and any mod that changes the duration (M-13's Reading Tweaks halves it seated) are counted by the
game's own chain, not copied. A partly read book also says how much is left. The row shows for
what the Read menu offers the player: not for an illiterate player's text book, a skill book too
complicated or too simple, or an empty notebook. Other fuel keeps its Burn time.

The stand-in action holds the book behind an overlay that swallows setAlreadyReadPages, the one
write getDuration makes on a book (it copies the player's count onto it). ISReadABook.checkLevel's
reset of a player's read pages (illiterate, or a skill book too hard) never happens here, since the
row is only worked out for a player the Read menu lets read, so looking at a tooltip changes nothing.
]]
require "TimedActions/ISReadABook"
require "ModpackFixes_Status"
require "ModpackFixes_Idp"
local M = LugliModpackFixes
local K = M.idp

local PROVIDER = "LugliModpackFixes.ReadTime"

local function swallow() end
local SWALLOW_PAGES = { setAlreadyReadPages = swallow }

local function check()
    local why = K.check()
    if why ~= nil then return why end
    local idp = ItemDetailsPanel
    if type(idp.addEquipmentValues) ~= "function" then return "Item Details Panel has no addEquipmentValues" end
    if type(idp.duration) ~= "function" then return "Item Details Panel has no duration formatter" end
    if type(ISReadABook) ~= "table" or type(ISReadABook.getDuration) ~= "function"
        or type(ISReadABook.checkLevel) ~= "function" then
        return "the Read action has no getDuration"
    end
    return nil
end

local function isLiterature(item)
    return item ~= nil and instanceof(item, "Literature")
end

-- What ContextMenu.doLiteratureMenu offers: a Read option that is not greyed out.
local function offersRead(item, player)
    if item:hasTag(ItemTag.UNINTERESTING) then return false end
    local picture = item:hasTag(ItemTag.PICTUREBOOK) or item:hasTag(ItemTag.PICTURE)
    if player:hasTrait(CharacterTrait.ILLITERATE) and not picture then return false end
    local book = SkillBook ~= nil and SkillBook[item:getSkillTrained()] or nil
    local perk = book ~= nil and book.perk or nil
    if perk == nil then return true end
    local level = player:getPerkLevel(perk)
    if item:getLvlSkillTrained() ~= -1 and item:getLvlSkillTrained() > level + 1 then return false end
    if item:getMaxLevelTrained() ~= -1 and item:getMaxLevelTrained() <= level then return false end
    return true
end

-- ISReadABook:new's own reading of the option.
local function minutesPerPage()
    local option = getSandboxOptions():getOptionByName("MinutesPerPage")
    local value = option ~= nil and option:getValue() or nil
    if type(value) ~= "number" or value < 0 then return 2.0 end
    return value
end

-- Game minutes the Read action takes from the first page. A timed action's duration is counted in
-- units of 1 / (2 * minutes per day) game minutes: getDuration divides pages * minutes per page by
-- that to make it.
local function readMinutes(item, player)
    local action = {
        character = player,
        item = M.overlay(item, SWALLOW_PAGES),
        minutesPerPage = minutesPerPage(),
    }
    local ticks = ISReadABook.getDuration(action)
    if type(ticks) ~= "number" or ticks ~= ticks or ticks <= 0 or ticks == math.huge then return nil end
    return ticks / (getGameTime():getMinutesPerDay() * 2)
end

local function clock(minutes)
    return ItemDetailsPanel.duration(minutes / 1440, 1)
end

local function collect(item, player, context)
    local enabled = context and context.enabledFields or {}
    if enabled.ReadTime == false or player == nil or not offersRead(item, player) then return nil end
    local minutes = readMinutes(item, player)
    if minutes == nil then return nil end
    local text = clock(minutes)
    local pages = item:getNumberOfPages()
    local read = pages > 0 and player:getAlreadyReadPages(item:getFullType()) or 0
    if read > 0 and read < pages then
        text = text .. " (" .. getText("IGUI_LugliMPF_IdpReadLeft", clock(minutes * (1 - read / pages))) .. ")"
    end
    return { { id = "ReadTime", value = text, section = "properties", order = 50 } }
end

local function install(ctx)
    ctx.wrap(ItemDetailsPanel, "addEquipmentValues", function(callOriginal)
        return function(item, values)
            callOriginal(item, values)
            if isLiterature(item) and type(values) == "table" then
                values.FuelTime = nil
                values.TinderTime = nil
            end
        end
    end)
    K.register(ctx, {
        id = PROVIDER, apiVersion = 1,
        name = "Reading time (Modpack Fixes)",
        description = "How long a book, magazine or other literature takes to read, as the Read action works it out, in place of its campfire burn time.",
        author = "Lugli", modId = "Lugli_ModpackFixes",
        displayTarget = "main", order = 50,
        fields = { { id = "ReadTime", labelKey = "IGUI_LugliMPF_IdpReadTime", label = "Reading time", section = "properties", order = 50 } },
        supports = function(item)
            return isLiterature(item)
        end,
        collect = collect,
    })
end

M.addPart({
    name = "idp-read",
    switch = "IdpRead",
    title = "Item Details Panel: reading time on books",
    tip = "Item Details Panel shows a book's campfire Burn time, the only time on its panel, and nothing about how long it takes to read. With this on, books and magazines show their Reading time instead (worked out the way the Read action does, with your skills, traits, glasses and sitting, and mods that change it), and a partly read one says how much is left. Other fuel keeps its Burn time. Only active with Item Details Panel.",
    kind = "compat",
    all = { "ItemDetailsPanel" },
    side = "client",
    phase = "boot",
    pins = { "idp.equipment", "idp.equipcall", "idp.fuel", "idp.duration", "vanilla.readcheck", "vanilla.readduration", "vanilla.readnew" },
    check = check,
    install = install,
})
