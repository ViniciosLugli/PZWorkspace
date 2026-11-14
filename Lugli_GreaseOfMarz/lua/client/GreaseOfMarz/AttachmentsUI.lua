--[[
Attachments UI beside Gunworks and Guns of Marz: the workbench works with no hand-made patch.

Attachments UI (mod id AttachmentsUI) replaces the weapon upgrade menus with a 3D workbench. It
ships a Gunworks adapter, but three things go wrong on the Guns of Marz stack:

- Rail slots. The workbench lists a slot only when a carried part mounts on the gun, or when an
  item script's MountOn text names it. Picatinny rails are Gunworks "universal" parts: the carried
  item mounts on MarzGuns.FakeItem and installs as an outcome part (Picatinny_Rail_Up, ...). Guns
  of Tien adds its guns to those outcomes with DoParam, which the script text never shows, so its
  AUG, P90, TMP, M249, Uzis, Groza, MDR and Vector get no rail slot and the rail cannot be fitted.
  This part adds every outcome slot Gunworks registers for the gun. Attachments UI's own outcome
  path already validates and installs them.
- Upside-down guns. The workbench takes "up" from the sight attachment's rotation, and treats only
  the vanilla handgun meshes as built sights-down. Every Guns of Marz and Guns of Tien handgun,
  revolver and machine pistol is built that way too (muzzle and sight below the origin, rotation
  0), so they render upside down. For models in those modules only, this part reads up from the
  geometry: the sight against the bore, else which side of the origin the bore sits. A patch saved
  before this fix, with a vertical flip that only undid the wrong answer, would now turn the gun
  back over, so a stored flip on a corrected model is dropped from the working copy as it loads:
  the gun looks exactly as that patch made it. Those guns also get vanilla's handgun framing
  (zoom 16), which the workbench gives only to the meshes it knows are built sights-down.
- Unanchored slots. With no part bound to a slot, the workbench draws its card's line to the
  model origin unless the slot id names an attachment point. Guns of Marz names its points
  rail_left, light_left, laser_right, ...; for those models a slot now finds its own point,
  else the rail its part mounts on.
- Bayonets. Gunworks bayonets refuse every generic install (their CanAttach always returns false)
  and attach only through Gunworks' own action, so the workbench shows a slot that can only say
  "Blocked". This part hides that slot. The right-click "Attach Bayonet" entry still works.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local ADAPTER_ID = "LugliGreaseOfMarz"
local OWN_MODULES = { MarzGuns = true, GunsOfTien = true, GunsOfTienPost93 = true }
-- Offsets are in metres; the smallest sight-to-bore gap among these models is 0.013.
local BORE_EPSILON = 0.001
-- Attachments UI's zoom for vanilla's sights-down handgun meshes.
local HANDGUN_ZOOM = 16
-- Model attachment points for each slot, in the names Guns of Marz and Guns of Tien use; the
-- rail a part mounts on stands in when its own point is missing.
local SLOT_POINTS = {
    RailUp = { "rail_up" },
    RailDown = { "rail_down" },
    RailLeft = { "rail_left" },
    RailRight = { "rail_right" },
    LightRifle = { "light_left", "rail_left" },
    LaserRifle = { "laser_right", "rail_right" },
    Foregrip = { "foregrip", "rail_down" },
    ForegripIntegrated = { "foregrip_deployed", "foregrip" },
    Bipod = { "bipod", "rail_down" },
    BipodIntegrated = { "integrated_bipod", "bipod" },
    Underbarrel = { "underbarrel", "rail_down" },
    BayonetKnife = { "bayonet" },
    StockIntegrated = { "stock", "integrated_stock", "stock_folded" },
    CanonMount = { "canon", "muzzle" },
    Barrel = { "barrel", "canon" },
    Sling = { "sling" },
}

local stats = { corrected = {}, unanchored = {} }
M.attachmentsUI = stats

local function modelModule(modelScript)
    local ok, name = pcall(function()
        local module = modelScript:getModule()
        return module and module:getName()
    end)
    if ok and type(name) == "string" and name ~= "" then return name end
    ok, name = pcall(function() return modelScript:getName() end)
    if ok and type(name) == "string" then return name:match("^([^.]+)%.") end
    return nil
end

local function offsetZ(modelScript, id)
    local attachment = modelScript:getAttachmentById(id)
    return attachment and attachment:getOffset():z() or nil
end

-- 1 sights up, -1 built sights down, nil when the model says nothing.
function M.modelUp(modelScript)
    local muzzle = offsetZ(modelScript, "muzzle")
    if muzzle == nil then return nil end
    local sight = offsetZ(modelScript, "reddot") or offsetZ(modelScript, "scope")
    if sight ~= nil and math.abs(sight - muzzle) > BORE_EPSILON then
        return sight < muzzle and -1 or 1
    end
    if math.abs(muzzle) > BORE_EPSILON then
        return muzzle < 0 and -1 or 1
    end
    return nil
end

local function isOwn(modelScript)
    return modelScript ~= nil and OWN_MODULES[modelModule(modelScript) or ""] == true
end

-- Our up for a model of these mods, and Attachments UI's own; nil when we leave it alone.
local stockOrientation
local function ownUp(modelScript)
    if not isOwn(modelScript) then return nil end
    local ok, fixed = pcall(M.modelUp, modelScript)
    if not ok or fixed == nil then return nil end
    return fixed, stockOrientation(modelScript)
end

local function installOrientation(BA)
    local previous = BA.modelOrientation
    if type(previous) ~= "function" then error("AttachmentsUI.modelOrientation not found") end
    if M.auiOrientation ~= nil and previous == M.auiOrientation then return end
    stockOrientation = previous
    local function orientation(modelScript)
        local up, forward, sure, strong, solid = previous(modelScript)
        local fixed = ownUp(modelScript)
        if fixed == nil then return up, forward, sure, strong, solid end
        if fixed ~= up then
            local name = BA.modelScriptName and BA.modelScriptName(modelScript) or tostring(modelScript)
            stats.corrected[name] = true
        end
        return fixed, forward, true, fixed < 0, true
    end
    BA.modelOrientation = orientation
    if BA.modelOrientation ~= orientation then error("AttachmentsUI.modelOrientation could not be replaced") end
    M.auiOrientation = orientation
end

local function viewModel(BA, view)
    local weapon = view.workbench and view.workbench.weapon
    return weapon and BA.resolveModelScript(weapon) or nil
end

local function wrapMethod(View, name, make)
    local previous = View[name]
    if type(previous) ~= "function" then error("BAWeaponView:" .. name .. " not found") end
    local marker = "lugliGreaseOfMarz_" .. name
    if View[marker] ~= nil and previous == View[marker] then return end
    local wrapped = make(previous)
    View[name] = wrapped
    View[marker] = wrapped
end

local function installView(BA, View)
    -- A stored flip on a model we turn upright was made against the old answer: drop it from the
    -- working copy so the gun keeps the orientation that patch gave it.
    wrapMethod(View, "loadPatch", function(previous)
        return function(self, ...)
            local before = self.patch
            local result = previous(self, ...)
            local patch = self.patch
            if patch ~= nil and patch ~= before and patch.flipV and patch.frame ~= "raw" then
                local fixed, stock = ownUp(viewModel(BA, self))
                if fixed ~= nil and fixed ~= stock then
                    patch.flipV = false
                    self.signature = nil
                    self:layout()
                end
            end
            return result
        end
    end)
    wrapMethod(View, "effectiveView", function(previous)
        return function(self, ...)
            local pitch, yaw, zoom = previous(self, ...)
            if not self.rawFrame and self.scene and zoom == self.scene.defaultZoom and zoom ~= HANDGUN_ZOOM then
                local fixed = ownUp(viewModel(BA, self))
                if fixed ~= nil and fixed < 0 then zoom = HANDGUN_ZOOM end
            end
            return pitch, yaw, zoom
        end
    end)
    wrapMethod(View, "referenceAnchor", function(previous)
        return function(self, modelScript, slot, ...)
            if isOwn(modelScript) then
                for _, id in ipairs(SLOT_POINTS[slot] or {}) do
                    local attachment = modelScript:getAttachmentById(id)
                    if attachment then
                        local offset = attachment:getOffset()
                        return { x = offset:x(), y = offset:y(), z = offset:z() }
                    end
                end
                local name = BA.modelScriptName and BA.modelScriptName(modelScript) or "?"
                stats.unanchored[name .. "/" .. tostring(slot)] = true
            end
            return previous(self, modelScript, slot, ...)
        end
    end)
end

local function railSlots(BA, Universal)
    return function(weapon)
        local slots = {}
        local generics = Universal.GetGenericItemTypes(weapon)
        if generics == nil then return slots end
        for i = 1, #generics do
            local outcomes = Universal.GetOutcomes(weapon, generics[i]) or {}
            for j = 1, #outcomes do
                local definition = BA.definition(outcomes[j])
                if definition and definition.slot then slots[#slots + 1] = definition.slot end
            end
        end
        return slots
    end
end

local function bayonetHidden(BA, Bayonet)
    local slotOf = {}
    local function partSlot(fullType)
        local slot = slotOf[fullType]
        if slot == nil then
            local definition = BA.definition(fullType)
            slot = definition and definition.slot or false
            slotOf[fullType] = slot
        end
        return slot
    end
    local function hidden(weapon, slot)
        local bayonets = Bayonet.BayonetMountableWeapons[weapon:getFullType()]
        if bayonets then
            for bayonetType in pairs(bayonets) do
                if partSlot(bayonetType) == slot then return true end
            end
        end
        local part = weapon:getWeaponPart(slot)
        if part and Bayonet.GetSpearTypeFromAttachment(part:getFullType()) then return true end
        return nil
    end
    -- An adapter that raises stops Attachments UI asking the next one, so never raise.
    return function(weapon, slot)
        local ok, hide = pcall(hidden, weapon, slot)
        if ok and hide then return true end
        return nil
    end
end

local function gunworks(name)
    local found, module = pcall(require, "WeaponSystems/Utils/" .. name)
    if not found or type(module) ~= "table" then error("Gunworks " .. name .. " module not reachable") end
    return module
end

local function install()
    local BA = AttachmentsUI
    if type(BA) ~= "table" or type(BA.registerExtension) ~= "function" or type(BA.registerAdapter) ~= "function"
        or type(BA.definition) ~= "function" or type(BA.resolveModelScript) ~= "function"
        or type(BAWeaponView) ~= "table" then
        error("AttachmentsUI API not found")
    end
    local Universal = gunworks("UniversalAttachment")
    local Bayonet = gunworks("Bayonet")
    if type(Universal.GetGenericItemTypes) ~= "function" or type(Universal.GetOutcomes) ~= "function" then
        error("Gunworks UniversalAttachment API changed")
    end
    if type(Bayonet.BayonetMountableWeapons) ~= "table" or type(Bayonet.GetSpearTypeFromAttachment) ~= "function" then
        error("Gunworks Bayonet API changed")
    end
    installOrientation(BA)
    installView(BA, BAWeaponView)
    BA.registerExtension(ADAPTER_ID, { slots = railSlots(BA, Universal) })
    BA.registerAdapter(ADAPTER_ID, { hiddenSlot = bayonetHidden(BA, Bayonet) })
end

M.addPart("AttachmentsUI", { "SWMG", "GunsOfMarz", "AttachmentsUI" }, install)
