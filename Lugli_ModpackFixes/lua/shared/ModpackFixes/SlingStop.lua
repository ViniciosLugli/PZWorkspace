--[[
Weapon Sling: a cancelled hotbar attach leaves no ghost weapon on the body.

What happens today. Weapon Sling replaces the hotbar attach action for every slot. Vanilla's
animation hangs the weapon model on the body halfway through the action and, if the action is
cancelled after that point, its stop() takes the model off again. Weapon Sling's stop() drops
that cleanup, so running or cancelling mid-attach leaves a weapon model on the back or belt that
is not on the hotbar.

What this part changes. When the attach action stops, the model is taken off under vanilla's own
rule: only if the item hangs on that slot of the body but never reached the hotbar slot.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local SLING_FILE = "ISAttachItemHotbar_AliceWeaponSling.lua"

local function fromSling(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, SLING_FILE, 1, true) ~= nil
end

local function install(ctx)
    if type(ISAttachItemHotbar) ~= "table" or not fromSling(ISAttachItemHotbar.stop) then
        error("ISAttachItemHotbar.stop is not Weapon Sling's")
    end
    ctx.wrap(ISAttachItemHotbar, "stop", function(callOriginal)
        return function(self, ...)
            local hotbar, item = self.hotbar, self.item
            if hotbar ~= nil and item ~= nil and hotbar.attachedItems[self.slotIndex] ~= item
                and self.character:getAttachedItem(self.slot) == item then
                self.character:removeAttachedItem(item)
            end
            return callOriginal(self, ...)
        end
    end)
end

M.addPart({
    name = "sling-stop",
    switch = "SlingStop",
    title = "Weapon Sling: no ghost weapon after a cancelled attach",
    tip = "Cancelling a hotbar attach halfway (for example by running) can leave the weapon model hanging on the body without it being on the hotbar. This takes the model off again, as vanilla does. Only active with Weapon Sling.",
    kind = "fix",
    all = { "alicesWeaponSling" },
    side = "client",
    phase = "boot",
    pins = { "sling.stop", "sling.time" },
    install = install,
})
