--[[
    Codes
    A safe's 4-digit code and the paper clues to it. Pure: every answer is a hash of the gate id
    and the world's salt, so the authority mints the same code and the same clues on every load,
    and dms-codes drives the whole module offline.

    A CLUE IS DATA, NEVER TEXT. Each is { key = <IG_UI translation key>, args = { numbers } }: the
    key is one of a kind's templates, a plain sentence in the dead man's own voice ("The first
    number is 4, and the third number is odd."), so a note reads in the player's language and
    codeCandidates() re-reads it from its kind without parsing a sentence. Positions are 1..4, left
    to right, and stay numbers in the data; only clueArgs() turns them into ordinal words
    (IGUI_LugliDMS_Clue_Pos_<n>: first, second, third, last) for the template. No kind is a sum
    or any other arithmetic: each says what a number is, is not, or how two compare.

    THE CLUES ARE ONE NESTED LIST. safeClues(n) is the first n of the same three, so each note
    found only ever narrows the code. Any one clue alone leaves at least 100 codes, since no kind
    says more than two numbers (a pair, or a number and two the same, leaves 100; dms-codes holds
    every clue to 20);
    two leave CLUE_PAIR_MIN_LEFT..CLUE_PAIR_MAX_LEFT, two lockouts at most to try them all; three
    at least CLUE_MIN_LEFT, so no set pins all four digits. Every clue rules something out.

    THE SEARCH ENUMERATES, IT DOES NOT GUESS. Every clue true of the code is listed and read in a
    seeded order that takes each kind in turn. The first clue is a strong kind (two numbers; one
    number and two that are the same; one number and a small range of another); after it, the
    second is the first in that order that fits and still admits a third, the third the first
    that fits. A first clue naming two numbers always completes (a third number leaves 10, odd or
    even of the last 5), so it is the last resort and the search always ends.

    A NOTE IS TAGGED WITH ITS SAFE. Keys mints each note with modData[NOTE_TAG] = the gate id (not
    a secret: the gate id is the safe's square). noteGateOf and carriedNotes read that tag on any
    side, so the client finds the notes a survivor carries for the safe in front of them.
]]

require "LugliDeadMansStash/Core"
require "LugliDeadMansStash/Spots"

LugliDeadMansStash = LugliDeadMansStash or {}

do
    local M = LugliDeadMansStash

    M.CODE_DIGITS = 4
    M.CLUE_MAX = 3
    M.CLUE_PAIR_MIN_LEFT = 3
    M.CLUE_PAIR_MAX_LEFT = 10
    M.CLUE_MIN_LEFT = 2
    -- How many seeded first clues are tried before the two-number one that always completes.
    M.CLUE_FIRST_TRIES = 3
    M.CLUE_POS_PREFIX = "IGUI_LugliDMS_Clue_Pos_"
    M.NOTE_TAG = "LugliDMSNote"

    -- THE TEMPLATES. A clue's key is IGUI_LugliDMS_Clue_<Name>_<variant>, variant 1..count.
    M.CLUE_KINDS = {
        digit = { name = "Digit", variants = 2 },
        pair = { name = "Pair", variants = 3 },
        odd = { name = "Odd", variants = 1 },
        even = { name = "Even", variants = 1 },
        range = { name = "Range", variants = 1 },
        greater = { name = "Greater", variants = 1 },
        same = { name = "Same", variants = 1 },
        without = { name = "Without", variants = 1 },
        digitOdd = { name = "DigitOdd", variants = 1 },
        digitEven = { name = "DigitEven", variants = 1 },
        digitRange = { name = "DigitRange", variants = 1 },
        digitSame = { name = "DigitSame", variants = 1 },
    }

    --- The translation key of a kind's template `variant`.
    function M.clueKey(kind, variant)
        return "IGUI_LugliDMS_Clue_" .. M.CLUE_KINDS[kind].name .. "_" .. variant
    end

    -- The kind each key reads as.
    local KIND_OF_KEY = {}
    for kind, def in pairs(M.CLUE_KINDS) do
        for v = 1, def.variants do KIND_OF_KEY[M.clueKey(kind, v)] = kind end
    end

    --- The kind a clue key reads as, or nil.
    function M.clueKind(key) return KIND_OF_KEY[key] end

    -- THE NOTE'S SAFE, after its room: IGUI_LugliDMS_Note_<room> ("the office safe"), else _safe.
    M.NOTE_ROOMS = {
        office = true, pawnshop = true, pawnshopoffice = true, pawnshopstorage = true,
        vault = true, depositboxes = true, bankstorage = true, jewelrystorage = true,
        policegunstorage = true, evidenceroom = true, policestorage = true, captainoffice = true,
        bedroom = true, gunstorestorage = true, pharmacystorage = true,
    }

    --- The translation key naming the safe a clue note is about, for a safe in this room.
    function M.clueNoteName(roomName)
        if type(roomName) == "string" and M.NOTE_ROOMS[roomName] then return "IGUI_LugliDMS_Note_" .. roomName end
        return "IGUI_LugliDMS_Note_safe"
    end

    -- What each kind says, as a test on the four digits d[1..4]: its arg count, which args are
    -- positions, and the test.
    local TESTS = {
        digit = { n = 2, pos = { 1 }, fn = function(d, a) return d[a[1]] == a[2] end },
        pair = { n = 4, pos = { 1, 2 }, fn = function(d, a) return d[a[1]] == a[3] and d[a[2]] == a[4] end },
        odd = { n = 1, pos = { 1 }, fn = function(d, a) return d[a[1]] % 2 == 1 end },
        even = { n = 1, pos = { 1 }, fn = function(d, a) return d[a[1]] % 2 == 0 end },
        range = { n = 3, pos = { 1 }, fn = function(d, a) return d[a[1]] >= a[2] and d[a[1]] <= a[3] end },
        greater = { n = 2, pos = { 1, 2 }, fn = function(d, a) return d[a[1]] > d[a[2]] end },
        same = { n = 2, pos = { 1, 2 }, fn = function(d, a) return d[a[1]] == d[a[2]] end },
        without = { n = 1, pos = {}, fn = function(d, a)
            return d[1] ~= a[1] and d[2] ~= a[1] and d[3] ~= a[1] and d[4] ~= a[1]
        end },
        digitOdd = { n = 3, pos = { 1, 3 }, fn = function(d, a) return d[a[1]] == a[2] and d[a[3]] % 2 == 1 end,
            parts = function(a) return { { "digit", { a[1], a[2] } }, { "odd", { a[3] } } } end },
        digitEven = { n = 3, pos = { 1, 3 }, fn = function(d, a) return d[a[1]] == a[2] and d[a[3]] % 2 == 0 end,
            parts = function(a) return { { "digit", { a[1], a[2] } }, { "even", { a[3] } } } end },
        digitRange = { n = 5, pos = { 1, 3 }, fn = function(d, a)
            return d[a[1]] == a[2] and d[a[3]] >= a[4] and d[a[3]] <= a[5]
        end, parts = function(a) return { { "digit", { a[1], a[2] } }, { "range", { a[3], a[4], a[5] } } } end },
        digitSame = { n = 4, pos = { 1, 3, 4 }, fn = function(d, a) return d[a[1]] == a[2] and d[a[3]] == d[a[4]] end,
            parts = function(a) return { { "digit", { a[1], a[2] } }, { "same", { a[3], a[4] } } } end },
    }

    local function digitsOf(n)
        return { math.floor(n / 1000) % 10, math.floor(n / 100) % 10, math.floor(n / 10) % 10, n % 10 }
    end

    local function textOf(d) return d[1] .. "" .. d[2] .. d[3] .. d[4] end

    local ALL = nil
    local function allCodes()
        if ALL == nil then
            ALL = {}
            for n = 0, 9999 do ALL[n + 1] = digitsOf(n) end
        end
        return ALL
    end

    --- The clue's test, or nil for a clue this module never writes: an unknown key, the wrong
    --- arg count, an arg that is not a number, a position outside 1..4, or one position twice.
    local function testOf(clue)
        if type(clue) ~= "table" or type(clue.args) ~= "table" then return nil end
        local kind = KIND_OF_KEY[clue.key]
        local test = kind ~= nil and TESTS[kind] or nil
        if test == nil or #clue.args ~= test.n then return nil end
        for i = 1, test.n do
            if M.finite(clue.args[i]) == nil then return nil end
        end
        local seen = {}
        for i = 1, #test.pos do
            local p = clue.args[test.pos[i]]
            if p ~= math.floor(p) or p < 1 or p > M.CODE_DIGITS or seen[p] then return nil end
            seen[p] = true
        end
        return test.fn
    end

    --- The args a clue's template is filled with: its numbers, each position as its ordinal word
    --- (IGUI_LugliDMS_Clue_Pos_<n>). A new list; the clue's own args stay numbers.
    function M.clueArgs(clue)
        local out = {}
        if type(clue) ~= "table" or type(clue.args) ~= "table" then return out end
        for i = 1, #clue.args do out[i] = clue.args[i] end
        local kind = KIND_OF_KEY[clue.key]
        local test = kind ~= nil and TESTS[kind] or nil
        if test == nil then return out end
        for i = 1, #test.pos do
            local p = out[test.pos[i]]
            if type(p) == "number" then out[test.pos[i]] = M.T(M.CLUE_POS_PREFIX .. p, tostring(p)) end
        end
        return out
    end

    --- The codes of `list` the clue allows; none for a clue that is not one. With `cap`, nil as
    --- soon as more than cap are allowed: the search stops reading a clue that cannot fit.
    local function filter(list, clue, cap)
        local out = {}
        local fn = testOf(clue)
        if fn == nil then return out end
        local args = clue.args
        for i = 1, #list do
            if fn(list[i], args) then
                out[#out + 1] = list[i]
                if cap ~= nil and #out > cap then return nil end
            end
        end
        return out
    end

    --- A seeded stream of draws in (0, 1). Each draw hashes the decimal digits of the last one:
    --- M.hash is affine in its characters, so draws keyed "...|1", "...|2" would step by a
    --- constant and a code's digits would follow each other.
    local function stream(seed)
        local h = M.hash(seed)
        return function()
            h = M.hash("n|" .. h)
            return M.unit("u|" .. h)
        end
    end

    --- The gate's 4-digit code, as a string of four digits ("0427").
    function M.safeCode(gateId, salt)
        local u = stream("code|" .. tostring(gateId) .. "|" .. tostring(salt))
        local d = {}
        for i = 1, M.CODE_DIGITS do d[i] = math.floor(u() * 10) % 10 end
        return textOf(d)
    end

    local function digitsOfText(code)
        local d = {}
        for i = 1, M.CODE_DIGITS do d[i] = tonumber(string.sub(code, i, i)) end
        return d
    end

    --- Every clue true of d, in a fixed order, each in a seeded template of its kind: strong ones
    --- (two numbers; a number and two the same; a number and a range) in `first`, every one in `any`.
    local function trueClues(u, d)
        local first, any = {}, {}
        local function add(kind, args, strong)
            local variants = M.CLUE_KINDS[kind].variants
            local clue = { key = M.clueKey(kind, 1 + math.min(variants - 1, math.floor(u() * variants))), args = args }
            any[#any + 1] = clue
            if strong then first[#first + 1] = clue end
        end
        for p = 1, 4 do
            add("digit", { p, d[p] })
            add(d[p] % 2 == 1 and "odd" or "even", { p })
            for w = 2, 5 do
                for lo = math.max(0, d[p] - w + 1), math.min(d[p], 10 - w) do add("range", { p, lo, lo + w - 1 }) end
            end
            for q = 1, 4 do
                if q ~= p then
                    add(d[q] % 2 == 1 and "digitOdd" or "digitEven", { p, d[p], q })
                    for w = 2, 5 do
                        for lo = math.max(0, d[q] - w + 1), math.min(d[q], 10 - w) do
                            add("digitRange", { p, d[p], q, lo, lo + w - 1 }, true)
                        end
                    end
                end
            end
        end
        for p = 1, 3 do
            for q = p + 1, 4 do
                add("pair", { p, q, d[p], d[q] }, true)
                if d[p] == d[q] then
                    add("same", { p, q })
                    for r = 1, 4 do
                        if r ~= p and r ~= q then add("digitSame", { r, d[r], p, q }, true) end
                    end
                elseif d[p] > d[q] then
                    add("greater", { p, q })
                else
                    add("greater", { q, p })
                end
            end
        end
        for v = 0, 9 do
            if d[1] ~= v and d[2] ~= v and d[3] ~= v and d[4] ~= v then add("without", { v }) end
        end
        return first, any
    end

    --- The list in a seeded order (Fisher-Yates), as a new list.
    local function shuffled(u, list)
        local out = {}
        for i = 1, #list do out[i] = list[i] end
        for i = #out, 2, -1 do
            local j = 1 + math.min(i - 1, math.floor(u() * i))
            out[i], out[j] = out[j], out[i]
        end
        return out
    end

    --- The clues in a seeded order that takes each kind in turn, so the many ranges do not crowd
    --- out the handful of every other kind.
    local function mixed(u, list)
        local groups, kinds = {}, {}
        for i = 1, #list do
            local kind = KIND_OF_KEY[list[i].key]
            if groups[kind] == nil then
                groups[kind] = {}
                kinds[#kinds + 1] = kind
            end
            local g = groups[kind]
            g[#g + 1] = list[i]
        end
        kinds = shuffled(u, kinds)
        for i = 1, #kinds do groups[kinds[i]] = shuffled(u, groups[kinds[i]]) end
        local out, round = {}, 1
        while #out < #list do
            for i = 1, #kinds do
                local c = groups[kinds[i]][round]
                if c ~= nil then out[#out + 1] = c end
            end
            round = round + 1
        end
        return out
    end

    --- Does every fact of a two-fact clue tell something `list` does not already, so a note never
    --- repeats what an earlier one said ("the last number is 5" ... "and the last is odd")?
    local function eachPartCuts(clue, list)
        local test = TESTS[KIND_OF_KEY[clue.key]]
        if test.parts == nil then return true end
        local parts = test.parts(clue.args)
        for i = 1, #parts do
            local left = filter(list, { key = M.clueKey(parts[i][1], 1), args = parts[i][2] }, #list - 1)
            if left == nil then return false end
        end
        return true
    end

    --- The first clue of `order`, from `from`, that cuts `list` to lo..hi and says nothing
    --- already known, with what it leaves and where it was.
    local function firstFit(order, list, lo, hi, from)
        for i = from or 1, #order do
            local left = filter(list, order[i], hi)
            if left ~= nil and #left >= lo and #left < #list and eachPartCuts(order[i], list) then
                return order[i], left, i
            end
        end
        return nil
    end

    --- The second and third clue after a first that leaves l1, or nil when none completes it.
    local function rest(order, l1)
        local from = 1
        while true do
            local c2, l2, at = firstFit(order, l1, M.CLUE_PAIR_MIN_LEFT, M.CLUE_PAIR_MAX_LEFT, from)
            if c2 == nil then return nil end
            local c3 = firstFit(order, l2, M.CLUE_MIN_LEFT, nil)
            if c3 ~= nil then return c2, c3 end
            from = at + 1
        end
    end

    local function build(gateId, salt)
        local d = digitsOfText(M.safeCode(gateId, salt))
        local u = stream("clue|" .. tostring(gateId) .. "|" .. tostring(salt))
        local first, any = trueClues(u, d)
        first = mixed(u, first)
        local order = mixed(u, any)
        local all = allCodes()
        for i = 1, math.min(M.CLUE_FIRST_TRIES, #first) do
            local c2, c3 = rest(order, filter(all, first[i]))
            if c2 ~= nil then return { first[i], c2, c3 } end
        end
        local sure = nil
        for i = 1, #first do
            if KIND_OF_KEY[first[i].key] == "pair" then sure = first[i] break end
        end
        local c2, c3 = rest(order, filter(all, sure))
        return { sure, c2, c3 }
    end

    -- The search is pure and costs tens of ms, and every note of a safe asks it again.
    local built = {}

    --- The first n (0..3) clues to the gate's code, each { key, args }.
    function M.safeClues(gateId, salt, n)
        n = M.clamp(math.floor(tonumber(n) or 0), 0, M.CLUE_MAX)
        local out = {}
        if n == 0 then return out end
        local memoKey = tostring(gateId) .. "|" .. tostring(salt)
        local full = built[memoKey]
        if full == nil then
            full = build(gateId, salt)
            built[memoKey] = full
        end
        for i = 1, n do
            local args = {}
            for a = 1, #full[i].args do args[a] = full[i].args[a] end
            out[i] = { key = full[i].key, args = args }
        end
        return out
    end

    --- Every code (a 4-digit string, ascending) that all these clues allow.
    function M.codeCandidates(clues)
        local list = allCodes()
        if type(clues) == "table" then
            for i = 1, #clues do list = filter(list, clues[i]) end
        end
        local out = {}
        for i = 1, #list do out[i] = textOf(list[i]) end
        return out
    end

    -- ---- the notes a survivor carries ---------------------------------------------------------------

    --- The gate id a clue note was minted for, or nil for any other item. Never creates modData.
    function M.noteGateOf(item)
        if item == nil or not item:hasModData() then return nil end
        local gate = item:getModData()[M.NOTE_TAG]
        if type(gate) == "string" then return gate end
        return nil
    end

    --- The clue notes for `gateId` (every safe's when nil) the survivor carries, in the main
    --- inventory and one level into the bags in it, each { item, text = its page 1 }. Newest
    --- first: an item picked up is appended to its container, so each container reads last to
    --- first, the main inventory before the bags.
    function M.carriedNotes(player, gateId)
        local out = {}
        local inv = player ~= nil and player:getInventory() or nil
        if inv == nil then return out end
        local want = gateId ~= nil and tostring(gateId) or nil
        local bags = {}
        local function walk(container, intoBags)
            local items = container:getItems()
            for i = items:size() - 1, 0, -1 do
                local item = items:get(i)
                local gate = M.noteGateOf(item)
                if gate ~= nil and (want == nil or gate == want) then
                    out[#out + 1] = { item = item, text = item:seePage(1) or "" }
                end
                if intoBags and instanceof(item, "InventoryContainer") then bags[#bags + 1] = item:getInventory() end
            end
        end
        walk(inv, true)
        for i = 1, #bags do
            if bags[i] ~= nil then walk(bags[i], false) end
        end
        return out
    end
end
