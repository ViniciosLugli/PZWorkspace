-- Spawn select centres on getMapInfo's zoomX/zoomY/zoomS. Some maps ship none, or one outside their own
-- cells; those get a point on the map's own town. getMapInfo builds a fresh table per call, so the
-- copy handed out is ours to change.
local M = LugliMapFixes
M.zoom = M.zoom or {}

local function hookMapInfo()
    local original = getMapInfo
    getMapInfo = function(mapDir, ...)
        local info = original(mapDir, ...)
        local name = type(mapDir) == "string" and string.match(mapDir, "^[^;]+") or nil
        local z = name and M.zoom[name]
        if type(info) == "table" and z then
            info.zoomX, info.zoomY, info.zoomS = z.x, z.y, z.s
        end
        return info
    end
end

function M.installZoom(map)
    if type(map.zoom) ~= "table" then
        error("no zoom point declared")
    end
    if not M.zoomHooked then
        if getMapInfo == nil then
            error("getMapInfo not found")
        end
        hookMapInfo()
        M.zoomHooked = true
    end
    M.zoom[map.folder] = map.zoom
end

for i = 1, #M.MAPS do
    local map = M.MAPS[i]
    if map.zoom then
        M.addPart("zoom-" .. map.part, map.id, function() M.installZoom(map) end)
    end
end
