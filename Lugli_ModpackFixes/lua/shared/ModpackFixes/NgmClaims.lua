--[[
Nick's Generator Manager in multiplayer: the server applies a claim only from a player who could
manage that generator.

What happens today. Manage Power sends the server "claim" (these objects are paid for by that
generator), "auto" (drop their claim) and "register" (a generator stands here). The server applies
all three as sent (NGM_Server.lua:277-288): any player, from anywhere, can move the cost of any
appliance onto any generator, including one inside another player's safehouse, so its fuel burns
for someone else's fridge, or drop the claims that base set. A "register" for a square where no
generator stands still starts a pass over every generator.

What this part changes. Before Nick's handler runs, the server keeps only what the sender may do:
- claim: the generator stands there, the player is inside its power range, the generator is not
  in a safehouse the player is not allowed in, and each object is in that range and not in such
  a safehouse;
- auto: each object is not in such a safehouse, and the player could manage the generator its
  claim names;
- register: a generator stands there and the player could manage it.
"Allowed in a safehouse" is the game's own rule (its owner, its members, and staff whose role can
enter safehouses). What is left goes to Nick's handler unchanged; a command left with nothing is
not applied. Single player has no such commands and is not affected. The Manage Power window of
the ngm-manage part shows the same rule: rows and buttons the server would refuse are greyed out,
with the reason under its title.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

local MODULE = "NicksGeneratorManager"
local LOG_EVERY_MS = 60000

local function squareOf(player)
    return math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
end

-- The game's safehouse rule for one square: nil when the player may act there, else the reason.
function M.ngmSafehouseBlocks(player, sq)
    if sq == nil then return nil end
    local sh = SafeHouse.getSafeHouse(sq)
    if sh ~= nil and not sh:playerAllowed(player) then return "safehouse" end
    return nil
end

-- nil when the player may manage the generator at gx, gy, gz, else "far" or "safehouse".
function M.ngmManageBlocks(player, gx, gy, gz)
    local NGM = NicksGeneratorManager
    local px, py, pz = squareOf(player)
    if not NGM.inRange(NGM.geom(), gx, gy, gz, px, py, pz) then return "far" end
    return M.ngmSafehouseBlocks(player, getSquare(gx, gy, gz))
end

-- True when this game is a client of a server that enforces the rule.
function M.ngmClaimsEnforced()
    local def
    for i = 1, #M.defs do
        if M.defs[i].name == "ngm-claims" then def = M.defs[i] end
    end
    return def ~= nil and M.isMultiplayerClient() and M.isModActive(MODULE) and M.readSwitch(def)
end

local function install(ctx)
    local NGM
    local refused, refusedFrom, lastLog = 0, {}, 0

    local function needNgm()
        NGM = NicksGeneratorManager
        for _, key in ipairs({ "inRange", "geom", "findObject", "getOwnerPref" }) do
            if type(NGM) ~= "table" or type(NGM[key]) ~= "function" then
                error("Nick's Generator Manager has no " .. key)
            end
        end
    end

    local function generatorAt(x, y, z)
        local sq = getSquare(x, y, z)
        return sq ~= nil and sq:getGenerator() ~= nil
    end

    local function objectOf(spec)
        if type(spec) ~= "table" or type(spec.x) ~= "number" or type(spec.y) ~= "number"
            or type(spec.z) ~= "number" or type(spec.index) ~= "number" then
            return nil
        end
        local sq = getSquare(spec.x, spec.y, spec.z)
        return sq ~= nil and NGM.findObject(sq, spec.index) or nil, sq
    end

    local function note(player, dropped, total)
        if dropped == 0 then return end
        refused = refused + dropped
        refusedFrom[tostring(player:getUsername())] = true
        local now = getTimestampMs()
        if now - lastLog < LOG_EVERY_MS then return end
        lastLog = now
        local names = {}
        for name in pairs(refusedFrom) do names[#names + 1] = name end
        table.sort(names)
        M.log("ngm-claims: refused " .. refused .. " object(s) from " .. table.concat(names, ", ")
            .. " (latest " .. dropped .. " of " .. total .. ")")
        refused, refusedFrom = 0, {}
    end

    -- allowed(obj, sq) answers true to keep, false to refuse, or "skip" for an object the
    -- command would not change (a return of an object with no claim), dropped without a refusal.
    local function keep(player, specs, allowed)
        local kept, skipped = {}, 0
        local total = type(specs) == "table" and #specs or 0
        for i = 1, total do
            local obj, sq = objectOf(specs[i])
            local verdict = obj ~= nil and M.ngmSafehouseBlocks(player, sq) == nil and allowed(obj, sq)
            if verdict == "skip" then skipped = skipped + 1
            elseif verdict then kept[#kept + 1] = specs[i] end
        end
        note(player, total - skipped - #kept, total)
        return kept
    end

    local function filterClaim(player, args)
        local gx, gy, gz = args.gx, args.gy, args.gz
        if type(gx) ~= "number" or type(gy) ~= "number" or type(gz) ~= "number"
            or not generatorAt(gx, gy, gz) or M.ngmManageBlocks(player, gx, gy, gz) ~= nil then
            note(player, type(args.objs) == "table" and #args.objs or 0, type(args.objs) == "table" and #args.objs or 0)
            args.objs, args.gx = {}, nil
            return
        end
        local g = NGM.geom()
        args.objs = keep(player, args.objs, function(_, sq)
            return NGM.inRange(g, gx, gy, gz, sq:getX(), sq:getY(), sq:getZ())
        end)
        if #args.objs == 0 then args.gx = nil end
    end

    local function filterReturn(player, args)
        args.objs = keep(player, args.objs, function(obj)
            local pref = NGM.getOwnerPref(obj)
            if pref == nil then return "skip" end
            return M.ngmManageBlocks(player, pref.gx, pref.gy, pref.gz) == nil
        end)
    end

    local function filterRegister(player, args)
        local gx, gy, gz = args.gx, args.gy, args.gz
        if type(gx) ~= "number" or type(gy) ~= "number" or type(gz) ~= "number"
            or not generatorAt(gx, gy, gz) or M.ngmManageBlocks(player, gx, gy, gz) ~= nil then
            args.gx = nil
        end
    end

    -- Registered while this mod's shared Lua loads, so it runs before Nick's server handler,
    -- which loads with the world.
    ctx.on("OnClientCommand", function(module, command, player, args)
        if module ~= MODULE or type(args) ~= "table" then return end
        if player == nil then
            args.gx, args.objs = nil, {}
            return
        end
        if NGM == nil then needNgm() end
        if command == "claim" then filterClaim(player, args)
        elseif command == "auto" then filterReturn(player, args)
        elseif command == "register" then filterRegister(player, args) end
    end)
end

M.addPart({
    name = "ngm-claims",
    switch = "NgmClaims",
    title = "Nick's Generator Manager: only players who could manage a generator change what it pays for",
    tip = "In multiplayer, Nick's Generator Manager lets any player, from anywhere, make any generator pay for any appliance, also a generator inside someone else's safehouse. With this on, the server accepts a change only from a player inside that generator's power range, and not for a generator or appliance in a safehouse the player is not allowed in. Turn it off to let everyone manage every generator.",
    kind = "fix",
    all = { MODULE },
    side = "server",
    phase = "load",
    pins = { "ngm.command", "ngm.apply", "ngm.pref", "ngm.range" },
    install = install,
})
