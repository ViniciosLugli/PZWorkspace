package lugli.optimizations;

import java.util.ArrayList;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ui.UIElementInterface;
import zombie.ui.UIManager;

/**
 * Spread the 10 Hz UI Lua tick across frames instead of firing every panel on the same one.
 * -Dlugli.opt.uistagger=off|on   (DEFAULT OFF as of 2026-08-25 -- see below)
 * -Dlugli.opt.uistagger.slices=N (default 4)
 *
 * DEFAULT FLIPPED TO OFF ON MEASUREMENT. This part shipped ON for weeks on evidence that was only
 * ever its OWN metric -- late flushes 18-24 % -> 2.8-4.0 % of windows. That is real and it still
 * happens. It just does not reach frame time.
 *
 * Isolated interleaved A/B, `s1b`, zoom 2.0, wind 0.15, 338 mods, every other part off, full
 * fidelity (no constrained heap), 5 pairs, pair 1 discarded, all 8 runs VALID with the arm asserted
 * from its own log:
 *
 *              uistagger=on        uistagger=off       overlap
 *   p50        14.853 - 15.780     14.754 - 15.847     YES   (-0.27 %)
 *   p90        22.633 - 24.050     23.686 - 25.676     YES   (-3.78 %)
 *   p99        39.401 - 41.939     39.495 - 42.821     YES   (-0.24 %)
 *
 * All three bands overlap, so by the project's own rule that is "no measurable difference", not a
 * small win. The result was PREDICTED before the run: a profiler comparison of an all-parts-off
 * campaign against an all-parts-on one put this part at ~0.27 ms/frame of `updateUIElements`,
 * against a ~0.8 ms p50 noise floor. Predicting the null first is why the
 * outcome could not be rationalised afterwards.
 *
 * The code is kept and still works -- it is switchable back on with `-Dlugli.opt.uistagger=on` for
 * anyone who wants the smoother tick distribution. What changed is only that it no longer claims a
 * default it did not earn. An ON-by-default switch justified only by its own counters is not
 * justified at all: `meshprio` read well on exactly that basis and was
 * an 18.3 s LOSS.
 *
 * THE BURST
 *   `UIManager.updateUIElements()` (`zombie/ui/UIManager.java:826-830`) is a trivial loop:
 *
 *       for (int i = 0; i < UI.size(); i++) { UI.get(i).update(); }
 *
 *   The cost is inside `UIElement.update()` (`:1696-1727`), which at `:1709-1710` does
 *
 *       if (UIManager.doTick && ...) LuaManager.caller.pcallvoid(..., tableget(table, "update"), ...)
 *
 *   and `doTick` is true only once per 100 ms (`UIManager.java:526-531`). So EVERY panel's Lua
 *   `update` fires on the SAME frame, once every ~6 frames at 60 fps. That is exactly the shape
 *   the profiler reports: `updateUIElements` at 1.0 occurrences per frame, p50 0.048 ms,
 *   **p99 7.177 ms**, and 14.1 % of the above-median time budget.
 *
 *   Those `pcallvoid` calls have no profiler probe of their own -- `"Lua - X"` spans exist only in
 *   `Event.trigger` (`zombie/Lua/Event.java:36,57`) -- so all of that mod Lua lands in
 *   `updateUIElements` SELF time. The 14.1 % is mod UI code, not engine loop overhead.
 *
 * THE CHANGE
 *   Run the loop ourselves, and give each panel its own phase inside the 100 ms window: on the
 *   frame the engine opens a tick window, only slice 0 of the panels sees `doTick == true`; the
 *   next frame slice 1 does, and so on. Every panel still ticks exactly once per window, so its
 *   rate is unchanged -- only its phase moves.
 *
 *   Per-frame maintenance is NOT staggered. `UIElement.update()` also reorders `toTop`, applies
 *   `resizeDirty` and recurses into children, and vanilla does that on every frame regardless of
 *   `doTick`. Every element is therefore still updated every frame; only the Lua callback is
 *   phased.
 *
 * WHY `uiUpdateIntervalMS` DOES NOT DRIFT
 *   Panels read the tick delta through `UIManager.uiUpdateIntervalMS` (`:86`, exposed at `:1435`
 *   and `:1439`). It is written only on the engine's own tick frame. Since each panel still ticks
 *   once per 100 ms window, the interval it observes is still the true time between its own
 *   ticks. Staggering the phase does not change the rate, which is what that value describes.
 *
 * WHY A LATE WINDOW IS FLUSHED
 *   If the frame rate is below slices x 10 fps, the engine can open a new tick window before all
 *   slices have run. Letting that happen would SKIP a panel's update for that window -- a
 *   behaviour change, not a scheduling one. So when a new window opens with slices outstanding,
 *   the remainder run immediately in that frame. Below ~40 fps at the default of 4 slices this
 *   degrades to vanilla behaviour, which is the correct failure mode.
 *
 * WHAT THIS IS AND IS NOT
 *   A p99 fix. Total work is unchanged -- the same Lua runs at the same rate. It moves a burst
 *   off one frame, exactly as `ChunkLuaSpread` does for chunk arrival. Do not expect p50 to move.
 *
 * BLAST RADIUS OF `doTick`
 *   Only two readers exist in the whole build: `UIElement.java:1709` (the call being phased) and
 *   `AtomUI.java:422`. The flag is restored to the engine's value before this advice returns, so
 *   nothing outside the loop can observe it changed.
 */
public final class UITickStagger {

    public static final String MODE = System.getProperty("lugli.opt.uistagger", "off");
    public static final boolean ENABLED = !"off".equals(MODE);
    /** Upper bound on the phase count. The live value adapts down to fit the frame rate. */
    public static final int MAX_SLICES = Math.max(1,
            Integer.getInteger("lugli.opt.uistagger.slices", 4).intValue());

    /**
     * Live slice count, derived from how many frames actually fit in a 100 ms tick window.
     *
     * A FIXED slice count only works above slices x 10 fps. Measured at 4 slices in Louisville,
     * **18-24 % of windows ran short** -- the engine opened the next window before all four slices
     * had run, so the remainder was flushed in one frame and those windows behaved exactly like
     * vanilla. The stagger was doing its job four times in five.
     *
     * The fix is not a smaller constant, because the right number depends on the frame rate at
     * that moment: 6 frames per window at 60 fps affords 4 phases, 3 frames at 30 fps affords 2.
     * So it is measured. A window that completes with slices to spare can afford more phases; one
     * that runs short must use fewer.
     */
    private static int slices = MAX_SLICES;
    private static long framesThisWindow = 0L;
    private static long emaFramesPerWindow = 0L;

    /** Slices still owed for the window the engine most recently opened. */
    private static int owed = 0;
    /** Which slice runs this frame. */
    private static int slice = 0;

    public static long windows = 0L;
    public static long flushes = 0L;
    public static long frames = 0L;

    /**
     * Advice-reached counter, the literal first statement of run(). `frames` sits behind both the
     * ENABLED check and the `UIManager.UI == null` check, so with the switch off it stays at zero
     * and cannot be told apart from a patch that never installed.
     */
    public static long invocations = 0L;

    private UITickStagger() {}

    /** True = the engine's updateUIElements body is skipped because this class ran the loop. */
    public static boolean run() {
        invocations++;                    // FIRST statement: installation, not intent
        PatchAudit.tick();                // second, independent emitter: see PatchAudit.tick
        if (!ENABLED) {
            return false;
        }
        ArrayList<UIElementInterface> ui = UIManager.UI;
        if (ui == null) {
            return false;
        }
        boolean engineTick = UIManager.doTick;
        frames++;

        boolean flushAll = false;
        framesThisWindow++;
        if (engineTick) {
            windows++;
            adaptSlices();
            if (owed > 0) {
                // The previous window never finished: the frame rate is below SLICES x 10 fps.
                // Skipping those panels would drop an update, so run everything now.
                flushes++;
                flushAll = true;
            }
            owed = slices;
            slice = 0;
        }

        int runSlice = -1;
        if (owed > 0) {
            runSlice = slice;
            slice++;
            owed--;
        }

        try {
            for (int i = 0; i < ui.size(); i++) {
                // Maintenance runs for every element every frame, as in vanilla. Only the Lua
                // callback is phased, and that is what doTick gates.
                UIManager.doTick = flushAll || (runSlice >= 0 && (i % slices) == runSlice);
                UIElementInterface e = ui.get(i);
                if (e != null) {
                    e.update();
                }
            }
            if (flushAll) {
                owed = 0;
            }
        } finally {
            UIManager.doTick = engineTick;
        }
        return true;
    }

    /**
     * Fit the phase count to the frames the window actually has. EMA over windows, weight 1/8, so
     * one stuttering window does not collapse the schedule and one fast one does not overreach.
     * Floor of 1 is vanilla behaviour; the cap is what the operator asked for.
     */
    private static void adaptSlices() {
        if (emaFramesPerWindow == 0L) {
            emaFramesPerWindow = Tuning.emaFramesInit(framesThisWindow);
        } else {
            emaFramesPerWindow = Tuning.emaFramesNext(emaFramesPerWindow, framesThisWindow);
        }
        slices = Tuning.sliceFit(emaFramesPerWindow, MAX_SLICES);
        framesThisWindow = 0L;
    }

    @Patch(className = "zombie.ui.UIManager", methodName = "updateUIElements")
    public static class Patch_updateUIElements {
        @Patch.OnEnter(skipOn = true)
        public static boolean in() {
            return UITickStagger.run();
        }
    }

    @LuaMethod(name = "Lugli_UIStaggerReport", global = true)
    public static String report() {
        if (!ENABLED) {
            return "[uistagger] off";
        }
        return "[uistagger] slices=" + slices + "/" + MAX_SLICES
                + " framesPerWindow=" + (emaFramesPerWindow / 8L) + " frames=" + frames + " windows=" + windows
                + " lateFlushes=" + flushes
                + (windows > 0L ? String.format(" (%.1f%% of windows ran short)",
                        100.0 * flushes / windows) : "");
    }
}
