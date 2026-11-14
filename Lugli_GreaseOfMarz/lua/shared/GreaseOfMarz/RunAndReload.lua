--[[
Run and Reload beside Gunworks: reloads keep their steps, in single player and multiplayer.

Gunworks splits a reload into steps, each one vanilla timed action: an opening stroke, a round
straight into the chamber, the rounds into the tube, a closing stroke. It tells the steps apart by
values it adds to the reload action constructors in shared Lua (ISRackFirearm, ISReloadWeaponAction,
ISInsertMagazine, ISEjectMagazine, ISUnloadBulletsFromFirearm), and it loads a magazine with a set
ammo type and round limit the same way (ISLoadBulletsInMagazine, which Easy Spare Magazine Reload
extends again). Run and Reload redefines those constructors and ISUnloadBulletsFromMagazine's in
client Lua, without calling the ones it replaces, only to let these actions go on while walking,
running or aiming. Every step then reads as a plain rack or a plain load, so the reload rules add
their strokes again until Gunworks stops them after six ("keep adding steps"): a Winchester 1873 or
a Remington 700 racks and reloads over and over, and a magazine loads any round instead of the one
chosen. In multiplayer the server builds its copy of each action from the parameters the client's
final constructor names, so it never learns the stroke either, runs every one as a full rack and
throws a live round out.

This part puts the constructors Run and Reload replaced back, so each action is built, and sent to
the server, exactly as the mods below it define. Run and Reload's own flags, the only thing its
constructors add, are applied when the action is created, which is where the engine reads them, so
reloading on the move still works. The constructors are kept as they stand when this file loads
(every earlier mod's shared Lua has run) and again when this mod's client Lua loads, if Run and
Reload's has not run yet (every mod's shared Lua has run). A dedicated server never loads Run and
Reload's client Lua, so the part does not exist there.
]]
require "GreaseOfMarz_Status"
local M = LugliGreaseOfMarz

local RR_DIR = "RunAndReload"
local RR_FILE = "TimedActionsOverrides.lua"
local CLASSES = { "ISRackFirearm", "ISReloadWeaponAction", "ISInsertMagazine", "ISEjectMagazine",
    "ISUnloadBulletsFromFirearm", "ISLoadBulletsInMagazine", "ISUnloadBulletsFromMagazine" }
local RR_FLAGS = { "stopOnAim", "stopOnWalk", "stopOnRun", "useProgressBar" }

local function constructorOf(name)
    local cls = rawget(_G, name)
    if type(cls) ~= "table" then return nil end
    return rawget(cls, "new")
end

local function fromRunAndReload(fn)
    if type(fn) ~= "function" then return false end
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and type(name) == "string" and string.find(name, RR_FILE, 1, true) ~= nil
        and string.find(name, RR_DIR, 1, true) ~= nil
end

local before = {}

--- Keeps each constructor Run and Reload has not replaced yet; one it has keeps the last kept.
function M.keepReloadConstructors()
    for i = 1, #CLASSES do
        local fn = constructorOf(CLASSES[i])
        if type(fn) == "function" and not fromRunAndReload(fn) then before[CLASSES[i]] = fn end
    end
end

M.keepReloadConstructors()

-- Everything that can fail runs before the first write, and a rejected write puts every class back,
-- so the part is either whole or absent.
local function install()
    local plan = {}
    for i = 1, #CLASSES do
        local name = CLASSES[i]
        local cls = rawget(_G, name)
        local rrNew, chain = constructorOf(name), before[name]
        if not fromRunAndReload(rrNew) then error(name .. ".new is not Run and Reload's") end
        if chain == nil then error(name .. ".new had no constructor before Run and Reload's") end
        local sample = rrNew(cls, nil)
        local flags = {}
        for f = 1, #RR_FLAGS do flags[RR_FLAGS[f]] = sample[RR_FLAGS[f]] end
        plan[i] = { name = name, cls = cls, rr = rrNew, chain = chain, flags = flags,
            ownCreate = rawget(cls, "create"), create = cls.create }
    end
    local function restore()
        for i = 1, #plan do
            plan[i].cls.new = plan[i].rr
            plan[i].cls.create = plan[i].ownCreate
        end
    end
    local replaced = {}
    for i = 1, #plan do
        local p = plan[i]
        local flags, create = p.flags, p.create
        local function flagged(self, ...)
            for flag, value in pairs(flags) do self[flag] = value end
            return create(self, ...)
        end
        p.cls.create = flagged
        p.cls.new = p.chain
        if rawget(p.cls, "new") ~= p.chain or rawget(p.cls, "create") ~= flagged then
            restore()
            error(p.name .. " rejected the assignment")
        end
        replaced[p.name] = { rr = p.rr, chain = p.chain, flags = flags }
    end
    M.runAndReload = { replaced = replaced }
end

if not (type(isServer) == "function" and isServer()) then
    M.addPart("RunAndReload", { "SWMG", "Run and Reload" }, install)
end
