package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.asset.FileTask_ParseXML;
import zombie.core.skinnedmodel.model.FileTask_LoadMesh;
import zombie.debug.DebugLog;
import zombie.fileSystem.FileTask;

/**
 * Fixes a priority inversion that cost about 11.6 s of every boot: animation meshes queue at
 * priority 6 while ~7,968 texture tasks queue at 7, and FileSystemImpl serves in descending
 * priority order, so the meshes starve for the whole initAnimationMeshes barrier.
 * DEFAULT OFF SINCE 2026-08-23 -- turn it on with -Dfastloading.meshprio=on.
 *
 * It is a TRADE, and measured end to end it is a LOSING one. Six interleaved runs, 5 s menu dwell:
 *
 *     arm            boot          world load   launch -> playing
 *     meshprio=off   35.2-35.7 s   54-55 s      89.2-90.7 s
 *     meshprio=on    23.4-24.2 s   77 s         100.4-101.2 s
 *
 * It buys 11.6 s of boot and hands back 22.4 s at world load: **a net 10.6 s loss** for a player
 * who reaches the menu and clicks Continue. Bands do not overlap anywhere.
 *
 * WHY. It raises 79 animation-mesh tasks above ~7,968 textures so `initAnimationMeshes` stops
 * starving -- but those textures do not disappear, they become a backlog the world load then waits
 * on (asset barrier #1). Boot looks better because the cost moved somewhere the boot timer cannot
 * see. Only a player who idles ~30 s at the menu comes out ahead, because the backlog drains in
 * that idle time; nobody can rely on that.
 *
 * Kept, off, because the boot-only win is real and someone measuring boot in isolation may want it.
 *
 * runAsync is overloaded (FileTask and AsyncItem) and ZombieBuddy matches by NAME, so the
 * argument is taken as Object and type-checked rather than declared.
 *
 * SCOPED TO BOOT. The raise is disarmed once the main menu is reached.
 *
 * Leaving it armed for the session costs far more than it saves. Measured 2026-08-22 on the
 * pinned world, three runs per arm:
 *     world load, meshprio off -> 59 s        boot, meshprio off -> ModelManager.create 12.9 s
 *     world load, meshprio on  -> 83, 83 s    boot, meshprio on  -> ModelManager.create 0.69 s
 * So it is worth about 12 s at boot and about -24 s at every world load. The merge and asset
 * barrier phases are nearly identical between arms, so the cost is not in either of them.
 *
 * The reason is structural: at boot the only thing blocking is initAnimationMeshes waiting on
 * 79 meshes, so promoting them above textures is pure win. At world load nothing waits on a
 * mesh that way, and promoting mesh tasks above priority-7 textures just reorders a queue whose
 * consumers do want the textures.
 *
 * This could not be measured until 2026-08-22, because the patch had no kill switch: every
 * earlier "MeshPriority is neutral at world load" claim compared two arms that were identical.
 *
 * SECOND BAND: CLOTHING XML AT PRIORITY 8. -Dfastloading.clothprio=off
 *
 * This class also fixes the priority inversion that MeshPriority itself creates, and which cost
 * far more than MeshPriority saved.
 *
 * World load parks on asset barrier #1 (`GameLoadingState.java:280-288`), released at `:962-971`
 * only when `OutfitManager.isLoadingClothingItems()` is false. That stays true while any cached
 * clothing item is still `Asset.State.EMPTY`, and those ~3,700 XMLs were queued back at boot by
 * `OutfitManager.init()`. `ClothingItemAssetManager.startLoading` (`:19-27`) never calls
 * `setPriority`, so they sit at the FileTask default of **5** -- behind the ~7,968 texture tasks
 * at 7 that this very class pushed past the menu.
 *
 * Measured across the A/B logs, as the silent gap between the engine's own `startTime`
 * (`GameLoadingState.java:231`) and the first metagrid line:
 *
 *     meshprio on, 5 s menu dwell     front gap 31.4 - 31.7 s
 *     meshprio off                    front gap 6.8 s
 *     30 s menu dwell                 front gap 0.9 s
 *     VehicleTextureWarm on vs off    no difference
 *
 * The whole MeshPriority world-load penalty is that gap, and `tools/loadscan.sh` never saw it
 * because its clock starts at the metagrid scan. An earlier revision of this comment said "the
 * cost is not in either of them", meaning the merge and barrier #2 -- true, and it was in
 * barrier #1 all along.
 *
 * Raising the clothing XMLs to 8 puts them above the textures they were stuck behind and below
 * the meshes. Barrier #1 then clears on ~3,700 small XML parses instead of on the entire texture
 * backlog, and the ~25 s of pure loader-thread CPU that follows it -- the distribution merge,
 * animal definitions, tile definitions, zones -- overlaps the texture decode instead of running
 * strictly after it.
 *
 * `FileTask_ParseXML` is constructed in exactly one place in the whole engine
 * (`ClothingItemAssetManager.java:21`), so matching the type is unambiguous.
 *
 * Reordering a queue changes nothing about WHAT is parsed: no loot, no item definitions, no
 * rendering. `TextureID.bindInternal` uploads inline on first bind, and barrier #2 still waits
 * for the entire queue regardless.
 *
 * Measurements, and the texture-artifact risk that was investigated and not reproduced:
 * docs/18-fastloading-internals.md#meshpriority-risk
 */
@Patch(className = "zombie.fileSystem.FileSystemImpl", methodName = "runAsync")
public class MeshPriority {

    public static final String TAG = "[FastLoading/meshprio]";

    /** Above the 7 that TextureIDAssetManager uses, below nothing else in the engine. */
    public static final int MESH_PRIORITY = 9;

    /** public: read by the advice body, which runs as FileSystemImpl. */
    public static final boolean ON =
            "on".equals(System.getProperty("fastloading.meshprio", "off"));

    /** Above textures (7), below meshes (9). Clothing XML defaults to 5 and starves. */
    public static final int CLOTHING_PRIORITY = 8;
    /**
     * DEFAULT OFF. It does exactly what it claims and gains nothing.
     *
     * Measured 2026-08-23 on the pinned world: the front gap (barrier #1) collapsed from
     * 30.96 s to under 1 s -- the inversion really is real and this really does fix it -- but
     * asset barrier #2 went 17.92 s -> 57.12 s and the total 82 s -> 86 s. Every second saved
     * came back, because barrier #2 waits for `FileSystemImpl.hasWork()` to go false, i.e. for
     * the ENTIRE queue, regardless of priority. Clearing barrier #1 sooner only means arriving
     * at barrier #2 sooner and waiting there instead.
     *
     * That is this project's oldest rule -- removing a blocker MOVES the wait -- in its purest
     * measured form. Kept because the front-gap collapse is a genuine, reproducible effect that
     * may matter on other hardware or mod lists, and because deleting it would lose the
     * evidence that reordering cannot fix the world-load cost. Turn it on with
     * -Dfastloading.clothprio=on.
     */
    public static final boolean CLOTH_ON =
            "on".equals(System.getProperty("fastloading.clothprio", "off"));
    public static int clothRaised;
    public static boolean clothAnnounced;

    // public: this body is inlined into FileSystemImpl, which then reads them as its own.
    public static int raised;
    public static boolean announced;

    /**
     * CENSUS, -Dfastloading.census=on. Counts every task queued through runAsync by class, so a
     * phase can be attributed to the work it is actually waiting on instead of to a guess.
     *
     * Barrier #2 is now 30.3 s -- more than half of world load -- and the assumption that tile
     * pages dominate it is an INFERENCE, never a measurement. A region filter is the plan's only
     * high-risk item; it should not be built against an assumption.
     *
     * A plain HashMap under a lock: runAsync is called from several threads, and this runs only
     * when explicitly armed.
     */
    public static final boolean CENSUS =
            "on".equals(System.getProperty("fastloading.census", "off"));
    public static final java.util.HashMap<String, int[]> CENSUS_COUNTS = new java.util.HashMap<>();

    /** public: called from a body inlined into FileSystemImpl. */
    public static void census(Object task) {
        if (task == null) {
            return;
        }
        // `FileSystemImpl` has TWO runAsync overloads -- public runAsync(FileTask) (:160) wraps into
        // an AsyncItem and calls private runAsync(AsyncItem) (:139) -- and ZombieBuddy matches by
        // NAME with no descriptor, so this advice fires twice per task. Counting only FileTasks
        // keeps the census a true task census; otherwise an `AsyncItem` row equal to the whole
        // total sits beside the per-class rows and anyone summing rows gets 2x.
        if (!(task instanceof zombie.fileSystem.FileTask)) {
            return;
        }
        String n = task.getClass().getSimpleName();
        // For loose images -- 61 % of all world-load asset tasks -- also bucket by directory.
        // FileTask_LoadImageData overrides getErrorMessage() to return its imageName
        // (FileTask_LoadImageData.java:24-26), so the path is reachable without reflection.
        // Knowing WHAT those 11,528 files are is what decides whether they can be deferred.
        if ("FileTask_LoadImageData".equals(n) && task instanceof zombie.fileSystem.FileTask ft) {
            String path = ft.getErrorMessage();
            if (path != null) {
                String q = path.replace('\\', '/');
                // Paths are ABSOLUTE (E:/SteamWindows/...), so bucket from "/media/" onward --
                // the first attempt bucketed the drive prefix and produced one useless row.
                int m = q.lastIndexOf("/media/");
                String rel = m >= 0 ? q.substring(m + 7) : q;
                int b1 = rel.indexOf('/');
                int b2 = b1 < 0 ? -1 : rel.indexOf('/', b1 + 1);
                String bucket = b2 > 0 ? rel.substring(0, b2) : (b1 > 0 ? rel.substring(0, b1) : rel);
                bump("img:" + bucket);
            }
        }
        bump(n);
    }

    /** public: reached from the inlined census body. */
    public static void bump(String key) {
        synchronized (CENSUS_COUNTS) {
            int[] c = CENSUS_COUNTS.get(key);
            if (c == null) {
                c = new int[1];
                CENSUS_COUNTS.put(key, c);
            }
            c[0]++;
        }
    }

    /**
     * Set once the main menu is reached, by FastLoading_VehicleWarm.lua through
     * LuaBridge.endBootPhase(). After that the engine's own ordering is restored.
     */
    public static volatile boolean bootDone;

    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object task) {
        if (CENSUS) {
            census(task);
        }
        // NOT gated on bootDone: these are queued during boot and their completion is what
        // barrier #1 waits for at world load. Independent of the mesh raise on purpose.
        if (CLOTH_ON && task instanceof FileTask_ParseXML xml) {
            xml.setPriority(CLOTHING_PRIORITY);
            clothRaised++;
            if (!clothAnnounced) {
                clothAnnounced = true;
                DebugLog.log(TAG + " clothing XML queued ahead of textures (barrier #1)");
            }
            return;
        }
        // A menu-time pack warm: push it BELOW the clothing XMLs (default priority 5) so it can
        // never delay world-load barrier #1. Checked first because it is the most specific case.
        if (PackPageWarm.ON && Boolean.TRUE.equals(PackPageWarm.WARMING.get())
                && task instanceof FileTask wf) {
            wf.setPriority(PackPageWarm.WARM_PRIORITY);
            return;
        }
        // Consume the hint UiPriority set a moment ago in TextureIDAssetManager.startLoading.
        // Consuming, not just reading: a hint that outlived its call would otherwise promote an
        // unrelated task. Runs before the bootDone gate for the same reason clothing does -- it
        // is about what the first frame needs, not about mesh ordering.
        if (UiPriority.ON && Boolean.TRUE.equals(UiPriority.HINT.get())) {
            UiPriority.HINT.remove();
            if (task instanceof FileTask ft) {
                ft.setPriority(UiPriority.UI_PRIORITY);
                UiPriority.raised++;
                if (!UiPriority.announced) {
                    UiPriority.announced = true;
                    DebugLog.log(UiPriority.TAG + " first-frame UI textures queued ahead of the rest");
                }
                return;
            }
        }
        if (!ON || bootDone) {
            return;
        }
        if (task instanceof FileTask_LoadMesh mesh) {
            mesh.setPriority(MESH_PRIORITY);
            raised++;
            if (!announced) {
                announced = true;
                DebugLog.log(TAG + " animation meshes queued ahead of textures");
            }
        }
    }
}
