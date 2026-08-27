package lugli.optimizations;

/**
 * Pure decision logic for the optimisations, deliberately free of any `zombie.*` import so it can
 * be unit-tested without the game on the classpath. The build runs those tests and aborts on
 * failure.
 *
 * This is where the load-bearing judgements live. The wind gate is only correct while the sprite
 * it hides is displaced by EXACTLY nothing, and only stable while the gate is not thrashing; both
 * of those are decided here rather than inline in the patch, so both are covered by tests.
 */
public final class Tuning {

    private Tuning() {}

    /**
     * Is a wind effect at rest -- i.e. displacing its sprite by exactly nothing?
     *
     * EXACT zero, deliberately, not an epsilon. The whole safety argument for gating is that a
     * baked sprite and a per-frame sprite are then the SAME PIXELS. A tolerance would trade that
     * proof for a guess about what displacement is small enough to be invisible, which is exactly
     * the kind of "probably fine" that ships a visual defect.
     */
    public static boolean atRest(double x1, double y1, double x2, double y2,
                                 double x3, double y3, double x4, double y4) {
        return x1 == 0.0 && y1 == 0.0 && x2 == 0.0 && y2 == 0.0
            && x3 == 0.0 && y3 == 0.0 && x4 == 0.0 && y4 == 0.0;
    }

    /**
     * Should the gate flip state now?
     *
     * The offsets pass through zero on every lerp, so an instantaneous test would flip the gate
     * constantly, and each flip invalidates chunk textures -- costing far more than the redraw it
     * replaces. A flip therefore requires `dwellFrames` consecutive frames of agreement.
     *
     * @param current   the gate's current belief ("calm")
     * @param observed  what this frame actually shows
     * @param agree     how many consecutive frames have already agreed with `observed`
     */
    public static boolean shouldFlip(boolean current, boolean observed, int agree, int dwellFrames) {
        return observed != current && agree + 1 >= dwellFrames;
    }

    /** Consecutive-agreement counter: reset when the observation matches the current belief. */
    public static int nextAgree(boolean current, boolean observed, int agree) {
        return observed == current ? 0 : agree + 1;
    }

    /**
     * Iterations the ENGINE performs in calculateZExtentsForChunkMap: it bounds both loops by the
     * flat array's length (gridWidth^2) instead of the grid dimension.
     */
    public static long engineZExtentScan(int gridWidth) {
        long len = (long) gridWidth * gridWidth;
        return len * len;
    }

    /** Iterations that can actually return a chunk -- getChunk is null outside [0, gridWidth). */
    public static long usefulZExtentScan(int gridWidth) {
        return (long) gridWidth * gridWidth;
    }

    /** How many times oversized the engine's scan is, for a given grid width. */
    public static long zExtentOverscanFactor(int gridWidth) {
        return engineZExtentScan(gridWidth) / usefulZExtentScan(gridWidth);
    }


    /**
     * Per-frame time allowance for the deferred LoadGridsquare drain.
     *
     * Pure so it can be unit tested: ChunkLuaSpread's own copy lives on the frame path and
     * imports zombie.*, which build-jars.sh cannot load in a test JVM.
     *
     * The rule is "clear the current backlog within lagFrames frames, at the observed cost per
     * square", floored at the resting budget and capped at ceilMult times it. The floor keeps
     * a trickle moving when the queue is nearly empty; the cap stops one enormous burst from
     * simply relocating the whole spike into a single frame.
     *
     * A FIXED budget was tried first and is wrong: any value below the mean ARRIVAL rate makes
     * the queue grow without bound, entries age past their chunk's lifetime, and the drain finds
     * them invalid. Measured at 2.5 ms/frame against a 3.3 ms/frame arrival rate: 16.2 % of
     * squares were dropped instead of dispatched.
     */
    public static long chunkDrainBudgetNs(int queued, long avgNsPerSquare, long budgetNs,
                                          int lagFrames, int ceilMult) {
        if (queued <= 0 || lagFrames <= 0) {
            return budgetNs;
        }
        long need = (long)queued * avgNsPerSquare / (long)lagFrames;
        long ceil = budgetNs * (long)ceilMult;
        if (need < budgetNs) {
            return budgetNs;
        }
        return need > ceil ? ceil : need;
    }

    /**
     * Exponential moving average of the drain's cost per square, weight 1/8.
     *
     * Integer arithmetic on purpose: this runs inside the frame and must not allocate. The floor
     * matters -- without it a run of cheap drains could drive the estimate to zero and the budget
     * formula would then allow an unbounded number of squares in one frame.
     */
    public static long emaCostNs(long current, long sampleNs, long floorNs) {
        long next = current + (sampleNs - current) / 8L;
        return next < floorNs ? floorNs : next;
    }

    /**
     * Does the room-square index disagree with the list it shadows?
     *
     * SIZE is the whole test, and that is deliberate. IsoRoom.squares is a public final
     * ArrayList mutated behind addSquare's back -- by removeSquare (IsoRoom:241) and by two
     * external `isoRoom.squares.clear()` calls (BREBuilding:265, WorldRegionToMetaGrid:456) --
     * so an index that trusted itself would drift silently, and a square missing from a room
     * changes which squares that room can pick for spawns without anything crashing.
     *
     * Sizes can only diverge if the list was mutated by something other than the advised
     * methods, so size equality is sufficient: with add and remove both advised, the two stay
     * in lockstep, and any third party shows up as a mismatch on the very next add.
     */
    public static boolean indexNeedsRebuild(int setSize, int listSize) {
        return setSize != listSize;
    }

    // ---- deferral queue geometry -----------------------------------------------------------------
    //
    // ChunkLuaSpread's queue is LINEAR, not circular: head and tail both only advance, and when the
    // tail reaches the end of the array the queue either slides its live range back to index 0 or
    // doubles. Getting that choice wrong is not a crash, it is a slow leak -- compact too eagerly
    // and every enqueue burst pays an arraycopy; grow too eagerly and the array ratchets upward and
    // never comes back down, because nothing ever shrinks it.

    /**
     * Compact (slide the live range to the front) rather than doubling the array?
     *
     * Two conditions, both necessary. `head > 0` because with head at 0 there is nothing to
     * reclaim -- compacting would copy the whole array onto itself and leave the tail exactly
     * where it was, so the next enqueue would immediately ask again and the queue would spin
     * without ever growing. `size * 2 <= capacity` because sliding is only worth an arraycopy when
     * it buys back at least half the array; below that the copy cost recurs every few enqueues and
     * doubling is the cheaper answer.
     */
    public static boolean shouldCompactQueue(int head, int size, int capacity) {
        return head > 0 && size * 2 <= capacity;
    }

    /**
     * Has the queue hit the operator's ceiling, so this square must be dispatched inline?
     *
     * The bound is on LIVE entries (tail - head), not on the array length. Bounding the array
     * instead would conflate "we are holding too much work" with "we have not compacted lately",
     * and would start dropping squares while the queue was mostly empty space.
     */
    public static boolean queueAtCapacity(int head, int tail, int maxQueue) {
        return tail - head >= maxQueue;
    }

    // ---- UI tick phase count ---------------------------------------------------------------------
    //
    // NOTE this is a DIFFERENT recurrence from emaCostNs above, and the difference is deliberate.
    // emaCostNs stores the mean directly: v += (sample - v) / 8. This one stores the mean SCALED BY
    // 8: ema += sample - ema / 8. Same time constant, but keeping the scale factor means the
    // integer division happens once on read instead of once per update, so a small frame count --
    // and 3 or 4 frames per window is normal at 30 fps -- does not get floored to zero on every
    // single update and drag the average down. Do not "simplify" one into the other.

    /** Seed the scaled accumulator so the first window is taken at face value rather than as zero. */
    public static long emaFramesInit(long framesThisWindow) {
        return framesThisWindow * 8L;
    }

    /** One update of the scaled EMA. Pass the previous accumulator, not the previous average. */
    public static long emaFramesNext(long ema, long framesThisWindow) {
        return ema + framesThisWindow - ema / 8L;
    }

    /**
     * How many slices one UI tick window should be split into, given the scaled accumulator.
     *
     * `avg - 1` leaves one frame of slack: scheduling exactly as many slices as there are frames
     * means any single late frame leaves a slice unrun, which `owed` then has to flush all at once
     * -- reintroducing the burst this part exists to remove. Floor of 1 is vanilla behaviour
     * (everything ticks on the engine's own frame) and is what a stalled window degrades to.
     */
    public static int sliceFit(long ema, int maxSlices) {
        long avg = ema / 8L;
        int fit = (int) Math.max(1L, avg - 1L);
        return Math.min(maxSlices, fit);
    }
}
