-- Nellis Air Force Base's vehicle interiors, shared by the nellis-power and nellis-exit parts.
-- The rectangles are Nellis' own (TeleportInterior_Final.lua, pinned as nellis.portals); the map
-- puts one generator in each (an in-game walk of all 11 on 2026-11-16).
LugliModpackFixes = LugliModpackFixes or {}
LugliModpackFixes.nellis = LugliModpackFixes.nellis or {}
local N = LugliModpackFixes.nellis

N.FILE = "TeleportInterior_Final.lua"
N.ORIGIN_KEY = "AC130_TP_Origem"
N.EXIT_OFFSET = 3
N.MAX_FUEL = 10
-- Nellis' spawn point (spawnpoints.lua: worldX 36, worldY 49, posX 119, posY 15, pinned as nellis.spawn).
N.SPAWN = { x = 36 * 300 + 119, y = 49 * 300 + 15, z = 0 }

N.INTERIORS = {
    { x1 = -19152, y1 = -17941, x2 = -19139, y2 = -17935, z = -2 },
    { x1 = -19152, y1 = -17881, x2 = -19139, y2 = -17875, z = -2 },
    { x1 = -19144, y1 = -17821, x2 = -19139, y2 = -17815, z = -1 },
    { x1 = -19144, y1 = -17761, x2 = -19139, y2 = -17755, z = -1 },
    { x1 = -19084, y1 = -17941, x2 = -19079, y2 = -17935, z = -1 },
    { x1 = -19084, y1 = -17881, x2 = -19079, y2 = -17875, z = -1 },
    { x1 = -19083, y1 = -17821, x2 = -19079, y2 = -17816, z = -1 },
    { x1 = -19083, y1 = -17761, x2 = -19079, y2 = -17756, z = -1 },
    { x1 = -19023, y1 = -17941, x2 = -19019, y2 = -17936, z = -1 },
    { x1 = -19023, y1 = -17881, x2 = -19019, y2 = -17876, z = -1 },
    { x1 = -19023, y1 = -17821, x2 = -19019, y2 = -17816, z = -1 },
}

function N.fromNellis(fn)
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, N.FILE, 1, true) ~= nil
end

function N.interiorAt(x, y, z)
    for i = 1, #N.INTERIORS do
        local r = N.INTERIORS[i]
        if z == r.z and x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then return r end
    end
    return nil
end

