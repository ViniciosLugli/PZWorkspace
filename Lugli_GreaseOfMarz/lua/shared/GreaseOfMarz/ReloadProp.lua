--[[
Gunworks reload props stay out of the inventory.

To show a magazine, a round or a ramrod in the reloading hand, Gunworks creates a real item in the
player's inventory and hangs it on a private attachment slot ("GunworksReloadMag", Bip01_Prop2),
then deletes it when the animation lets go (ReloadAnim/Props.lua applyProp, ReloadAnim/Visuals.lua
attachReloadMagazine). For that moment the inventory lists a second, empty magazine: an M1911 with
one magazine shows two while it ejects or inserts. In multiplayer the server creates the item and
syncs it to the player, so it stays listed for a whole round trip, and a prop that is never
cleared is a real item left behind.

The engine draws an attached item from its model alone (ModelManager), never saves an attachment
that is not in the inventory (IsoPlayer.save writes worn and hand items only), and a corpse drops
any attachment outside its container. So this part makes every prop a bare item that only hangs on
the slot:
- single player and the server: the prop is attached and sent to nearby players as a whole item
  (sendAttachedItem), never added to an inventory;
- the reloading player in multiplayer: the server names the prop with its own command, and the
  client hangs a bare copy through AttachedItems.setItem. IsoGameCharacter.setAttachedItem would
  send the slot to the server by container and id, which the server resolves to nothing and relays
  as an empty slot to everyone else;
- Gunworks' client-side magazine prop (Visuals) is bare the same way.

It replaces applyPropEvent, clearOffHandProp, attachReloadMagazine and detachReloadMagazine on
Gunworks' module table, which is where Gunworks itself calls them. If any of them is missing or no
longer comes from Gunworks' own file, the part stands down at its check and stock Gunworks runs.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local COMMAND_MODULE = "LugliGreaseOfMarz"
local OWNER_COMMAND = "ownerProp"
local SOURCES = {
    applyPropEvent = "ReloadAnim/Props.lua",
    clearOffHandProp = "ReloadAnim/Props.lua",
    attachReloadMagazine = "ReloadAnim/Visuals.lua",
    detachReloadMagazine = "ReloadAnim/Visuals.lua",
}

local function fromFile(fn, file)
    if type(fn) ~= "function" then return false end
    local ok, name = pcall(getFilenameOfClosure, fn)
    if not ok or type(name) ~= "string" then return false end
    name = string.gsub(name, "\\", "/")
    return string.find(name, file, 1, true) ~= nil
end

local function onClient() return type(isClient) == "function" and isClient() end
local function onServer() return type(isServer) == "function" and isServer() end

-- Hang or drop an item on this machine only. A client's setAttachedItem would tell the server,
-- which cannot resolve an item outside any container and would empty the slot for everyone else.
local function hangLocal(character, location, item)
    if onClient() then
        character:getAttachedItems():setItem(location, item)
    else
        character:setAttachedItem(location, item)
    end
end

local function dropLocal(character, item)
    if onClient() then
        character:getAttachedItems():remove(item)
    else
        character:removeAttachedItem(item)
    end
end

local NEEDED = { "hasAttachLocation", "resolveReloadMagItem", "detachVisualPart", "attachVisualPart" }
local NAMES = { "RELOAD_MAGAZINE_ATTACH_LOCATION", "RELOAD_HAND_ATTACH_LOCATION", "PROP_SET_EVENT",
    "PROP_SET_HAND_EVENT", "PART_TO_HAND_EVENT", "PART_TO_GUN_EVENT" }

local function reloadAnim()
    local found, ReloadAnim = pcall(require, "WeaponSystems/Utils/ReloadAnim")
    if not found or type(ReloadAnim) ~= "table" then return nil end
    pcall(require, "WeaponSystems/ReloadAnim/Visuals")
    pcall(require, "WeaponSystems/ReloadAnim/Props")
    return ReloadAnim
end

local function check()
    local ReloadAnim = reloadAnim()
    if ReloadAnim == nil then return "Gunworks ReloadAnim module not reachable" end
    for name, file in pairs(SOURCES) do
        if not fromFile(ReloadAnim[name], file) then return "ReloadAnim." .. name .. " is not Gunworks' " .. file end
    end
    for i = 1, #NEEDED do
        if type(ReloadAnim[NEEDED[i]]) ~= "function" then return "ReloadAnim." .. NEEDED[i] .. " not found" end
    end
    for i = 1, #NAMES do
        if type(ReloadAnim[NAMES[i]]) ~= "string" then return "ReloadAnim." .. NAMES[i] .. " not found" end
    end
    return nil
end

local function install(ctx)
    local ReloadAnim = reloadAnim()
    local MAG_SLOT, HAND_SLOT = ReloadAnim.RELOAD_MAGAZINE_ATTACH_LOCATION, ReloadAnim.RELOAD_HAND_ATTACH_LOCATION
    local SET, SET_HAND = ReloadAnim.PROP_SET_EVENT, ReloadAnim.PROP_SET_HAND_EVENT
    local TO_HAND, TO_GUN = ReloadAnim.PART_TO_HAND_EVENT, ReloadAnim.PART_TO_GUN_EVENT

    local stats = { hung = 0, ownerSent = 0 }
    M.reloadProp = stats
    -- The prop each character holds per slot, so a clear still finds it if the slot reads empty.
    local held = {}
    local stockClear = ReloadAnim.clearOffHandProp

    local function removeProp(character, location)
        local attached = character:getAttachedItem(location)
        local byChar = held[character]
        local item = attached or (byChar and byChar[location])
        if byChar then byChar[location] = nil end
        if not item then return false end
        if attached then character:removeAttachedItem(attached) end
        sendAttachedItem(character, location, nil)
        return true
    end

    -- Single player and the server: the authoritative prop, the same steps as Gunworks' applyProp
    -- without the inventory.
    local function applyProp(character, location, itemType)
        if not ReloadAnim.hasAttachLocation(character, location) then return false end
        local changed = removeProp(character, location)
        local item = nil
        if itemType and itemType ~= "" then item = instanceItem(itemType) end
        if item then
            held[character] = held[character] or {}
            held[character][location] = item
            character:setAttachedItem(location, item)
            sendAttachedItem(character, location, item)
            stats.hung = stats.hung + 1
            changed = true
        end
        if changed then character:resetEquippedHandsModels() end
        if onServer() then
            sendServerCommand(character, COMMAND_MODULE, OWNER_COMMAND,
                { location = location, itemType = item and itemType or "" })
            stats.ownerSent = stats.ownerSent + 1
        end
        return changed
    end

    local function applyPropEvent(character, gun, event, value)
        if event == SET or event == SET_HAND then
            applyProp(character, event == SET_HAND and HAND_SLOT or MAG_SLOT, value)
            return
        end
        if not instanceof(gun, "HandWeapon") or not value or value == "" then return end
        local changed
        if event == TO_HAND then
            changed = ReloadAnim.detachVisualPart(character, gun, value)
            applyProp(character, MAG_SLOT, value)
        elseif event == TO_GUN then
            applyProp(character, MAG_SLOT, "")
            changed = ReloadAnim.attachVisualPart(character, gun, value)
        else
            return
        end
        if not changed then return end
        character:resetEquippedHandsModels()
        syncHandWeaponFields(character, gun)
    end

    local function clearOffHandProp(character)
        if not character then return end
        if onClient() then return stockClear(character) end
        applyProp(character, MAG_SLOT, "")
        applyProp(character, HAND_SLOT, "")
    end

    local function attachReloadMagazine(action, handler)
        if not action or not handler or not handler.magItem then return end
        if action.reloadHandlerMagazineItem then return end
        if not ReloadAnim.hasAttachLocation(action.character, MAG_SLOT) then return end
        local itemType = ReloadAnim.resolveReloadMagItem(action, handler)
        local item = itemType and instanceItem(itemType)
        if not item then return end
        action.reloadHandlerMagazineItem = item
        hangLocal(action.character, MAG_SLOT, item)
        action.character:resetEquippedHandsModels()
        stats.hung = stats.hung + 1
    end

    local function detachReloadMagazine(action)
        local item = action.reloadHandlerMagazineItem
        if not item then return end
        dropLocal(action.character, item)
        action.character:resetEquippedHandsModels()
        action.reloadHandlerMagazineItem = nil
    end

    local replacements = {
        applyPropEvent = applyPropEvent,
        clearOffHandProp = clearOffHandProp,
        attachReloadMagazine = attachReloadMagazine,
        detachReloadMagazine = detachReloadMagazine,
    }
    local stock = {}
    for name, fn in pairs(replacements) do stock[name] = ReloadAnim[name] end
    for name, fn in pairs(replacements) do
        ReloadAnim[name] = fn
        if ReloadAnim[name] ~= fn then
            for back, old in pairs(stock) do ReloadAnim[back] = old end
            M.reloadProp = nil
            return ctx.standDown("ReloadAnim." .. name .. " rejected the assignment")
        end
    end
    stats.module, stats.stock, stats.part = ReloadAnim, stock, replacements

    -- The reloading player in multiplayer: the server cannot hang an attachment on the local
    -- player, so it names the prop and the client hangs its own bare copy.
    if onClient() and Events and Events.OnServerCommand then
        Events.OnServerCommand.Add(function(module, command, args)
            if module ~= COMMAND_MODULE or command ~= OWNER_COMMAND or type(args) ~= "table" then return end
            local player = getSpecificPlayer(0)
            local location = args.location
            if not player or (location ~= MAG_SLOT and location ~= HAND_SLOT) then return end
            if not ReloadAnim.hasAttachLocation(player, location) then return end
            local items = player:getAttachedItems()
            local current = items:getItem(location)
            if current then items:remove(current) end
            if type(args.itemType) == "string" and args.itemType ~= "" then
                local item = instanceItem(args.itemType)
                if item then
                    items:setItem(location, item)
                    stats.hung = stats.hung + 1
                end
            end
            player:resetEquippedHandsModels()
        end)
    end
end

M.addPart("ReloadProp", { "SWMG" }, install, { check = check })
