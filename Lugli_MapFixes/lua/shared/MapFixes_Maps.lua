-- The maps this mod presents. `folder` is the map's own folder under media/maps; our generated data
-- lives beside it in "<folder> (Lugli)", never in the map's own folder: a file there would make the
-- folder resolve to this mod and drop the map's lots.
LugliMapFixes = LugliMapFixes or {}
local M = LugliMapFixes

M.SUFFIX = " (Lugli)"

M.MAPS = {
    -- zoom: `tools/mapfixes.py zoom <folder>`, the centre of building mass of the map's main town.
    -- preview: the spawn preview's world bounds, as `tools/mapfixes.py paper` prints them.
    -- dataBy: an older fix of the map's data. It wraps the same loaders after us, so it wins anyway;
    -- while it is active our data stays out and the map is wholly its.
    { part = "dirkerdam", id = "DirkerdamIntegratedB42", folder = "Dirkerdam Integrated B42", dataBy = "DirkerdamMapFix",
        zoom = { x = 7698, y = 3358, s = 14.0 }, preview = { 0, 0, 11776, 6400 } },
    { part = "camden", id = "ARC_CamdenCounty_B42", folder = "ARC_Camden County Relocated",
        zoom = { x = 22713, y = 14079, s = 14.0 }, preview = { 19712, 12288, 26624, 19200 } },
    { part = "ravencreek", id = "RavenCreekB42", folder = "Raven Creek B42",
        zoom = { x = 5098, y = 15885, s = 14.0 }, preview = { 3840, 14080, 6912, 18176 } },
    { part = "benning", id = "FortBenningB42", folder = "Fort Benning B42",
        zoom = { x = 6142, y = 7058, s = 14.0 }, preview = { 5632, 6400, 6912, 7680 } },
    { part = "waterfront", id = "Fort Waterfront B42", folder = "Fort Waterfront B42",
        zoom = { x = 10296, y = 11022, s = 14.0 }, preview = { 9728, 10496, 11264, 11520 } },
    { part = "nellis", id = "NellisAFB", folder = "Nellis Air Force Base",
        zoom = { x = 11008, y = 14581, s = 14.0 }, preview = { 10240, 12032, 14336, 15872 } },
    { part = "atlas", id = "Atlas Underground", folder = "Atlas Underground Complex",
        zoom = { x = 10280, y = 11522, s = 14.0 }, preview = { 9472, 11008, 11264, 12800 } },
    { part = "fortknox", id = "ARC_FortKnox_B42", folder = "ARC_Fort Knox",
        zoom = { x = 17947, y = 14331, s = 14.0 }, preview = { 13568, 9728, 20224, 18432 } },
    { part = "bedfordfalls", id = "ARC_BedfordFalls_B42", folder = "ARC_BedfordFalls",
        zoom = { x = 13843, y = 11031, s = 14.0 }, preview = { 11264, 7168, 19968, 15872 } },
    { part = "bedfordroad", id = "ARC_BedfordRoad_B42", folder = "ARC_Bedford road",
        zoom = { x = 12486, y = 7969, s = 14.0 }, preview = { 11008, 7424, 13824, 8704 } },
    { part = "lakecumberland", id = "ARC_LakeCumberland_B42", folder = "ARC_LCV2",
        zoom = { x = 16911, y = 6633, s = 14.0 }, preview = { 12800, 4096, 19712, 11008 } },
    { part = "kingsmouth", id = "ARC_KingsmouthNorth_B42", folder = "ARC_Kingsmouth North B42",
        zoom = { x = 517, y = 4636, s = 14.0 }, preview = { -256, 3584, 1536, 5376 } },
    { part = "maplewood", id = "Maplewood", folder = "Maplewood",
        zoom = { x = 8243, y = 8562, s = 14.0 }, preview = { 7680, 7936, 8960, 9216 } },
}

function M.oursFor(folder)
    return folder .. M.SUFFIX
end

M.MOD_ID = "Lugli_MapFixes"

-- The absolute path of one of this mod's files, or nil. Mod folders lie outside the game's base, so
-- fileExists on an absolute path tests that exact file. Native separators: the world map matches a
-- pyramid to its style layer by the text after the path's last File.separator.
function M.modFile(relative)
    local info = getModInfoByID(M.MOD_ID)
    if info == nil then
        error(M.MOD_ID .. " not found")
    end
    local sep = getFileSeparator()
    local dirs = { info:getVersionDir(), info:getCommonDir() }
    for i = 1, 2 do
        if dirs[i] ~= nil then
            local path = (string.gsub(dirs[i] .. "/" .. relative, "[/\\]", sep))
            if fileExists(path) then
                return path
            end
        end
    end
    return nil
end
