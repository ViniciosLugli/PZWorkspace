package lugli.optimizations;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaEventManager;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;

/**
 * Spread the per-square LoadGridsquare Lua burst across frames.
 * -Dlugli.opt.chunklua=off|observe|spread     (default observe)
 * -Dlugli.opt.chunklua.budget=N               (microseconds per frame, default 4000)
 *
 * THE PROBLEM, MEASURED
 *   Chunk arrival is the single largest source of frame spikes in a city. Two Louisville runs:
 *
 *     frames where IsoChunk.doLoadGridsquare fires   8.9 % / 7.9 %
 *     frame p50 in those frames                      37.0 ms / 35.1 ms
 *     frame p50 in every other frame                 15.6 ms / 15.1 ms
 *     p90 in those frames                            104.5 ms / 96.2 ms
 *
 *   A chunk load turns a 64 fps frame into a 27 fps one, and at p90 into 9.6 fps. Two thirds of
 *   that is mod Lua: `Lua - LoadGridsquare` is 25.1 % of the above-median time budget against
 *   12.0 % for the engine's own doLoadGridsquare work.
 *
 *   The burst is structural. Crossing one chunk boundary queues a whole 19-chunk edge, and the
 *   drain throttle (IsoChunkMap.java:178-181) is
 *       count = 1 + count * 3 / chunkGridWidth
 *   which is BACKLOG-PROPORTIONAL: the further behind you are the more chunks are taken in one
 *   frame, so it amplifies bursts rather than smoothing them. Each chunk then dispatches the
 *   event once per non-empty square (IsoChunk.java:3802-3837) to every registered handler.
 *
 * WHY NOT CAP THE CHUNK DRAIN
 *   Tried and REJECTED -- see src/Dev/lugli/dev/ChunkBudget.java. Deferring the chunk itself
 *   decouples `chunk.loaded` from vehicle streaming and produces
 *   NullPointerException: Cannot read field "vehicles" because "this.chunk" is null.
 *   The queue's drain RATE is an invariant other systems depend on.
 *
 *   This patch does the opposite: the chunk loads in exactly the frame it always did, with the
 *   same `loaded` flag at the same instant. Only the LUA NOTIFICATION is spread. Nothing in the
 *   engine reads the event -- triggerEvent returns void, Event.trigger's boolean is discarded by
 *   every 1-arg caller, and the Java-side per-square work already lives in
 *   LoadGridsquarePerformanceWorkaround and MapObjects.loadGridSquare, both independent of it.
 *
 * WHAT A HANDLER CAN OBSERVE
 *   The same IsoGridSquare, later. Newly loaded chunks arrive at the edge of the 19x19 grid,
 *   72-76 tiles from the player, so a handler that decorates a square is acting on ground at or
 *   beyond the screen edge. The budget bounds the lag: at the ORIGINAL 2.5 ms/frame and 64 fps a p90 burst
 *   (~38 ms of Lua) finishes in ~15 frames, about 240 ms, during which a walking player covers
 *   under two tiles.
 *
 * SAFETY, in the order it can bite
 *   1. A deferred square can be discarded first. discard() nulls `chunk` (IsoGridSquare:1180),
 *      and squares are POOLED (isoGridSquareCache, 16384), so a recycled one can be live again
 *      at a DIFFERENT location. Both are covered: an entry is dispatched only if the square
 *      still has a chunk AND still reports the x/y/z it was queued at. A recycled square that
 *      lands on the same coordinates is the same place, so dispatching for it is correct.
 *   2. Re-entrancy: the drain calls triggerEvent, the method this class advises. A flag makes
 *      the drain's own calls pass straight through.
 *   3. Off-main-thread dispatch (WorldStreamer Convert/SoftReset jobs, WorldStreamer.java:491)
 *      must not be captured -- LuaEventManager already routes those to its own queue. Only calls
 *      on the thread that owns the drain are deferred.
 *   4. World exit CLEARS the queue rather than flushing it: IngameState.exit is already tearing
 *      the world down and firing ReuseGridsquare, and dispatching load events into a dying world
 *      is strictly worse than dropping them.
 *   5. Unbounded growth: above MAX_QUEUE the deferral gives up and dispatches inline, so the
 *      worst case degrades to vanilla behaviour rather than to an OOM.
 *
 * OBSERVE MODE
 *   Measures without changing anything: per frame it accumulates how many LoadGridsquare
 *   dispatches happened and how long they took, then reports the distribution. It exists because
 *   GameProfiler inflates exactly this measurement -- it wraps EVERY callback in a pooled,
 *   synchronized ProfileArea, and the bench's own duty cycle shows armed p50 19.712 ms against
 *   disarmed 13.055 ms on the same run. Any claim about what this costs must come from a
 *   profiler-free number.
 */
public final class ChunkLuaSpread {

    public static final String EVENT = "LoadGridsquare";

    public static final String MODE = System.getProperty("lugli.opt.chunklua", "observe");
    public static final boolean ENABLED = !"off".equals(MODE);
    public static final boolean SPREAD = "spread".equals(MODE);

    /** Microseconds of deferred Lua allowed per frame, at rest. */
    public static final long BUDGET_NS =
            Integer.getInteger("lugli.opt.chunklua.budget", 4000).longValue() * 1000L;

    /**
     * The backlog must always be drainable within this many frames.
     *
     * A FIXED budget is not enough, and the first measured run proves it. At the 2.5 ms/frame this
     * defaulted to back then -- BUDGET_NS is 4000 us now -- the
     * drain could clear ~35 squares a frame while arrival averaged 46 (434,324 squares over
     * 9,437 frames at ~72 us each = 3.3 ms/frame of work against a 2.5 ms allowance). A budget
     * below the mean ARRIVAL RATE does not smooth a burst, it accumulates one: the queue grows
     * without bound, entries age, their chunks unload, and the drain finds them invalid.
     * Result was dropped=65,267 of deferred=403,519 -- 16.2 % of squares never got their event
     * at all, which is a mod-behaviour regression, not a performance trade.
     *
     * So the budget is derived from the backlog instead: each frame, allow enough time to clear
     * what is queued within MAX_LAG_FRAMES, using the drain's own observed cost per square. That
     * bounds latency by construction -- which is what bounds drops -- while the ceiling stops a
     * huge burst from simply moving the whole spike into one frame.
     */
    public static final int MAX_LAG_FRAMES = Integer.getInteger("lugli.opt.chunklua.lag", 12);

    /**
     * Staleness rate above which the lag window is tightened, in parts per thousand of deferrals.
     *
     * WHAT THIS IS NOT. It was once read as a correctness budget, on the belief that a square the
     * drain finds stale is "a mod handler that never ran for that tile". That belief is wrong.
     * `IsoChunk.doLoadGridsquare` fires LoadGridsquare for every non-empty square on every entry
     * of a chunk into the world, and the `isNewChunk()` guard beside it covers only
     * `addRatsAfterLoading` -- in 42.20.4 bytecode the `ifeq` targets the dispatch itself, so it
     * is the join point. A stale entry is a tile that LEFT THE WORLD, and it is re-announced when
     * it returns: on one city run 49,330 of 60,000 tracked coordinates fired the event more than
     * once. Nothing is lost, so this is a LATENCY knob.
     *
     * The history behind the number is still sound: a fixed 2.5 ms budget went stale on 16.2 % of
     * entries; deriving the budget from the backlog took it to 3-7 %; an explicit age cap took it
     * to 1.6-1.8 %.
     *
     * Rather than pick a lag that happens to work on one route, the window tightens itself
     * whenever the observed staleness rate exceeds this, and relaxes back toward MAX_LAG_FRAMES when
     * it is comfortably under. The floor of 1 frame is vanilla behaviour: everything dispatched
     * the frame after it was queued.
     *
     * DEFAULTED TO 1000 (never tightens) ON 2026-08-27, which effectively disables the governor.
     *
     * It was 5 while a stale entry was believed to be a lost event, and tightening the window was
     * how that loss was minimised. Nothing is lost, so the governor now buys nothing -- and it is
     * not free. Measured against itself on 42.20.4, Louisville, interleaved pairs, spread vs
     * observe:
     *
     *     governor active (5)     p50 +5.7 %, p90 +7.4 %, BOTH BANDS SEPARATED WORSE, p99 -10.0 %
     *     governor off    (1000)  p50 +2.1 %, p90 +2.4 %, bands overlap,              p99 -13.2 %
     *
     * A tightening window drains harder every frame, and that is exactly the mean cost. Turning it
     * off removes the cost AND improves the tail. The knob stays, so the old behaviour is one
     * property away. What never tightening costs is latency, not correctness: entries wait longer
     * and more are re-announced on chunk re-entry instead, on ground at the edge of the map.
     *
     * History, for anyone re-tuning: at 5 ppt the window churned 4-5 times a run, and tightening to
     * 3 made staleness WORSE (1.24-1.54 % against 1.06-1.10 %) -- the signature of a floor the lag
     * cannot reach. The bench route's teleports were once blamed for those unloads; removing every
     * teleport changed nothing, so they are ordinary scroll unloads.
     */
    public static final int DROP_BUDGET_PPT = Integer.getInteger("lugli.opt.chunklua.dropppt", 1000);

    /** Hard ceiling on one frame's deferred work, as a multiple of the resting budget. */
    public static final int BUDGET_CEIL_MULT = Integer.getInteger("lugli.opt.chunklua.ceil", 4);

    /** Above this the deferral gives up and runs inline, so the failure mode is vanilla. */
    public static final int MAX_QUEUE = Integer.getInteger("lugli.opt.chunklua.maxqueue", 60000);

    // ---- queue: parallel arrays, no per-entry allocation --------------------------------------
    private static Object[] qSquare = new Object[8192];
    private static int[] qX = new int[8192];
    private static int[] qY = new int[8192];
    private static int[] qZ = new int[8192];
    /** Frame number each entry was queued on, so latency can be bounded explicitly. */
    private static long[] qAt = new long[8192];
    private static int qHead = 0;
    private static int qTail = 0;

    /** Set while the drain dispatches, so its own triggerEvent calls are not re-captured. */
    private static boolean draining = false;

    /** The thread the drain runs on. Only calls on this thread are ever deferred. */
    private static Thread drainThread = null;

    // ---- counters -----------------------------------------------------------------------------
    public static long dispatches = 0L;
    public static long deferred = 0L;
    public static long dropped = 0L;
    /**
     * Stale entries recovered by re-resolving the PLACE, and entries whose place has left the
     * world and will be re-announced when it returns.
     *
     * These two were once a single `dropped` tally, and conflating them is what produced the wrong
     * verdict: neither is a lost event, so counting them as losses made the part look like it
     * traded correctness for smoothness when it does not. See the SAFETY section above.
     */
    public static long reresolved = 0L;
    public static long deferredToReload = 0L;

    /**
     * Self-test for `resolve()`, on the first RESOLVE_CHECKS live entries.
     *
     * The first run of the re-resolve reported `reresolved=0`, and TWO different things predict
     * that number: there was nothing to recover, or `resolve()` never works. Telling them apart
     * cannot wait for a case that may never occur, so the check runs on the path that is always
     * taken: for a square the queue just validated by identity, `resolve()` must hand back THAT
     * square. Any disagreement means the lookup is wrong and every `deferredToReload` is suspect.
     * Bounded, so it costs 256 lookups in a run and nothing after.
     */
    public static int resolveOk = 0;
    public static int resolveBad = 0;
    public static long overflowed = 0L;
    public static long frames = 0L;

    /**
     * Advice-reached counters, one per @Patch, each the literal FIRST statement of its entry
     * point -- before the ENABLED check, before the event-name compare, before everything.
     *
     * The existing tallies cannot serve this purpose. `dispatches` sits behind three guards
     * including `!ENABLED`, and `frames` behind `!ENABLED` as well. In `observe` mode -- which is
     * the SHIPPING default -- every one of those legitimately stays low or zero, so a missing
     * patch and a working one are indistinguishable from the report. That is not a hypothetical:
     * the deleted `doLoadGridsquare` advice read zero on its install probe in every run, and it
     * took a corpus-wide log study to establish that the patch genuinely never installed rather
     * than the path never being taken.
     *
     * `resets` counts world teardown and is legitimately 0 in any run that never leaves a world,
     * so PatchAudit reports zero there as UNKNOWN rather than as a missing patch.
     */
    public static long invTrigger = 0L;
    public static long invDrain = 0L;
    public static long resets = 0L;


    private ChunkLuaSpread() {}

    // -------------------------------------------------------------------------------------------

    /** True = the engine's triggerEvent body is skipped because this class took the square. */
    public static boolean intercept(String event, Object param) {
        invTrigger++;                     // FIRST statement: installation, not intent
        if (!ENABLED || draining) {
            return false;
        }
        // Reference compare first: IsoChunk.java:3837 passes a class-file literal and so does
        // this class, so both resolve to the same interned String. equals() is the fallback for
        // any caller that builds the name at runtime.
        if (event != EVENT && !EVENT.equals(event)) {
            return false;
        }
        if (!(param instanceof IsoGridSquare)) {
            return false;
        }
        countDispatch();
        if (!SPREAD) {
            return false;                       // observe mode counts and stands aside
        }
        Thread t = drainThread;
        if (t == null || t != Thread.currentThread()) {
            return false;                       // off-main dispatch: leave it to the engine
        }
        if (!enqueue((IsoGridSquare)param)) {
            overflowed++;
            return false;                       // queue full: behave exactly like vanilla
        }
        deferred++;
        return true;
    }

    private static boolean enqueue(IsoGridSquare sq) {
        if (Tuning.queueAtCapacity(qHead, qTail, MAX_QUEUE)) {
            return false;
        }
        if (qTail == qSquare.length) {
            compactOrGrow();
        }
        int depth = qTail - qHead + 1;
        if (depth > maxQueued) {
            maxQueued = depth;            // PEAK, not the instantaneous qTail-qHead the report shows
            maxQueuedFrame = frames;      // WHEN, because a teleport peak prices nothing a player pays
        }
        if (depth > steadyMaxQueued && frames > STEADY_AFTER) {
            steadyMaxQueued = depth;
        }
        qSquare[qTail] = sq;
        qX[qTail] = sq.getX();
        qY[qTail] = sq.getY();
        qZ[qTail] = sq.getZ();
        qAt[qTail] = frames;
        qTail++;
        return true;
    }

    private static void compactOrGrow() {
        int size = qTail - qHead;
        if (Tuning.shouldCompactQueue(qHead, size, qSquare.length)) {
            System.arraycopy(qSquare, qHead, qSquare, 0, size);
            System.arraycopy(qX, qHead, qX, 0, size);
            System.arraycopy(qY, qHead, qY, 0, size);
            System.arraycopy(qZ, qHead, qZ, 0, size);
            System.arraycopy(qAt, qHead, qAt, 0, size);
            java.util.Arrays.fill(qSquare, size, qTail, null);
            qHead = 0;
            qTail = size;
            return;
        }
        int cap = qSquare.length * 2;
        Object[] ns = new Object[cap];
        int[] nx = new int[cap];
        int[] ny = new int[cap];
        int[] nz = new int[cap];
        long[] na = new long[cap];
        System.arraycopy(qSquare, qHead, ns, 0, size);
        System.arraycopy(qX, qHead, nx, 0, size);
        System.arraycopy(qY, qHead, ny, 0, size);
        System.arraycopy(qZ, qHead, nz, 0, size);
        System.arraycopy(qAt, qHead, na, 0, size);
        qSquare = ns;
        qX = nx;
        qY = ny;
        qZ = nz;
        qAt = na;
        qHead = 0;
        qTail = size;
    }

    /** Called once per frame on the game thread. */
    public static void drain() {
        invDrain++;                       // FIRST statement: installation, not intent
        PatchAudit.tick();                // before the guard: the audit must survive chunklua=off
        if (!ENABLED) {
            return;
        }
        drainThread = Thread.currentThread();
        frames++;
        adaptLag();
        if (!SPREAD || qHead == qTail) {
            return;
        }
        long drainStart = System.nanoTime();
        long deadline = drainStart + frameBudgetNs(qTail - qHead);
        long drainedHere = 0L;
        draining = true;
        try {
            while (qHead < qTail) {
                Object o = qSquare[qHead];
                int x = qX[qHead];
                int y = qY[qHead];
                int z = qZ[qHead];
                qSquare[qHead] = null;
                qHead++;
                if (o instanceof IsoGridSquare) {
                    IsoGridSquare sq = (IsoGridSquare)o;
                    if (sq.getChunk() != null && sq.getX() == x && sq.getY() == y
                            && sq.getZ() == z) {
                        if (resolveOk + resolveBad < RESOLVE_CHECKS) {
                            if (resolve(x, y, z) == sq) {
                                resolveOk++;
                            } else {
                                resolveBad++;
                            }
                        }
                        LuaEventManager.triggerEvent(EVENT, sq);
                        drainedHere++;
                    } else {
                        // The queued OBJECT went stale -- its chunk unloaded, or the pooled square
                        // was recycled to another location. The PLACE is what the event describes,
                        // so ask for the place rather than throwing the entry away.
                        IsoGridSquare now = resolve(x, y, z);
                        if (now != null) {
                            // Still loaded: a different square object occupies the same tile. This
                            // is the same place, so dispatching for it is correct -- and resolving
                            // by coordinate makes the pooled-recycle case disappear entirely.
                            LuaEventManager.triggerEvent(EVENT, now);
                            drainedHere++;
                            reresolved++;
                        } else {
                            // The place has left the world. NOT a lost event: doLoadGridsquare
                            // fires LoadGridsquare for every non-empty square on every entry of a
                            // chunk into the world, and the isNewChunk() guard beside it covers
                            // only addRatsAfterLoading -- verified in 42.20.4 bytecode, where
                            // `ifeq` targets the dispatch itself, so it is the join point.
                            // Measured too: on one city run 49,330 of 60,000 tracked coordinates
                            // fired the event more than once, so this square is re-announced
                            // when the player returns to it.
                            deferredToReload++;
                        }
                    }
                } else {
                    dropped++;
                }
                // Age cap. The budget AIMS to clear the backlog within MAX_LAG_FRAMES, but its
                // ceiling can stop it doing so under load, and an entry that outlives its chunk
                // is dropped rather than dispatched -- a behaviour regression, not a slowdown.
                // So latency is also bounded explicitly: keep going past the deadline while the
                // head of the queue is older than MAX_LAG_FRAMES. Dropped fell from 16.2 % to
                // 3-7 % when the budget became backlog-derived; this closes the remainder.
                if (System.nanoTime() >= deadline
                        && (qHead >= qTail || frames - qAt[qHead] <= (long)lagFrames)) {
                    break;
                }
            }
            if (qHead == qTail) {
                qHead = 0;
                qTail = 0;
            }
        } finally {
            draining = false;
            if (drainedHere > 0L) {
                observeDrainCost(System.nanoTime() - drainStart, drainedHere);
            }
        }
    }

    // ---- self-tuning cost model ------------------------------------------------------------------
    //
    // Per-square cost is a property of the installed mod list, not something that can be
    // hardcoded: ~72 us on this list, ten times that with one heavy handler, and zero on a
    // vanilla profile where nothing is registered. So it is measured from the drain itself and
    // kept as an exponential moving average.

    /** Live lag window, tightened when squares are being dropped. */
    private static int lagFrames = MAX_LAG_FRAMES;
    private static long lastDeferred = 0L;
    private static long lastStale = 0L;
    public static int lagFloorHits = 0;
    /**
     * Times the lag window was tightened / relaxed.
     *
     * COUNTERS, not println. The tighten path logged through System.out, which lands in
     * console.txt -- and the benchmark harness reads the DebugLog. So a run reported lag=12/12 at
     * the end with no way to tell whether the window had never tightened or had tightened and
     * relaxed back. Anything the harness must be able to see has to be in the report string.
     */
    public static int lagTightened = 0;
    public static int lagRelaxed = 0;
    public static int lagMin = Integer.MAX_VALUE;

    private static long avgNsPerSquare = 60000L;      // seeded high; converges within a few drains
    public static long drained = 0L;

    /**
     * Deepest the pending queue has ever been, which the instantaneous `queued=` in the report
     * cannot show -- it reads `qTail - qHead` at teardown, by which time the drain has emptied it,
     * so every run has reported `queued=0` regardless of how deep it got mid-route.
     *
     * This is the number that prices a zero-drop flush at chunk unload: such a flush pays
     * `queued x costPerSquare` in ONE frame, so the peak is its worst case and the average is not
     * a bound. Purely observational; nothing reads it but the report.
     */
    public static int maxQueued = 0;

    /**
     * The frame `maxQueued` was set on, and the same peak restricted to frames after the world has
     * settled.
     *
     * A 19x19 chunk grid is 23,104 squares before z-levels, so a peak of ~30,000 is the shape of a
     * WHOLE-GRID arrival -- world entry or a teleport -- not of walking. Pricing a flush against
     * that peak prices an event no player pays during play, and pricing it against the walking peak
     * is what that gate actually needed. Recording both so the two can never be confused again.
     *
     * STEADY_AFTER is deliberately generous: the bench teleports at arm time and settles 300
     * frames, and the first legs are cold.
     */
    public static long maxQueuedFrame = 0L;
    public static int steadyMaxQueued = 0;
    private static final long STEADY_AFTER = 900L;

    private static void observeDrainCost(long ns, long count) {
        drained += count;
        avgNsPerSquare = Tuning.emaCostNs(avgNsPerSquare, ns / count, 1000L);
    }

    /**
     * Re-tune the lag window from the drop rate observed since the last check.
     *
     * Sampled over a window of deferrals rather than every frame, so a single unlucky chunk
     * unload cannot collapse the window, and so the measurement has enough denominator to mean
     * anything.
     */
    private static void adaptLag() {
        long dDef = deferred - lastDeferred;
        if (dDef < 20000L) {
            return;
        }
        // FEEDS ON STALENESS, NOT ON LOSS. This read `dropped` until the counter was split, and
        // the split pinned `dropped` at 0 -- which silently blinded the governor: ppt was always
        // 0, so the window only ever relaxed and never tightened. One whole A/B campaign was run
        // against that before `tightened=0 relaxed=0 lagMin=12`, against a historical
        // `lagMin=3-6 tightened=1-2`, gave it away. The signal the window is meant to chase is
        // entries going stale before the drain reaches them, and that is `deferredToReload`.
        long dStale = deferredToReload - lastStale;
        lastDeferred = deferred;
        lastStale = deferredToReload;
        long ppt = dStale * 1000L / dDef;
        if (ppt > (long)DROP_BUDGET_PPT) {
            if (lagFrames > 1) {
                lagFrames = Math.max(1, lagFrames / 2);
                lagTightened++;
                if (lagFrames < lagMin) {
                    lagMin = lagFrames;
                }
            } else {
                lagFloorHits++;
            }
        } else if (ppt * 4L < (long)DROP_BUDGET_PPT && lagFrames < MAX_LAG_FRAMES) {
            lagFrames = Math.min(MAX_LAG_FRAMES, lagFrames * 2);
            lagRelaxed++;
        }
    }

    /** How many live entries the resolve self-test verifies before standing down. */
    private static final int RESOLVE_CHECKS = 256;

    /**
     * The square occupying these coordinates NOW, or null if the place is not loaded.
     *
     * `IsoCell.getGridSquare(int,int,int)` is a bounds-checked array lookup against each chunk
     * map: it allocates nothing, never triggers a load, and returns null once the chunk is out of
     * the world. That is what makes it safe to call from inside the drain, and it is only ever
     * reached on the stale path -- 0.04-2.65 % of entries -- so the common path is untouched.
     */
    private static IsoGridSquare resolve(int x, int y, int z) {
        IsoWorld world = IsoWorld.instance;
        if (world == null) {
            return null;
        }
        IsoCell cell = world.getCell();
        if (cell == null) {
            return null;
        }
        return cell.getGridSquare(x, y, z);
    }

    /** Time to allow this frame: enough to clear the backlog within the live lag window. */
    public static long frameBudgetNs(int queued) {
        return Tuning.chunkDrainBudgetNs(queued, avgNsPerSquare, BUDGET_NS,
                lagFrames, BUDGET_CEIL_MULT);
    }

    /** Drop everything without dispatching. Called when the world is torn down. */
    public static void reset() {
        resets++;
        java.util.Arrays.fill(qSquare, null);
        java.util.Arrays.fill(qAt, 0L);
        qHead = 0;
        qTail = 0;
        draining = false;
        // Clearing drainThread is what keeps WORLD LOAD out of the deferral, and it is not
        // cosmetic. IngameState.enter (:743) calls IsoChunkMap.processAllLoadGridSquare (:145),
        // which drains the ENTIRE queue in one go, outside the per-frame throttle. Deferring
        // that is wrong twice over: there are no gameplay frames yet to drain into, so the
        // backlog would only start clearing at the then-default 2.5 ms/frame once play began -- order 9 s of
        // catch-up during which handlers have not run on ground the player is standing on.
        // With drainThread null, intercept() declines everything until the first
        // IsoCell.updateInternal of actual play, so world load behaves exactly like vanilla.
        // Static state persists across worlds, so without this the SECOND world of a session
        // would defer its load while the first did not -- a difference that would never show up
        // in a benchmark, because the harness creates one fresh world per process.
        drainThread = null;
    }

    // ---- measurement ---------------------------------------------------------------------------
    //
    // Timed at the CHUNK, not at the event. There is no way to pass a value from an OnEnter advice
    // to its OnExit through the ZombieBuddy Patch API, so a per-dispatch stopwatch is not
    // available -- and it would be the wrong thing to measure anyway. What matters is the whole
    // doLoadGridsquare call as one frame-blocking unit: the engine's own per-square work AND the
    // Lua it dispatches, which is what the player feels as a hitch.
    //
    public static void countDispatch() {
        dispatches++;
    }

    // ---- patches -------------------------------------------------------------------------------

    /**
     * The 1-arg overload, LuaEventManager.java:239. Chosen over the IsoChunk call site because it
     * is a small, stable, public method whose whole body is the dispatch, and because skipping at
     * ENTRY also skips `synchronized (EventMap)` (:240) -- the lock vanilla holds across the
     * entire callback chain.
     */
    @Patch(className = "zombie.Lua.LuaEventManager", methodName = "triggerEvent")
    public static class Patch_triggerEvent {
        @Patch.OnEnter(skipOn = true)
        public static boolean in(@Patch.Argument(0) String event, @Patch.Argument(1) Object param) {
            return ChunkLuaSpread.intercept(event, param);
        }
    }

    // The @Patch on zombie.iso.IsoChunk|doLoadGridsquare was DELETED 2026-08-26. It never wove:
    // its unconditional install probe read zero across every run while profscan measured the
    // method itself at 0.5 calls/f, and `warmUp = true` plus Main.PRELOAD_FOR_PATCHING could not
    // change that -- IsoChunk loads before ZomboidFileSystem.loadMods and ZombieBuddy's
    // explicit-retransform pass covers only ONE already-loaded class per mod. Every
    // relocation to a class ZB can reach either measures a superset (IsoChunkMap.updateInternal
    // runs every frame, not only on chunk loads) or moves the clock onto the per-dispatch path,
    // which would add cost to the SHIPPED default for a diagnostic. The per-chunk histogram it
    // fed is gone with it rather than left reading zero.

    /** Once-per-frame drain point on the game thread. */
    @Patch(className = "zombie.iso.IsoCell", methodName = "updateInternal")
    public static class Patch_cellUpdate {
        @Patch.OnExit
        public static void out() {
            ChunkLuaSpread.drain();
        }
    }

    /** World teardown: drop pending squares rather than dispatch into a dying world. */
    @Patch(className = "zombie.gameStates.IngameState", methodName = "exit")
    public static class Patch_exit {
        @Patch.OnEnter
        public static void in() {
            ChunkLuaSpread.reset();
        }
    }

    @LuaMethod(name = "Lugli_ChunkLuaReport", global = true)
    public static String report() {
        if (!ENABLED) {
            return "[chunklua] off";
        }
        StringBuilder sb = new StringBuilder();
        sb.append("[chunklua] mode=").append(MODE)
          .append(" budget=").append(BUDGET_NS / 1000L).append("us")
          .append(" frames=").append(frames)
          .append(" dispatches=").append(dispatches)
          .append(" deferred=").append(deferred)
          .append(" dropped=").append(dropped)
          .append(" reresolved=").append(reresolved)
          .append(" deferredToReload=").append(deferredToReload)
          .append(deferred > 0L
                  ? String.format(" (%.2f%%)", 100.0 * deferredToReload / deferred) : "")
          .append(" resolveCheck=").append(resolveOk).append("/").append(resolveOk + resolveBad)
          .append(" overflowed=").append(overflowed)
          .append(" queued=").append(qTail - qHead)
          .append(" maxQueued=").append(maxQueued)
          .append("@f").append(maxQueuedFrame)
          .append(" steadyMaxQueued=").append(steadyMaxQueued)
          .append(" costPerSquare=").append(avgNsPerSquare / 1000L).append("us")
          .append(" lag=").append(lagFrames).append("/").append(MAX_LAG_FRAMES)
          .append(" lagMin=").append(lagMin == Integer.MAX_VALUE ? MAX_LAG_FRAMES : lagMin)
          .append(" tightened=").append(lagTightened).append(" relaxed=").append(lagRelaxed)
          .append(lagFloorHits > 0 ? " lagFloorHits=" + lagFloorHits : "");
        return sb.toString();
    }
}
