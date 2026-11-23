-- Spawn select shows vanilla's map with a demo video above its description; a mod map gets a preview
-- image there instead. <IMAGECENTRE> draws at a fixed size and the panel's width follows the screen,
-- so the tag is sized to the panel whenever that width changes.
local M = LugliMapFixes
M.images = M.images or {}

M.IMAGE_W, M.IMAGE_H = 16, 9

local function imageFor(item)
    if type(item) ~= "table" or item.demoVideo or type(item.dir) ~= "string" then return nil end
    return M.images[string.match(item.dir, "^[^;]+")]
end

local function hookRender()
    local original = MapSpawnSelect.render
    MapSpawnSelect.render = function(self, ...)
        local entry = self.listbox and self.listbox.items and self.listbox.items[self.listbox.selected]
        local item = entry and entry.item
        local path = imageFor(item)
        if path and self.richText then
            local w = math.floor(self.richText:getWidth() - (self.richText.marginLeft or 0)
                - (self.richText.marginRight or 0) - 4)
            if w > 0 and item.lugliImageWidth ~= w then
                if item.lugliText == nil then item.lugliText = item.desc or "" end
                local h = math.floor(w * M.IMAGE_H / M.IMAGE_W)
                item.desc = "<IMAGECENTRE:" .. path .. "," .. w .. "," .. h .. "> <LINE> " .. item.lugliText
                item.lugliImageWidth = w
            end
        end
        return original(self, ...)
    end
end

function M.installImage(map)
    local path = "media/ui/LugliMapFixes/" .. map.part .. ".png"
    if not fileExists(path) then
        error("preview image missing: " .. path)
    end
    if not M.imageHooked then
        if type(MapSpawnSelect) ~= "table" or type(MapSpawnSelect.render) ~= "function" then
            error("MapSpawnSelect.render not found")
        end
        hookRender()
        M.imageHooked = true
    end
    M.images[map.folder] = path
end

for i = 1, #M.MAPS do
    local map = M.MAPS[i]
    if map.preview then
        M.addPart("image-" .. map.part, map.id, function() M.installImage(map) end)
    end
end
