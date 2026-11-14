--[[
damnlib: the military vehicles' seats can be repaired.

What happens today. damnlib's two seat repairs, "Fix USMIL Seat" (duct tape) and "Fix USMIL Seat 1"
(needle and thread), require damnCraft.Seat0, damnCraft.Seat1front, damnCraft.Seat1rear and
damnCraft.Seat2 (42.20/media/scripts/USMIL/fixing_USMIL.txt), but those seats are defined in module
USMIL (42.20/media/scripts/USMIL/items_USMIL.txt) and no damnCraft item by those names exists. The
game offers a repair only for an item whose full type is in the list (FixingManager.java:22-33 on
42.22.2), so the seats of every vehicle built on damnlib's military parts (M35A2, M998, M911, P19A,
KAT1, the '67 Commando, B700) can never be repaired.

What this part changes. Both repairs also accept the four USMIL seats, with damnlib's own fixers,
skills and odds. damnCraft names are left in the list, so nothing is lost if damnlib ever defines them.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local FIXES = { ["Fix USMIL Seat"] = true, ["Fix USMIL Seat 1"] = true }
local SEATS = { "Seat0", "Seat1front", "Seat1rear", "Seat2" }

local function install(ctx)
    local scripts = getScriptManager()
    local all = scripts:getAllFixing(ArrayList.new())
    local added = {}
    for i = 0, all:size() - 1 do
        local fixing = all:get(i)
        if FIXES[fixing:getName()] then
            local list = fixing:getRequiredItem()
            for s = 1, #SEATS do
                local wrong, right = "damnCraft." .. SEATS[s], "USMIL." .. SEATS[s]
                if list:contains(wrong) and not list:contains(right) then
                    if scripts:FindItem(right) == nil then error(right .. " is missing") end
                    if scripts:FindItem(wrong) ~= nil then error(wrong .. " exists: nothing to fix") end
                    fixing:addRequiredItem(right)
                    added[#added + 1] = { list = list, item = right }
                end
            end
        end
    end
    if #added == 0 then error("no USMIL seat repair lists a damnCraft seat") end
    ctx.undo(function()
        for i = 1, #added do added[i].list:remove(added[i].item) end
    end)
end

M.addPart({
    name = "usmil-seats",
    switch = "UsmilSeats",
    title = "damnlib: military vehicle seats can be repaired",
    tip = "damnlib's seat repairs name seats that do not exist, so the seats of its military vehicles (M35A2, M998, M911 and others) can never be repaired with duct tape or needle and thread. This makes both repairs accept the real seats, with damnlib's own tools and skills. Only active with damnlib.",
    kind = "fix",
    all = { "damnlib" },
    side = "both",
    phase = "boot",
    pins = { "usmil.seats" },
    install = install,
})
