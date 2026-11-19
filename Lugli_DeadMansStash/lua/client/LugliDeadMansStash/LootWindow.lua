--[[
    LootWindow
    A sealed gate in the loot window: its button is neutered exactly the way vanilla neuters a
    locked thumpable's (ISInventoryPage.lua, the IsoThumpable isLockedToCharacter branch), with the
    lock icon and the gate's own name, and nothing can be put into it.

    THE CONTAINER IS EMPTY ANYWAY (docs/31 section 1), so the lock is the player's cue, not the
    security. The transfer refusal is what keeps a survivor from filling a sealed crate with
    things the payout would then sit on top of.

    NO RESTORE PATH IS NEEDED. addContainerButton resets onclick, the mouse-over functions and
    textureOverride on every refresh, pooled buttons included, so an opened gate gets a vanilla
    button on the next refresh by itself.
]]

require "TimedActions/ISInventoryTransferAction"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Actions"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "LootWindow"

    local function sealedParentOf(container)
        if container == nil then return nil end
        local ok, parent = pcall(container.getParent, container)
        if not ok or parent == nil then return nil end
        return M.sealedGateOf(parent)
    end
    M.sealedParentOf = sealedParentOf

    local lockTexture = nil
    local function lock()
        if lockTexture == nil and getTexture ~= nil then lockTexture = getTexture("media/ui/lock.png") end
        return lockTexture
    end

    --- Neuter every sealed gate's button on this page. Returns how many it neutered.
    function M.lockSealedButtons(page)
        local buttons = page ~= nil and page.backpacks or nil
        if type(buttons) ~= "table" then return 0 end
        local n = 0
        for _, button in ipairs(buttons) do
            local md = sealedParentOf(button.inventory)
            if md ~= nil then
                button.onclick = nil
                button.onmousedown = nil
                button:setOnMouseOverFunction(nil)
                button:setOnMouseOutFunction(nil)
                button.textureOverride = lock()
                -- The container's own title, the one it keeps once opened.
                local title = M.T("IGUI_ContainerTitle_" .. tostring(M.GATE_BOXES[md.kind].container), "Stash Box")
                button.name = title
                button.tooltip = title .. " <LINE> " .. M.T("Tooltip_LugliDMS_RightClick", "Right-click the box to open it.")
                n = n + 1
            end
        end
        return n
    end

    M.addHandler(PART, "OnRefreshInventoryWindowContainers", function(page, state)
        if state ~= "buttonsAdded" then return end
        M.lockSealedButtons(page)
    end)

    -- THE TRANSFER REFUSAL. Only the gate check is guarded: whatever it answers, an ordinary
    -- transfer always reaches vanilla's own isValid.
    local function intoSealed(action)
        return sealedParentOf(action.destContainer) ~= nil
    end

    local function wrapTransfer()
        if ISInventoryTransferAction == nil or type(ISInventoryTransferAction.isValid) ~= "function" then
            M.defect(PART, "ISInventoryTransferAction.isValid is missing: a sealed gate takes items", true)
            return false
        end
        local original = ISInventoryTransferAction.isValid
        local failed = false
        ISInventoryTransferAction.isValid = function(self)
            if not failed then
                local ok, sealed = pcall(intoSealed, self)
                if not ok then
                    failed = true
                    M.defect(PART, "transfer check removed after: " .. tostring(sealed))
                elseif sealed then
                    if not self.lugliDMSSaid then
                        self.lugliDMSSaid = true
                        pcall(function()
                            HaloTextHelper.addBadText(self.character, M.T("IGUI_LugliDMS_SealedShut", "It is sealed shut."))
                        end)
                    end
                    return false
                end
            end
            return original(self)
        end
        return true
    end

    -- An opened box's button, of every kind: vanilla's wooden crate icon, which the small box
    -- shares, unless another mod already gave that container type one.
    if ContainerButtonIcons ~= nil and M.GATE_BOXES ~= nil then
        for _, box in pairs(M.GATE_BOXES) do
            ContainerButtonIcons[box.container] = ContainerButtonIcons[box.container] or ContainerButtonIcons.crate
        end
    end

    -- THE SLEDGE ON A SAFE. Refused here so the cursor never offers it; the authority refuses it
    -- too (World.lua). The sprite says it is a safe, sealed or opened: modData is client-writable.
    -- ISDestroyCursor is a server file, so it exists only from world load, and every world load
    -- defines it afresh: the wrap goes on at OnGameStart, once per definition.
    local function isSafe(object)
        local kind = M.kindOfSprite(M.liveSpriteName(object))
        return kind ~= nil and M.GATE_BOXES[kind].safe == true
    end

    local wrappedCanDestroy = nil
    function M.wrapDestroyCursor()
        if ISDestroyCursor == nil or type(ISDestroyCursor.canDestroy) ~= "function" then
            M.defect(PART, "ISDestroyCursor.canDestroy is missing: the sledge is offered on a safe", true)
            return false
        end
        if ISDestroyCursor.canDestroy == wrappedCanDestroy then return true end
        local original = ISDestroyCursor.canDestroy
        local failed = false
        wrappedCanDestroy = function(self, object)
            if not failed then
                local ok, safe = pcall(isSafe, object)
                if not ok then
                    failed = true
                    M.defect(PART, "sledge check removed after: " .. tostring(safe))
                elseif safe then
                    return false
                end
            end
            return original(self, object)
        end
        ISDestroyCursor.canDestroy = wrappedCanDestroy
        return true
    end
    M.addHandler(PART, "OnGameStart", M.wrapDestroyCursor)

    if wrapTransfer() then M.status(PART, true) end
end
