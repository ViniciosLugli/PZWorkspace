-- Spawn select draws one image, vanilla's spawnSelectImagePyramid, for every region, so a mod map shows
-- vanilla's paper map under it (or nothing, east of it). Each listed map gets its own preview image,
-- drawn over vanilla's, and the view bounds grow to cover them.
-- The engine draws spawn-select pyramids in reverse order of adding: added first, drawn on top.
-- With no vanilla image listed (a server without Muldraugh), vanilla falls back to vector data; when
-- every listed map has a preview they replace that view, so each still shows as a paper map.
local M = LugliMapFixes
M.previews = M.previews or {}
M.previewOrder = M.previewOrder or {}

M.PREVIEW_FILE = "spawnSelectImagePyramid.zip"

local function listedFolders(screen)
    local ok, regions = pcall(function() return screen:getSpawnRegions() end)
    if not ok or type(regions) ~= "table" then return nil end
    local folders = {}
    for _, region in ipairs(regions) do
        if type(region) == "table" and type(region.name) == "string" then
            folders[string.match(region.name, "^[^;]+")] = true
        end
    end
    return folders
end

local function shown()
    local out = {}
    for i = 1, #M.previewOrder do
        local folder = M.previewOrder[i]
        if M.spawnFolders == nil or M.spawnFolders[folder] then
            out[#out + 1] = M.previews[folder]
        end
    end
    return out
end

-- Whether every listed map has a preview. One without (a map this mod does not know) keeps vanilla's
-- vector view, which draws it; clearing that for our previews would leave it blank.
local function allPreviewed(folders)
    if folders == nil then return false end
    for folder in pairs(folders) do
        if M.previews[folder] == nil and getMapInfo(folder) ~= nil then return false end
    end
    return true
end

local function previewsOnly(panel, list)
    panel:clear()
    for i = 1, #list do
        panel.mapAPI:addImagePyramid(list[i].path)
    end
    panel.pyramidFileName = list[1].path
    panel.lugliPreviews = list
    panel.lugliPreviewsOnly = true
    panel.mapAPI:setBoolean("ImagePyramid", true)
end

local function hookSpawnSelect()
    local originalFill = MapSpawnSelect.fillList
    MapSpawnSelect.fillList = function(self, ...)
        M.spawnFolders = listedFolders(self)
        if self.mapPanel then
            self.mapPanel.lugliPreviews = nil
            self.mapPanel.lugliPreviewsOnly = nil
        end
        local result = originalFill(self, ...)
        local pending = shown()
        if self.mapPanel and self.mapPanel.pyramidFileName == nil and #pending > 0
                and allPreviewed(M.spawnFolders) then
            local ok, err = pcall(previewsOnly, self.mapPanel, pending)
            if not ok then
                -- previewsOnly cleared vanilla's vector view; fillList clears and rebuilds it whole
                M.log("spawn previews failed, vanilla view kept: " .. tostring(err))
                self.mapPanel.lugliPreviews = nil
                self.mapPanel.lugliPreviewsOnly = nil
                result = originalFill(self, ...)
            end
        end
        return result
    end

    local originalSet = MapSpawnSelectImage.setImagePyramid
    MapSpawnSelectImage.setImagePyramid = function(self, fileName, ...)
        local list = shown()
        local ok, err = pcall(function()
            for i = 1, #list do
                self.mapAPI:addImagePyramid(list[i].path)
            end
        end)
        if ok then
            self.lugliPreviews = list
        else
            M.log("spawn previews failed, vanilla image kept: " .. tostring(err))
        end
        return originalSet(self, fileName, ...)
    end

    -- Vanilla sets the view bounds to its own image on the first frame; widen them to every preview's.
    local originalPrerender = MapSpawnSelectImage.prerender
    MapSpawnSelectImage.prerender = function(self, ...)
        local list = self.lugliPreviews
        if list and #list > 0 and not self.hasResetView and self.pyramidFileName and self:getWidth() >= 1
                and self.mapAPI:getDataCount() == 0 then
            local x0, y0, x1, y1
            if self.lugliPreviewsOnly then
                x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
            else
                x0, y0 = 0, 0
                x1 = self.mapAPI:getImagePyramidWidthInSquares(self.pyramidFileName)
                y1 = self.mapAPI:getImagePyramidHeightInSquares(self.pyramidFileName)
            end
            for i = 1, #list do
                local b = list[i].bounds
                x0, y0 = math.min(x0, b[1]), math.min(y0, b[2])
                x1, y1 = math.max(x1, b[3]), math.max(y1, b[4])
            end
            self.hasResetView = true
            self.mapAPI:setBoundsInSquares(x0, y0, x1, y1)
            self.mapAPI:resetView()
        end
        return originalPrerender(self, ...)
    end
end

function M.installPreview(map)
    if type(map.preview) ~= "table" then
        error("no preview bounds declared")
    end
    local relative = "media/maps/" .. M.oursFor(map.folder) .. "/" .. M.PREVIEW_FILE
    local path = M.modFile(relative)
    if path == nil then
        error("generated preview missing: " .. relative)
    end
    if not M.previewHooked then
        if type(MapSpawnSelect) ~= "table" or type(MapSpawnSelect.fillList) ~= "function"
                or type(MapSpawnSelectImage) ~= "table" or type(MapSpawnSelectImage.setImagePyramid) ~= "function"
                or type(MapSpawnSelectImage.prerender) ~= "function" then
            error("spawn select not found")
        end
        hookSpawnSelect()
        M.previewHooked = true
    end
    if M.previews[map.folder] == nil then
        M.previewOrder[#M.previewOrder + 1] = map.folder
    end
    M.previews[map.folder] = { path = path, bounds = map.preview }
end

for i = 1, #M.MAPS do
    local map = M.MAPS[i]
    if map.preview then
        M.addPart("preview-" .. map.part, map.id, function() M.installPreview(map) end)
    end
end
