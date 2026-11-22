--[[
    Doors
    A Locksmith picks a locked building door: the rule (who, which door, what tool, how long, the
    odds) and the authority's answer to it (claim, release, submit, the roll, the unlock).

    VANILLA HAS NO DOOR PICK, only the crowbar (ISForceOpen.lua, where a Burglar halves the fail
    chance), so this is the Locksmith's alone; a Burglar keeps hotwiring and forcing. It unlocks
    and never locks. The numbers are the lockbox pick's, through Gates' own tool, odds and time
    (findRouteTool, routeChance, routeTimeFactor): Neat Lockpicking's picks, a paperclip or a
    screwdriver, the Locksmith's and Dextrous' time, Nimble and Lockpicking odds, a failed try
    using up the pick or wearing a store lockpick (spendPick), and no jam.

    WHICH DOOR. An IsoDoor, or an IsoThumpable that is a door, closed and locked, as vanilla's
    force menu judges it (ISWorldObjectContextMenuLogic.canPlayerForceDoor): never force-locked,
    never from inside its own room (from there vanilla unlocks it by hand), and only within
    vanilla's own reach of the side the survivor stands on (IsoGridSquare.isWithinReachOfCharacter
    reads GridSquareEdgeElement.getSquareFacingCharacter). Never a padlocked thumpable or an admin's
    CustomLock: clearing the key lock would not open either. Never a safehouse the survivor is not
    allowed in (SafeHouse.getSafeHouse, playerAllowed), on either side of the door.

    THE UNLOCK IS VANILLA'S (ISLockDoor:complete): setLockedByKey(false), which also clears the
    lock itself, then syncIsoObject(false, 0, nil, nil) on the door and every double or garage door
    partner (IsoDoor.getDoubleDoorObject, getGarageDoorPrev/Next, as buildUtil walks them).
    setLockedByKey never syncs on a server (IsoDoor.java:1847, IsoThumpable.java:2472), and the
    explicit syncIsoObject is what sends SyncIsoObject to the clients; in single player both are
    no-ops past the field writes.

    SHARED, NOT SERVER: single player's client calls the authority directly, as World.lua's does,
    and the rule and its enforcement stay one file so the menu and the authority cannot disagree.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Gates"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "DoorPick"

    -- The wire, apart from the boxes' module so World.lua and Actions.lua never see it.
    M.DOOR_MODULE = "LugliDMSDoor"
    M.DOOR_CLAIM = "claim"
    M.DOOR_RELEASE = "release"
    M.DOOR_SUBMIT = "submit"
    M.DOOR_RESULT = "result"

    M.REASON_DOOR_LOCKSMITH = "IGUI_LugliDMS_DoorNeedsLocksmith"
    M.REASON_DOOR_NOT_LOCKED = "IGUI_LugliDMS_DoorNotLocked"
    M.REASON_DOOR_SAFEHOUSE = "IGUI_LugliDMS_DoorSafehouse"

    -- Between two commands from one survivor, and the share of the pick a submit must come back
    -- after, both as World.lua's (RATE_MS, SUBMIT_FLOOR), kept here so neither file waits on the other.
    M.DOOR_RATE_MS = 200
    M.DOOR_SUBMIT_FLOOR = 0.7

    local function call(obj, method, ...)
        local fn = obj ~= nil and obj[method] or nil
        if fn == nil then return nil end
        local ok, v = pcall(fn, obj, ...)
        if ok then return v end
        return nil
    end

    local function hasLocksmith(player)
        if CharacterTrait == nil then return false end
        local ok, trait = pcall(function() return CharacterTrait.get(ResourceLocation.of(M.LOCKSMITH_TRAIT)) end)
        if not ok or trait == nil then return false end
        local okH, v = pcall(function() return player:hasTrait(trait) end)
        return okH and v == true
    end

    local function isDoor(obj)
        if obj == nil or instanceof == nil then return false end
        if instanceof(obj, "IsoDoor") then return true end
        return instanceof(obj, "IsoThumpable") and call(obj, "isDoor") == true
    end

    --- A door this mod picks: closed, locked by its lock or its key, and nothing else holding it.
    function M.pickableDoor(obj)
        if not isDoor(obj) then return false end
        if call(obj, "IsOpen") == true then return false end
        if call(obj, "isLocked") ~= true and call(obj, "isLockedByKey") ~= true then return false end
        if call(obj, "isForceLocked") == true then return false end
        if instanceof(obj, "IsoThumpable") and call(obj, "isLockedByPadlock") == true then return false end
        if call(obj, "hasModData") == true then
            local md = call(obj, "getModData")
            if type(md) == "table" and md.CustomLock == true then return false end
        end
        return true
    end

    --- Every double door leaf and garage door section that moves with this door, itself excluded.
    function M.doorPartners(door)
        local out, seen = {}, { [door] = true }
        local function add(o)
            if o ~= nil and not seen[o] then
                seen[o] = true
                out[#out + 1] = o
            end
        end
        if IsoDoor == nil then return out end
        for i = 1, 4 do
            local ok, o = pcall(IsoDoor.getDoubleDoorObject, door, i)
            if ok then add(o) end
        end
        local okI, index = pcall(IsoDoor.getGarageDoorIndex, door)
        if okI and index ~= nil and index ~= -1 then
            for _, step in ipairs({ IsoDoor.getGarageDoorPrev, IsoDoor.getGarageDoorNext }) do
                local okS, o = pcall(step, door)
                while okS and o ~= nil and not seen[o] do
                    add(o)
                    okS, o = pcall(step, o)
                end
            end
        end
        return out
    end

    local function lockedOut(player, square)
        if square == nil or SafeHouse == nil then return false end
        local ok, safe = pcall(SafeHouse.getSafeHouse, square)
        if not ok or safe == nil then return false end
        local okA, allowed = pcall(function() return safe:playerAllowed(player) end)
        return not (okA and allowed == true)
    end

    -- Before 42.22 the engine has no edge-reach helpers: the door's own square stands in for the
    -- side the survivor faces.
    local function within(player, door)
        if IsoGridSquare == nil then return false end
        if IsoGridSquare.isWithinReachOfCharacter ~= nil then
            local ok, v = pcall(IsoGridSquare.isWithinReachOfCharacter, player, door)
            return ok and v == true
        end
        local at, sq = call(player, "getCurrentSquare"), call(door, "getSquare")
        return at ~= nil and sq ~= nil and call(sq, "isAdjacentTo", at) == true
    end

    local function sameRoom(player, door)
        if IsoGridSquare == nil then return false end
        if IsoGridSquare.isCharacterInSameRoom ~= nil then
            local ok, v = pcall(IsoGridSquare.isCharacterInSameRoom, player, door)
            return ok and v == true
        end
        local at, sq = call(player, "getCurrentSquare"), call(door, "getSquare")
        local room = at ~= nil and call(at, "getRoom") or nil
        return room ~= nil and sq ~= nil and call(sq, "getRoom") == room
    end

    local function refuse(reason, offered)
        return { ok = false, offered = offered == true, reason = reason }
    end

    --- What picking this door costs this survivor, or why not. offered: the menu lists it (a
    --- Locksmith outside a pickable door); reach: the survivor must already be within reach.
    function M.doorPickCheck(player, door, reach)
        if player == nil or door == nil then return refuse("IGUI_LugliDMS_Gone") end
        if not hasLocksmith(player) then return refuse(M.REASON_DOOR_LOCKSMITH) end
        if not M.pickableDoor(door) then return refuse(M.REASON_DOOR_NOT_LOCKED) end
        if sameRoom(player, door) then return refuse(M.REASON_DOOR_NOT_LOCKED) end
        if lockedOut(player, call(door, "getSquare")) or lockedOut(player, call(door, "getOppositeSquare")) then
            return refuse(M.REASON_DOOR_SAFEHOUSE, true)
        end
        if reach and not within(player, door) then return refuse("IGUI_LugliDMS_TooFar", true) end
        local def = M.ROUTES.pick
        local tool = M.findRouteTool(player, "pick")
        if tool == nil then return refuse(M.REASON_NO_TOOL, true) end
        local seconds = def.seconds * M.routeTimeFactor(player, "pick") * (M.finite(M.cfg("TimeScale")) or 1)
        local noise = math.floor(def.noise * (M.finite(M.cfg("NoiseScale")) or 1) + 0.5)
        return { ok = true, offered = true, tool = tool, chance = M.routeChance(player, "pick", tool),
            seconds = seconds, noise = noise, spends = M.spendKind(def, tool), xp = def.xp, skill = def.skill }
    end

    --- The first door among the clicked objects, else on their squares, that the menu could offer.
    function M.doorAmong(worldObjects)
        if type(worldObjects) ~= "table" then return nil end
        for _, obj in ipairs(worldObjects) do
            if M.pickableDoor(obj) then return obj end
        end
        local seen = {}
        for _, obj in ipairs(worldObjects) do
            local sq = call(obj, "getSquare")
            if sq ~= nil and not seen[sq] then
                seen[sq] = true
                local list = sq:getObjects()
                for i = 0, list:size() - 1 do
                    local o = list:get(i)
                    if M.pickableDoor(o) then return o end
                end
            end
        end
        return nil
    end

    --- Where a door is on the wire: its square and its index there, and the id answers name it by.
    function M.doorArgs(door)
        local sq = call(door, "getSquare")
        if sq == nil then return nil end
        local i = call(sq:getObjects(), "indexOf", door)
        if type(i) ~= "number" or i < 0 then return nil end
        local x, y, z = sq:getX(), sq:getY(), sq:getZ()
        return { x = x, y = y, z = z, i = i }, x .. "," .. y .. "," .. z .. "," .. i
    end

    --- The survivor knows the door and its partners are no longer locked, as vanilla's admin unlock
    --- records it (AdminContextMenu.OnDoorLock) for pathfinding.
    function M.doorPickLearn(player, door)
        local mk = call(player, "getMapKnowledge")
        if mk == nil then return end
        local doors = M.doorPartners(door)
        table.insert(doors, 1, door)
        for _, d in ipairs(doors) do pcall(function() mk:setKnownBlockedDoor(d, false) end) end
    end

    -- ---- the authority -------------------------------------------------------------------------

    local claims = {}
    local lastAt = {}

    local function now()
        return getTimestampMs ~= nil and getTimestampMs() or 0
    end

    local function nameOf(player)
        if M.isMultiplayer() then
            local n = call(player, "getUsername")
            if type(n) == "string" then return n end
        end
        return "local"
    end

    local function reply(player, args)
        if M.isMultiplayer() then
            if sendServerCommand ~= nil then sendServerCommand(player, M.DOOR_MODULE, M.DOOR_RESULT, args) end
        elseif M.doorPickReply ~= nil then
            M.doorPickReply(args)
        end
    end

    local function doorAt(args)
        if type(args) ~= "table" or getCell == nil then return nil end
        local x, y, z, i = M.finite(args.x), M.finite(args.y), M.finite(args.z), M.finite(args.i)
        if x == nil or y == nil or z == nil or i == nil then return nil end
        local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
        if sq == nil then return nil end
        local list = sq:getObjects()
        i = math.floor(i)
        if i < 0 or i >= list:size() then return nil end
        local door = list:get(i)
        if not isDoor(door) then return nil end
        return door
    end

    --- The answer names the door as the request did, so the asker finds its own action by it.
    local function answer(player, args, outcome, extra)
        local out = { outcome = outcome }
        for k, v in pairs(extra or {}) do out[k] = v end
        if type(args) == "table" then
            out.id = tostring(args.x) .. "," .. tostring(args.y) .. "," .. tostring(args.z) .. "," .. tostring(args.i)
        end
        reply(player, out)
    end

    local function unlock(door)
        local doors = M.doorPartners(door)
        table.insert(doors, 1, door)
        for _, d in ipairs(doors) do
            d:setLockedByKey(false)
            d:syncIsoObject(false, 0, nil, nil)
        end
    end

    local function floorExempt(player)
        if not M.isMultiplayer() then return true end
        return call(player, "isTimedActionInstant") == true
    end

    local function claim(player, args, who)
        local door = doorAt(args)
        if door == nil then return answer(player, args, "refused", { reason = "IGUI_LugliDMS_Gone" }) end
        local _, id = M.doorArgs(door)
        local check = M.doorPickCheck(player, door, true)
        if not check.ok then return answer(player, args, "refused", { reason = check.reason }) end
        claims[who] = { id = id, at = now(), seconds = check.seconds }
    end

    local function release(player, args, who)
        local door = doorAt(args)
        local held = claims[who]
        if held == nil or door == nil then return end
        local _, id = M.doorArgs(door)
        if held.id == id then claims[who] = nil end
    end

    local function submit(player, args, who)
        local door = doorAt(args)
        if door == nil then return answer(player, args, "refused", { reason = "IGUI_LugliDMS_Gone" }) end
        local _, id = M.doorArgs(door)
        local held = claims[who]
        if held == nil or held.id ~= id then
            return answer(player, args, "refused", { reason = "IGUI_LugliDMS_NotClaimed" })
        end
        claims[who] = nil
        if not floorExempt(player) and (now() - held.at) / 1000 < held.seconds * M.DOOR_SUBMIT_FLOOR then
            return answer(player, args, "refused", { reason = "IGUI_LugliDMS_TooSoon" })
        end
        -- Everything again from this survivor as it is now: the trait, the tool, the reach, the lock.
        local recheck = M.doorPickCheck(player, door, true)
        if not recheck.ok then return answer(player, args, "refused", { reason = recheck.reason }) end
        local sq = door:getSquare()
        if recheck.noise > 0 and addSound ~= nil then
            pcall(addSound, player, sq:getX(), sq:getY(), sq:getZ(), recheck.noise, recheck.noise)
        end
        if ZombRand(1000) >= recheck.chance * 1000 then
            M.spendPick(recheck.tool, recheck.spends)
            if recheck.skill ~= nil then M.grantXp(player, recheck.skill.perk, recheck.skill.failed) end
            M.debug(PART, nameOf(player) .. " failed to pick the door at " .. id)
            return answer(player, args, "failed", { spent = recheck.spends })
        end
        unlock(door)
        M.grantXp(player, recheck.xp.perk, recheck.xp.amount)
        if recheck.skill ~= nil then M.grantXp(player, recheck.skill.perk, recheck.skill.opened) end
        M.debug(PART, nameOf(player) .. " picked the door at " .. id)
        answer(player, args, "opened")
    end

    local HANDLERS = { [M.DOOR_CLAIM] = claim, [M.DOOR_RELEASE] = release, [M.DOOR_SUBMIT] = submit }

    --- Every door pick request, from the wire or (single player) straight from the client.
    function M.doorPickServe(player, command, args)
        local fn = HANDLERS[command]
        if fn == nil or player == nil then return end
        local who = nameOf(player)
        local t = now()
        if lastAt[who] ~= nil and t - lastAt[who] < M.DOOR_RATE_MS and command ~= M.DOOR_RELEASE then
            return answer(player, args, "refused", { reason = "IGUI_LugliDMS_Wait" })
        end
        lastAt[who] = t
        fn(player, args, who)
    end

    --- Forget every claim and every rate stamp older than a minute; all of it when `all`.
    function M.doorPickSweep(all)
        local t = now()
        for who, held in pairs(claims) do
            if all or t - held.at > (held.seconds * 2 + 30) * 1000 then claims[who] = nil end
        end
        for who, at in pairs(lastAt) do
            if all or t - at > 60000 then lastAt[who] = nil end
        end
    end
end
