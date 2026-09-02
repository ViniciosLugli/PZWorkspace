LugliAchievements = LugliAchievements or {}
LugliAchievements.parts = LugliAchievements.parts or {}

local M = LugliAchievements

M.MODDATA_KEY = "LugliAchievements"
M.OPTIONS_ID = "LugliAchievements"
M.DATA_VERSION = 1
M.TAG = "LugliAch"

-- Read once: fixed for the life of the process, and each call crosses into Java. Guarded
-- because shared/ also loads on a bare VM, where neither global exists.
local function boolCall(fn)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn)
    return ok and v == true
end

local IS_SERVER = boolCall(isServer)
local IS_CLIENT = boolCall(isClient)

-- There is no isDedicatedServer(): a dedicated server is a server that is not also a client.
function M.isDedicatedServer()
    return IS_SERVER and not IS_CLIENT
end

function M.isCoopHost()
    return IS_SERVER and IS_CLIENT
end

--- A client process that is not also the server. Global ModData is client-local there: nothing
--- transmits it and GameWindow.save never persists it, so it is empty again on reconnect.
function M.isMpClient()
    return IS_CLIENT and not IS_SERVER
end

M.NET_MODULE = "LugliAchievements"

function M.envName()
    if M.isCoopHost() then return "co-op host" end
    if M.isDedicatedServer() then return "dedicated server" end
    if IS_CLIENT then return "multiplayer client" end
    return "single player"
end

--- Outcome of one part, rendered by the status panel.
--- kind: "dep" a dependency you chose not to install, nothing is wrong.
---       "bug" this should have worked, and is worth reporting.
---       "pending" not decided yet; checked when you load a world.
function M.status(key, ok, note, kind)
    M.parts[key] = { ok = ok, note = note, kind = kind }
end

function M.log(part, msg)
    print("[" .. M.TAG .. "/" .. tostring(part) .. "] " .. tostring(msg))
end

--- Writes a DEFECT line as well as recording it, so "no errors in the log" can be told apart
--- from "the part never ran".
function M.defect(part, note)
    M.status(part, false, note, "bug")
    print("[" .. M.TAG .. "/" .. tostring(part) .. "] DEFECT: " .. tostring(note))
end

--- Run fn with unlock toasts and their sound suppressed, and always put the flag back.
---
--- A helper rather than a flag each caller sets: several handlers sit on OnCreatePlayer with no
--- ordering guarantee, and the one that did not save-set-restore made a completed category
--- announce its milestone on every world load.
---
--- Depth counted because these nest: a backfill unlock reaches Meta's chained hook, which
--- rechecks and can unlock again. A plain boolean would unmute the outer call halfway through.
local quietDepth = 0

function M.quietly(fn, ...)
    quietDepth = quietDepth + 1
    M.toastQuiet = true
    local ok, a, b = pcall(fn, ...)
    quietDepth = quietDepth - 1
    if quietDepth <= 0 then
        quietDepth = 0
        M.toastQuiet = false
    end
    return ok, a, b
end

--- getText echoes the key back when it is absent, so an unresolved unit would otherwise be
--- concatenated into a progress line verbatim. Hence the s ~= key guard.
function M.text(key, fallback)
    if type(key) ~= "string" then return fallback or "" end
    if getText == nil then return fallback or key end
    local ok, s = pcall(getText, key)
    if ok and type(s) == "string" and s ~= key then return s end
    return fallback or key
end

function M.worldHours()
    if getGameTime == nil then return 0 end
    local ok, h = pcall(function() return getGameTime():getWorldAgeHours() end)
    return (ok and type(h) == "number") and h or 0
end

--- Register an event handler that fails ONCE and then goes quiet: a handler throwing on every
--- zombie death is worse than a missing achievement.
function M.addHandler(part, eventName, fn)
    if Events == nil or Events[eventName] == nil then
        M.defect(part, "Events." .. tostring(eventName) .. " does not exist on this build")
        return nil
    end
    local wrapped
    wrapped = function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            Events[eventName].Remove(wrapped)
            M.defect(part, eventName .. " handler removed after: " .. tostring(err))
        end
    end
    Events[eventName].Add(wrapped)
    return wrapped
end

--- The index of a local player, or nil if the character is not one of ours. Index, not a
--- boolean, because split screen needs per-player bookkeeping.
function M.playerIndex(character)
    if character == nil or getNumActivePlayers == nil or getSpecificPlayer == nil then return nil end
    for i = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(i) == character then return i end
    end
    return nil
end

--- Every local player, so split screen is tracked rather than only player one.
function M.forEachLocalPlayer(fn)
    if getNumActivePlayers == nil or getSpecificPlayer == nil then return end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p ~= nil then fn(p, i) end
    end
end

--- Run fn(self) after a timed action's method, wrapping the class at most once: ISBuildAction
--- alone feeds four counters, and a second wrapper would silently do nothing.
---
--- perform, not complete: the engine skips complete() on a multiplayer client, so counting
--- there would record nothing for a player on a server.
---
--- The callback list lives on the CLASS, beside the wrapper that closes over it. Held in a
--- module local instead, a Lua VM reload would empty it while the old wrapper survived, and
--- every later callback would be appended to a list nothing reads.
---
--- Each entry carries the part that registered it, because a throwing callback is dropped and
--- reported by name -- the same fail-once-then-go-quiet contract addHandler gives an event
--- handler. A bare pcall here removed nothing and logged nothing, so a callback that threw did
--- so on every occurrence of that action for the rest of the session, dumping to the engine log
--- with nothing in this mod's log to say whose it was.
function M.onAction(part, clsName, fn, method)
    method = method or "perform"
    local cls = rawget(_G, clsName)
    if type(cls) ~= "table" or type(cls[method]) ~= "function" then
        -- The game changed, not this mod: a dependency, not a defect.
        M.status(part, false, clsName .. "." .. method .. " is not on this build", "dep")
        return false
    end
    local hookField = "_lugliAch_" .. method
    local list = rawget(cls, hookField)
    if list == nil then
        list = {}
        local original = cls[method]
        cls[method] = function(self, ...)
            local result = original(self, ...)
            local i = 1
            while i <= #list do
                local entry = list[i]
                local ok, err = pcall(entry.fn, self)
                if ok then
                    i = i + 1
                else
                    table.remove(list, i)
                    M.defect(entry.part, clsName .. "." .. method ..
                                         " callback removed after: " .. tostring(err))
                end
            end
            return result
        end
        cls[hookField] = list
    end
    list[#list + 1] = { part = part, fn = fn }
    return true
end

--- The common case: finishing this action increments this stat by one.
function M.countAction(part, clsName, stat)
    return M.onAction(part, clsName, function(self)
        if self ~= nil and self.character ~= nil then
            M.incStat(self.character, stat, 1)
        end
    end)
end

--- A whole tracker made of { class, stat } rows. Wrapped at OnGameStart so the copy chained is
--- whatever is current after every mod has had its turn at the class.
function M.countActions(part, counters)
    local h = M.addHandler(part, "OnGameStart", function()
        local missing = 0
        for i = 1, #counters do
            if not M.countAction(part, counters[i][1], counters[i][2]) then missing = missing + 1 end
        end
        if missing == 0 then
            M.status(part, true, #counters .. " action(s) tracked")
        else
            M.status(part, false, missing .. " of " .. #counters .. " action(s) absent on this build", "dep")
        end
    end)
    if h ~= nil then M.status(part, nil, "checked when you load a world", "pending") end
end

-- getAnimalType() returns the growth STAGE, which encodes species, sex and age together, so the
-- farm animals alone would fill twelve slots in a set meant to hold species. An unlisted type is
-- left as itself, so a modded animal still counts as something.
local ANIMAL_SPECIES = {
    chick = "chicken", cockerel = "chicken", hen = "chicken",
    bull = "cow", cow = "cow", cowcalf = "cow",
    buck = "deer", doe = "deer", fawn = "deer",
    mouse = "mouse", mousefemale = "mouse", mousepups = "mouse",
    boar = "pig", piglet = "pig", sow = "pig",
    rabbuck = "rabbit", rabdoe = "rabbit", rabkitten = "rabbit",
    raccoonboar = "raccoon", raccoonkit = "raccoon", raccoonsow = "raccoon",
    rat = "rat", ratbaby = "rat", ratfemale = "rat",
    ewe = "sheep", lamb = "sheep", ram = "sheep",
    gobblers = "turkey", turkeyhen = "turkey", turkeypoult = "turkey",
}

--- IsoAnimal and IsoDeadBody both expose getAnimalType(), so one accessor covers a petted
--- chicken and a butchered deer alike. Lives here because two trackers need the same answer.
function M.animalSpecies(obj)
    if obj == nil or obj.getAnimalType == nil then return nil end
    local ok, kind = pcall(function() return obj:getAnimalType() end)
    if not ok or type(kind) ~= "string" or kind == "" then return nil end
    return ANIMAL_SPECIES[string.lower(kind)] or kind
end

M.status("Core", true)
