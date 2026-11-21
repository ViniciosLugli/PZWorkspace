--[[
    Actions
    One timed action for every route on a sealed gate (the crate's pry, claw and smash, the
    lockbox's key, pick, force and jimmy, the footlocker's key, cut and snap, the safes' code,
    manipulate, drill, torch, bypass and battery), and the one path that starts it: walk to the
    gate, equip the route's tool, work. Inspect takes the same walk, then a one-second look that
    opens the inspect window; a code route's look opens the code window instead, and its submit
    starts the work with the typed code. The action only times and animates
    the work. The authority decides (World.lua): the action claims the gate as it starts, gives it
    back if it is put down, and submits when it finishes.

    ONE SEND FOR BOTH WORLDS. sendClientCommand is broken in single player (docs/13), so there the
    client calls M.serverRequest directly and the reply comes straight back through M.onReply,
    INSIDE the call that sent it. A refusal therefore only sets a flag the action's isValid reads;
    stopping an action from inside its own start() is not safe.

    ANIMATIONS ARE THE ENGINE'S OWN STATE NAMES (media/AnimSets/player/actions). Every box sits on
    the floor and a safe is knee to hip high, so the work is done crouched: VehicleWorkOnTire
    (vanilla's tyre work, the tool held into the thing) for a tool worked into a lid or a lock,
    BuildLow (vanilla's own for a floor moveable) for the claw's hammer, vanilla's floor weld
    (BlowTorchFloor) for the torch, the low container search (Loot, LootPosition Low) for a key,
    a code or a battery, and vanilla's sledge swing (Destroy) for the smash. The route's own
    item is the hand model. A typo is no error anywhere, just a survivor standing still.

    THE WORK PANEL (WorkPanel.lua, read at call time: it loads after this file) is opened by
    start, ticked by update, and closed by stop and perform; its rests ride on the submit and the
    release as `rests`, which the authority replays (Gates.WORK_CHOICES).
]]

require "TimedActions/ISBaseTimedAction"
require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Config"
require "LugliDeadMansStash/Gates"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash
    local PART = "Actions"

    -- ---- the gate, as the client sees it ---------------------------------------------------------

    --- The gate record of an object that is a SEALED gate, else nil. Runs for every loot button,
    --- so gateRecord reads the sprite before any modData.
    function M.sealedGateOf(obj)
        local rec = M.gateRecord(obj)
        if rec == nil or rec.state ~= "sealed" then return nil end
        return rec
    end

    --- The index of the gated container on its object: the first whose type a gate kind takes,
    --- which is the index Gating.lua sealed it under.
    function M.gateIndexOf(obj)
        local okN, n = pcall(function() return obj:getContainerCount() end)
        if not okN or type(n) ~= "number" then return nil end
        for i = 0, n - 1 do
            local okC, ctype = pcall(function() return obj:getContainerByIndex(i):getType() end)
            if okC and M.kindForContainer(ctype) ~= nil then return i end
        end
        return nil
    end

    --- The wire arguments naming this gate and route, and the gate id the authority answers with.
    function M.gateArgs(obj, routeId)
        local okSq, sq = pcall(function() return obj:getSquare() end)
        if not okSq or sq == nil then return nil end
        local i = M.gateIndexOf(obj)
        if i == nil then return nil end
        local x, y, z = sq:getX(), sq:getY(), sq:getZ()
        local id = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. "," .. tostring(i)
        return { x = x, y = y, z = z, i = i, route = routeId }, id
    end

    --- The object's square, or nil: a keypad's grid power is read from it (Gates.route).
    local function squareOf(obj)
        if obj == nil then return nil end
        local ok, sq = pcall(function() return obj:getSquare() end)
        if ok then return sq end
        return nil
    end
    M.squareOf = squareOf

    --- What this survivor can do on this gate by this route now, its square read for power.
    local function routeOn(player, obj, md, routeId)
        return M.route(player, md, routeId, nil, squareOf(obj))
    end

    --- Is an intact tool for this route in the survivor's main hand? A route without a tool (the
    --- key, which works from the main inventory or a key ring, the code, the battery) takes none.
    local function toolInHand(player, routeId)
        local def = M.ROUTES[routeId]
        if def == nil then return false end
        if def.tools == nil and def.items == nil then return true end
        local okH, item = pcall(function() return player:getPrimaryHandItem() end)
        if not okH or item == nil then return false end
        local okB, broken = pcall(function() return item:isBroken() end)
        if not okB or broken ~= false then return false end
        local items = def.items or {}
        local okT, fullType = pcall(function() return item:getFullType() end)
        for i = 1, #items do
            if okT and fullType == items[i] then return true end
        end
        if ItemTag == nil then return false end
        local tools = def.tools or {}
        for i = 1, #tools do
            local tag = ItemTag[tools[i]]
            if tag ~= nil then
                local ok, yes = pcall(function() return item:hasTag(tag) end)
                if ok and yes == true then return true end
            end
        end
        return false
    end
    M.toolInHand = toolInHand

    local function halo(player, text, good)
        if HaloTextHelper == nil or player == nil or text == nil then return end
        pcall(function()
            if good then HaloTextHelper.addGoodText(player, text) else HaloTextHelper.addBadText(player, text) end
        end)
    end

    --- A reason key as the player reads it; `fallback` is its English when the key has none.
    function M.reasonText(reason, fallback)
        return M.T(reason, fallback or M.T("IGUI_LugliDMS_Refused", "That did not work."))
    end

    --- A translation with %1 filled with `a`, treating an echoed key as a miss.

    -- ---- the safe's alarm --------------------------------------------------------------------------

    -- Vanilla's house alarm (sounds_ambience.txt), played where the authority says a safe tripped
    -- it for as long as the authority sounds it. The event loops, so it is stopped by hand.
    M.ALARM_SOUND = "HouseAlarm"
    M.ALARM_SECONDS = 30

    --- The alarms ringing here, by "x,y,z": { emitter, id, stopAt }.
    local alarms = {}

    local function nowMs()
        return getTimestampMs ~= nil and getTimestampMs() or 0
    end

    local function silence(key)
        local a = alarms[key]
        if a == nil then return end
        alarms[key] = nil
        pcall(function() a.emitter:stopSound(a.id) end)
    end

    --- Ring the alarm at x, y, z for M.ALARM_SECONDS; asked again while it rings, it rings on from
    --- now instead of starting a second one. A free emitter needs no loaded square. True when it rings.
    function M.soundAlarm(x, y, z)
        x, y, z = M.finite(x), M.finite(y), M.finite(z)
        if x == nil or y == nil or z == nil then return false end
        local key = x .. "," .. y .. "," .. z
        local stopAt = nowMs() + M.ALARM_SECONDS * 1000
        if alarms[key] ~= nil then
            alarms[key].stopAt = stopAt
            return true
        end
        local okE, emitter = pcall(function() return getWorld():getFreeEmitter(x + 0.5, y + 0.5, z) end)
        if not okE or emitter == nil then return false end
        local okP, id = pcall(function() return emitter:playSound(M.ALARM_SOUND) end)
        if not okP or id == nil or id == 0 then return false end
        alarms[key] = { emitter = emitter, id = id, stopAt = stopAt }
        return true
    end

    --- Another survivor's answer at a box near here (World.lua relays it): args.sounds is the
    --- names joined by ";", and only names Sounds.lua plays are played.
    function M.soundAt(args)
        local x, y, z = M.finite(args.x), M.finite(args.y), M.finite(args.z)
        if x == nil or y == nil or z == nil or type(args.sounds) ~= "string" then return false end
        local played = false
        for name in string.gmatch(args.sounds, "[^;]+") do
            if M.isModSound(name) then
                local okE, emitter = pcall(function() return getWorld():getFreeEmitter(x + 0.5, y + 0.5, z) end)
                if okE and emitter ~= nil then
                    local okP = pcall(function() emitter:playSound(name) end)
                    played = played or okP
                end
            end
        end
        return played
    end

    M.addTicker(PART, 1, function()
        local t, done = nowMs(), {}
        for key, a in pairs(alarms) do
            if t >= a.stopAt then done[#done + 1] = key end
        end
        for i = 1, #done do silence(done[i]) end
    end)

    -- ---- the wire --------------------------------------------------------------------------------

    --- One request to the authority, in either world. Read at call time: World.lua is a server
    --- file and loads after this one.
    function M.send(player, command, args)
        if M.isMultiplayer() then
            if sendClientCommand ~= nil then sendClientCommand(player, M.NET_MODULE, command, args) end
            return
        end
        if M.serverRequest == nil then
            M.defect(PART, "no authority to send " .. tostring(command) .. " to")
            return
        end
        local ok, err = pcall(M.serverRequest, player, command, args)
        if not ok then M.defect(PART, tostring(command) .. " request failed: " .. tostring(err)) end
    end

    -- WHO ASKED, per gate id: { player, action }. An answer naming a gate nobody here asked about
    -- is somebody else's and is not spoken. The rate-limit answer names no gate, so it goes to
    -- whoever sent last.
    local holders = {}
    local lastGateId = nil

    local function redrawLoot()
        if ISInventoryPage ~= nil and ISInventoryPage.dirtyUI ~= nil then pcall(ISInventoryPage.dirtyUI) end
    end

    local function hold(gateId, player, action, spends, obj)
        holders[gateId] = { player = player, action = action, spends = spends or false, obj = obj }
        lastGateId = gateId
    end

    --- Hand a code reply to the open code window (Keypad.lua, read now: it loads after this one).
    --- The wire's lockedUntil is the world-age hour the lockout ends; the window counts hours left.
    local function toKeypad(h, outcome, args)
        if type(M.keypadResult) ~= "function" then return end
        local out = { player = h.player, obj = h.obj, triesLeft = args.triesLeft }
        if args.lockedUntil ~= nil then out.lockedFor = M.lockedFor({ lockedUntil = args.lockedUntil }) end
        local ok, err = pcall(M.keypadResult, outcome, out)
        if not ok then M.defect(PART, "keypadResult failed: " .. tostring(err)) end
    end

    --- The words for a roll that did not open it: the alarm and a lockout when it tripped them,
    --- else the lock holding or jamming, and the pick when one was spent or worn.
    local function failedText(h, args)
        local text
        if args.alarm == true then
            text = M.T(M.REASON_ALARM, "The alarm goes off!")
            if M.lockedFor({ lockedUntil = args.lockedUntil }) > 0 then
                text = text .. " " .. M.T(M.REASON_LOCKOUT, "It locks me out.")
            end
        elseif args.jammed == true then
            text = M.T("IGUI_LugliDMS_LockJams", "The lock jams.")
        else
            text = M.T("IGUI_LugliDMS_LockHolds", "The lock holds.")
        end
        return text .. M.spentText(h.spends)
    end

    --- Every answer from the authority: OnServerCommand in multiplayer, a direct call from
    --- World.lua in single player.
    function M.onReply(command, args)
        if type(args) ~= "table" then return end
        if command == M.NET_PLACED then
            -- Its own guard: this handler going quiet would take every route's answers with it.
            local ok, err = pcall(M.onPlaced, args)
            if not ok then M.defect("BoxSync", "placed: " .. tostring(err)) end
            return
        end
        if command == M.NET_OPENED then redrawLoot(); return end
        -- Every client near a tripped safe hears it, whoever asked.
        if command == M.NET_ALARM then M.soundAlarm(args.x, args.y, args.z); return end
        if command == M.NET_SOUND then M.soundAt(args); return end
        local gateId = args.gateId or lastGateId
        if gateId == nil then return end
        local h = holders[gateId]
        if h == nil then return end
        local outcome = command == M.NET_RESULT and args.outcome or nil
        if outcome ~= nil and h.player ~= nil then
            for _, name in ipairs(M.outcomeSounds(args, M.boxKindOf(h.obj))) do
                pcall(function() h.player:playSound(name) end)
            end
        end
        -- A code that was wrong, or wrong once too often: the safe stays shut.
        if outcome == "wrong" then
            holders[gateId] = nil
            toKeypad(h, "wrong", args)
            halo(h.player, M.Tf(M.REASON_WRONG_CODE, "Wrong code. Tries left: %1.", M.finite(args.triesLeft) or 0), false)
            return
        end
        if outcome == "lockout" then
            holders[gateId] = nil
            toKeypad(h, "lockout", args)
            local text = M.T(M.REASON_LOCKOUT, "It locks me out.")
            if args.alarm == true then text = text .. " " .. M.T(M.REASON_ALARM, "The alarm goes off!") end
            halo(h.player, text, false)
            return
        end
        -- The dial gave up a digit; the mask is the authority's, the code never reaches here.
        if outcome == "revealed" then
            holders[gateId] = nil
            halo(h.player, M.Tf(M.REASON_REVEALED, "I felt a number click into place: %1", tostring(args.revealed)), true)
            return
        end
        if outcome == "slipped" then
            holders[gateId] = nil
            halo(h.player, M.reasonText(args.reason or M.REASON_DIAL_SLIPS), false)
            return
        end
        if outcome == "powered" then
            holders[gateId] = nil
            halo(h.player, M.T(M.REASON_POWERED, "The keypad lights up."), true)
            return
        end
        if command == M.NET_BUSY or (command == M.NET_RESULT and args.outcome == "refused") then
            holders[gateId] = nil
            local a = h.action
            if a ~= nil then
                -- The authority holds no claim for this survivor now, so there is nothing to release.
                a.claimSent = false
                a.refusedBy = args.reason or "IGUI_LugliDMS_Refused"
            end
            halo(h.player, M.reasonText(args.reason), false)
            return
        end
        -- A roll that did not open it: the gate stays sealed, and a jam is the authority's word.
        if command == M.NET_RESULT and args.outcome == "failed" then
            holders[gateId] = nil
            halo(h.player, failedText(h, args), false)
            return
        end
        if command == M.NET_RESULT and args.outcome == "opened" then
            holders[gateId] = nil
            toKeypad(h, "opened", args)
            local text = M.T("IGUI_LugliDMS_Opened", "It is open.")
            if M.finite(args.broken) ~= nil and args.broken > 0 then
                text = text .. " " .. M.T("IGUI_LugliDMS_SomeBroke", "Some things inside broke.")
            end
            halo(h.player, text, true)
            redrawLoot()
        end
    end

    -- ---- the boxes the authority placed -----------------------------------------------------------

    -- A BOX CAN MISS THIS CLIENT (docs/31 section 2a). The authority sends a box it places to the
    -- clients that have its square; one still loading a neighbouring chunk drops it
    -- (AddItemToMapPacket.java:56) and may have been served that chunk without it. So every
    -- placement is also announced, and an announced square is checked once it is loaded here: a
    -- square with no box on it is asked for again, a few times, spaced.
    local SYNC = "BoxSync"
    M.SETTLE_MS = 1000        -- after the announcement or the chunk load: the add and the command race
    M.RESEND_EVERY_MS = 3000  -- between two asks for one square
    M.RESEND_TRIES = 3
    M.PLACED_MS = 60000       -- an announced square still unsettled this long after its announcement
                              -- or its chunk's load is not this client's: dropped, quietly

    --- The announced squares not settled yet, by "x,y,z": { x, y, z, since, due, asks }. due nil:
    --- the square is not loaded here, and its chunk's load sets it.
    local placed = {}

    -- Kahlua has no `next` (docs/15).
    local function nonePlaced()
        for _ in pairs(placed) do return false end
        return true
    end

    local function announcedSquare(p)
        return getCell():getGridSquare(p.x, p.y, p.z)
    end

    --- Does the square hold one of the mod's boxes? The sprite is the proof; the tag may lag it.
    local function holdsBox(sq)
        local objects = sq:getObjects()
        for k = 0, objects:size() - 1 do
            if M.kindOfSprite(M.liveSpriteName(objects:get(k))) ~= nil then return true end
        end
        return false
    end

    --- A local survivor within the authority's resend range of the square, or nil.
    local function askerFor(p)
        if getNumActivePlayers == nil or getSpecificPlayer == nil then return nil end
        for i = 0, getNumActivePlayers() - 1 do
            local pl = getSpecificPlayer(i)
            if pl ~= nil and math.abs(pl:getX() - (p.x + 0.5)) <= M.RESEND_RANGE
                and math.abs(pl:getY() - (p.y + 0.5)) <= M.RESEND_RANGE then return pl end
        end
        return nil
    end

    local function intOf(v)
        v = M.finite(v)
        if v == nil or v ~= math.floor(v) then return nil end
        return v
    end

    --- The authority placed a box at args.x, y, z.
    function M.onPlaced(args)
        local x, y, z = intOf(args.x), intOf(args.y), intOf(args.z)
        if x == nil or y == nil or z == nil then return end
        local key = x .. "," .. y .. "," .. z
        if placed[key] ~= nil then return end
        local t = nowMs()
        local p = { x = x, y = y, z = z, since = t, asks = 0 }
        if announcedSquare(p) ~= nil then p.due = t + M.SETTLE_MS end
        placed[key] = p
    end

    --- A chunk came in: its announced squares are checked once the add has had its chance.
    function M.onPlacedChunk(chunk)
        if nonePlaced() then return end
        local origin = chunk:getGridSquare(0, 0, 0)
        local x0 = origin ~= nil and origin:getX() or nil
        local y0 = origin ~= nil and origin:getY() or nil
        local t = nowMs()
        for _, p in pairs(placed) do
            -- A chunk with no origin square to place it by: every waiting square gets a look.
            if p.due == nil and (x0 == nil or (p.x >= x0 and p.x < x0 + 8 and p.y >= y0 and p.y < y0 + 8)) then
                p.due = t + M.SETTLE_MS
                p.since = t
            end
        end
    end

    --- Check the announced squares that are due. One ask a pass at most, so the authority's
    --- per-survivor limit (World.lua) never refuses the second of two boxes placed together.
    function M.checkPlaced()
        if nonePlaced() then return end
        local t = nowMs()
        local asked, done = false, {}
        for key, p in pairs(placed) do
            -- Asking ends well inside this; what is left is unloaded or out of every survivor's range.
            if t - p.since >= M.PLACED_MS then
                done[#done + 1] = key
            elseif p.due ~= nil and t >= p.due then
                local sq = announcedSquare(p)
                if sq == nil then
                    p.due = nil
                elseif holdsBox(sq) then
                    done[#done + 1] = key
                elseif p.asks >= M.RESEND_TRIES then
                    done[#done + 1] = key
                    M.defect(SYNC, "the box at " .. key .. " never arrived after " .. p.asks .. " asks")
                elseif not asked then
                    local player = askerFor(p)
                    if player ~= nil then
                        M.send(player, M.NET_RESEND, { x = p.x, y = p.y, z = p.z })
                        p.asks = p.asks + 1
                        asked = true
                    end
                    p.due = t + M.RESEND_EVERY_MS
                end
            end
        end
        for i = 1, #done do placed[done[i]] = nil end
    end

    --- AN ADD IS IDEMPOTENT. A resend reaches every client near the box (IsoObject.java:4666), and
    --- an add can land on a chunk that was served with the box in it, so a box arriving on a square
    --- that already holds one of its kind is a second copy, and is removed here only:
    --- RemoveTileObject sends nothing (IsoGridSquare.java:5752 to :5757). The copy goes in at the
    --- authority's index, ahead of the original (IsoObject.java:4519), so it goes by identity.
    function M.onBoxAdded(obj)
        if not M.isMultiplayer() or obj == nil then return end
        local kind = M.kindOfSprite(M.liveSpriteName(obj))
        if kind == nil then return end
        local sq = obj:getSquare()
        if sq == nil then return end
        local objects = sq:getObjects()
        for k = 0, objects:size() - 1 do
            local other = objects:get(k)
            if other ~= obj and M.kindOfSprite(M.liveSpriteName(other)) == kind then
                sq:RemoveTileObject(obj)
                redrawLoot()
                M.debug(SYNC, "dropped a second copy of the box at " .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ())
                return
            end
        end
    end

    -- NOT M.addHandler, for Gating's reason: these run once a chunk and once an object, and one odd
    -- one must not end the check for the session.
    local function guarded(eventName, fn)
        if Events == nil or Events[eventName] == nil then
            M.defect(SYNC, "Events." .. eventName .. " does not exist on this build", true)
            return false
        end
        Events[eventName].Add(function(arg)
            local ok, err = pcall(fn, arg)
            if not ok then M.defect(SYNC, eventName .. ": " .. tostring(err)) end
        end)
        return true
    end
    local chunkHooked = guarded("LoadChunk", M.onPlacedChunk)
    local addHooked = guarded("OnObjectAdded", M.onBoxAdded)
    M.addTicker(SYNC, 1, M.checkPlaced)
    M.addTeardown(SYNC, function() placed = {} end)
    if chunkHooked and addHooked then M.status(SYNC, true) end

    -- ---- the action ------------------------------------------------------------------------------

    -- BaseAction adds GameTime.getMultiplier() a tick, which is 48 x multiplierBias units a real
    -- second (GameTime.getTimeDeltaFromMultiplier), not 30: at 30 the work ran 0.625 of the
    -- authority's clock and every submit came back too soon (docs/28 has the same derivation).
    M.ACTION_UNITS_PER_SECOND = 48

    -- HOW EACH ROUTE LOOKS: anim is the action state; hand what is held, the route's tool when
    -- unset, nothing for "none", the key that opens it for "key", the item the try uses up for
    -- "consumed". What it sounds like is Sounds.lua's: its begin plays from the start (hushed for a
    -- pause), and its ending is the authority's answer (M.onReply).
    --
    -- THE POSES, chosen from in-game frames of every route on every box (the audition probe, two
    -- frames a take, the survivor at the box's stance). The mod's own LugliDMS_* states
    -- (media/AnimSets/player/actions) play vanilla clips with no sound events of their own, so a
    -- route's sounds are only its own: PryLow is Bob_IdleLeverOpenLow, a crouched crowbar lever
    -- no vanilla state plays; FineLow Bob_IdleCraftTyingLow, crouched hands at lock height for the
    -- pick, the screwdriver, the cutters, the stethoscope and the wires; ReachLow
    -- Bob_Idle_LureLow, a steady low push for the drill (a hammering clip read as knocking the
    -- safe); ClawLow Bob_IdleHammering_Low without Build's Hammering sound. The smash swings at a
    -- low box (DestroyFloor), the torch is vanilla's floor weld.
    local STYLES = {
        code = { anim = "Loot", hand = "none" },
        manipulate = { anim = "LugliDMS_FineLow" },
        battery = { anim = "Loot", hand = "consumed" },
        bypass = { anim = "LugliDMS_FineLow" },
        drill = { anim = "LugliDMS_ReachLow" },
        torch = { anim = "BlowTorchFloor" },
        smash = { anim = "DestroyFloor" },
        pry = { anim = "LugliDMS_PryLow" },
        force = { anim = "LugliDMS_PryLow" },
        snap = { anim = "LugliDMS_PryLow" },
        claw = { anim = "LugliDMS_ClawLow" },
        key = { anim = "Loot", hand = "key" },
        pick = { anim = "LugliDMS_FineLow" },
        jimmy = { anim = "LugliDMS_FineLow" },
        cut = { anim = "LugliDMS_FineLow" },
    }

    --- The kind of box an object shows, opened or not, or nil.
    local function kindOf(obj)
        if obj == nil then return nil end
        return (M.kindOfSprite(M.liveSpriteName(obj)))
    end
    M.boxKindOf = kindOf

    --- How a route looks and sounds (the in-game pose probe reads it, so a sheet shows what ships).
    function M.routeStyle(routeId)
        return STYLES[routeId] or STYLES.claw
    end

    --- The model an item shows in the hand: the item itself, or its world model's name when it has
    --- no hand model of its own (a stethoscope, a paperclip), which setOverrideHandModelsString takes.
    function M.handModelOf(item)
        if item == nil then return nil, nil end
        local okS, static = pcall(function() return item:getStaticModel() end)
        if okS and type(static) == "string" and static ~= "" then return item, nil end
        local okW, world = pcall(function() return item:getWorldStaticModel() end)
        if okW and type(world) == "string" and world ~= "" then return nil, world end
        return item, nil
    end

    --- Put the route's own item in the survivor's hand for the work.
    local function holdForWork(self, look)
        local item = nil
        if look.hand == nil then
            item = self.character:getPrimaryHandItem()
        elseif look.hand ~= "none" then
            local md = M.sealedGateOf(self.obj)
            local route = routeOn(self.character, self.obj, md, self.routeId)
            if route.ok and look.hand == "key" then item = route.key end
            if route.ok and look.hand == "consumed" and type(route.consumes) == "table" then item = route.consumes[1] end
        end
        local obj, model = M.handModelOf(item)
        if model ~= nil then
            self:setOverrideHandModelsString(model, nil)
        else
            self:setOverrideHandModels(obj, nil)
        end
    end

    ISLugliDMSRouteAction = ISBaseTimedAction:derive("ISLugliDMSRouteAction")

    function ISLugliDMSRouteAction:isValid()
        if self.refusedBy ~= nil then return false end
        local md = M.sealedGateOf(self.obj)
        if md == nil then return false end
        if squareOf(self.obj) == nil then return false end
        local route = routeOn(self.character, self.obj, md, self.routeId)
        if not route.ok then
            self.stoppedBy = route.reason
            return false
        end
        return toolInHand(self.character, self.routeId)
    end

    function ISLugliDMSRouteAction:waitToStart()
        self.character:faceThisObject(self.obj)
        return self.character:shouldBeTurning()
    end

    --- The work panel's hooks (WorkPanel.lua), read at call time. A panel that fails is a defect,
    --- never a stopped action.
    local function panel(name, self)
        local fn = M[name]
        if type(fn) ~= "function" then return end
        local ok, err = pcall(fn, self)
        if not ok then M.defect("WorkPanel", name .. " failed: " .. tostring(err)) end
    end

    function ISLugliDMSRouteAction:update()
        self.character:faceThisObject(self.obj)
        panel("workTick", self)
    end

    local function stopSound(self)
        local s, name = self.sound, self.soundName
        self.sound, self.soundName = nil, nil
        if s ~= nil then pcall(function() self.character:getEmitter():stopSound(s) end) end
        -- In game the drill and torch loops played on after their id was stopped; each loop is one
        -- instance an emitter (maxInstancesPerEmitter = 1), so its name stops just it.
        if name ~= nil then pcall(function() self.character:getEmitter():stopSoundByName(name) end) end
    end

    local function play(self, name)
        local ok, id = pcall(function() return self.character:playSound(name) end)
        if ok then return id end
        return nil
    end

    --- Hush the work's sound for a rest (the panel's button), and bring it back after.
    function ISLugliDMSRouteAction:hush() stopSound(self) end
    function ISLugliDMSRouteAction:resound()
        local begin = M.routeSound(self.routeId, kindOf(self.obj), "begin")
        if begin ~= nil and self.sound == nil then
            self.sound, self.soundName = play(self, begin), begin
        end
    end

    --- The wire arguments of this action with its rests (WorkPanel.lua), when it took any.
    local function withRests(self, args)
        local out = {}
        for k, v in pairs(args) do out[k] = v end
        if type(self.workRests) == "table" and #self.workRests > 0 then
            out.rests = {}
            for i, r in ipairs(self.workRests) do out.rests[i] = { at = r.at, s = r.s } end
        end
        return out
    end

    function ISLugliDMSRouteAction:start()
        local args, gateId = M.gateArgs(self.obj, self.routeId)
        if args == nil then
            self.refusedBy = "IGUI_LugliDMS_Gone"
            return
        end
        self.args, self.gateId = args, gateId
        -- THE CLAIM STARTS THE AUTHORITY'S CLOCK. Flagged and held before the send, because in
        -- single player the refusal comes back inside it.
        self.claimSent = true
        hold(gateId, self.character, self)
        M.send(self.character, M.NET_CLAIM, args)

        local look = M.routeStyle(self.routeId)
        self:setActionAnim(look.anim)
        if look.anim == "Loot" then self:setAnimVariable("LootPosition", "Low") end
        holdForWork(self, look)
        self:resound()
        -- A claim refused inside the send (single player) leaves no work to show.
        if self.refusedBy == nil then panel("workOpen", self) end
    end

    --- The smash swings like vanilla's sledge (ISDestroyStuffAction:animEvent).
    function ISLugliDMSRouteAction:animEvent(event, parameter)
        if self.routeId ~= "smash" then return end
        local tool = self.character:getPrimaryHandItem()
        if tool == nil then return end
        if event == "PlaySwingSound" then
            pcall(function() self.character:playSound(tool:getSwingSound()) end)
        elseif event == "PlayHitSound" then
            pcall(function() self.character:playSound(tool:getDoorHitSound()) end)
        end
    end

    function ISLugliDMSRouteAction:stop()
        stopSound(self)
        panel("workClose", self)
        -- Only a claim this action sent and the authority did not refuse is given back.
        if self.claimSent then
            self.claimSent = false
            if self.gateId ~= nil then holders[self.gateId] = nil end
            M.send(self.character, M.NET_RELEASE, withRests(self, self.args))
        end
        local why, fallback = self.stoppedBy, self.stoppedFallback
        if why ~= nil then
            self.stoppedBy, self.stoppedFallback = nil, nil
            halo(self.character, M.reasonText(why, fallback), false)
        end
        ISBaseTimedAction.stop(self)
    end

    function ISLugliDMSRouteAction:perform()
        stopSound(self)
        panel("workClose", self)
        if self.claimSent then
            self.claimSent = false
            -- The answer to the submit is spoken to this survivor; the action is over by then. Whether
            -- a failure spends or wears the pick is read now: in single player the authority answers,
            -- and removes the clip, inside the send.
            local route = routeOn(self.character, self.obj, M.sealedGateOf(self.obj), self.routeId)
            hold(self.gateId, self.character, nil, route.ok and route.spends, self.obj)
            -- Only the submit carries the typed code; the claim never does.
            local submit = withRests(self, self.args)
            submit.code = self.code
            M.send(self.character, M.NET_SUBMIT, submit)
        end
        ISBaseTimedAction.perform(self)
    end

    --- code: the four digits a code route submits, nil for every other route.
    function ISLugliDMSRouteAction:new(character, obj, routeId, code)
        local o = ISBaseTimedAction.new(self, character)
        o.obj = obj
        o.routeId = routeId
        o.code = code
        o.stopOnWalk = true
        o.stopOnRun = true
        o.stopOnAim = true
        -- The same length the authority times the claim against (Gates.lua), in REAL seconds.
        local route = routeOn(character, obj, M.sealedGateOf(obj), routeId)
        local seconds = (route.ok and M.finite(route.seconds)) or 1
        o.maxTime = math.max(1, math.floor(seconds * M.ACTION_UNITS_PER_SECOND))
        if character:isTimedActionInstant() then o.maxTime = 1 end
        return o
    end

    --- Queue the walk up to the gate, or say it cannot be reached. The survivor kneels square in
    --- front of the box, on the side away from its wall (Spots.frontOfSprite), as at a crate's
    --- lid; any free side when that square is blocked. Both walks clear the queue first.
    local function walkTo(player, obj)
        local okSq, sq = pcall(function() return obj:getSquare() end)
        if not okSq or sq == nil then return false end
        local okN, name = pcall(function() return obj:getSprite():getName() end)
        local front = okN and M.frontOfSprite(name) or nil
        local stance = okN and M.GATE_BOXES[M.kindOfSprite(name) or ""] ~= nil
            and M.GATE_BOXES[M.kindOfSprite(name)].stance or nil
        if front ~= nil and stance ~= nil then
            local fsq = getCell():getGridSquare(sq:getX() + front[1], sq:getY() + front[2], sq:getZ())
            if fsq ~= nil and fsq:isFree(false) and not sq:isBlockedTo(fsq) then
                ISTimedActionQueue.clear(player)
                local path = ISPathFindAction:pathToLocationF(player, sq:getX() + 0.5 + front[1] * stance,
                    sq:getY() + 0.5 + front[2] * stance, sq:getZ())
                -- A stance the pathfinder cannot reach exactly may still leave the survivor in reach,
                -- so the queue is kept and the work's own isValid judges it; out of reach, say so.
                path:setOnFail(function()
                    if not M.inspectInReach(player, obj) then halo(player, M.reasonText("IGUI_LugliDMS_TooFar"), false) end
                end)
                path:setRunActionsAfterFailing(true)
                ISTimedActionQueue.add(path)
                return true
            end
        end
        if not luautils.walkAdj(player, sq) then
            halo(player, M.reasonText("IGUI_LugliDMS_TooFar"), false)
            return false
        end
        return true
    end

    --- THE ONE WAY TO START A ROUTE, from the context menu and the inspect window alike: say now
    --- why it cannot be done, else walk to the gate, equip the tool and work. Returns true when
    --- the work was queued.
    function M.startRoute(player, obj, routeId)
        if player == nil or obj == nil then return false end
        local md = M.sealedGateOf(obj)
        if md == nil then return false end
        local route = routeOn(player, obj, md, routeId)
        if not route.ok then
            halo(player, M.reasonText(route.reason), false)
            return false
        end
        -- THE SAME WORK PICKED AGAIN IS LEFT RUNNING. walkAdj clears the queue, so restarting it
        -- would release the claim and claim again inside the authority's rate limit.
        if M.workingOn(player, obj, routeId) then return true end
        if not walkTo(player, obj) then return false end
        -- A code is typed first: the look opens the code window, and its submit starts the work.
        if route.code then
            ISTimedActionQueue.add(ISLugliDMSInspectAction:new(player, obj, M.openCode))
            return true
        end
        if not toolInHand(player, routeId) then
            ISWorldObjectContextMenu.equip(player, player:getPrimaryHandItem(), route.tool, true, routeId == "smash")
        end
        ISTimedActionQueue.add(ISLugliDMSRouteAction:new(player, obj, routeId))
        return true
    end

    --- Is this survivor's own action on this route of this gate queued or running?
    function M.workingOn(player, obj, routeId)
        local _, gateId = M.gateArgs(obj, routeId)
        local held = gateId ~= nil and holders[gateId] or nil
        return held ~= nil and held.player == player and held.action ~= nil and held.action.routeId == routeId
    end

    -- ---- the code ----------------------------------------------------------------------------------

    --- What the code window shows of a safe, from the tag the authority mirrors: never the code.
    function M.keypadView(md, square)
        return { kind = md.kind, revealed = md.revealed, triesLeft = md.triesLeft,
                 lockedFor = M.lockedFor(md), powered = M.keypadPowered(md, square) }
    end

    --- Is a try at this safe's code in the survivor's queue, started or not? The queue's first
    --- entry is the running action (ISTimedActionQueue.lua), so a double Enter is one try.
    local function codeQueued(player, obj)
        local ok, found = pcall(function()
            local list = ISTimedActionQueue.getTimedActionQueue(player).queue
            for _, a in ipairs(list) do
                if a.Type == "ISLugliDMSRouteAction" and a.obj == obj and a.routeId == "code" then return true end
            end
            return false
        end)
        return ok and found == true
    end

    --- Type a code into a safe: the four digits go to the authority after the 4 second try, from
    --- where the survivor stands (the window only stays open in reach). A try already under way
    --- keeps its code. True when the try was queued.
    function M.submitCode(player, obj, code)
        if type(code) ~= "string" or string.find(code, "^%d%d%d%d$") == nil then return false end
        local md = M.sealedGateOf(obj)
        if md == nil then return false end
        local route = routeOn(player, obj, md, "code")
        if not route.ok then
            halo(player, M.reasonText(route.reason), false)
            return false
        end
        if codeQueued(player, obj) then return false end
        ISTimedActionQueue.add(ISLugliDMSRouteAction:new(player, obj, "code", code))
        return true
    end

    --- Open the code window on a safe (Keypad.lua, read now: it loads after this one).
    function M.openCode(player, obj)
        local md = M.sealedGateOf(obj)
        if md == nil then return nil end
        if type(M.openKeypad) ~= "function" then
            M.defect(PART, "the code window did not load")
            return nil
        end
        return M.openKeypad(player, obj, M.keypadView(md, squareOf(obj)), function(code)
            return M.submitCode(player, obj, code)
        end, function()
            local fresh = M.sealedGateOf(obj)
            return fresh ~= nil and M.keypadView(fresh, squareOf(obj)) or nil
        end)
    end

    -- ---- inspecting ------------------------------------------------------------------------------

    --- Real seconds the survivor looks the box over before its window opens: 1 until 2026-11-19,
    --- when the user asked for it 1.5 times faster.
    M.INSPECT_SECONDS = 1 / 1.5

    --- A short look at the box, then its window (InspectWindow.lua). The window's own reach decides
    --- whether the look can go on, so the two never disagree about where the survivor must stand.
    ISLugliDMSInspectAction = ISBaseTimedAction:derive("ISLugliDMSInspectAction")

    function ISLugliDMSInspectAction:isValid()
        if M.sealedGateOf(self.obj) == nil then return false end
        return M.inspectInReach(self.character, self.obj) == true
    end

    function ISLugliDMSInspectAction:waitToStart()
        self.character:faceThisObject(self.obj)
        return self.character:shouldBeTurning()
    end

    function ISLugliDMSInspectAction:update()
        self.character:faceThisObject(self.obj)
    end

    --- Vanilla's container search (ISInventoryTransferAction:start), low: the box sits on the floor.
    function ISLugliDMSInspectAction:start()
        self:setActionAnim("Loot")
        self:setAnimVariable("LootPosition", "Low")
    end

    function ISLugliDMSInspectAction:perform()
        ISBaseTimedAction.perform(self)
        if self.opens ~= nil then
            self.opens(self.character, self.obj)
        else
            M.openInspect(self.character, self.obj)
        end
    end

    --- opens(player, obj) is the window the look ends in: the inspect window when nil.
    function ISLugliDMSInspectAction:new(character, obj, opens)
        local o = ISBaseTimedAction.new(self, character)
        o.obj = obj
        o.opens = opens
        o.stopOnWalk = true
        o.stopOnRun = true
        o.stopOnAim = true
        o.maxTime = math.max(1, math.floor(M.INSPECT_SECONDS * M.ACTION_UNITS_PER_SECOND))
        if character:isTimedActionInstant() then o.maxTime = 1 end
        return o
    end

    --- THE ONE WAY TO INSPECT A GATE: walk to it the way a route does, look it over, and only then
    --- open its window. The window is InspectWindow.lua's, read now: that file loads after this one.
    --- Returns true when the look was queued.
    function M.startInspect(player, obj)
        if player == nil or obj == nil then return false end
        if M.sealedGateOf(obj) == nil then return false end
        if type(M.openInspect) ~= "function" or type(M.inspectInReach) ~= "function" then
            M.defect(PART, "the inspect window did not load")
            return false
        end
        if not walkTo(player, obj) then return false end
        ISTimedActionQueue.add(ISLugliDMSInspectAction:new(player, obj))
        return true
    end

    M.addHandler(PART, "OnServerCommand", function(module, command, args)
        if module ~= M.NET_MODULE then return end
        M.onReply(command, args)
    end)
    M.addTeardown(PART, function()
        holders = {}
        lastGateId = nil
        local ringing = {}
        for key in pairs(alarms) do ringing[#ringing + 1] = key end
        for i = 1, #ringing do silence(ringing[i]) end
    end)
    M.status(PART, true)
end
