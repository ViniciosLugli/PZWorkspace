package lugli.optimizations;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.debug.DebugLog;

/**
 * Did each advice actually install? One block, every patch, checkable without the dev mod.
 *
 * WHY THIS EXISTS
 *   A patch that silently stops existing is this project's worst failure mode, because every
 *   downstream measurement stays plausible. Three separate A/Bs have been run against builds
 *   where the thing under test was not present.
 *
 *   The framework cannot tell you. `[ZB] patching <class>.<method> with N advice(s)` is emitted
 *   from INSIDE the transform callback, so it fires whenever the class is transformed -- which for
 *   a PRELOADED mod is during PREMAIN, before PZ has opened DebugLog or console.txt. None of this
 *   mod's premain transforms appear in any log. Absence of that line is therefore expected and
 *   proves nothing whatsoever. Counters are the only evidence.
 *
 * WHAT WENT WRONG WITHOUT IT
 *   - `ZExtents` reported `calls=0` for fifteen consecutive runs on 2026-08-22 -- including the
 *     whole campaign that produced the "FINAL validated result" -- and nothing noticed, because
 *     the old version of this file covered six of twelve patches and ZExtents was not one of them.
 *   - `IsoChunk.doLoadGridsquare` counted 2,178-2,327 chunks across fifteen runs and then zero
 *     across three, after nothing but a rebuild. Same source, opposite outcome.
 *   - `RoomSquareIndex` never fired in eleven runs, and only a control counter on a getter the
 *     engine calls constantly established that the CLASS was uninstrumented rather than the call
 *     site being wrong.
 *
 * THE THREE-STATE VERDICT, and why two was a lie
 *   The old file printed `NOT FIRED  <-- patch did not install`. It could not know that. A zero
 *   is consistent with three different worlds and they need opposite fixes:
 *
 *     FIRED          the advice bytecode is in the engine method and was reached. Proven.
 *     NOT INSTALLED  zero here, but a control probe on the SAME CLASS is non-zero. Proven absent.
 *     COLD           zero, and this patch only fires on a path the run never took (world exit).
 *                    Not diagnostic, and not a problem.
 *     UNKNOWN        zero, no control probe available. Honest answer: we cannot tell.
 *
 *   UNKNOWN is a feature. Buying a stronger verdict would mean adding a @Patch to a hot engine
 *   method purely to watch it, and a diagnostic that costs frame time on every user's machine
 *   forever is a bad trade for a line of text.
 *
 * WHAT IT COSTS
 *   Nothing on any hot path. Each counter is one non-volatile static increment that the advice
 *   was going to reach anyway, and the report is formatted once per session.
 */
public final class PatchAudit {

    private PatchAudit() {}

    /**
     * Control probes are real @Patch advice on engine methods that exist only to prove the class
     * is instrumented. `IsoRoom.getBuilding` is called ~55 M times in a three-minute route, so it
     * is a `static final` read the JIT folds away entirely when this is false.
     *
     * Default ON: 55 M increments measured no cost that ever surfaced above the frame noise, and
     * this probe is the single reason the RoomSquareIndex diagnosis was possible. Turn it off with
     * -Dlugli.opt.patchaudit.controls=false and RoomSquareIndex simply degrades to UNKNOWN.
     */
    public static final boolean CONTROLS =
            !"false".equals(System.getProperty("lugli.opt.patchaudit.controls", "true"));

    /** Emit the block once, after enough frames that the counters mean something. */
    private static final long ANNOUNCE_AT = 1200L;

    public static long ticks = 0L;
    private static boolean announced = false;

    /**
     * Called from every per-frame entry point we own, so the audit still emits when any one of
     * them fails to install -- which is precisely the situation it exists to report. Guarded by a
     * single already-announced read, so the steady-state cost is one static boolean load.
     */
    public static void tick() {
        if (announced) {
            return;
        }
        if (++ticks < ANNOUNCE_AT) {
            return;
        }
        announced = true;
        emit();
    }

    /**
     * Straight to DebugLog, NOT System.out.
     *
     * console.txt is truncated on every launch and is not what the harness reads; DebugLog is
     * per-run, timestamped, and is where `framebench.sh` greps. Emitting from Java rather than
     * from a Lua handler also matters: a Lua OnGameStart handler lands about one run in six, and
     * this mod ships no Lua at all, so the previous arrangement made the audit reachable only
     * through Lugli_Dev.
     */
    public static void emit() {
        String[] lines = report().split("\n");
        for (int i = 0; i < lines.length; i++) {
            DebugLog.log(lines[i]);
        }
    }

    // ---- verdicts -------------------------------------------------------------------------------

    private static final int NO_CONTROL = -1;

    private static String verdict(long hits, long control, boolean cold) {
        if (hits > 0L) {
            return "FIRED   (" + hits + ")";
        }
        if (cold) {
            return "COLD    (path not taken this run -- not diagnostic)";
        }
        if (control > 0L) {
            return "NOT INSTALLED  <-- control on same class fired " + control;
        }
        if (control == 0L && CONTROLS) {
            return "UNKNOWN (control also zero -- class may be uninstrumented)";
        }
        return "UNKNOWN (no control probe -- cannot distinguish install from reach)";
    }

    private static String row(String name, String target, long hits, long control, boolean cold) {
        StringBuilder sb = new StringBuilder("  ");
        sb.append(pad(name, 34));
        sb.append(pad(target, 46));
        sb.append(verdict(hits, control, cold));
        return sb.toString();
    }

    private static String pad(String s, int width) {
        StringBuilder sb = new StringBuilder(s);
        while (sb.length() < width) {
            sb.append(' ');
        }
        return sb.toString();
    }

    /**
     * Every @Patch this mod declares, eleven of them across ten distinct engine methods --
     * `zombie.gameStates.IngameState.exit` carries two advices, one from each of ChunkLuaSpread
     * and RoomSquareIndex, which is why ten methods need eleven pinned lines. Keep this list and
     * tools/expected-patches-Optimizations.txt in step; a patch that is pinned but unaudited is
     * exactly how ZExtents went dark for fifteen runs.
     */
    @LuaMethod(name = "Lugli_PatchAudit", global = true)
    public static String report() {
        long roomControl = CONTROLS ? RoomSquareIndex.probeGetBuilding : NO_CONTROL;

        StringBuilder sb = new StringBuilder("[patchaudit] advice installation, this session"
                + (CONTROLS ? "" : " (controls off)") + ":");

        sb.append('\n').append(row("ChunkLuaSpread.triggerEvent",
                "zombie.Lua.LuaEventManager|triggerEvent",
                ChunkLuaSpread.invTrigger, NO_CONTROL, false));
        // PROVEN UNREACHABLE on this install (2026-08-25). A control probe on IsoChunk.update --
        // same class, no overloads, called every frame per loaded chunk -- ALSO read zero, and the
        // log carries no `Transformed: zombie.iso.IsoChunk` line for any mod in the whole run.
        // IsoChunk loads BEFORE loadMods, so it needs the explicit-retransform path, and
        // PatchEngine.java:220's `break` caps that at ONE already-loaded class per mod. Neither
        // warmUp nor PRELOAD_FOR_PATCHING can help: Class.forName on an already-loaded class is a
        // no-op. Kept as a row so the zero stays visible rather than being quietly dropped.
        sb.append('\n').append(row("ChunkLuaSpread.cellUpdate",
                "zombie.iso.IsoCell|updateInternal",
                ChunkLuaSpread.invDrain, NO_CONTROL, false));
        sb.append('\n').append(row("ChunkLuaSpread.exit",
                "zombie.gameStates.IngameState|exit",
                ChunkLuaSpread.resets, NO_CONTROL, true));

        sb.append('\n').append(row("RoomSquareIndex.addSquare",
                "zombie.iso.areas.IsoRoom|addSquare",
                RoomSquareIndex.invocations, roomControl, false));
        sb.append('\n').append(row("RoomSquareIndex.removeSquare",
                "zombie.iso.areas.IsoRoom|removeSquare",
                RoomSquareIndex.removals, roomControl, false));
        sb.append('\n').append(row("RoomSquareIndex.getBuilding (control)",
                "zombie.iso.areas.IsoRoom|getBuilding",
                CONTROLS ? RoomSquareIndex.probeGetBuilding : 0L, NO_CONTROL, !CONTROLS));
        sb.append('\n').append(row("RoomSquareIndex.exit",
                "zombie.gameStates.IngameState|exit",
                RoomSquareIndex.resets, NO_CONTROL, true));

        sb.append('\n').append(row("UITickStagger.updateUIElements",
                "zombie.ui.UIManager|updateUIElements",
                UITickStagger.invocations, NO_CONTROL, false));

        sb.append('\n').append(row("WindGate.getWindRenderEffects",
                "zombie.iso.IsoObject|getWindRenderEffects",
                WindGate.invWind, WindGate.invApply, false));
        sb.append('\n').append(row("WindGate.getObjectRenderEffectsToApply",
                "zombie.iso.IsoObject|getObjectRenderEffectsToApply",
                WindGate.invApply, WindGate.invWind, false));

        sb.append('\n').append(row("ZExtents.calculateZExtents",
                "zombie.iso.IsoChunkMap|calculateZExtentsForChunkMap",
                ZExtents.invocations, NO_CONTROL, false));

        // KahluaGet was a measurement part. It answered its question on 2026-08-25 -- 31,023
        // tableget calls/frame against the 230,414 needed to clear 1.0 ms -- and was deleted with
        // the idea. Its counters are not kept as a permanent diagnostic because
        // observe mode cost one extra map probe per Lua table read, i.e. ~31k/frame.

        sb.append('\n').append("  -- modes: windgate=").append(WindGate.MODE)
          .append(" zextents=").append(ZExtents.MODE)
          .append(" uistagger=").append(UITickStagger.MODE)
          .append(" chunklua=").append(ChunkLuaSpread.MODE)
          .append(" roomindex=").append(RoomSquareIndex.MODE);
        sb.append('\n').append("  -- a mode being off does NOT zero these counters: every one is "
                + "the first statement of its advice, before any guard.");
        return sb.toString();
    }
}
