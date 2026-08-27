package lugli.optimizations;

/**
 * ZombieBuddy entry point for Lugli - Optimizations.
 *
 * SCOPE, deliberately narrow: changes to the GAME ENGINE's own per-frame work that are
 * independent of any mod, revert cleanly, and are proven not to alter what is drawn. Nothing here
 * targets another mod's behaviour and nothing changes a user-facing game setting.
 *
 * Every part follows the same contract:
 *   - it can be turned off individually with a -Dlugli.opt.* property;
 *   - it carries a runtime self-test and DISARMS ITSELF rather than risk a visual defect;
 *   - it reports whether its advice actually installed -- see PatchAudit.
 *
 * DEFAULTS. A part that is OFF has not earned ON yet.
 *
 *   windgate    fast     ON   -- the headline part
 *   zextents    fast     ON   -- exact and self-verifying, but far under the noise floor
 *   roomindex   fast     ON   -- the same shape
 *   uistagger   off      OFF  -- real on its own metric, but the frame-time bands overlap
 *   chunklua    observe  OFF  -- lossless, but `spread` costs the mean (p50 +5.7 %, p90 +7.4 %)
 *
 * Measured results and the conditions attached to them live in the README, not here.
 *
 * Nothing here may touch zombie.* at premain: the game classes are on the classpath but not
 * initialised, so loading one early can change static-initialiser order.
 */
public final class Main {

    public static final String VERSION = "1.0.0";

    private Main() {}

    /**
     * Classes we patch that the game would otherwise load too late for ZombieBuddy to instrument.
     *
     * This is BELT AND BRACES alongside @Patch(warmUp = true), not a replacement: the two levers
     * fail in opposite conditions. `warmUp` calls Class.forName from applyPatches -- premain for a
     * preloaded mod -- and is a no-op if the class is already loaded by then. This list runs at
     * MAIN phase, too late for a class loaded during boot but clean for one loaded later.
     *
     * Listing a class some other lever already handled costs one cached Class.forName. Getting it
     * wrong costs a patch that silently does not exist, which is this project's worst failure mode.
     *
     * NEITHER LEVER CAN SAVE A CLASS LOADED BEFORE `ZomboidFileSystem.loadMods`. ZombieBuddy's
     * explicit-retransform pass covers only ONE already-loaded class per mod, so `IsoChunk`,
     * `IsoCell`, `UIManager` and `UIElement` are on the wrong side of that line and an advice on
     * them is contingent on which other mods happen to retransform the same class. That is settled
     * rather than a hypothesis, and one advice was deleted over it.
     *
     * `initialize = false`: the class must be LOADED, not initialized. Running a zombie.* static
     * initialiser at premain would change initialisation order before the game has started, which
     * is exactly the trap that makes `FileSystemImpl` unpatchable.
     */
    private static final String[] PRELOAD_FOR_PATCHING = {
        "zombie.iso.areas.IsoRoom",
        "zombie.iso.IsoChunk",
        "zombie.iso.IsoChunkMap",
    };

    public static void premain(String[] args) {
        System.out.println("[Lugli/Opt] preloaded at agent premain, v" + VERSION);
    }

    /**
     * Make our patch targets visible to ZombieBuddy's retransform pass.
     *
     * READ FROM PatchEngine.applyPatches (decompiled): it builds the set of already-loaded target
     * classes from `Loader.g_instrumentation.getAllLoadedClasses()`, and for each one that carries
     * advice it calls `Class.forName` + `retransformClasses` explicitly. Classes NOT loaded at that
     * moment are left to the AgentBuilder's new-load transformer instead.
     *
     * The log proves main() runs BEFORE that pass -- `class lugli.optimizations.Main: method main()
     * invoked successfully` at 04:13:01.910, the first `patching ...` line at 04:13:02.2. So a
     * class loaded here lands in `getAllLoadedClasses()` and takes the deterministic explicit
     * retransform path rather than depending on the new-load transformer firing later.
     *
     * That matters because the new-load path is demonstrably unreliable for us:
     * `IsoChunk.doLoadGridsquare` counted 2,178-2,327 chunks across fifteen runs and then ZERO
     * across six, with no change to that patch -- only a rebuild in between. `IsoRoom` has never
     * been instrumented at all across eleven runs.
     *
     * `initialize = false`: LOAD the class, do not run its static initialiser. Running a zombie.*
     * <clinit> from inside loadMods would reorder engine initialisation, which is the trap that
     * makes FileSystemImpl unpatchable in the first place.
     *
     * SUPERSEDED 2026-08-24 -- this note used to read "ZombieBuddy's own `warmUp` flag cannot be
     * used for this", and that was WRONG. It is right about the mechanism it looked at and wrong
     * about the conclusion:
     *
     *   PatchEngine:631  builder = builder.warmUp(cls)   <- genuinely discarded. AgentBuilder is a
     *                                                       fluent immutable and installOn already
     *                                                       ran at :606. This is what was read.
     *   PatchEngine:630  Class.forName(className)        <- THE OPERATIVE LINE, one line earlier.
     *                                                       Issued AFTER installOn, it drives the
     *                                                       class through the freshly installed
     *                                                       transformer as a NEW LOAD.
     *
     * Measured 46/46 in this machine's logs on peekaview's FBORenderTrees and WeatherFxMask, always
     * `(new load)`, never a miss. So `warmUp = true` is the supported and reliable mechanism, and
     * the five patches that need it now declare it.
     *
     * This method is kept for now only as belt and braces for IsoRoom, whose instrumentation it is
     * currently responsible for. Delete it once a run confirms the IsoRoom counters still move with
     * warmUp alone -- and note it can never have helped IsoChunk, because by MAIN phase that class
     * is already loaded and a forced load then is far too late.
     */
    private static void loadPatchTargets() {
        for (String name : PRELOAD_FOR_PATCHING) {
            try {
                Class.forName(name, false, Main.class.getClassLoader());
                System.out.println("[Lugli/Opt] loaded for patching: " + name);
            } catch (Throwable t) {
                System.out.println("[Lugli/Opt] could NOT load " + name + ": " + t);
            }
        }
    }

    /** MAIN phase: the normal path, from inside ZomboidFileSystem.loadMods. */
    public static void main(String[] args) {
        loadPatchTargets();
        System.out.println("[Lugli/Opt] loaded, v" + VERSION
                + "  windgate=" + WindGate.MODE);
    }
}
