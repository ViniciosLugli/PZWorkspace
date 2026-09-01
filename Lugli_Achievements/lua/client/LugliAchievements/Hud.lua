require "LugliAchievements/Neat"

local M = LugliAchievements
local PART = "HUD button"
local ICON_DIR = "media/ui/achievements/sidebar/"

--- The game picks 48, 64, 80 or 96 from the UI scale and sizes every sidebar button to it, so
--- ours reads its own size off a sibling rather than re-deriving the setting.
local function icons(px)
    local size = 64
    for _, s in ipairs({ 48, 64, 80, 96 }) do
        if px >= s then size = s end
    end
    local N = M.neat
    local off = N and N.tex(ICON_DIR .. "off_" .. size .. ".png") or nil
    local on = N and N.tex(ICON_DIR .. "on_" .. size .. ".png") or nil
    return off, on
end

--- The lowest button already in the column. Which buttons exist varies -- map only when the
--- world map is allowed, admin only for admins -- so the position comes from what is present.
local function lowest(panel)
    local names = { "invBtn", "healthBtn", "craftingBtn", "buildBtn", "movableBtn",
                    "searchBtn", "zoneBtn", "mapBtn", "debugBtn", "arfBtn", "safetyBtn",
                    "clientBtn", "adminBtn", "warManagerBtn" }
    local bottom, ref = nil, nil
    for i = 1, #names do
        local b = panel[names[i]]
        if b ~= nil and b.getBottom ~= nil and b:isVisible() then
            local y = b:getBottom()
            if bottom == nil or y > bottom then bottom = y; ref = b end
        end
    end
    return bottom, ref
end

local function attach(panel)
    if panel == nil or panel.lugliAchBtn ~= nil then return end
    local bottom, ref = lowest(panel)
    if bottom == nil or ref == nil then return end

    local px = ref:getWidth()
    local off, on = icons(px)
    -- ISEquippedItem declares UI_BORDER_SPACING as a FILE LOCAL, not a global, so reading the
    -- name from here returns nil. Its value is 10, plus the 5 the column puts between groups.
    local spacing = 15

    local btn = ISButton:new(ref:getX(), bottom + spacing, px, ref:getHeight(), "", panel,
                             function() M.toggleWindow(panel.chr and panel.chr:getPlayerNum() or 0) end)
    btn.internal = "LUGLI_ACHIEVEMENTS"
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn:ignoreWidthChange()
    btn:ignoreHeightChange()
    if off ~= nil then btn:setImage(off) end
    btn.lugliAchIconOff, btn.lugliAchIconOn = off, on
    panel:addChild(btn)
    panel.lugliAchBtn = btn

    if panel.addMouseOverToolTipItem ~= nil then
        pcall(function()
            panel:addMouseOverToolTipItem(btn, getText("UI_LugliAch_window_title"))
        end)
    end
    -- The panel's height is the bottom of its last button, and it now has one more.
    if btn:getBottom() > panel:getHeight() then panel:setHeight(btn:getBottom()) end
    M.status(PART, true, "docked in the game's sidebar, under " .. tostring(ref.internal or "?"))
end

local function install()
    if type(ISEquippedItem) ~= "table" or type(ISEquippedItem.createChildren) ~= "function" then
        M.status(PART, nil, "the game's sidebar panel is not present", "dep")
        return
    end
    if ISEquippedItem.lugliAchWrapped == true then return end

    local original = ISEquippedItem.createChildren
    ISEquippedItem.createChildren = function(self, ...)
        local r = { original(self, ...) }
        self.lugliAchBtn = nil
        return unpack(r)
    end

    -- The attach happens on the first PRERENDER, not in createChildren: the column's buttons
    -- exist by then but are not laid out or made visible, so every one fails isVisible() and
    -- there is nothing to measure a position from.
    local originalPre = ISEquippedItem.prerender
    if type(originalPre) == "function" then
        ISEquippedItem.prerender = function(self, ...)
            -- pcall: a fault here would take the whole HUD column down with it.
            if self.lugliAchBtn == nil then pcall(attach, self) end
            local btn = self.lugliAchBtn
            if btn ~= nil and btn.lugliAchIconOn ~= nil and btn.lugliAchIconOff ~= nil then
                pcall(function()
                    btn:setImage(M.isWindowOpen() and btn.lugliAchIconOn or btn.lugliAchIconOff)
                end)
            end
            return originalPre(self, ...)
        end
    end

    ISEquippedItem.lugliAchWrapped = true
    -- Pending, not done: whether a button actually lands is only known when the column first
    -- renders. Reporting success here read green while the sidebar had no button.
    M.status(PART, nil, "waiting for the sidebar to render", "pending")
end

install()

-- The panel is rebuilt on a resolution or UI-scale change, so the wrapper is re-asserted.
M.addHandler(PART, "OnGameStart", install)
