package lugli.optimizations;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.PerformanceSettings;
import zombie.iso.IsoCamera;
import zombie.iso.IsoChunk;
import zombie.iso.objects.ObjectRenderEffects;

/**
 * Keep "Wind Sprite Effects" ON, but stop paying for it while the wind is not actually moving
 * anything. -Dlugli.opt.windgate=off|observe|fast (default fast).
 *
 * NOTE ON THE PROPERTY NAME. This header used to read `-Dlugli.windgate ... (default off)`, which
 * was wrong on both counts -- it was copied from src/Dev/lugli/dev/WindGate.java, the dev-gated
 * original, and never updated when the part shipped. It matters more than a typo: every recorded
 * wind-gate A/B on this project was armed with `-Dlugli.windgate=fast`, i.e. the DEV jar's switch,
 * so the published "+31 % fps" figure has never been re-measured against the property this file
 * actually reads. The two implementations diff as behaviourally identical, but identical on
 * inspection is not measured. Until it is re-run under -Dlugli.opt.windgate, no number from this
 * part is quotable.
 *
 * THE COST BEING TARGETED (measured here, 6-run A/B, non-overlapping bands)
 *   Turning the option off moved p50 7.879-8.080 -> 6.219-6.471 ms (-20 %) and p90 ~17.2 ->
 *   ~11.7 ms (-31 %). The visual must be KEPT, so disabling is not the fix.
 *   The cost is not the sway maths: that is 90 shared pooled effects updated once per frame
 *   (ObjectRenderEffects.init:190-206, updateStatic:475). It is that
 *   FBORenderCell.isObjectRenderLayer_Translucent (:1949-1954) treats any object whose
 *   getWindRenderEffects() is non-null as TRANSLUCENT, which excludes it from the baked FBO
 *   chunk texture and redraws it every frame on the game thread, the thread that gates the frame.
 *
 * THE OPENING
 *   ObjectRenderEffects.update (:352-370) remaps wind per windType and then hard-zeroes the
 *   corners: windType 1/2/3 zero below raw wind 0.02/0.2/0.6, and after the remap a further
 *   "wind less-or-equal 0.05" zeroes them. Effective raw thresholds 0.069 / 0.24 / 0.62.
 *   Below those the applied offsets are EXACTLY zero, so a baked sprite and a per-frame sprite
 *   are pixel-identical and the per-frame redraw buys nothing at all.
 *
 * WHY IT READS THE OFFSETS INSTEAD OF THE THRESHOLDS
 *   x1..y4 are public doubles carrying the APPLIED (already lerped) offsets. Testing them
 *   directly states the real invariant, "this sprite is not displaced", and cannot drift if TIS
 *   retunes the thresholds or the remap. Re-deriving 0.069 / 0.24 / 0.62 here would be a second
 *   copy of engine logic that silently goes wrong on the next game patch.
 *
 * WHY THE DECISION IS AGGREGATED, NOT PER OBJECT
 *   Flipping one sprite between baked and per-frame is only safe if the chunk texture is rebuilt
 *   at the same moment. Both directions are VISIBLE bugs otherwise: windy to calm leaves the
 *   sprite absent from the baked texture and it VANISHES; calm to windy leaves it in the texture
 *   AND draws it per-frame, a GHOST. So the gate is one global state that changes rarely, and
 *   every flip invalidates the loaded chunks.
 *
 * DWELL
 *   Offsets pass through zero on every lerp, so an instantaneous test would thrash the gate and
 *   invalidate constantly, costing far more than the redraw it replaces. The state only flips
 *   after DWELL_FRAMES consecutive frames of agreement.
 */
public final class WindGate {

    /**
     * Shipping default is ON. A performance mod that needs a JVM flag to do anything is a mod
     * that helps nobody, so this is enabled unless explicitly turned off:
     *   -Dlugli.opt.windgate=off       disable entirely
     *   -Dlugli.opt.windgate=observe   count what WOULD be gated, change nothing (for A/B)
     */
    public static final String MODE = System.getProperty("lugli.opt.windgate", "fast");
    public static final boolean ENABLED = !"off".equals(MODE);
    public static final boolean FAST = "fast".equals(MODE);

    /** Consecutive agreeing frames before the gate flips. About 3 s at 60 fps. */
    public static final int DWELL_FRAMES = 180;

    /**
     * Per-windType calm state, NOT one global flag.
     *
     * The dead zones differ enormously by windType: raw wind 0.069 / 0.24 / 0.62 for type 1/2/3
     * (ObjectRenderEffects.update:352-370). An all-or-nothing gate needs EVERY type at rest, i.e.
     * wind below 0.069, which simulated fair weather reaches only ~20 % of the time and a storm
     * never -- so it would measure well on the benchmark (which pins wind to 0.0) and do almost
     * nothing in real play. Gating per type instead keeps type 3 baked below wind 0.62 and type 2
     * below 0.24, which is most weather.
     *
     * This adds no new visual state: a type-1 grass swaying next to a still type-2 grass at wind
     * 0.15 is already what vanilla does, because the engine zeroes them at different thresholds.
     */
    public static final boolean[] calm = {false, false, false};
    public static final int[] agree = {0, 0, 0};
    public static int lastFrame = -1;
    public static int flips = 0;
    public static int staleFlips = 0;
    public static long gatedCalls = 0L;

    /**
     * Advice-reached counters, one per @Patch, incremented BEFORE every guard.
     *
     * `gatedCalls` cannot do this job: it only increments at the very end of gate(), after the
     * ENABLED/broken/null checks, the POOL_TYPE lookup and the calm test. A zero there is
     * ambiguous between "the advice never installed" and "it installed and declined every call",
     * and those need opposite fixes. These two are the first statement the inlined advice reaches,
     * so a zero means exactly one thing: the bytecode is not in the engine method.
     *
     * Two counters, not one, because both advices delegate to the same gate() and a single tally
     * could be carried entirely by one of them while the other was silently missing -- which is
     * the more dangerous half, since getObjectRenderEffectsToApply reads the field directly and a
     * gate applied only to the getter would still shear the sprite at draw time.
     */
    public static long invWind = 0L;
    public static long invApply = 0L;

    public static boolean broken = false;
    public static String breakReason = "";

    private WindGate() {}

    /** Recompute at most once per frame. 90 pooled effects, 8 double compares each. */
    public static void tick() {
        int f = IsoCamera.frameState.frameCount;
        if (f == lastFrame) {
            return;
        }
        lastFrame = f;
        resolvePools();
        if (broken || poolPlain == null || poolTrees == null) {
            return;
        }
        for (int id = 0; id < poolPlain.length && id < 3; id++) {
            boolean rest = allAtRest(id);
            if (!Tuning.shouldFlip(calm[id], rest, agree[id], DWELL_FRAMES)) {
                agree[id] = Tuning.nextAgree(calm[id], rest, agree[id]);
                continue;
            }
            calm[id] = rest;
            agree[id] = 0;
            flips++;
            invalidateLoadedChunks();
            System.out.println("[Lugli/Opt/windgate] windType " + (id + 1) + " -> "
                    + (rest ? "CALM (baked)" : "WINDY (per-frame)") + " flips=" + flips);
        }
    }

    /**
     * Is every pooled effect at rest?
     *
     * The pools are the only source of wind offsets: getNextWindEffect (:171-190) hands out
     * WIND_EFFECTS / WIND_EFFECTS_TREES entries and nothing else. If all 90 are zero then no
     * wind sprite anywhere is displaced.
     *
     * Read by REFLECTION because both arrays are private (ObjectRenderEffects.java:63-64).
     * Two alternatives were rejected. Sampling the effects that flow through the patched getters
     * is unsound: once sprites are baked, isObjectRenderLayer_Translucent stops being called for
     * them, so observation would dry up exactly when the gate is closed and the wind returning
     * would never be noticed -- vegetation frozen through a storm. Re-deriving the thresholds
     * (0.069 / 0.24 / 0.62) from ClimateManager duplicates engine logic that silently goes wrong
     * if TIS retunes it. Reflection reads the truth, and this runs once per frame, not per call.
     */
    public static Object[][] poolPlain = null;
    public static Object[][] poolTrees = null;
    public static boolean poolsResolved = false;

    /**
     * Identity set of the 90 pooled WIND effects.
     *
     * REQUIRED, and its absence was a real bug caught by the self-test on the first armed run:
     * getObjectRenderEffectsToApply (IsoObject.java:5413-5417) returns `objectRenderEffects`
     * FIRST -- a DYNAMIC effect from ObjectRenderEffects.getNew (Vegetation_Rustle,
     * Hit_Tree_Shudder, Hit_Door) -- and only falls through to the wind effect when that is null.
     * A dynamic rustle is displaced even in dead-calm wind, so gating on "the wind pools are all
     * at rest" tried to null a moving effect and the self-test disarmed, three runs out of three.
     * Gating must therefore apply ONLY to effects that came from the wind pools.
     */
    public static final java.util.IdentityHashMap<Object, Integer> POOL_TYPE =
            new java.util.IdentityHashMap<Object, Integer>();

    public static void resolvePools() {
        if (poolsResolved) {
            return;
        }
        poolsResolved = true;
        try {
            java.lang.reflect.Field a = ObjectRenderEffects.class.getDeclaredField("WIND_EFFECTS");
            java.lang.reflect.Field b =
                    ObjectRenderEffects.class.getDeclaredField("WIND_EFFECTS_TREES");
            a.setAccessible(true);
            b.setAccessible(true);
            poolPlain = (Object[][]) a.get(null);
            poolTrees = (Object[][]) b.get(null);
            for (int id = 0; id < poolPlain.length; id++) {
                for (int i = 0; i < poolPlain[id].length; i++) {
                    POOL_TYPE.put(poolPlain[id][i], Integer.valueOf(id));
                    POOL_TYPE.put(poolTrees[id][i], Integer.valueOf(id));
                }
            }
        } catch (Throwable t) {
            broken = true;
            breakReason = "cannot read wind pools: " + t;
            System.out.println("[Lugli/Opt/windgate] DISARMED -- " + breakReason);
        }
    }

    public static boolean allAtRest(int id) {
        for (int i = 0; i < poolPlain[id].length; i++) {
            if (!atRest((ObjectRenderEffects) poolPlain[id][i])
                    || !atRest((ObjectRenderEffects) poolTrees[id][i])) {
                return false;
            }
        }
        return true;
    }

    /** Delegates to Tuning so the predicate under test is the predicate in use. */
    public static boolean atRest(ObjectRenderEffects e) {
        return e == null
                || Tuning.atRest(e.x1, e.y1, e.x2, e.y2, e.x3, e.y3, e.x4, e.y4);
    }

    /**
     * Rebuild the baked textures so a flip is never visible. Uses the engine own dirty flag for
     * a render-effect change (256L, as IsoObject.removeRenderEffect does at :5401-5407).
     * Rare by construction, because DWELL_FRAMES gates it.
     */
    public static void invalidateLoadedChunks() {
        if (!PerformanceSettings.fboRenderChunk) {
            return;
        }
        try {
            java.util.ArrayList<IsoChunk> all = new java.util.ArrayList<>();
            zombie.iso.IsoCell cell = zombie.iso.IsoWorld.instance.currentCell;
            for (int n = 0; n < zombie.characters.IsoPlayer.numPlayers; n++) {
                zombie.iso.IsoChunkMap cm = cell.getChunkMap(n);
                if (cm == null) {
                    continue;
                }
                for (int x = cm.getWorldXMinTiles() / 8; x <= cm.getWorldXMaxTiles() / 8; x++) {
                    for (int y = cm.getWorldYMinTiles() / 8; y <= cm.getWorldYMaxTiles() / 8; y++) {
                        IsoChunk c = cm.getChunk(x, y);
                        if (c != null && !all.contains(c)) {
                            all.add(c);
                        }
                    }
                }
            }
            for (int i = 0; i < all.size(); i++) {
                all.get(i).invalidateRenderChunkLevels(256L);
            }
        } catch (Throwable t) {
            broken = true;
            breakReason = "invalidate failed: " + t;
            System.out.println("[Lugli/Opt/windgate] DISARMED -- " + breakReason);
        }
    }

    /**
     * Should this object wind effect be hidden from the render-layer predicate right now?
     *
     * Self-test built in: gating is only correct when the effect is genuinely at rest, so if we
     * are about to gate a DISPLACED effect the gate is wrong and disarms PERMANENTLY rather than
     * shipping a visual bug. Same standard as PZFixPack_DistributionChecksum for loot.
     */
    public static boolean gate(Object effect) {
        if (!ENABLED || broken || effect == null) {
            return false;
        }
        tick();
        Integer id = POOL_TYPE.get(effect);
        if (id == null) {
            return false;     // a dynamic rustle/shudder/door effect -- never ours to gate
        }
        int t = id.intValue();
        if (!calm[t]) {
            return false;
        }
        if (!atRest((ObjectRenderEffects) effect)) {
            // Staleness, not a logic error: tick() samples once per frame but updateStatic()
            // can displace the pools LATER in that same frame. Flip this type to WINDY -- the
            // direction that renders per-frame and is therefore always visually correct -- and
            // re-arm after the usual dwell. A permanent disarm is kept only for a rate far
            // beyond what a per-frame race can explain.
            calm[t] = false;
            agree[t] = 0;
            staleFlips++;
            invalidateLoadedChunks();
            if (staleFlips > 400) {
                broken = true;
                breakReason = "gate raced " + staleFlips + " times -- not a per-frame race";
                System.out.println("[Lugli/Opt/windgate] DISARMED -- " + breakReason);
            }
            return false;
        }
        gatedCalls++;
        return FAST;
    }

    /** Advice entry for getWindRenderEffects. Counts first, then decides -- see invWind. */
    public static boolean gateWind(Object effect) {
        invWind++;
        return gate(effect);
    }

    /** Advice entry for getObjectRenderEffectsToApply. Counts first, then decides -- see invApply. */
    public static boolean gateApply(Object effect) {
        invApply++;
        return gate(effect);
    }

    @Patch(className = "zombie.iso.IsoObject", methodName = "getWindRenderEffects")
    public static class Patch_getWindRenderEffects {
        @Patch.OnExit
        public static void out(@Patch.Return(readOnly = false) ObjectRenderEffects ret) {
            if (WindGate.gateWind(ret)) {
                ret = null;
            }
        }
    }

    /**
     * The second gate is REQUIRED, not belt and braces: getObjectRenderEffectsToApply (:5417)
     * reads the windRenderEffects FIELD directly instead of calling the getter, so patching the
     * getter alone would take the sprite out of the per-frame path while still applying a wind
     * shear to it at draw time.
     */
    @Patch(className = "zombie.iso.IsoObject", methodName = "getObjectRenderEffectsToApply")
    public static class Patch_getObjectRenderEffectsToApply {
        @Patch.OnExit
        public static void out(@Patch.Return(readOnly = false) ObjectRenderEffects ret) {
            if (WindGate.gateApply(ret)) {
                ret = null;
            }
        }
    }

    @se.krka.kahlua.integration.annotations.LuaMethod(name = "Lugli_WindGateReport", global = true)
    public static String report() {
        if (!ENABLED) {
            return "[windgate] off";
        }
        return "[windgate] mode=" + MODE + " calm=[" + calm[0] + "," + calm[1] + ","
                + calm[2] + "] flips=" + flips
                + " gatedCalls=" + gatedCalls + " staleFlips=" + staleFlips
                + (broken ? " DISARMED(" + breakReason + ")" : "");
    }
}
