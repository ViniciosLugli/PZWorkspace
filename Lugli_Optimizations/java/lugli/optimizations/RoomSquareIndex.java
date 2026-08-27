package lugli.optimizations;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.concurrent.ConcurrentHashMap;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.iso.IsoGridSquare;
import zombie.iso.areas.IsoRoom;

/**
 * Replace an O(n^2) membership scan on the chunk-load path with a hash lookup.
 * -Dlugli.opt.roomindex=off|verify|fast     (default fast)
 *
 * INSTALLATION: RESOLVED. This patch now runs, and the history is worth keeping because the
 * diagnosis was wrong twice before it was right.
 *
 * For eleven runs `invocations` stayed at 0 -- counted as the first statement of the advice,
 * before every guard, so it could not be confused with "fired and declined". A control counter on
 * `IsoRoom.getBuilding()`, a one-line getter on the SAME class the engine calls constantly, also
 * read 0, which proved the class was not instrumented rather than the call site being wrong.
 *
 * The fix that worked at the time was Main.loadPatchTargets() doing a MAIN-phase
 * `Class.forName("zombie.iso.areas.IsoRoom", false, ...)`. It succeeded only by luck: IsoRoom
 * loads late enough that a MAIN-phase forced load still produced a new-load transform. The same
 * trick listed `zombie.iso.IsoChunk` and never fixed it, because IsoChunk is already loaded by
 * then. Loader:903 explains both outcomes -- `applyPatches` runs on the FIRST phase a package is
 * seen in, which for a preloaded mod is PREMAIN, so anything main() does happens after the
 * transformer is installed and is a race against the engine's own loading.
 *
 * `warmUp = true` on the three IsoRoom patches replaces that luck with the supported mechanism:
 * PatchEngine:630 issues `Class.forName` immediately after `installOn`, inside PREMAIN. Safe here
 * beyond doubt -- IsoRoom's entire `<clinit>` is one `new ArrayList()`.
 *
 * WHAT IT IS WORTH, so nobody quotes it: with the patch live it recorded 337,953 adds across
 * 3,592 rooms with `duplicates=0`. ~94 squares/room means the ArrayList scan it replaces costs
 * N(N-1)/2 ~= 4,371 comparisons per room, ~15.7 M per run, ~16 ms spread over ~11,930 frames --
 * about 0.0013 ms/frame. `duplicates=0` means every one of those scans ran to full length and
 * returned false, i.e. this is the WORST case for the vanilla code and it is still negligible.
 * This part ships because a hash lookup is the right shape and it verifies itself, NOT for speed
 * Do not spend a frame A/B on it; the effect is an order of magnitude below the noise floor.
 *
 * THE WASTE (zombie/iso/areas/IsoRoom.java:162-166)
 *
 *   public void addSquare(IsoGridSquare sq) {
 *       if (!this.squares.contains(sq)) {
 *           this.squares.add(sq);
 *       }
 *   }
 *
 * `squares` is an ArrayList that grows to hold every square of the room, and `contains` is a
 * linear scan of it. `IsoChunk.loadInMainThread()` calls this for EVERY square of an arriving
 * chunk (`IsoChunk.java:2824-2828`), so filling one room costs N^2/2 comparisons. A large
 * Louisville interior spans many chunks.
 *
 * WHERE IT LANDS
 *   Inside the `Recalc Nav` probe (`IsoChunk.java:2764`), measured at
 *   0.18 occurrences per frame -- the same cadence as chunk arrival -- with a p99 of 23.3 ms and
 *   3.2 % of the above-median time budget. So it piles onto exactly the frames that already carry
 *   the per-square LoadGridsquare burst, and it compounds with ChunkLuaSpread rather than
 *   overlapping it.
 *
 * WHY THE REPLACEMENT IS EXACT, NOT APPROXIMATE
 *   `ArrayList.contains` tests with `equals`. `IsoGridSquare` declares neither `equals` nor
 *   `hashCode` (only an unrelated `hashCodeNoOverride` helper at :4797), so it inherits identity
 *   semantics -- and a `HashSet` of the same objects therefore answers the identical question.
 *   Same for `IsoRoom` as a map key. This is equivalence by construction, not a close-enough
 *   substitute.
 *
 *   Insertion ORDER is also preserved, and would be safe to change anyway: every read of
 *   `squares` is `isEmpty()` or `get(Rand.Next(size))` (`IsoRoom.java:299, 318-488`).
 *
 * WHY THE INDEX MUST SELF-HEAL
 *   `IsoRoom.squares` is a `public final ArrayList` (`:49`) and it is mutated behind this
 *   method's back: `removeSquare` (`:241`), and two external `isoRoom.squares.clear()` calls in
 *   `BREBuilding.java:265` and `WorldRegionToMetaGrid.java:456`. A side index that trusted itself
 *   would drift, and the failure would be silent -- a square missing from a room changes which
 *   squares that room can pick for spawns, and nothing crashes.
 *
 *   So: `removeSquare` is advised too, keeping the set aligned, and every add first checks that
 *   the set and the list still agree on SIZE. They can only disagree if something mutated the
 *   list directly, and the response is to rebuild the set from the list -- cheap, because the
 *   external mutations are `clear()`.
 *
 * VERIFICATION
 *   `verify` mode, and the first VERIFY_CALLS calls of `fast` mode, also run the original
 *   `contains` and compare. Any disagreement disarms the fast path permanently and logs it. Same
 *   standard the loot-table and script-database checksums are held to: a wrong answer here does
 *   not crash, it quietly changes where things spawn.
 */
public final class RoomSquareIndex {

    public static final String MODE = System.getProperty("lugli.opt.roomindex", "fast");
    public static final boolean ENABLED = !"off".equals(MODE);
    public static final boolean VERIFY_ALWAYS = "verify".equals(MODE);

    /** Cross-check this many calls even in fast mode, then stop paying for it. */
    public static final int VERIFY_CALLS = 5000;

    private static final ConcurrentHashMap<IsoRoom, HashSet<IsoGridSquare>> INDEX =
            new ConcurrentHashMap<>();

    /**
     * Incremented BEFORE any check, so it distinguishes "the advice never fired" from "the advice
     * fired and declined". The first run of this patch reported adds=0 and there was no way to
     * tell which had happened -- and this project's own rule is that a new advice must prove it
     * fires with an unconditional counter, because an advice that never installs looks exactly
     * like one whose condition never matched.
     */
    public static long invocations = 0L;
    public static long removals = 0L;

    public static long adds = 0L;
    public static long duplicates = 0L;
    public static long rebuilds = 0L;
    public static long verified = 0L;
    public static boolean broken = false;

    private RoomSquareIndex() {}

    /** True = the engine's addSquare body is skipped because this class did the work. */
    public static boolean addSquare(Object self, Object square) {
        invocations++;
        if (!ENABLED || broken) {
            return false;
        }
        if (!(self instanceof IsoRoom) || !(square instanceof IsoGridSquare)) {
            return false;
        }
        IsoRoom room = (IsoRoom)self;
        IsoGridSquare sq = (IsoGridSquare)square;
        ArrayList<IsoGridSquare> list = room.squares;
        if (list == null) {
            return false;
        }

        HashSet<IsoGridSquare> set = INDEX.get(room);
        if (set == null || Tuning.indexNeedsRebuild(set.size(), list.size())) {
            set = rebuild(room, list);
        }

        boolean present = set.contains(sq);

        if (VERIFY_ALWAYS || verified < VERIFY_CALLS) {
            boolean truth = list.contains(sq);
            verified++;
            if (present != truth) {
                broken = true;
                INDEX.clear();
                System.out.println("[Lugli/roomindex] DISARMED: index said " + present
                        + " but the list said " + truth + " -- falling back to the engine scan");
                return false;
            }
        }

        adds++;
        if (present) {
            duplicates++;
            return true;                  // exactly what the engine does: nothing
        }
        set.add(sq);
        list.add(sq);
        return true;
    }

    /** Keep the set aligned when the engine removes a square. Runs AFTER the engine's removal. */
    public static void removeSquare(Object self, Object square) {
        removals++;
        if (!ENABLED || broken) {
            return;
        }
        if (!(self instanceof IsoRoom) || !(square instanceof IsoGridSquare)) {
            return;
        }
        HashSet<IsoGridSquare> set = INDEX.get(self);
        if (set != null) {
            set.remove(square);
        }
    }

    private static HashSet<IsoGridSquare> rebuild(IsoRoom room, ArrayList<IsoGridSquare> list) {
        HashSet<IsoGridSquare> set = new HashSet<>(Math.max(16, list.size() * 2));
        for (int i = 0; i < list.size(); i++) {
            set.add(list.get(i));
        }
        INDEX.put(room, set);
        rebuilds++;
        return set;
    }

    /** Drop the whole index. Rooms do not outlive their world, and neither should this. */
    /**
     * World-teardown count. Legitimately 0 in any run that never leaves a world, which is why
     * PatchAudit reports this one as UNKNOWN rather than "not installed" when it reads zero --
     * a benchmark route that ends at the desktop never triggers IngameState.exit.
     */
    public static long resets = 0L;

    public static void reset() {
        resets++;
        INDEX.clear();
    }

    // ---- patches --------------------------------------------------------------------------------

    @Patch(className = "zombie.iso.areas.IsoRoom", methodName = "addSquare", warmUp = true)
    public static class Patch_addSquare {
        @Patch.OnEnter(skipOn = true)
        public static boolean in(@Patch.This Object self, @Patch.Argument(0) Object square) {
            return RoomSquareIndex.addSquare(self, square);
        }
    }

    @Patch(className = "zombie.iso.areas.IsoRoom", methodName = "removeSquare", warmUp = true)
    public static class Patch_removeSquare {
        @Patch.OnExit
        public static void out(@Patch.This Object self, @Patch.Argument(0) Object square) {
            RoomSquareIndex.removeSquare(self, square);
        }
    }

    /**
     * World teardown. Rooms belong to a world; the index must not outlive one, or the second
     * world of a session starts with entries keyed on rooms that no longer exist -- which would
     * also hold them alive against GC.
     */
    @Patch(className = "zombie.gameStates.IngameState", methodName = "exit")
    public static class Patch_exit {
        @Patch.OnEnter
        public static void in() {
            RoomSquareIndex.reset();
        }
    }

    /**
     * DISCRIMINATOR, not an optimization.
     *
     * `addSquare` reported invocations=0 across six runs while its call site at
     * `IsoChunk.java:2828` is demonstrably live -- inside `loadInMainThread`, inside the
     * `Recalc Nav` probe, guarded only by `sq.getRoom() != null`. Two explanations remain and
     * they need different fixes: either ZombieBuddy is not instrumenting this class at all, or
     * the class is instrumented and `addSquare` genuinely never runs on this route.
     *
     * `getBuilding()` is a one-line public getter on the SAME class that the engine calls
     * constantly. If its counter moves while addSquare's stays at zero, the class is patchable
     * and the call site is the problem. If both stay at zero, the class is not being patched and
     * no amount of work on this file will help.
     *
     * The `[ZB] patching ...` log line cannot answer this: `zombie.iso.IsoChunk` appears nowhere
     * in a 96-line patch list while our IsoChunk advice demonstrably ran in that same session.
     */
    public static long probeGetBuilding = 0L;

    /**
     * Gated on PatchAudit.CONTROLS, which is `static final`, so when it is false the JIT folds
     * this whole body away and the advice becomes an empty inline. `getBuilding` is called ~55 M
     * times in a three-minute route -- cheap per call, but a diagnostic on a hot getter should be
     * switchable rather than permanent. Turning it off costs only the ability to distinguish
     * "IsoRoom uninstrumented" from "addSquare never reached"; PatchAudit then says UNKNOWN.
     */
    public static void probe() {
        if (PatchAudit.CONTROLS) {
            probeGetBuilding++;
        }
    }

    @Patch(className = "zombie.iso.areas.IsoRoom", methodName = "getBuilding", warmUp = true)
    public static class Patch_probe {
        @Patch.OnEnter
        public static void in() {
            RoomSquareIndex.probe();
        }
    }

    @LuaMethod(name = "Lugli_RoomIndexReport", global = true)
    public static String report() {
        if (!ENABLED) {
            return "[roomindex] off";
        }
        return "[roomindex] mode=" + MODE + " probeGetBuilding=" + probeGetBuilding
                + " invocations=" + invocations
                + " removals=" + removals + " adds=" + adds + " duplicates=" + duplicates
                + " rebuilds=" + rebuilds + " verified=" + verified + " rooms=" + INDEX.size()
                + (broken ? " DISARMED" : "");
    }
}
