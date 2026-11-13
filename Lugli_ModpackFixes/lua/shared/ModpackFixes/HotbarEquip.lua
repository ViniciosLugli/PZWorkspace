--[[
SwapIt against Fancy Handwork and H_E_C_U on the hotbar.

What happens today. SwapIt replaces ISHotbar.equipItem whole and keeps nothing of what was there,
so two hotbar features of mods loaded before it are gone:
  - Fancy Handwork: a hotbar key pressed with its modifier key held takes the item into the off
    hand. SwapIt has its own support for this, but it looks for the mod id "FancyHandwork" and
    this build of Fancy Handwork is "FancyHandworkB42_19", so it never turns on.
  - H_E_C_U: a hotbar key on a helmet or mask clipped to the belt puts it on, or takes it off,
    instead of holding it in a hand.
Both mods keep their own versions in locals, so neither can be put back.

What this part changes. It wraps SwapIt's function with the two behaviours, written here:
  - With H_E_C_U active, a hotbar key on a piece of clothing toggles wearing it.
  - With Fancy Handwork active and its modifier key held, a hotbar key takes a one-handed item
    into the off hand. An item already in a hand, or a two-handed weapon, goes to SwapIt as usual.
Everything else, and every press without the modifier, is SwapIt's own.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local SWAPIT_FILE = "SwapIt Main.lua"

local function fromSwapIt(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, SWAPIT_FILE, 1, true) ~= nil
end

local function refresh(chr)
    chr:getInventory():setDrawDirty(true)
    local data = getPlayerData(chr:getPlayerNum())
    if data ~= nil and data.playerInventory ~= nil then data.playerInventory:refreshBackpacks() end
end

local function wearLocation(item)
    if not instanceof(item, "Clothing") then return nil end
    local location = item:getBodyLocation()
    if location == nil or location == "" then return nil end
    return location
end

local function toggleWear(chr, item, location)
    if chr:getWornItem(location) == item then
        ISTimedActionQueue.add(ISUnequipAction:new(chr, item, 20))
    else
        ISTimedActionQueue.add(ISWearClothing:new(chr, item))
    end
    refresh(chr)
end

local function takesOffHand(chr, item)
    if chr:getPrimaryHandItem() == item or chr:getSecondaryHandItem() == item then return false end
    if instanceof(item, "HandWeapon") and item:isTwoHandWeapon() then return false end
    return true
end

local function install(ctx)
    if type(ISHotbar) ~= "table" or not fromSwapIt(ISHotbar.equipItem) then
        error("ISHotbar.equipItem is not SwapIt's")
    end
    local wear = M.isModActive("H_E_C_U")
    local offHand = M.isModActive("FancyHandworkB42_19")
    if offHand and type(isFHModKeyDown) ~= "function" then error("Fancy Handwork's modifier check is missing") end
    ctx.wrap(ISHotbar, "equipItem", function(callOriginal)
        return function(self, item)
            local chr = self.chr
            if item == nil or chr == nil then return callOriginal(self, item) end
            local location = wear and wearLocation(item) or nil
            if location ~= nil then
                toggleWear(chr, item, location)
                return
            end
            if offHand and isFHModKeyDown() and takesOffHand(chr, item) then
                ISInventoryPaneContextMenu.transferIfNeeded(chr, item)
                ISTimedActionQueue.add(ISEquipWeaponAction:new(chr, item, 20, false, false))
                refresh(chr)
                return
            end
            return callOriginal(self, item)
        end
    end)
end

M.addPart({
    name = "hotbar-equip",
    switch = "HotbarEquip",
    title = "SwapIt: off-hand and wear-from-hotbar keys",
    tip = "SwapIt replaces the hotbar's equip step, which turns off Fancy Handwork's modifier + hotbar key (take into the off hand) and H_E_C_U's hotbar key on helmets and masks (put on or take off). This brings both back on top of SwapIt. Only active with SwapIt and at least one of the two.",
    kind = "compat",
    all = { "SwapIt" },
    any = { "FancyHandworkB42_19", "H_E_C_U" },
    side = "client",
    phase = "boot",
    pins = { "swapit.equip", "swapit.fhid", "fh.modkey", "hecu.equip" },
    install = install,
})
