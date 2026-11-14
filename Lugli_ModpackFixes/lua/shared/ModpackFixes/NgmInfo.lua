--[[
Nick's Generator Manager: every Generator Info text lists what that generator pays for, in the
engine's own number format.

What happens today. Nick's Generator Manager rebuilds the Generator Info text so it lists only the
appliances each generator pays for, but prints their draw without the leading zero (".0008 L/h")
right above base and Total lines the engine prints with one ("0.0028 L/h"). Badlands Power builds
its battery bank's text itself from the engine's list of every appliance in range, so a bank lists
the fridges another generator pays for and its list does not add up to its Total. The same text is
the right-click tooltip of a generator.

What this part changes. The appliance list in that text, whichever mod built it, becomes the lines
Nick bills to that generator, printed as the engine prints its own. Until Nick's first pass has
billed a generator, its text is left as it is.
]]
require "ModpackFixes_Status"
require "ModpackFixes/NgmNeat"
local M = LugliModpackFixes

local ITEM = "   "
local LINE = " <LINE> "

-- Vanilla, Nick and Badlands all open the list with this head and write each appliance as
-- ITEM .. text .. LINE; the first line after it that is not indented that way ends the list.
function M.ngmRichText(object, text)
    local head = getText("IGUI_PowerConsumption") .. ":" .. LINE .. " <INDENT:10> "
    local _, headEnd = string.find(text, head, 1, true)
    if headEnd == nil then return text end
    local lines = M.ngmLines(object)
    if lines == nil then return text end
    local p = headEnd + 1
    while string.sub(text, p, p + #ITEM - 1) == ITEM do
        local _, lineEnd = string.find(text, LINE, p, true)
        if lineEnd == nil then return text end
        p = lineEnd + 1
    end
    local list = {}
    for i = 1, #lines do list[i] = ITEM .. lines[i] .. LINE end
    return string.sub(text, 1, headEnd) .. table.concat(list) .. string.sub(text, p)
end

local function install(ctx)
    M.needNgmCache()
    if type(ISGeneratorInfoWindow) ~= "table" or type(ISGeneratorInfoWindow.getRichText) ~= "function" then
        error("the Generator Info window has no text builder")
    end
    ctx.wrap(ISGeneratorInfoWindow, "getRichText", function(callOriginal)
        return function(object, displayStats, ...)
            local text = callOriginal(object, displayStats, ...)
            if object == nil or type(text) ~= "string" then return text end
            return M.ngmRichText(object, text)
        end
    end)
end

M.addPart({
    name = "ngm-info",
    switch = "NgmInfo",
    title = "Nick's Generator Manager: the Generator Info list in the engine's format, also for Badlands banks",
    tip = "Nick's Generator Manager prints its appliance list as \".0008 L/h\" under lines that read \"0.0028 L/h\", and a Badlands Power battery bank lists every appliance in range instead of what it pays for. This prints Nick's list the way the game prints its own numbers, in every generator's Info text and tooltip. Only active with Nick's Generator Manager.",
    kind = "compat",
    all = { "NicksGeneratorManager" },
    side = "client",
    phase = "boot",
    pins = { "ngm.targets", "ngm.rich", "bp.bank" },
    install = install,
})
