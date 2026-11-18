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
- Runtime mounts. Guns of Tien Post-93 puts its guns on Guns of Marz parts the same way: the SCAR-L
  takes the AR muzzle mount, suppressors, compensator, flash hider and muzzle brake, and the SCARs,
  UMPs, Five-seveN and UCP their optics, lights, lasers, grips and bipods. Those slots showed only
  while the player happened to carry such a part, so a SCAR-L with a suppressor in the bag offered
  the muzzle slot, refused it for a missing mount, and never showed where the mount goes. This part
  adds the slot of every part whose live MountOn names the gun, through Attachments UI's own
  compatibility rule; carrying and installing the part already read the live list.
- Upside-down guns. The workbench takes "up" from the sight attachment's rotation, and treats only
  the vanilla handgun meshes as built sights-down. Every Guns of Marz and Guns of Tien handgun,
  revolver and machine pistol is built that way too (muzzle and sight below the origin, rotation
  0), so they render upside down. For models in those modules only, this part reads up from the
  geometry: the sight against the bore, else which side of the origin the bore sits. A patch saved
  before this fix, with a vertical flip that only undid the wrong answer, would now turn the gun
  back over, so a stored flip on a corrected model is dropped from the working copy as it loads:
  the gun looks exactly as that patch made it. Without a measured frame (below) those guns get
  vanilla's handgun framing (zoom 16), which the workbench gives only to its own sights-down meshes.
- Framing. The workbench centres a gun on the span of its attachment points, which starts at the
  model origin and never reaches a stock or grip past the last point: rifles sat up to 6% of the
  view right of centre, the P90 and Groza 10%, the MP7 10% left, and its zoom made a Glock a fifth
  of the view wide and an MP7 two thirds. Each of these models' real box was measured in the
  workbench itself (tools/aui-frames.py, AttachmentsUIFrames.lua): the gun is centred on that box
  and zoomed to half the view's width, or less when it would be too tall. A model the table does
  not know, or whose mesh or muzzle changed since, and a patch that moved the gun, keep the
  workbench's own framing.
- Unanchored slots. With no part bound to a slot, the workbench draws its card's line to the
  model origin unless the slot id names an attachment point. Guns of Marz names its points
  rail_left, light_left, laser_right, ...; for those models a slot now finds its own point,
  else the rail its part mounts on.
- Bayonets. Gunworks bayonets refuse every generic install (their CanAttach always returns false)
  and attach only through Gunworks' own action, so the workbench shows a slot that can only say
  "Blocked". This part hides that slot. The right-click "Attach Bayonet" entry still works.
- Magazine slots. Gunworks gives speed loaders, stripper clips and magazines a weapon-part slot
  (Clip) but refuses every install (CanAttach = its IsMagazine rule, always false): they go in by
  reloading. A slot whose every part is one of those can only say "Blocked", so it is hidden too.
- Slots that need a missing mount. Guns of Marz lists the CAR-15 for its foregrips, but neither the
  lower rail they need nor the CAR-15's rail kit lists the CAR-15, so the slot could only say
  "needs a mount". A slot is hidden when no part in it can be fitted with mounts this gun can take.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local ADAPTER_ID = "LugliGreaseOfMarz"
local OWN_MODULES = { MarzGuns = true, GunsOfTien = true, GunsOfTienPost93 = true }
-- Offsets are in metres; the smallest sight-to-bore gap among these models is 0.013.
local BORE_EPSILON = 0.001
-- Attachments UI's zoom for vanilla's sights-down handgun meshes.
local HANDGUN_ZOOM = 16
-- A measured gun fills this share of the view's width, unless it would take more than this share
-- of its height. UI3DScene draws exp(0.2 * zoom) * 160 / 1.82 pixels per unit at a 1366 px wide
-- view (zoomMult, calcMatrices), and its zoom is a whole number, so a gun lands within 11% of it.
local FRAME_WIDTH = 0.5
local FRAME_HEIGHT = 0.4
local ZOOM_UNIT = 160 / 1.82
local ZOOM_WIDTH = 1366
-- Attachments UI lifts the gun by a fixed scene distance, sized for its rifle zoom.
local LIFT_ZOOM = 13
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

local stats = { corrected = {}, unanchored = {}, framed = {}, unframed = {} }
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

-- Measured frames, keyed by model script; generated by tools/aui-frames.py.
local frames
local function frameTable()
    if frames == nil then
        local ok, loaded = pcall(require, "GreaseOfMarz/AttachmentsUIFrames")
        frames = ok and type(loaded) == "table" and loaded or {}
    end
    return frames
end

local function offsetYZ(modelScript, id)
    local attachment = modelScript:getAttachmentById(id)
    if attachment == nil then return nil end
    local offset = attachment:getOffset()
    return offset:y(), offset:z()
end

-- A model's key in the frame table: its full name, or its mesh when the script has no name (Guns
-- of Tien's MP5SD view is one, and getFullType reads "MarzGuns.null" for every such model).
function M.auiFrameKey(modelScript)
    local name = modelScript:getName()
    if name == nil or name == "" then return "mesh:" .. tostring(modelScript:getMeshName()) end
    return modelScript:getFullType()
end

-- The measured box of one of these models, nil when it has none or the model changed since.
function M.auiFrame(modelScript)
    if not isOwn(modelScript) then return nil end
    local key = M.auiFrameKey(modelScript)
    local frame = frameTable()[key]
    local fits = frame ~= nil and modelScript:getMeshName() == frame.mesh
    if fits then
        local y, z = offsetYZ(modelScript, "muzzle")
        if frame.muzzle == nil then
            fits = y == nil
        else
            fits = y ~= nil and math.abs(y - frame.muzzle[1]) < 0.0005 and math.abs(z - frame.muzzle[2]) < 0.0005
        end
    end
    if not fits then
        stats.unframed[key] = true
        return nil
    end
    stats.framed[key] = true
    return frame
end

-- The whole zoom that brings a box closest to FRAME_WIDTH of a view, capped by FRAME_HEIGHT.
function M.frameZoom(frame, width, height)
    local length, tall = frame.y1 - frame.y0, frame.z1 - frame.z0
    local byWidth = math.floor(5 * math.log(FRAME_WIDTH * ZOOM_WIDTH / (length * ZOOM_UNIT)) + 0.5)
    local byHeight = math.floor(5 * math.log(FRAME_HEIGHT * ZOOM_WIDTH * height / (tall * ZOOM_UNIT * width)))
    return math.max(1, math.min(20, byWidth, byHeight))
end

-- A patch that moved the gun was placed against Attachments UI's own frame: keep that frame.
local function patchMoved(view)
    local patch = view.activePatch and view:activePatch()
    return patch ~= nil and ((patch.offsetX or 0) ~= 0 or (patch.offsetY or 0) ~= 0)
end

-- The patch editor also keeps Attachments UI's frame, so the offsets it saves are against the
-- frame they are loaded on.
local function viewFrame(view, modelScript)
    if view.rawFrame or view.editing or modelScript == nil or patchMoved(view) then return nil end
    return M.auiFrame(modelScript)
end

local function installOrientation(BA)
    local previous = BA.modelOrientation
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
            if self.rawFrame or not self.scene or zoom ~= self.scene.defaultZoom then return pitch, yaw, zoom end
            local modelScript = viewModel(BA, self)
            local frame = viewFrame(self, modelScript)
            local width, height = self.scene:getWidth(), self.scene:getHeight()
            if frame and width > 0 and height > 0 then
                zoom = M.frameZoom(frame, width, height)
            elseif zoom ~= HANDGUN_ZOOM then
                local fixed = ownUp(modelScript)
                if fixed ~= nil and fixed < 0 then zoom = HANDGUN_ZOOM end
            end
            return pitch, yaw, zoom
        end
    end)
    -- Attachments UI centres the gun on its attachment points; a stock or grip past the last point
    -- pushed the gun off centre. A measured model is centred on its real box instead, which also
    -- tells the slot cards where the gun ends.
    wrapMethod(View, "cacheAnchors", function(previous)
        return function(self, modelScript, ...)
            local result = previous(self, modelScript, ...)
            local frame = viewFrame(self, modelScript)
            if frame == nil or self.scene == nil then return result end
            local forward, up = self.forwardSign or 1, self.upSign or 1
            local midY, midZ = (frame.y0 + frame.y1) / 2, (frame.z0 + frame.z1) / 2
            -- Scaled by the frame's own zoom, never the wheel's, so a refresh after zooming keeps the gun still.
            local width, height = self.scene:getWidth(), self.scene:getHeight()
            local zoom = (width > 0 and height > 0) and M.frameZoom(frame, width, height) or LIFT_ZOOM
            local lift = (self.verticalLift or 0) * math.exp(0.2 * (LIFT_ZOOM - zoom))
            self.baExtent = { minY = frame.y0, maxY = frame.y1, minZ = frame.z0, maxZ = frame.z1 }
            self.baseCenterX, self.baseCenterY = forward * midY, -up * midZ + lift
            local muzzleY = offsetYZ(modelScript, "muzzle")
            if muzzleY ~= nil then
                local diff = muzzleY - midY
                self.muzzleRight = math.abs(diff) > 0.01 and (-forward * diff > 0) or false
            end
            self.centerX, self.centerY = self.baseCenterX, self.baseCenterY
            self.scene.javaObject:fromLua1("getObjectTranslation", "BAWeapon"):set(self.centerX, self.centerY, 0.0)
            return result
        end
    end)
    -- Opening or closing the patch editor switches between the two frames, which only a model
    -- refresh would otherwise apply.
    wrapMethod(View, "setEditing", function(previous)
        return function(self, on, ...)
            local result = previous(self, on, ...)
            local modelScript = viewModel(BA, self)
            if modelScript ~= nil and M.auiFrame(modelScript) ~= nil then
                pcall(function()
                    self:cacheAnchors(modelScript)
                    self:applyOffsets()
                end)
            end
            return result
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

local function railSlots(BA, Universal, slots, weapon)
    local generics = Universal.GetGenericItemTypes(weapon)
    if generics == nil then return end
    for i = 1, #generics do
        local outcomes = Universal.GetOutcomes(weapon, generics[i]) or {}
        for j = 1, #outcomes do
            local definition = BA.definition(outcomes[j])
            if definition and definition.slot then slots[#slots + 1] = definition.slot end
        end
    end
end

-- Mount name -> the parts whose live MountOn has it and whose script text does not. Built on first
-- use in a world, so after every DoParam pass (Post-93 repeats its own at OnInitGlobalModData).
local function runtimeMountIndex(BA)
    local index = {}
    local items = getScriptManager():getAllItems()
    for i = 0, items:size() - 1 do
        local script = items:get(i)
        if script:isItemType(ItemType.WEAPON_PART) and not script:getObsolete() then
            local fullType = script:getFullName()
            local part = instanceItem(fullType)
            local live = part and part:getMountOn()
            if live and live:size() > 0 then
                local definition = BA.definition(fullType)
                local declared = {}
                for _, mount in ipairs(definition and definition.mounts or {}) do declared[mount] = true end
                local entry = { fullType = fullType, definition = { slot = part:getPartType(), mounts = {},
                    properties = definition and definition.properties or {} } }
                local added = {}
                for j = 0, live:size() - 1 do
                    local mount = tostring(live:get(j))
                    entry.definition.mounts[#entry.definition.mounts + 1] = mount
                    if not declared[mount] then added[#added + 1] = mount end
                end
                for _, mount in ipairs(added) do
                    index[mount] = index[mount] or {}
                    table.insert(index[mount], entry)
                end
            end
        end
    end
    return index
end

local function extraSlots(BA, Universal)
    local index
    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(function() index = nil end)
    end
    return function(weapon)
        local slots = {}
        railSlots(BA, Universal, slots, weapon)
        if index == nil then
            -- A failed scan keeps the rail slots and stock behaviour for the rest.
            local ok, built = pcall(runtimeMountIndex, BA)
            index = ok and built or {}
        end
        local keys = { weapon:getFullType(), weapon:getType() }
        for k = 1, #keys do
            local entries = index[keys[k]] or {}
            for e = 1, #entries do
                local entry = entries[e]
                if BA.definitionCompatible(entry.definition, weapon, entry.fullType) then slots[#slots + 1] = entry.definition.slot end
            end
        end
        return slots
    end
end

-- A weapon part whose script names Gunworks' magazine rule as its CanAttach: speed loaders,
-- stripper clips and magazines, loaded by reloading and never fitted. The bodies merge per field,
-- so the last CanAttach wins; the rule must be a function that answers false.
local function gunworksMagazine(script)
    local bodies = script:getLoadedScriptBodies()
    local callback
    for i = 0, bodies:size() - 1 do
        for value in string.gmatch(tostring(bodies:get(i)), "CanAttach%s*=%s*([%w_%.]+)") do callback = value end
    end
    if callback == nil or not string.find(callback, "_AttachAndDetach%.IsMagazine$") then return false end
    local owner, name = string.match(callback, "^([%w_]+)%.([%w_]+)$")
    local rule = owner and type(_G[owner]) == "table" and _G[owner][name]
    if type(rule) ~= "function" then return false end
    local ok, answer = pcall(rule)
    return ok and answer == false
end

-- Every weapon part Attachments UI can list, with its slot, the mounts it lists it under and
-- whether it is a Gunworks magazine.
local function partIndex(BA)
    local parts = {}
    local items = getScriptManager():getAllItems()
    for i = 0, items:size() - 1 do
        local script = items:get(i)
        if script:isItemType(ItemType.WEAPON_PART) and not script:getObsolete() then
            local fullType = script:getFullName()
            local definition = BA.definition(fullType)
            if definition and definition.slot then
                parts[#parts + 1] = { fullType = fullType, definition = definition, magazine = gunworksMagazine(script) }
            end
        end
    end
    return parts
end

local function bayonetHidden(BA, Bayonet, Universal, Required)
    local slotOf = {}
    -- [weapon full type][slot] = hidden, from the part index; rebuilt per world.
    local unfillableSlot, parts = {}, nil
    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(function() unfillableSlot, parts = {}, nil end)
    end
    -- A part can be on this gun when its MountOn names it, the gun's rail kit offers it, or the gun
    -- already carries it (an integrated rail).
    local function mountable(weapon, fullType)
        if Universal.IsRegisteredOutcome(weapon, fullType) then return true end
        if Required.IsPartInstalledOnWeapon(weapon, fullType) then return true end
        local definition = BA.definition(fullType)
        return definition ~= nil and BA.definitionCompatible(definition, weapon, fullType) == true
    end
    -- Every mount a part needs can be fitted first, down the mount's own needs. A chain too deep
    -- to follow counts as reachable, so a slot is only ever hidden on proof.
    local function reachable(weapon, fullType, depth)
        if depth > 4 then return true end
        for parent in pairs(Required.Dependencies[fullType] or {}) do
            if not (mountable(weapon, parent) and reachable(weapon, parent, depth + 1)) then return false end
        end
        local needed = false
        for parent in pairs(Required.AnyDependencies[fullType] or {}) do
            if mountable(weapon, parent) and reachable(weapon, parent, depth + 1) then return true end
            needed = true
        end
        return not needed
    end
    -- A slot none of whose parts can ever be fitted can only say "Blocked" or "needs a mount".
    local function unfillable(weapon, slot)
        local fullType = weapon:getFullType()
        local known = unfillableSlot[fullType]
        if known == nil then
            known = {}
            unfillableSlot[fullType] = known
        end
        if known[slot] == nil then
            if parts == nil then
                -- A failed scan hides nothing for the rest of the world.
                local ok, built = pcall(partIndex, BA)
                parts = ok and built or {}
            end
            local any, all = false, true
            for i = 1, #parts do
                local entry = parts[i]
                if entry.definition.slot == slot and BA.definitionCompatible(entry.definition, weapon, entry.fullType) then
                    any = true
                    if not entry.magazine and reachable(weapon, entry.fullType, 1) then all = false break end
                end
            end
            known[slot] = any and all
            if known[slot] then stats.unfillableSlots = (stats.unfillableSlots or 0) + 1 end
        end
        return known[slot]
    end
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
        if unfillable(weapon, slot) then return true end
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
    if found and type(module) == "table" then return module end
    return nil
end

local VIEW_METHODS = { "loadPatch", "effectiveView", "cacheAnchors", "setEditing", "referenceAnchor" }

local function check()
    local BA = AttachmentsUI
    if type(BA) ~= "table" or type(BA.registerExtension) ~= "function" or type(BA.registerAdapter) ~= "function"
        or type(BA.definition) ~= "function" or type(BA.resolveModelScript) ~= "function"
        or type(BA.definitionCompatible) ~= "function"
        or type(BAWeaponView) ~= "table" then
        return "AttachmentsUI API not found"
    end
    if type(BA.modelOrientation) ~= "function" then return "AttachmentsUI.modelOrientation not found" end
    for i = 1, #VIEW_METHODS do
        if type(BAWeaponView[VIEW_METHODS[i]]) ~= "function" then return "BAWeaponView:" .. VIEW_METHODS[i] .. " not found" end
    end
    local modules = {}
    for _, name in ipairs({ "UniversalAttachment", "Bayonet", "RequiredAttachment" }) do
        modules[name] = gunworks(name)
        if modules[name] == nil then return "Gunworks " .. name .. " module not reachable" end
    end
    local Universal, Required, Bayonet = modules.UniversalAttachment, modules.RequiredAttachment, modules.Bayonet
    if type(Universal.GetGenericItemTypes) ~= "function" or type(Universal.GetOutcomes) ~= "function"
        or type(Universal.IsRegisteredOutcome) ~= "function" then
        return "Gunworks UniversalAttachment API changed"
    end
    if type(Required.Dependencies) ~= "table" or type(Required.AnyDependencies) ~= "table"
        or type(Required.IsPartInstalledOnWeapon) ~= "function" then
        return "Gunworks RequiredAttachment API changed"
    end
    if type(Bayonet.BayonetMountableWeapons) ~= "table" or type(Bayonet.GetSpearTypeFromAttachment) ~= "function" then
        return "Gunworks Bayonet API changed"
    end
    return nil
end

local function install()
    local BA = AttachmentsUI
    local Universal = gunworks("UniversalAttachment")
    local Bayonet = gunworks("Bayonet")
    local Required = gunworks("RequiredAttachment")
    installOrientation(BA)
    installView(BA, BAWeaponView)
    BA.registerExtension(ADAPTER_ID, { slots = extraSlots(BA, Universal) })
    BA.registerAdapter(ADAPTER_ID, { hiddenSlot = bayonetHidden(BA, Bayonet, Universal, Required) })
end

M.addPart("AttachmentsUI", { "SWMG", "GunsOfMarz", "AttachmentsUI" }, install, { check = check })
