--[[
    Config
]]

require "LugliEmergencyLights/Items"

LugliEmergencyLights = LugliEmergencyLights or {}
LugliEmergencyLights.parts = LugliEmergencyLights.parts or {}

local M = LugliEmergencyLights
local PART = "Config"

local cache = nil

local function typeOk(kind, v)
    if kind == "boolean" then return type(v) == "boolean" end
    return type(v) == "number"
end

local function readAll()
    local out = {}
    local vars = nil
    if SandboxVars ~= nil then
        local ok, t = pcall(function() return SandboxVars[M.SANDBOX_PAGE] end)
        if ok then vars = t end
    end
    local bad = 0
    for name, spec in pairs(M.SANDBOX) do
        local v = nil
        if vars ~= nil then
            local ok, got = pcall(function() return vars[name] end)
            if ok then v = got end
        end
        -- A present but wrong-shaped value is worse than a missing one: it reaches arithmetic
        -- and throws somewhere unrelated.
        if v ~= nil and not typeOk(spec.kind, v) then
            bad = bad + 1
            v = nil
        end
        if v == nil then v = spec.default end
        out[name] = v
    end
    if bad > 0 then
        M.log(PART, bad .. " sandbox value(s) had the wrong type, used the default")
    end
    return out
end

function M.config()
    if cache == nil then cache = readAll() end
    return cache
end

--- Re-read the sandbox and adopt anything that changed. Returns true when something did.
function M.configDrift()
    local out, n = nil, 0
    for name, spec in pairs(M.SANDBOX) do
        local v = M.cfg(name)
        if v ~= spec.default then
            n = n + 1
            local one = name .. "=" .. tostring(v) .. " (default " .. tostring(spec.default) .. ")"
            out = out == nil and one or (out .. ", " .. one)
        end
    end
    if n == 0 then return nil end
    return n, out
end

function M.refreshConfig()
    local fresh = readAll()
    if cache == nil then
        cache = fresh
        return true
    end

    local moved = false
    for name, v in pairs(fresh) do
        if cache[name] ~= v then moved = true break end
    end
    if not moved then return false end

    cache = fresh
    M.configGen = (M.configGen or 0) + 1
    return true
end

function M.cfg(name)
    local spec = M.SANDBOX[name]
    if spec == nil then
        M.defect(PART, "unknown sandbox option: " .. tostring(name))
        return nil
    end
    local v = M.config()[name]
    if v == nil then return spec.default end
    return v
end

--- Drop the cache. Called at OnGameStart, the only point the answers can change.
M.configGen = 0

function M.resetConfig()
    cache = nil
    M.configGen = (M.configGen or 0) + 1
end

-- Derived reads, so no caller builds an option name by concatenation: a typo would be a silent
-- nil rather than a reported defect.

function M.burnHours(familyId)
    local v = M.cfg(tostring(familyId) .. "Hours")
    if type(v) ~= "number" or v <= 0 then
        local fam = M.FAMILIES[familyId]
        return fam ~= nil and fam.burnHours or 1.0
    end
    return v
end

function M.lightRadius(familyId)
    local v = M.cfg(tostring(familyId) .. "Radius")
    if type(v) ~= "number" or v < 1 then
        local fam = M.FAMILIES[familyId]
        v = fam ~= nil and fam.radius or 4
    end
    -- THE 20-TILE CAP IS THE LAMPPOST'S, NOT THE ENGINE'S.
    if M.uncappedRadius ~= true and v > 20 then return 20 end
    return v
end

--- How far past the point of impact this family carries, as a fraction of the throw's length.
function M.positive(name, fallback)
    local v = M.cfg(name)
    if type(v) ~= "number" or v ~= v or v <= 0 then return fallback end
    return v
end

--- Which way the air is moving, and how hard: wx, wy as a unit vector, and speed in kph.
function M.windVector()
    if getClimateManager == nil then return 0.0, 0.0, 0.0 end
    local ok, wx, wy, kph = pcall(function()
        local cm = getClimateManager()
        if cm == nil then return 0.0, 0.0, 0.0 end
        local rad = cm:getWindAngleRadians()
        rad = math.pi - (rad - math.pi * 0.75)
        return math.cos(rad), math.sin(rad), cm:getWindspeedKph()
    end)
    if not ok or type(wx) ~= "number" or type(kph) ~= "number" then return 0.0, 0.0, 0.0 end
    if kph ~= kph or kph < 0.0 then kph = 0.0 end
    return wx, wy, kph
end

--- How much the wind pushes this family about, 0 to 1. A property of the object: a 75 g plastic
--- tube tumbling through the air catches far more of it than a 150 g flare.
function M.windageFor(familyId)
    local fam = M.FAMILIES[familyId]
    if fam == nil or type(fam.windage) ~= "number" then return 0.0 end
    return fam.windage
end

--- How accurate a throw of this family is: one standard deviation of miss, in TILES, at the
--- family's maximum range.
function M.spreadFor(familyId)
    local fam = M.FAMILIES[familyId]
    if fam == nil or type(fam.spread) ~= "number" then return 0.0 end
    return fam.spread
end

--- Per-family base scaled by one multiplier, so families keep their relative feel.
function M.throwRange(familyId)
    local fam = M.FAMILIES[familyId]
    local base = fam ~= nil and fam.throwRange or 6.0
    local mult = M.cfg("ThrowRangeMult")
    if type(mult) ~= "number" or mult <= 0 then mult = 1.0 end
    return base * mult
end

M.status(PART, true)
