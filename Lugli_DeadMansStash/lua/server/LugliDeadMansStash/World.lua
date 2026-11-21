--[[
    World
    The authority's side of every route: the wire handler, the claim clock, validation, and the
    one place a gate is opened (payout, noise, tool wear, XP, salvage).

    REBUILD, NEVER FORWARD (docs/13). A client sends only which gate and which route. The square,
    the tool, the traits and perks, the reach and the elapsed time all come from the authority's
    own view of that player, so a modified client can ask for anything and still get only what
    its survivor could do.

    THE CLAIM IS THE CLOCK. A route starts with a claim and ends with a submit; the authority
    refuses a submit that comes back sooner than the route takes, and a second survivor starting a
    gate somebody else is working on. Putting the work down records how far it got on the gate's
    store record, measured on the authority's clock, so a half-pried crate stays half pried. While
    a claim lasts the work is heard every WORK_NOISE_MS; a claim whose holder died, left, or stood
    out of reach for CLAIM_AWAY_MS is dropped for nothing, so the gate is free at once.

    THE GATE IS ITS STORE RECORD (Gating.lua). Every check and every write below goes to the
    record; the object's tag is only re-mirrored from it, and healed when a client forged it.

    A ROUTE WITH A CHANCE IS ROLLED HERE, at submit. A failed roll is outcome "failed": nothing
    paid, the gate still sealed, that route's progress gone, and a lock that jams jammed for good.
    A key route matches only the key id on the gate's record (Keys.lua), never "any key".

    THE SAFES (docs/31 section 8) answer every submit with a NET_RESULT of their own outcome. A
    code is right (opened) or wrong (wrong, triesLeft), never per digit; the SafeTries-th wrong
    one is a lockout: a dial for half of SafeLockoutHours and quiet, a keypad for all of it and,
    with SafeAlarm, the alarm. The manipulation reveals one seeded digit a success (revealed),
    a miss is slipped, and a success with MANIPULATE_OPENS_AT found opens the dial. A drill wears
    on every session and a torch spends the fuel of the work each session did; both keep their
    progress, and a torch burns paper, money and food in the haul before the clients see it. A
    tool left alone cools for the time away: a drill keeps a share of its heat, a seam left near
    the contents earns that time's cooling (Gates.workResume). A bypass spends
    its scrap whatever the roll, and a miss is the alarm and a lockout (failed). A battery powers
    the keypad for good (powered). The rests in the work (Gates.WORK_CHOICES) ride on the submit
    and the release as `rests`: a finishing drill that ran red past its grace wears once more, a
    cooled seam burns at lower odds, and a rest is never credited as progress. The tag is
    re-mirrored after every answer, so tries left,
    the lockout, the found digits and the power are on the object between replies. The code
    never leaves the store.

    In single player sendClientCommand is broken (docs/13), so the client calls
    M.serverRequest directly and the reply comes back through M.onReply.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Gates"
require "LugliDeadMansStash/Codes"
require "LugliDeadMansStash/Gating"
require "LugliDeadMansStash/Payout"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "World"

    -- Tiles from the survivor to the gate's square centre, on the same floor.
    M.REACH = 2.5
    -- A submit is honoured once the claim is this share of the route old. The client's action
    -- runs 48 * multiplierBias units a second (GameTime.getTimeDeltaFromMultiplier, 42.22.2) and
    -- the sandbox speed sets the bias as high as 1.2, so honest work lasts 0.83 of nominal at the
    -- fastest speed; 0.7 leaves room for the network hop between claim and submit.
    -- Single player and an instant-action survivor skip it: fast-forward and the cheat shorten
    -- honest work, and with one survivor there is nobody to defend (PowerGrid Repair.lua precedent).
    M.SUBMIT_FLOOR = 0.7
    -- Between two commands from one survivor.
    M.RATE_MS = 200
    -- What the claw salvages: nails, more with the trade.
    M.CLAW_NAILS = { min = 2, max = 4 }
    -- A client's tag write (ObjectModDataPacket) and its command travel on different streams
    -- (PacketTypes.java:509-510), so a forged tag can land after the request whose touch would
    -- have put it right. Every gate a request names is mirrored again this long after it.
    M.RESYNC_MS = 1000
    -- A safe's alarm: heard ALARM_RADIUS tiles out, once every ALARM_EVERY_MS for ALARM_MS.
    M.ALARM_RADIUS = 40
    M.ALARM_EVERY_MS = 5000
    M.ALARM_MS = 30000
    -- The manipulation finds at most this many digits; a success with them found opens the dial.
    M.MANIPULATE_OPENS_AT = 2
    -- A code submit without a 4-digit code.
    M.REASON_NO_ROUTE = "IGUI_LugliDMS_NoRoute"
    -- What a torch burns besides food and paper (Literature).
    M.BURN_TYPES = { ["Base.Money"] = true, ["Base.MoneyBundle"] = true }
    -- Between two resends for one survivor, apart from the routes' limit so a resend never makes
    -- a claim come back busy. The client asks at most once a second.
    M.RESEND_RATE_MS = 500
    -- Work under way is heard at its route's noise this often, between the claim and the outcome.
    M.WORK_NOISE_MS = 4000
    -- A claim's holder out of reach this long has stopped working: the claim is dropped.
    M.CLAIM_AWAY_MS = 3000
    -- The shortest lockout, one game minute, whatever SafeLockoutHours says.
    M.LOCKOUT_FLOOR_HOURS = 1 / 60

    local claims = {}
    local lastAt = {}
    local resentAt = {}
    local resync = {}
    local alarms = {}

    local function now()
        return getTimestampMs ~= nil and getTimestampMs() or 0
    end

    local function nameOf(player)
        if M.isMultiplayer() then
            local ok, n = pcall(function() return player:getUsername() end)
            if ok and type(n) == "string" then return n end
        end
        return "local"
    end

    function M.reply(player, command, args)
        if M.isMultiplayer() then
            sendServerCommand(player, M.NET_MODULE, command, args)
        elseif M.onReply ~= nil then
            M.onReply(command, args)
        end
    end

    local function intArg(v)
        v = M.finite(v)
        if v == nil then return nil end
        return math.floor(v)
    end

    --- Is the survivor within M.REACH of the centre of square x,y on floor z?
    local function inReach(player, x, y, z)
        local dx, dy = player:getX() - (x + 0.5), player:getY() - (y + 0.5)
        return math.floor(player:getZ()) == z and dx * dx + dy * dy <= M.REACH * M.REACH
    end

    --- The gate a request names, if it exists, wherever the survivor is. nil plus a reason.
    local function locate(args)
        if type(args) ~= "table" then return nil, "IGUI_LugliDMS_Gone" end
        local x, y, z, i = intArg(args.x), intArg(args.y), intArg(args.z), intArg(args.i)
        if x == nil or y == nil or z == nil or i == nil then return nil, "IGUI_LugliDMS_Gone" end
        local obj, container, md = M.gateAt(x, y, z, i)
        if obj == nil then return nil, "IGUI_LugliDMS_Gone" end
        M.syncMirror(obj, md)
        if M.isMultiplayer() then
            resync[M.gateId(x, y, z, i)] = { x = x, y = y, z = z, i = i, at = now() + M.RESYNC_MS }
        end
        return { obj = obj, container = container, md = md, id = M.gateId(x, y, z, i), x = x, y = y, z = z,
            square = obj:getSquare() }
    end

    --- The gate a request names, if it exists and the survivor can reach it. nil plus a reason.
    local function resolve(player, args)
        local gate, why = locate(args)
        if gate == nil then return nil, why end
        if not inReach(player, gate.x, gate.y, gate.z) then return nil, "IGUI_LugliDMS_TooFar" end
        return gate
    end

    local function noise(player, gate, radius)
        local r = math.floor(radius + 0.5)
        if r <= 0 or addSound == nil then return end
        addSound(player, gate.x, gate.y, gate.z, r, r)
    end

    local function wear(player, tool)
        if tool == nil or tool.damageCheck == nil then return end
        local ok = pcall(function() tool:damageCheck(0, 1.0, true, true, player) end)
        if ok and M.isMultiplayer() then
            pcall(function() tool:syncItemFields() end)
        end
    end

    local function grantXp(player, xp)
        if type(xp) ~= "table" then return end
        M.grantXp(player, xp.perk, xp.amount)
    end

    --- A route's XP in another perk (the pick's Lockpicking, with Neat Lockpicking), opened or failed.
    local function grantSkill(player, route, opened)
        local skill = route ~= nil and route.skill or nil
        if type(skill) ~= "table" then return end
        M.grantXp(player, skill.perk, opened and skill.opened or skill.failed)
    end

    local function salvage(player, routeId)
        if routeId ~= "claw" then return end
        local inv = player:getInventory()
        local n = ZombRand(M.CLAW_NAILS.min, M.CLAW_NAILS.max + 1)
        if M.isCarpenter ~= nil and M.isCarpenter(player) then n = M.CLAW_NAILS.max end
        for _ = 1, n do
            local item = inv:AddItem("Base.Nails")
            if item ~= nil and M.isMultiplayer() then sendAddItemToContainer(inv, item) end
        end
    end

    --- A stash box shows its lid off once open. setSprite plus transmitUpdatedSpriteToClients is
    --- the engine's own sprite-change path (docs/28); anything not one of our sealed boxes stays.
    local function showOpened(obj)
        local want = M.openedSpriteOf(M.liveSpriteName(obj))
        if want == nil or getSprite == nil then return end
        local sprite = getSprite(want)
        if sprite == nil then return end
        obj:setSprite(sprite)
        if M.isMultiplayer() then obj:transmitUpdatedSpriteToClients() end
    end

    --- The payout's damage level for a route: the sandbox's BruteDamage for full brute force, the
    --- light profile for light brute force unless BruteDamage is Off (1), 1 for a careful route.
    local function damageLevel(route)
        if route == nil then return 1 end
        local level = M.cfg("BruteDamage")
        if route.damage then return level end
        if route.brute == "light" and level > 1 then return M.BRUTE_LIGHT end
        return 1
    end

    --- Paper, money and food: what a torch can set alight.
    local function burnable(item)
        if instanceof(item, "Food") or instanceof(item, "Literature") then return true end
        local ok, full = pcall(function() return item:getFullType() end)
        return ok and M.BURN_TYPES[full] == true
    end

    --- A TORCH SCORCHES THE HAUL: each burnable item burns at `chance`, before the clients are
    --- sent the container. Returns how many burnt.
    local function burnHaul(container, chance)
        local items = container:getItems()
        local doomed = {}
        for k = 0, items:size() - 1 do
            local item = items:get(k)
            if burnable(item) and ZombRand(1000) < chance * 1000 then doomed[#doomed + 1] = item end
        end
        for k = 1, #doomed do container:Remove(doomed[k]) end
        return #doomed
    end

    --- OPEN A GATE. The one place a payout is rolled.
    function M.openGate(player, gate, routeId, route)
        local md = gate.md
        if md.state ~= "sealed" then return nil end
        md.state = "opened"
        md.by = routeId
        md.progress = {}
        local result = M.payout(gate.container, md, damageLevel(route)) or { added = 0, broken = 0 }
        result.burnt = 0
        local burn = route ~= nil and M.finite(route.burn) or 0
        if burn > 0 then
            result.burnt = burnHaul(gate.container, burn)
            result.added = math.max(0, result.added - result.burnt)
        end
        showOpened(gate.obj)
        M.syncMirror(gate.obj, md)
        if M.isMultiplayer() and sendItemsInContainer ~= nil then
            sendItemsInContainer(gate.obj, gate.container)
            -- Every other survivor's loot window still draws the lock until it next refreshes.
            sendServerCommand(M.NET_MODULE, M.NET_OPENED, { gateId = gate.id })
        end
        if route ~= nil then
            noise(player, gate, route.noise)
            if route.wear then wear(player, route.tool) end
            grantXp(player, route.xp)
            grantSkill(player, route, true)
        end
        salvage(player, routeId)
        M.debug(PART, nameOf(player) .. " opened " .. gate.id .. " by " .. tostring(routeId) .. ": "
            .. tostring(result.added) .. " item(s), " .. tostring(result.broken) .. " broken")
        return result
    end

    local function refuse(player, gate, reason)
        M.reply(player, M.NET_RESULT, { gateId = gate and gate.id or nil, outcome = "refused", reason = reason })
    end

    -- FAIL CLOSED. Gates.route with no key id is the client's question, "any key the mod
    -- minted"; the authority always passes the record's own id, and a record with none passes an
    -- id no key carries, so it opens to no key at all.
    M.NO_KEY_ID = 0

    --- Does the authority's roll open it? A route without a chance always does.
    local function rolled(chance)
        chance = M.finite(chance) or 1
        if chance >= 1 then return true end
        return ZombRand(1000) < chance * 1000
    end

    -- The gate's own square answers for a keypad's grid power.
    local function routeFor(player, md, routeId, square)
        return M.route(player, md, routeId, md.keyId or M.NO_KEY_ID, square)
    end

    -- ---- the alarm ---------------------------------------------------------------------------------

    --- Tell every client near x,y,z, so each plays the vanilla HouseAlarm there for its length.
    local function tellAlarm(x, y, z)
        local args = { x = x, y = y, z = z }
        if not M.isMultiplayer() then
            if M.onReply ~= nil then M.onReply(M.NET_ALARM, args) end
            return
        end
        local r2 = M.ALARM_RADIUS * M.ALARM_RADIUS
        M.forEachWorldPlayer(function(p)
            local dx, dy = p:getX() - (x + 0.5), p:getY() - (y + 0.5)
            if dx * dx + dy * dy <= r2 then sendServerCommand(p, M.NET_MODULE, M.NET_ALARM, args) end
        end)
    end

    local function alarmSound(a)
        if addSound ~= nil then addSound(nil, a.x, a.y, a.z, M.ALARM_RADIUS, M.ALARM_RADIUS) end
    end

    --- A SAFE'S ALARM at x,y,z: a world sound now and every ALARM_EVERY_MS until ALARM_MS, with no
    --- source, since whoever tripped it may be long gone, and the clients near it told once.
    --- Not doAlarm, which needs the building's alarm flag and grid power.
    function M.soundAlarm(x, y, z)
        local t = now()
        local a = { x = x, y = y, z = z, at = t + M.ALARM_EVERY_MS, ends = t + M.ALARM_MS }
        alarmSound(a)
        alarms[#alarms + 1] = a
        tellAlarm(x, y, z)
    end

    local function tickAlarms()
        local t = now()
        for k = #alarms, 1, -1 do
            local a = alarms[k]
            if a.at >= a.ends then
                table.remove(alarms, k)
            elseif t >= a.at then
                a.at = a.at + M.ALARM_EVERY_MS
                alarmSound(a)
            end
        end
    end

    -- ---- the safes -------------------------------------------------------------------------------

    --- Lock a safe out for `hours` game hours from now, never under LOCKOUT_FLOOR_HOURS, so even
    --- SafeLockoutHours 0 cannot be brute-forced back to back; its wrong tries start over. Returns
    --- the world-age hour it ends.
    local function lockOut(rec, hours)
        rec.tries = 0
        rec.lockedUntil = (M.worldHours() or 0) + math.max(M.LOCKOUT_FLOOR_HOURS, M.finite(hours) or 0)
        return rec.lockedUntil
    end

    local function isCode(code)
        return type(code) == "string" and string.find(code, "^%d%d%d%d$") ~= nil
    end

    --- The items a try used up, whatever its outcome: a bypass's scrap, a battery.
    local function spendConsumed(route)
        if type(route.consumes) ~= "table" then return end
        for k = 1, #route.consumes do
            local item = route.consumes[k]
            local container = item:getContainer()
            if container ~= nil then
                container:Remove(item)
                if M.isMultiplayer() then sendRemoveItemFromContainer(container, item) end
            end
        end
    end

    --- A torch session burns its fuel, `uses` uses of the tool.
    local function spendFuel(tool, uses)
        uses = math.floor(M.finite(uses) or 0)
        if tool == nil or uses <= 0 then return end
        for _ = 1, uses do
            local ok, left = pcall(function() return tool:getCurrentUses() end)
            if not ok or type(left) ~= "number" or left <= 0 then return end
            tool:UseAndSync()
        end
    end

    --- One more seeded digit the manipulation finds: a stable draw among the hidden positions.
    local function revealDigit(gate)
        local rec = gate.md
        if type(rec.code) ~= "string" then return false end
        if type(rec.revealed) ~= "table" then rec.revealed = {} end
        local hidden = {}
        for pos = 1, M.CODE_DIGITS do
            if rec.revealed[pos] == nil then hidden[#hidden + 1] = pos end
        end
        if #hidden == 0 then return false end
        local pos = hidden[1 + M.hash("reveal|" .. gate.id .. "|" .. tostring(M.store().salt) .. "|" .. #hidden) % #hidden]
        rec.revealed[pos] = string.sub(rec.code, pos, pos)
        return true
    end

    local function revealedCount(rec)
        local n = 0
        if type(rec.revealed) == "table" then
            for pos = 1, M.CODE_DIGITS do
                if rec.revealed[pos] ~= nil then n = n + 1 end
            end
        end
        return n
    end

    --- THE ANSWER IS HEARD NEARBY. The worker plays it on its own reply (Actions.lua); a client's
    --- character sounds reach no one else, so the players near the box are told what it sounded
    --- like (Sounds.lua), by name, never by anything about the box itself.
    local function relaySound(player, gate, args)
        if not M.isMultiplayer() then return end
        local names = M.outcomeSounds(args, gate.md.kind)
        if #names == 0 then return end
        local out = { x = gate.x, y = gate.y, z = gate.z, sounds = table.concat(names, ";") }
        local r2 = M.SOUND_RELAY_RANGE * M.SOUND_RELAY_RANGE
        M.forEachWorldPlayer(function(p)
            if p == player then return end
            local dx, dy = p:getX() - (gate.x + 0.5), p:getY() - (gate.y + 0.5)
            if dx * dx + dy * dy <= r2 then sendServerCommand(p, M.NET_MODULE, M.NET_SOUND, out) end
        end)
    end

    --- The worker's NET_RESULT, and its sound to the players near the box.
    local function sendResult(player, gate, args)
        M.reply(player, M.NET_RESULT, args)
        relaySound(player, gate, args)
    end

    --- A safe's answer, after its tag is re-mirrored, so the client reads it between replies.
    local function answer(player, safe, args)
        M.syncMirror(safe.obj, safe.md)
        args.gateId = safe.id
        sendResult(player, safe, args)
    end

    local function openAndReply(player, gate, routeId, route)
        local opened = M.openGate(player, gate, routeId, route)
        if opened == nil then return refuse(player, gate, "IGUI_LugliDMS_AlreadyOpen") end
        sendResult(player, gate, { gateId = gate.id, outcome = "opened", route = routeId,
            added = opened.added, broken = opened.broken, burnt = opened.burnt })
    end

    --- A TYPED CODE: right opens, wrong costs a try, the last try locks it out.
    local function answerCode(player, gate, code, route)
        local rec = gate.md
        if type(rec.code) == "string" and code == rec.code then return openAndReply(player, gate, "code", route) end
        rec.tries = (M.finite(rec.tries) or 0) + 1
        if M.safeTriesLeft(rec) > 0 then
            return answer(player, gate, { route = "code", outcome = "wrong", triesLeft = M.safeTriesLeft(rec) })
        end
        local keypad = M.KINDS[rec.kind].keypad == true
        local hours = M.cfg("SafeLockoutHours")
        if not keypad then hours = hours / 2 end
        local alarm = keypad and M.cfg("SafeAlarm") == true
        local untilHour = lockOut(rec, hours)
        if alarm then M.soundAlarm(gate.x, gate.y, gate.z) end
        M.debug(PART, nameOf(player) .. " locked out of " .. gate.id .. (alarm and " (alarm)" or ""))
        return answer(player, gate, { route = "code", outcome = "lockout", lockedUntil = untilHour, alarm = alarm,
            triesLeft = M.safeTriesLeft(rec) })
    end

    --- THE MANIPULATION: a miss slips, a success finds a digit, or opens once enough are found.
    local function manipulate(player, gate, route)
        if not rolled(route.chance) then
            return answer(player, gate, { route = "manipulate", outcome = "slipped", reason = M.REASON_DIAL_SLIPS })
        end
        if revealedCount(gate.md) >= M.MANIPULATE_OPENS_AT then return openAndReply(player, gate, "manipulate", route) end
        if not revealDigit(gate) then
            return answer(player, gate, { route = "manipulate", outcome = "slipped", reason = M.REASON_DIAL_SLIPS })
        end
        grantXp(player, route.xp)
        return answer(player, gate, { route = "manipulate", outcome = "revealed",
            revealed = M.maskedCode(gate.md.revealed), opened = false })
    end

    --- A BATTERY powers the keypad for good.
    local function powerUp(player, gate)
        gate.md.powered = true
        return answer(player, gate, { route = "battery", outcome = "powered" })
    end

    --- A ROUTE WHOSE ROLL FAILED: no payout, the gate stays sealed, the route's progress starts
    --- over, and a lock that jams may jam for good (mirrored, so the client stops offering the pick).
    local function failGate(player, gate, routeId, route)
        local rec = gate.md
        if type(rec.progress) == "table" then rec.progress[routeId] = nil end
        if route.jams and ZombRand(1000) < M.JAM_CHANCE * 1000 then rec.jammed = true end
        noise(player, gate, route.noise)
        if route.wear then wear(player, route.tool) end
        -- A failed roll uses up a paperclip or a handmade pick and wears a store lockpick.
        M.spendPick(route.tool, route.spends)
        grantSkill(player, route, false)
        local out = { gateId = gate.id, outcome = "failed", route = routeId, jammed = rec.jammed == true }
        -- A route that trips the alarm (a bypass) also locks the keypad out for the full time.
        if route.alarm then
            out.lockedUntil = lockOut(rec, M.cfg("SafeLockoutHours"))
            out.alarm = M.cfg("SafeAlarm") == true
            if out.alarm then M.soundAlarm(gate.x, gate.y, gate.z) end
        end
        M.syncMirror(gate.obj, rec)
        M.debug(PART, nameOf(player) .. " failed " .. gate.id .. " by " .. tostring(routeId)
            .. (rec.jammed == true and " (jammed)" or "") .. (out.alarm == true and " (alarm)" or ""))
        sendResult(player, gate, out)
    end

    local function floorExempt(player)
        if not M.isMultiplayer() then return true end
        local ok, instant = pcall(function() return player:isTimedActionInstant() == true end)
        return ok and instant
    end

    -- A claim's expiry only keeps OTHER survivors off the gate. Single player has none, and a
    -- paused game must not expire the work it paused, so there a claim never expires.
    local function expired(held, t)
        return held.expires ~= nil and t >= held.expires
    end

    local function claim(player, args)
        local gate, why = resolve(player, args)
        if gate == nil then return refuse(player, nil, why) end
        local route = routeFor(player, gate.md, args.route, gate.square)
        if not route.ok then return refuse(player, gate, route.reason) end
        local held = claims[gate.id]
        local who = nameOf(player)
        if held ~= nil and held.user ~= who and not expired(held, now()) then
            return M.reply(player, M.NET_BUSY, { gateId = gate.id, reason = "IGUI_LugliDMS_Busy" })
        end
        local left = type(gate.md.workLeft) == "table" and gate.md.workLeft[args.route] or nil
        local resume = M.workResume(args.route, left or {
            progress = gate.md.progress and gate.md.progress[args.route] }, left and left.at or nil, now())
        claims[gate.id] = { user = who, route = args.route, at = now(), seconds = route.seconds,
            resumes = route.resumes ~= false, from = resume,
            expires = M.isMultiplayer() and (now() + (route.seconds * 2 + 30) * 1000) or nil,
            player = player, x = gate.x, y = gate.y, z = gate.z, i = intArg(args.i), noise = route.noise,
            nextNoise = now() + M.WORK_NOISE_MS }
        noise(player, gate, route.noise * 0.5)
    end

    --- The claim's holder as the authority sees them now: nil when dead or no longer connected.
    local function holderOf(held)
        local found = nil
        if M.isMultiplayer() then
            M.forEachWorldPlayer(function(p)
                if found == nil and nameOf(p) == held.user then found = p end
            end)
        else
            found = held.player
        end
        if found == nil then return nil end
        local ok, dead = pcall(function() return found:isDead() end)
        if ok and dead == true then return nil end
        return found
    end

    --- EVERY LIVE CLAIM, once a second. Long work is heard for as long as it lasts, not only at
    --- its claim and its outcome. A claim on a gate that is gone or no longer sealed (a sledge,
    --- a carry), or whose holder died, left the server, or stood out of reach for CLAIM_AWAY_MS,
    --- is dropped, so the gate is free at once instead of at its expiry; it earns nothing, since
    --- only the holder's own release says which of that time was rest.
    local function tickClaim(id, held, t)
        local obj, _, md = M.gateAt(held.x, held.y, held.z, held.i)
        local holder = nil
        if obj ~= nil and md ~= nil and md.state == "sealed" then holder = holderOf(held) end
        if holder ~= nil and not inReach(holder, held.x, held.y, held.z) then
            held.awayAt = held.awayAt or t
            if t - held.awayAt >= M.CLAIM_AWAY_MS then holder = nil end
        elseif holder ~= nil then
            held.awayAt = nil
        end
        if holder == nil then
            claims[id] = nil
            M.debug(PART, "dropped " .. held.user .. "'s claim on " .. id)
            return
        end
        if (M.finite(held.noise) or 0) > 0 and t >= held.nextNoise then
            held.nextNoise = t + M.WORK_NOISE_MS
            noise(holder, held, held.noise)
        end
    end

    local function tickClaims()
        local t = now()
        for id, held in pairs(claims) do
            local ok, err = pcall(tickClaim, id, held, t)
            if not ok then
                claims[id] = nil
                M.defect(PART, "claim " .. tostring(id) .. ": " .. tostring(err))
            end
        end
    end

    --- PUTTING THE WORK DOWN, from wherever the holder is now: it records the work up to here.
    local function release(player, args)
        local gate = locate(args)
        if gate == nil then return end
        local held = claims[gate.id]
        if held == nil or held.user ~= nameOf(player) then return end
        claims[gate.id] = nil
        -- A claim walked away from earns nothing: the work stopped when it expired.
        if expired(held, now()) then return end
        if gate.md.state ~= "sealed" or held.seconds <= 0 then return end
        -- A try that starts over (a code, a manipulation, a bypass) keeps nothing.
        if not held.resumes then return end
        local before = gate.md.progress[held.route] or 0
        -- A rest the client says it took (Gates.WORK_CHOICES) is no work: it can only lower this.
        local session = M.workSession(held.route, args.rests, (now() - held.at) / 1000, 0, held.from)
        local done = session.work / held.seconds
        local after = math.min(M.PROGRESS_CAP, before + (1 - before) * M.clamp(done, 0, 1))
        gate.md.progress[held.route] = after
        local c = M.WORK_CHOICES[held.route]
        if c ~= nil then
            if type(gate.md.workLeft) ~= "table" then gate.md.workLeft = {} end
            gate.md.workLeft[held.route] = { heat = session.heat, credit = session.credit, progress = after, at = now() }
        end
        M.syncMirror(gate.obj, gate.md)
        -- The session cost the tool: the drill wears once, the torch burns the fuel of the work done.
        local route = routeFor(player, gate.md, held.route, gate.square)
        if route.ok then
            if route.wearsSession then wear(player, route.tool) end
            local fuel = M.fuelFor(M.ROUTES[held.route] and M.ROUTES[held.route].fuel, after - before)
            if fuel > 0 then spendFuel(route.tool, fuel) end
        end
    end

    local function submit(player, args)
        local gate, why = locate(args)
        if gate == nil then return refuse(player, nil, why) end
        local held = claims[gate.id]
        local who = nameOf(player)
        if held == nil or held.user ~= who or held.route ~= args.route then
            if not inReach(player, gate.x, gate.y, gate.z) then return refuse(player, gate, "IGUI_LugliDMS_TooFar") end
            return refuse(player, gate, "IGUI_LugliDMS_NotClaimed")
        end
        -- The holder's submit ends the claim whatever the answer: the client's try is over either way.
        claims[gate.id] = nil
        if not inReach(player, gate.x, gate.y, gate.z) then return refuse(player, gate, "IGUI_LugliDMS_TooFar") end
        if args.route == "code" and not isCode(args.code) then return refuse(player, gate, M.REASON_NO_ROUTE) end
        local exempt = floorExempt(player)
        local elapsed = (now() - held.at) / 1000
        if not exempt and elapsed < held.seconds * M.SUBMIT_FLOOR then
            return refuse(player, gate, "IGUI_LugliDMS_TooSoon")
        end
        -- THE RESTS (Gates.WORK_CHOICES), clamped there: honoured only when they were paid on this
        -- clock over the same floor, and then only a wear less or a lower burn.
        local session = M.workSession(args.route, args.rests, elapsed,
            exempt and 0 or held.seconds * M.SUBMIT_FLOOR, held.from)
        if type(gate.md.workLeft) == "table" then gate.md.workLeft[args.route] = nil end
        local route = routeFor(player, gate.md, args.route, gate.square)
        if not route.ok then return refuse(player, gate, route.reason) end
        route.burn = (M.finite(route.burn) or 0) * session.burnFactor
        if session.hot then
            for _ = 1, M.WORK_CHOICES[args.route].extraWear do wear(player, route.tool) end
        end
        spendConsumed(route)
        if (M.finite(route.fuel) or 0) > 0 then spendFuel(route.tool, route.fuel) end
        if route.code then return answerCode(player, gate, args.code, route) end
        if args.route == "manipulate" then return manipulate(player, gate, route) end
        if args.route == "battery" then return powerUp(player, gate) end
        if not rolled(route.chance) then return failGate(player, gate, args.route, route) end
        openAndReply(player, gate, args.route, route)
    end

    local HANDLERS = { [M.NET_CLAIM] = claim, [M.NET_RELEASE] = release, [M.NET_SUBMIT] = submit }

    --- The box this mod placed at x,y,z, when its square is loaded here: a store record names it.
    local function placedBoxAt(x, y, z)
        local square = getCell():getGridSquare(x, y, z)
        if square == nil then return nil end
        local objects = square:getObjects()
        for k = 0, objects:size() - 1 do
            local obj = objects:get(k)
            for i = 0, obj:getContainerCount() - 1 do
                if M.gateOf(obj, i) ~= nil then return obj end
            end
        end
        return nil
    end

    --- A CLIENT MISSED A BOX (docs/31 section 2a): send it again to every client near it, which
    --- drops it where it already has one (Actions.lua). Only the position is read off the wire;
    --- anything wrong is refused silently, since the asker is a background check, not a survivor.
    local function resend(player, args)
        if not M.isMultiplayer() or type(args) ~= "table" then return end
        local who = nameOf(player)
        local t = now()
        if resentAt[who] ~= nil and t - resentAt[who] < M.RESEND_RATE_MS then return end
        resentAt[who] = t
        local x, y, z = intArg(args.x), intArg(args.y), intArg(args.z)
        if x == nil or y == nil or z == nil then return end
        if math.abs(player:getX() - (x + 0.5)) > M.RESEND_RANGE or math.abs(player:getY() - (y + 0.5)) > M.RESEND_RANGE then
            return
        end
        local obj = placedBoxAt(x, y, z)
        if obj == nil then return end
        obj:transmitCompleteItemToClients()
        M.debug(PART, "resent the box at " .. x .. "," .. y .. "," .. z .. " for " .. who)
    end

    --- Every request, from the wire or (single player) straight from the client.
    function M.serverRequest(player, command, args)
        if command == M.NET_RESEND then
            if player ~= nil then resend(player, args) end
            return
        end
        local fn = HANDLERS[command]
        if fn == nil or player == nil then return end
        local who = nameOf(player)
        local t = now()
        if lastAt[who] ~= nil and t - lastAt[who] < M.RATE_MS and command ~= M.NET_RELEASE then
            return M.reply(player, M.NET_BUSY, { reason = "IGUI_LugliDMS_Wait" })
        end
        lastAt[who] = t
        fn(player, args)
    end

    --- A SLEDGE IS A ROUTE TOO. Vanilla destroy dumps a container's contents on the floor
    --- (ISDestroyStuffAction.lua:132), which for a sealed gate is nothing: the payout is rolled
    --- here first, at the brute-force damage level, only when vanilla is about to destroy it.
    local function wrapDestroy()
        if ISDestroyStuffAction == nil or type(ISDestroyStuffAction.complete) ~= "function" then
            M.defect(PART, "ISDestroyStuffAction.complete is missing: a sledge empties a sealed gate", true)
            return
        end
        local original = ISDestroyStuffAction.complete
        ISDestroyStuffAction.complete = function(self)
            local refused = false
            local ok, err = pcall(function()
                local obj = self.item
                if obj == nil or obj:getSquare() == nil then return end
                -- A SEALED SAFE TAKES NO SLEDGE: its only ways in are its routes. Opened, it is
                -- furniture, and a sledge clears it away like any other.
                local kind, opened = M.kindOfSprite(M.liveSpriteName(obj))
                if M.isSafeKind(kind) and not opened then
                    refused = true
                    return
                end
                local sealed = {}
                for i = 0, obj:getContainerCount() - 1 do
                    local rec, container = M.gateOf(obj, i)
                    if rec ~= nil and rec.state == "sealed" then sealed[#sealed + 1] = { i = i, rec = rec, container = container } end
                end
                if #sealed == 0 then return end
                if not self.character:isBuildCheat() and not self:hasSledgehammerInRange(self.character, obj) then return end
                if getServerOptions ~= nil and getServerOptions():getBoolean("SledgehammerOnlyInSafehouse") then
                    local role = self.character:getRole()
                    local privileged = role ~= nil and role:hasCapability(Capability.UseBuildCheat)
                    local safe = SafeHouse.isSafeHouse(obj:getSquare(), nil, false)
                    if not privileged and not (safe and safe:playerAllowed(self.character)) then return end
                end
                local square = obj:getSquare()
                for _, s in ipairs(sealed) do
                    local gate = { obj = obj, container = s.container, md = s.rec, x = square:getX(), y = square:getY(),
                        z = square:getZ(), id = M.gateId(square:getX(), square:getY(), square:getZ(), s.i) }
                    M.openGate(self.character, gate, "sledge", { damage = true, noise = 0 })
                end
            end)
            if not ok then M.defect(PART, "sledge payout: " .. tostring(err)) end
            if refused then return false end
            return original(self)
        end
    end

    if M.isWorldAuthority() then
        if M.isMultiplayer() then
            M.addHandler(PART, "OnClientCommand", function(module, command, player, args)
                if module ~= M.NET_MODULE then return end
                M.serverRequest(player, command, args)
            end)
        end
        M.addTicker(PART, 10, function()
            local t = now()
            for id, held in pairs(claims) do
                if expired(held, t) then claims[id] = nil end
            end
            for who, at in pairs(lastAt) do
                if t - at > 60000 then lastAt[who] = nil end
            end
            for who, at in pairs(resentAt) do
                if t - at > 60000 then resentAt[who] = nil end
            end
        end)
        M.addTicker(PART, 1, function()
            local t = now()
            for id, r in pairs(resync) do
                if t >= r.at then
                    resync[id] = nil
                    local obj, _, md = M.gateAt(r.x, r.y, r.z, r.i)
                    if obj ~= nil then M.syncMirror(obj, md) end
                end
            end
        end)
        M.addTicker(PART, 1, tickAlarms)
        M.addTicker(PART, 1, tickClaims)
        M.addTicker(PART, 30, function() M.refreshConfig() end)
        M.addTeardown(PART, function() claims = {}; lastAt = {}; resentAt = {}; resync = {}; alarms = {} end)
        wrapDestroy()
        M.status(PART, true)
    end
end
