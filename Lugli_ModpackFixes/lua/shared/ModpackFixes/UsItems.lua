--[[
Undead Survivor: its gas masks survive a filter change, and the Stalker knife can be sharpened.

What happens today.
  - Its three gas masks (Headhunter, Deadly Headhunter, Prepper) carry the vanilla gas mask tag,
    so vanilla's filter recipes take them, but not vanilla's KeepOnDeplete. Removing the filter
    sets the mask's uses to 0, and an item at 0 uses without KeepOnDeplete is deleted the next
    time it is used, so the mask vanishes (RecipeCodeOnCreate.removeTankOrFilter, ItemUser).
  - The Stalker knife is a long blade with a Sharpness value but without the sharpenable tag
    every vanilla long blade has, so no sharpening recipe accepts it.

What this part changes. The masks get KeepOnDeplete, read live from the item script, so masks
already in a save are covered. The knife gets the sharpenable tag and is added to every recipe
input that takes that tag: the engine resolves a tag to its items once, before any Lua runs, so
the tag alone would not reach the recipes. Repair is unchanged: vanilla repairs no metal blade.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local MASKS = { "UndeadSurvivor.HeadhunterGasmask", "UndeadSurvivor.DeadlyHeadhunterGasmask", "UndeadSurvivor.PrepperMask" }
local KNIFE = "UndeadSurvivor.StalkerKnife"

local function script(manager, fullType)
    local item = manager:getItem(fullType)
    if item == nil then error(fullType .. " is not defined") end
    return item
end

local function contains(list, value)
    for i = 0, list:size() - 1 do
        if list:get(i) == value then return true end
    end
    return false
end

local function install(ctx)
    local manager = ScriptManager.instance
    local sharpenable = ItemTag.SHARPENABLE
    if sharpenable == nil or ItemTag.GAS_MASK == nil then error("ItemTag.SHARPENABLE or GAS_MASK is missing") end

    for i = 1, #MASKS do
        local mask = script(manager, MASKS[i])
        if not mask:hasTag(ItemTag.GAS_MASK) then error(MASKS[i] .. " is no longer a gas mask") end
        if not mask:isKeepOnDeplete() then
            mask:setKeepOnDeplete(true)
            ctx.undo(function() mask:setKeepOnDeplete(false) end)
            if not mask:isKeepOnDeplete() then error(MASKS[i] .. " did not take KeepOnDeplete") end
        end
    end

    local knife = script(manager, KNIFE)
    if not knife:hasTag(sharpenable) then
        knife:DoParam("Tags = base:sharpenable")
        ctx.undo(function() knife:getTags():remove(sharpenable) end)
        if not knife:hasTag(sharpenable) then error(KNIFE .. " did not take the sharpenable tag") end
    end
    local recipes, joined = manager:getAllCraftRecipes(), 0
    for r = 0, recipes:size() - 1 do
        local recipe = recipes:get(r)
        local inputs = recipe:getInputs()
        for i = 0, inputs:size() - 1 do
            local input = inputs:get(i)
            local tags = input:getItemTags()
            if tags ~= nil and tags:contains(sharpenable) then
                local items = input:getPossibleInputItems()
                if not contains(items, knife) then
                    items:add(knife)
                    ctx.undo(function() items:remove(knife) end)
                    if not contains(items, knife) then error(recipe:getName() .. " did not take " .. KNIFE) end
                end
                local used = knife:getUsedInRecipes()
                if not contains(used, recipe:getName()) then
                    used:add(recipe:getName())
                    ctx.undo(function() used:remove(recipe:getName()) end)
                end
                joined = joined + 1
            end
        end
    end
    if joined == 0 then error("no recipe input takes the sharpenable tag") end
end

M.addPart({
    name = "us-items",
    switch = "UsItems",
    title = "Undead Survivor: gas masks keep after a filter change, Stalker knife sharpens",
    tip = "Undead Survivor's three gas masks are deleted once their filter is removed, and its Stalker knife cannot be sharpened. This makes the masks stay like vanilla gas masks and lets the sharpening recipes take the knife. Only active with Undead Survivor.",
    kind = "fix",
    all = { "UndeadSuvivor" },
    side = "both",
    phase = "world",
    install = install,
})
