require "LugliAchievements/Core"

local M = LugliAchievements
local PART = "NeatUI chrome"

local N = {}
M.neat = N

N.TEX = {
    titleBar   = "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png",
    panelFlat  = "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png",
    panelRound = "media/ui/NeatUI/DefaultPanel/MainPanelBG_RoundTop.png",
    innerPanel = "media/ui/NeatUI/DefaultPanel/InnerPanel_BG.png",
    contentBG  = "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png",
}

N.accent   = { r = 0.87, g = 0.64, b = 0.34 }
N.text     = { r = 0.92, g = 0.90, b = 0.86 }
N.textDim  = { r = 0.62, g = 0.60, b = 0.57 }
N.line     = { r = 0.38, g = 0.36, b = 0.33 }
N.tierCol  = {
    bronze = { r = 0.80, g = 0.52, b = 0.25 },
    silver = { r = 0.74, g = 0.77, b = 0.81 },
    gold   = { r = 0.90, g = 0.74, b = 0.36 },
}

N.TITLE_TINT = 0.08
N.PANEL_TINT = 0.15
N.PANEL_A    = 0.86
N.INNER_TINT = 0.11

local hasNP = false
local primed = {}

local function ninePatch(path)
    if not hasNP then return nil end
    local ok, np = pcall(NinePatchTexture.getSharedTexture, path)
    if ok then return np end
    return nil
end

--- The flat branch is not an error path: getSharedTexture returns nil on the FIRST call for a
--- path, so it is what the opening frame of every panel draws. It has to look deliberate.
function N.panel(el, path, x, y, w, h, tint, alpha)
    if w <= 0 or h <= 0 then return end
    local np = ninePatch(path)
    if np ~= nil then
        local ok = pcall(function()
            np:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h,
                      tint, tint, tint, alpha or N.PANEL_A)
        end)
        if ok then return end
    end
    el:drawRect(x, y, w, h, alpha or N.PANEL_A, tint, tint, tint)
    el:drawRectBorder(x, y, w, h, 0.55, N.line.r, N.line.g, N.line.b)
end

function N.window(el, x, y, w, h, headerH)
    N.panel(el, N.TEX.titleBar, x, y, w, headerH, N.TITLE_TINT, 1.0)
    N.panel(el, N.TEX.panelFlat, x, y + headerH, w, h - headerH, N.PANEL_TINT, N.PANEL_A)
end

function N.inner(el, x, y, w, h, alpha)
    N.panel(el, N.TEX.innerPanel, x, y, w, h, N.INNER_TINT, alpha or 0.62)
end

local texCache = {}

function N.tex(path)
    if path == nil then return nil end
    if texCache[path] == nil then
        local ok, t = pcall(getTexture, path)
        texCache[path] = (ok and t) or false
    end
    if texCache[path] == false then return nil end
    return texCache[path]
end

--- The right texture for the size it will be drawn at. Every achievement ships twice, 256px for
--- the grid and 96px under small/, and a large sheet in a small slot is a minification with no
--- mipmaps behind it: it aliases rather than softens. 110 is the crossover, above which the 96px
--- copy would be upscaled and go soft.
function N.art(path, px)
    if type(path) ~= "string" then return nil end
    if px ~= nil and px <= 110 then
        local small = N.tex((string.gsub(path, "([^/]+)$", "small/%1")))
        if small ~= nil then return small end
    end
    return N.tex(path)
end

--- Cut text to a pixel width. Measured rather than counted, because a character count is wrong
--- the moment the string is translated.
function N.fit(text, maxW, font)
    if type(text) ~= "string" then return "" end
    if NeatTool ~= nil and type(NeatTool.truncateText) == "function" then
        local ok, cut = pcall(NeatTool.truncateText, text, maxW, font, "...")
        if ok and type(cut) == "string" then return cut end
    end
    if getTextManager == nil then return text end
    local tm = getTextManager()
    local okm, w = pcall(function() return tm:MeasureStringX(font, text) end)
    if not okm or w <= maxW then return text end
    local lo, hi = 1, #text
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        local ok2, cw = pcall(function()
            return tm:MeasureStringX(font, string.sub(text, 1, mid) .. "...")
        end)
        if ok2 and cw <= maxW then lo = mid else hi = mid - 1 end
    end
    return string.sub(text, 1, lo) .. "..."
end

function N.width(text, font)
    if getTextManager == nil or type(text) ~= "string" then return #(text or "") * 6 end
    local ok, w = pcall(function() return getTextManager():MeasureStringX(font, text) end)
    return ok and w or (#text * 6)
end

--- The game's own UI sounds. An unknown name is silent with no error, so each is verified present
--- in the installed build. ISButton already plays UIActivateButton itself (ISButton.lua:521); only
--- what this window draws by hand needs a voice.
N.SOUND = {
    open   = "UIPauseMenuEnter",    -- the window arriving
    close  = "UIPauseMenuExit",     -- and leaving
    tab    = "UIActivateTab",       -- a category on the rail, which behaves as a tab
    pick   = "UISelectListItem",    -- an achievement tile
    option = "UIToggleComboBox",    -- zoom and sort, which vanilla leaves silent
}

--- Blend two palette entries. t = 0 is `a`, t = 1 is `b`.
function N.mix(a, b, t)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return { r = a.r + (b.r - a.r) * t,
             g = a.g + (b.g - a.g) * t,
             b = a.b + (b.b - a.b) * t }
end

N.done = { r = 0.45, g = 0.80, b = 0.42 }

--- Amber to green as a set closes out. Held at the accent until halfway, so early progress does
--- not read as almost-finished.
function N.progressCol(frac)
    if type(frac) ~= "number" or frac ~= frac then return N.accent end
    return N.mix(N.accent, N.done, (frac - 0.5) * 2.0)
end

function N.sound(name)
    if name == nil or getSoundManager == nil then return end
    pcall(function() getSoundManager():playUISound(name) end)
end

--- Prime each path once, so the unavoidable first-call nil happens at load rather than on the
--- frame a player opens the window.
local function prime()
    hasNP = (NinePatchTexture ~= nil and type(NinePatchTexture.getSharedTexture) == "function")
    if not hasNP then
        M.status(PART, false, "NinePatchTexture is not available, using flat panels", "dep")
        return
    end
    for _, path in pairs(N.TEX) do
        if not primed[path] then
            pcall(NinePatchTexture.getSharedTexture, path)
            primed[path] = true
        end
    end
    M.status(PART, true)
end

M.addHandler(PART, "OnGameBoot", prime)
M.addHandler(PART, "OnGameStart", prime)
