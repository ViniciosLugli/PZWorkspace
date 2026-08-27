package lugli.optimizations;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;

/**
 * Fix a 362x over-scan in IsoChunkMap.calculateZExtentsForChunkMap.
 * -Dlugli.opt.zextents=off|verify|fast   (default fast)
 *
 * THE BUG (read at IsoChunkMap.java:959-975)
 *   chunksSwapA is a FLAT array of chunkGridWidth * chunkGridWidth entries (:88). The scan bounds
 *   BOTH loops by `chunksSwapA.length` instead of `chunkGridWidth`:
 *
 *       for (int xx = 0; xx < this.chunksSwapA.length; xx++)
 *           for (int yy = 0; yy < this.chunksSwapA.length; yy++)
 *               IsoChunk c = this.getChunk(xx, yy);
 *
 *   At 3440x1440 chunkGridWidth is 19, so the array length is 361 and the scan runs
 *   361 x 361 = 130,321 iterations. getChunk (:476-484) returns null for any index >=
 *   chunkGridWidth, so only 19 x 19 = 361 of those can ever return a chunk. 129,960 iterations --
 *   99.7 % -- are a bounds check and a null test that cannot do anything. The flat array's LENGTH
 *   was mistaken for the grid's DIMENSION.
 *
 * WHY IT MATTERS HERE
 *   Both call sites are chunk-change driven: `:234` runs when a chunk loaded this frame
 *   (`if (bChanged)`), `:947` when the chunk set changed. So the waste lands on chunk-arrival
 *   frames -- precisely the frames that already carry the per-square LoadGridsquare burst and
 *   produce the p99 tail.
 *
 * WHY THE FIX IS EXACT, NOT AN APPROXIMATION
 *   Iterating 0..chunkGridWidth-1 visits every index for which getChunk can return non-null, and
 *   min/max over a set is unchanged by also visiting members that contribute nothing. The result
 *   is identical by construction, not merely close.
 *
 * PROVEN AT RUNTIME ANYWAY
 *   `verify` mode, and the first VERIFY_CALLS calls of `fast` mode, compute the ORIGINAL full scan
 *   as well and compare both extents. Any disagreement disarms the fast path permanently and logs
 *   it. A wrong z extent would not crash -- it would silently change which levels render -- so this
 *   is held to the same standard as the loot checksum.
 */
public final class ZExtents {

    public static final String MODE = System.getProperty("lugli.opt.zextents", "fast");
    public static final boolean ENABLED = !"off".equals(MODE);
    public static final boolean VERIFY_ALWAYS = "verify".equals(MODE);

    /** Cross-check this many calls even in fast mode, then stop paying for it. */
    public static final int VERIFY_CALLS = 200;

    /**
     * Advice-reached counter, incremented BEFORE every guard.
     *
     * `calls` is not a substitute: it only increments after the ENABLED/broken/instanceof checks
     * and the `chunkGridWidth > 0` test, so `calls=0` cannot tell "the patch never installed"
     * apart from "it installed and declined". That ambiguity is not hypothetical here -- this
     * patch reported `calls=0` for fifteen consecutive runs on 2026-08-22, including the entire
     * campaign that produced the "FINAL validated result", and nobody noticed because PatchAudit
     * did not cover ZExtents at all. `invocations` makes that state self-announcing.
     */
    public static long invocations = 0L;

    public static long calls = 0L;
    public static long verified = 0L;
    /**
     * Direct cost measurement, populated only while cross-checking.
     *
     * WHY: the saving is ~0.9 ms on chunk-arrival frames only, so averaged over a route it is a
     * fraction of a millisecond -- far below the 2.6 ms run-to-run spread of the frame benchmark.
     * Trying to detect it in aggregate p50 measures noise. Timing both scans at the point of use
     * measures the thing itself.
     */
    public static long nanosOurs = 0L;
    public static long nanosEngine = 0L;
    public static boolean broken = false;
    public static boolean announced = false;

    private ZExtents() {}

    /**
     * Compute the extents correctly. Returns true to SKIP the engine's version.
     * Everything it touches is public: getChunk(int,int) (:476), chunkGridWidth (:61),
     * maxHeight/minHeight (:80-81), IsoChunk.minLevel/maxLevel (:147-148).
     */
    public static boolean compute(Object self) {
        invocations++;                    // FIRST statement: proves installation, not intent
        if (!ENABLED || broken || !(self instanceof IsoChunkMap)) {
            return false;
        }
        IsoChunkMap map = (IsoChunkMap) self;
        int w = IsoChunkMap.chunkGridWidth;
        if (w <= 0) {
            return false;                 // not initialised yet; let the engine handle it
        }
        if (!announced) {
            announced = true;
            System.out.println("[Lugli/Opt/zextents] active, mode=" + MODE
                    + " grid=" + w + " (engine scans " + (w * w) + "x" + (w * w) + ")");
        }
        calls++;

        long t0 = System.nanoTime();
        int max = 0;
        int min = 0;
        for (int x = 0; x < w; x++) {
            for (int y = 0; y < w; y++) {
                IsoChunk c = map.getChunk(x, y);
                if (c != null) {
                    max = Math.max(c.maxLevel, max);
                    min = Math.min(min, c.minLevel);
                }
            }
        }

        long t1 = System.nanoTime();
        if (VERIFY_ALWAYS || verified < VERIFY_CALLS) {
            verified++;
            nanosOurs += t1 - t0;
            long t2 = System.nanoTime();
            int emax = 0;
            int emin = 0;
            int n = map.getChunks().length;          // exactly what the engine bounds by
            for (int x = 0; x < n; x++) {
                for (int y = 0; y < n; y++) {
                    IsoChunk c = map.getChunk(x, y);
                    if (c != null) {
                        emax = Math.max(c.maxLevel, emax);
                        emin = Math.min(emin, c.minLevel);
                    }
                }
            }
            nanosEngine += System.nanoTime() - t2;
            if (emax != max || emin != min) {
                broken = true;
                System.out.println("[Lugli/Opt/zextents] DISARMED -- disagreement:"
                        + " ours(min=" + min + ",max=" + max + ")"
                        + " engine(min=" + emin + ",max=" + emax + ")");
                return false;             // let the engine recompute; never ship a wrong extent
            }
        }

        map.maxHeight = max;
        map.minHeight = min;
        return true;
    }

    /**
     * `warmUp = true` is LOAD-BEARING, not decoration. Without it this advice never installs.
     *
     * THE EVIDENCE
     *   Across every DebugLog on this machine, `Transformed: zombie.iso.IsoChunkMap` appears 84
     *   times and every one of them says `(retransformed)` -- never `(new load)`. This advice has
     *   therefore never installed on its own. It landed only when some OTHER mod's `installOn`
     *   happened to retransform the class, and the only mod that ever did was ZB Better FPS, whose
     *   `Patch_IsoChunkMap` targets `CalcChunkWidth` on the same class. When that mod stopped
     *   triggering the retransform (2026-08-24 03-01 onward) this patch went dead in five
     *   consecutive boots and nothing noticed, because PatchAudit did not cover ZExtents.
     *
     * WHY warmUp FIXES IT, given the builder reassignment is discarded
     *   PatchEngine:626-638 loops over the warm-up set doing `Class.forName(className)` at :630
     *   and `builder.warmUp(cls)` at :631. The :631 reassignment IS thrown away -- AgentBuilder is
     *   a fluent immutable and `installOn` already ran at :606. But :630 is the operative line: a
     *   `Class.forName` issued AFTER `installOn` drives the class through the freshly installed
     *   transformer as a NEW LOAD. Measured 46/46 in peekaview's FBORenderTrees and WeatherFxMask,
     *   always `(new load)`, never a miss. The note that used to sit in Main.java claiming warmUp
     *   was unusable read :631 and missed :630.
     *
     * WHY IT IS SAFE HERE, checked rather than assumed
     *   PatchEngine uses the one-arg INITIALISING `Class.forName`, so this runs IsoChunkMap's
     *   `<clinit>` at premain. Every invocation in that initialiser is a plain allocation --
     *   HashMap, ArrayList, two int[4], CappedConcurrentQueue(1024), a fair ReentrantLock,
     *   ColorInfo, PerformanceProfileProbe -- plus `Class.desiredAssertionStatus`. No engine
     *   singleton, no GL, no file I/O, no thread start. `chunkGridWidth = 13` is set here and
     *   recomputed by CalcChunkWidth later, so initialising early cannot pin a stale grid width.
     *   This is NOT a licence to add warmUp elsewhere by reflex: FileSystemImpl is unpatchable
     *   precisely because running a zombie.* initialiser early reorders engine startup.
     */
    // Keep this annotation on ONE line: check-patch-targets.sh greps line by line, so a wrapped
    // @Patch is invisible to the pin -- the exact "silently stopped existing" failure it guards.
    @Patch(className = "zombie.iso.IsoChunkMap", methodName = "calculateZExtentsForChunkMap", warmUp = true)
    public static class Patch_calculateZExtents {
        @Patch.OnEnter(skipOn = true)
        public static boolean in(@Patch.This Object self) {
            return ZExtents.compute(self);
        }
    }

    @se.krka.kahlua.integration.annotations.LuaMethod(
            name = "Lugli_ZExtentsReport", global = true)
    public static String report() {
        if (!ENABLED) {
            return "[zextents] off";
        }
        String cost = "";
        if (verified > 0) {
            double ours = nanosOurs / 1000000.0 / verified;
            double eng = nanosEngine / 1000000.0 / verified;
            cost = String.format("  per call: ours %.4f ms, engine %.4f ms, saved %.4f ms (%.0fx)",
                    ours, eng, eng - ours, ours > 0 ? eng / ours : 0.0);
        }
        return "[zextents] mode=" + MODE + " calls=" + calls + " verified=" + verified
                + (broken ? " DISARMED" : "") + cost;
    }
}
