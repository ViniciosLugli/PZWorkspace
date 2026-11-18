--[[
Nick's Generator Manager: its once-a-minute billing scan is spread over many ticks instead of one.

What happens today. Every in-game minute, and on every claim, Nick's Generator Manager walks every
square in range of every running generator (about 8,800 squares at range 20, vertical 3) to find
the appliances it bills, all inside one tick, on the server and on every client that has the
generator loaded. Measured on 42.22.2 at a suburban spawn (1,516 loaded squares, 2,188 objects in
range): 7.6 ms per running generator, 22.8 ms for three, every 5 s at a 2-hour day. The cost grows
with every base that runs a generator.

What this part changes. A generator's scan becomes a job that walks up to SQUARES_PER_TICK square
positions per tick; when its disc is done, Nick's own recompute bills it from that list. Nothing in
the billing changes: the same squares, the same predicate (Nick's isBillable), the same order, and
Nick's own recomputeGenerator does the owner resolution and writes the target. A generator's target
moves to the new pass a few ticks later instead of at once, and the per-tick re-assert holds the
previous target until then. The Manage Power panel still scans on its own, as before.
]]
require "ModpackFixes_Status"
local M = LugliModpackFixes

-- Square positions per tick. 7.6 ms over about 8,800 positions is about 0.9 us each, so 1,000 is
-- about 1 ms of a 100 ms server tick, and a generator's disc takes about 9 ticks.
local SQUARES_PER_TICK = 1000

local function check()
    local NGM = NicksGeneratorManager
    for _, key in ipairs({ "recomputeGenerator", "poweredObjectsInRange", "isBillable", "liveGenerator",
                           "isActive", "geom", "genKey" }) do
        if type(NGM) ~= "table" or type(NGM[key]) ~= "function" then
            return "Nick's Generator Manager has no " .. key
        end
    end
    if type(NGM.generators) ~= "table" or type(NGM.targets) ~= "table" then
        return "Nick's Generator Manager has no generator registry"
    end
    return nil
end

local function install(ctx)
    local NGM = NicksGeneratorManager
    local queue, queued = {}, {}
    local job = nil
    local serving = nil
    local recompute

    local function enqueue(e)
        local key = NGM.genKey(e.gx, e.gy, e.gz)
        if queued[key] then return end
        queued[key] = true
        queue[#queue + 1] = key
    end

    local function startJob()
        while #queue > 0 do
            local key = table.remove(queue, 1)
            queued[key] = nil
            local e = NGM.generators[key]
            if e ~= nil then
                local g = NGM.geom()
                return { e = e, key = key, g = g, oz = e.gz - g.vr, ox = e.gx - g.radius, oy = e.gy - g.radius, out = {} }
            end
        end
        return nil
    end

    -- Walks the disc in Nick's order (z, then x, then y) and bills from the list when it is done.
    local function step()
        local budget = SQUARES_PER_TICK
        while budget > 0 do
            if job == nil then
                job = startJob()
                if job == nil then return end
            end
            local j, g, e = job, job.g, job.e
            local dx, dy = j.ox - e.gx, j.oy - e.gy
            if dx * dx + dy * dy <= g.r2 then
                local sq = getSquare(j.ox, j.oy, j.oz)
                if sq ~= nil then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local o = objs:get(i)
                        if NGM.isBillable(o, sq, g.allowExt) then j.out[#j.out + 1] = o end
                    end
                end
            end
            budget = budget - 1
            j.oy = j.oy + 1
            if j.oy > e.gy + g.radius then
                j.oy = e.gy - g.radius
                j.ox = j.ox + 1
                if j.ox > e.gx + g.radius then
                    j.ox = e.gx - g.radius
                    j.oz = j.oz + 1
                end
            end
            if j.oz > e.gz + g.vr then
                job = nil
                serving = j
                local ok, err = pcall(recompute, e)
                serving = nil
                if not ok then error(err) end
            end
        end
    end

    ctx.wrap(NGM, "poweredObjectsInRange", function(callOriginal)
        return function(gx, gy, gz, ...)
            local s = serving
            if s ~= nil and s.e.gx == gx and s.e.gy == gy and s.e.gz == gz then return s.out end
            return callOriginal(gx, gy, gz, ...)
        end
    end)

    recompute = NGM.recomputeGenerator
    ctx.wrap(NGM, "recomputeGenerator", function(callOriginal)
        return function(e, ...)
            if serving ~= nil or e == nil then return callOriginal(e, ...) end
            local gen = NGM.liveGenerator(e)
            if gen == nil or not NGM.isActive(gen) then return callOriginal(e, ...) end
            enqueue(e)
            local target = NGM.targets[NGM.genKey(e.gx, e.gy, e.gz)]
            return target and target.total or nil
        end
    end)

    ctx.on("OnTick", step)
    ctx.undo(function()
        queue, queued, job, serving = {}, {}, nil, nil
    end)
end

M.addPart({
    name = "ngm-slice",
    switch = "NgmSlice",
    title = "Nick's Generator Manager: the minute billing scan is spread over ticks",
    tip = "Nick's Generator Manager scans every square around each running generator once a minute, all in one tick, on the server and on each player's game: about 8 ms per generator. This spreads that scan over a few ticks, so bases with generators no longer cause a stall every few seconds. Billing is unchanged.",
    kind = "perf",
    all = { "NicksGeneratorManager" },
    side = "both",
    phase = "world",
    pins = { "ngm.scan", "ngm.recompute", "ngm.pass" },
    check = check,
    install = install,
})
