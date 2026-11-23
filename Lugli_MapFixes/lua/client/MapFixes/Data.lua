-- World map and minimap: a map's folder loads our generated data and images in place of its own.
-- Installed at OnGameBoot, after every mod's file-scope hooks, so it wraps them; a map's own loader
-- (Camden's ArcadiaNativeForestData) then sees our folder name and stays out. A hook another mod adds
-- at OnGameBoot from client/ lands after ours and wraps it, which is why a map's `dataBy` fix yields.
local M = LugliMapFixes
M.redirect = M.redirect or {}
M.clear = M.clear or {}
M.CLEAR_FILE = "forestclear.pyramid.zip"
M.CLEAR_LAYER = "lugli-forestclear"

local function redirectedName(name)
    return M.redirect[name] or name
end

-- getLotDirectories() as the minimap reads it, with redirected names. It stands in for the ArrayList
-- while InitPlayer runs, so it carries the read methods any other hook inside InitPlayer may call.
local function redirectedList(list)
    local names, has = {}, {}
    for i = 0, list:size() - 1 do
        names[i + 1] = redirectedName(list:get(i))
        has[names[i + 1]] = true
    end
    return {
        size = function() return #names end,
        isEmpty = function() return #names == 0 end,
        get = function(_, i) return names[i + 1] end,
        contains = function(_, name) return has[name] == true end,
        indexOf = function(_, name)
            for i = 1, #names do
                if names[i] == name then return i - 1 end
            end
            return -1
        end,
    }
end

local function hookWorldMap()
    local original = MapUtils.initDirectoryMapData
    MapUtils.initDirectoryMapData = function(mapUI, directory, ...)
        local name = type(directory) == "string" and string.match(directory, "^media/maps/(.+)$")
        if name and M.redirect[name] then
            local result = original(mapUI, "media/maps/" .. M.redirect[name], ...)
            mapUI.javaObject:getAPIv3():addImagePyramid(M.clear[name])
            return result
        end
        return original(mapUI, directory, ...)
    end
end

-- Below zoom 15 the world map draws every folder's forest.pyramid.zip over the whole view, with no
-- cell priority, so vanilla's forest shows through a map's clearings wherever the map replaced
-- vanilla land. Each map's forestclear pyramid marks those squares, and this layer, right above
-- vanilla's, repaints them in the map's background colour until the vector forest takes over at 15.
local function addClearLayer(mapUI)
    local styleAPI = mapUI.javaObject:getAPIv3():getStyleAPI()
    local forest = styleAPI:indexOfLayer("pyramid-forest")
    if forest < 0 then
        return
    end
    local layer = styleAPI:newPyramidLayer(M.CLEAR_LAYER)
    layer:setPyramidFileName(M.CLEAR_FILE)
    layer:addFill(0.0, 219, 215, 192, 255.0)
    layer:addFill(14.999, 219, 215, 192, 255.0)
    layer:addFill(15.0, 0.0, 0.0, 0.0, 0.0)
    styleAPI:moveLayer(styleAPI:indexOfLayer(M.CLEAR_LAYER), forest + 1)
end

local function hookStyle()
    local original = MapUtils.initDefaultStyleV3
    MapUtils.initDefaultStyleV3 = function(mapUI, ...)
        local result = original(mapUI, ...)
        local ok, err = pcall(addClearLayer, mapUI)
        if not ok then
            M.log("forest clearing layer failed, vanilla style kept: " .. tostring(err))
        end
        return result
    end
end

local function hookMiniMap()
    local original = ISMiniMap.InitPlayer
    ISMiniMap.InitPlayer = function(...)
        local real = getLotDirectories
        getLotDirectories = function() return redirectedList(real()) end
        local ok, result = pcall(original, ...)
        getLotDirectories = real
        if not ok then error(result) end
        return result
    end
end

function M.installData(map)
    local ours = M.oursFor(map.folder)
    if not fileExists("media/maps/" .. ours .. "/worldmap.xml") then
        error("generated data missing: media/maps/" .. ours)
    end
    local clear = M.modFile("media/maps/" .. ours .. "/" .. M.CLEAR_FILE)
    if clear == nil then
        error("generated data missing: media/maps/" .. ours .. "/" .. M.CLEAR_FILE)
    end
    if not M.dataHooked then
        if type(MapUtils) ~= "table" or type(MapUtils.initDirectoryMapData) ~= "function"
                or type(MapUtils.initDefaultStyleV3) ~= "function" then
            error("MapUtils.initDirectoryMapData or initDefaultStyleV3 not found")
        end
        if type(ISMiniMap) ~= "table" or type(ISMiniMap.InitPlayer) ~= "function" then
            error("ISMiniMap.InitPlayer not found")
        end
        hookWorldMap()
        hookStyle()
        hookMiniMap()
        M.dataHooked = true
    end
    M.clear[map.folder] = clear
    M.redirect[map.folder] = ours
end

for i = 1, #M.MAPS do
    local map = M.MAPS[i]
    M.addPart("data-" .. map.part, map.id, function() M.installData(map) end, map.dataBy)
end
