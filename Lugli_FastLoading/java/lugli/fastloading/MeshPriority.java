package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.asset.FileTask_ParseXML;
import zombie.core.skinnedmodel.model.FileTask_LoadMesh;
import zombie.debug.DebugLog;
import zombie.fileSystem.FileTask;

/**
 * Queues animation meshes ahead of textures during boot.
 * -Dfastloading.meshprio=on (default OFF).
 *
 * Meshes queue at priority 6 and textures at 7, and FileSystemImpl serves in descending
 * priority, so the meshes starve for the whole initAnimationMeshes barrier. Raising them cuts
 * ~12 s from boot but hands back more than that at world load, because the deferred textures
 * become the backlog the world load waits on. Measured 10.6 s worse end to end, hence off.
 *
 * Also hosts the asset task census (-Dfastloading.census=on) and the priority hints used by
 * UiPriority and PackPageWarm, since all three sit on the same runAsync advice.
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
