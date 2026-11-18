--[[
CleanUI: the vanilla tutorial can point at a container again.

What happens today. The tutorial calls setBlinkingContainer on the inventory and loot windows to
make a container button blink. CleanUI's own inventory window (its default mode) has no such
method, only its vanilla-mode copy does, so the tutorial raises a Lua error at those steps.

What this part changes. CleanUI's window gets the method with vanilla's meaning (blink every
container button, or only those of one container type, until told to stop), and the blinking
buttons get a pulsing red overlay drawn over them, clipped to the scrolled button rail.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local PAGE_MARKER = "cleanUIGetContentY"
local PERIOD_MS = 667

-- A method only CleanUI's own page has; render's file is unreliable since Better Containers wraps it.
local function cleanUIPage()
    local cls = rawget(_G, "CleanUI_Clean_ISInventoryPage") or ISInventoryPage
    if type(cls) ~= "table" or type(rawget(cls, PAGE_MARKER)) ~= "function" then return nil end
    return cls
end

local function pulse()
    local phase = (getTimestampMs() % PERIOD_MS) / PERIOD_MS
    return 0.3 + 0.4 * math.abs(1 - 2 * phase)
end

local function blinks(page, button)
    return button.inventory ~= nil and button:getIsVisible()
        and (page.blinkContainerType == nil or button.inventory:getType() == page.blinkContainerType)
end

local function drawBlink(page)
    local rail = page.containerButtonPanel or page
    local top, bottom = rail:getAbsoluteY(), rail:getAbsoluteY() + rail:getHeight()
    local pageX, pageY = page:getAbsoluteX(), page:getAbsoluteY()
    local alpha = pulse()
    for _, button in ipairs(page.backpacks or {}) do
        if blinks(page, button) then
            local y1 = math.max(button:getAbsoluteY(), top)
            local y2 = math.min(button:getAbsoluteY() + button:getHeight(), bottom)
            if y2 > y1 then
                local a = button.inventory == page.inventoryPane.inventory and alpha or alpha * 0.75
                page:drawRect(button:getAbsoluteX() - pageX, y1 - pageY, button:getWidth(), y2 - y1, a, 1, 0, 0)
            end
        end
    end
end

local function install(ctx)
    local cls = cleanUIPage()
    if cls == nil then error("ISInventoryPage is not CleanUI's") end
    if cls.setBlinkingContainer ~= nil then error("CleanUI's inventory page already has setBlinkingContainer") end
    cls.setBlinkingContainer = function(self, blinking, containerType)
        if not ctx.enabled() then return end
        self.blinkContainer = blinking == true
        self.blinkContainerType = blinking and containerType or nil
    end
    ctx.undo(function() cls.setBlinkingContainer = nil end)
    ctx.wrap(cls, "render", function(callOriginal)
        return function(self, ...)
            local results = { callOriginal(self, ...) }
            if self.blinkContainer then drawBlink(self) end
            return unpack(results)
        end
    end)
end

M.addPart({
    name = "cleanui-blink",
    switch = "CleanUIBlink",
    title = "CleanUI: tutorial container highlight",
    tip = "The vanilla tutorial makes a container button blink, but CleanUI's inventory window has no way to do that and the tutorial raises an error. This adds it to CleanUI's window. Only active with CleanUI.",
    kind = "fix",
    all = { "CleanUI" },
    side = "client",
    phase = "boot",
    pins = { "cleanui.page" },
    install = install,
})
