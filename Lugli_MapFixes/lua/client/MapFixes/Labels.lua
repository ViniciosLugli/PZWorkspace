-- World map town labels (M.LABELS, generated) for the maps whose own annotations name none. The
-- engine loads each lot directory's worldmap-annotations.lua in Java, from the map UI's creation and
-- every prerender; ours are added after it, as symbols of the same kind: not user-defined, so never
-- saved with the player's map, and cleared with vanilla's when the defaults reload.
local M = LugliMapFixes
M.labelled = M.labelled or {}

local function addLabel(api, label)
    local symbol = api:addUntranslatedText(label.text, "text-town", label.x, label.y)
    symbol:setRGBA(0.0, 0.0, 0.0, 0.0)
    symbol:setScale(label.scale)
    symbol:setAnchor(0.5, 0.5)
    symbol:setRotation(0.0)
    symbol:setMatchPerspective(true)
    symbol:setApplyZoom(true)
    symbol:setMinZoom(0.0)
    symbol:setMaxZoom(13.0)
    symbol:setUserDefined(false)
end

-- The texts the map's own annotations (and ours, once added) already show. A player's marks are
-- user-defined and never count, and another mod naming the same town (3821109144 names three) wins.
local function namedTexts(api)
    local named = {}
    for i = 0, api:getSymbolCount() - 1 do
        local symbol = api:getSymbolByIndex(i)
        if not symbol:isUserDefined() and symbol.getUntranslatedText then
            local text = symbol:getUntranslatedText()
            if text then named[text] = true end
        end
    end
    return named
end

-- The world's lot folders: a map whose mod is on but whose folder is not in Map= has no land to name.
local function loadedFolders()
    local ok, list = pcall(getLotDirectories)
    local out = {}
    if not ok or list == nil then return out end
    for i = 0, list:size() - 1 do
        out[list:get(i)] = true
    end
    return out
end

function M.addLabels(api)
    local named, loaded = namedTexts(api), loadedFolders()
    for i = 1, #M.MAPS do
        local labels = loaded[M.MAPS[i].folder] and M.labelled[M.MAPS[i].folder]
        if labels then
            for j = 1, #labels do
                if not named[labels[j].text] then addLabel(api, labels[j]) end
            end
        end
    end
end

-- Scans only when the UI's symbol count changed since its last look: on open, after the defaults
-- are cleared and reloaded, or when the player adds or removes a mark.
local function ensureLabels(mapUI)
    local api = mapUI.mapAPI and mapUI.mapAPI:getSymbolsAPIv2()
    if not api then return end
    if api:getSymbolCount() == mapUI.lugliLabelCount then return end
    local ok, err = pcall(M.addLabels, api)
    -- remembered either way: a failing label is reported once, not retried every frame
    mapUI.lugliLabelCount = api:getSymbolCount()
    if not ok and not M.labelsFailed then
        M.labelsFailed = true
        M.log("labels failed: " .. tostring(err))
    end
end

local function withLabels(original)
    return function(self, ...)
        local result = original(self, ...)
        ensureLabels(self)
        return result
    end
end

function M.installLabels(map)
    local labels = M.LABELS and M.LABELS[map.folder]
    if not labels or #labels == 0 then
        error("no generated labels for " .. map.folder)
    end
    if not M.labelsHooked then
        if type(ISWorldMap) ~= "table" or type(ISWorldMap.prerender) ~= "function" then
            error("ISWorldMap.prerender not found")
        end
        if type(ISMiniMapInner) ~= "table" or type(ISMiniMapInner.prerender) ~= "function" then
            error("ISMiniMapInner.prerender not found")
        end
        ISWorldMap.prerender = withLabels(ISWorldMap.prerender)
        ISMiniMapInner.prerender = withLabels(ISMiniMapInner.prerender)
        M.labelsHooked = true
    end
    M.labelled[map.folder] = labels
end

for i = 1, #M.MAPS do
    local map = M.MAPS[i]
    if M.LABELS and M.LABELS[map.folder] then
        M.addPart("labels-" .. map.part, map.id, function() M.installLabels(map) end)
    end
end
