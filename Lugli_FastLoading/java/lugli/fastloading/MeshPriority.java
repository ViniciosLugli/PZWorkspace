package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.skinnedmodel.model.FileTask_LoadMesh;
import zombie.debug.DebugLog;

/**
 * Queues animation meshes ahead of textures during boot. -Dfastloading.meshprio=on (default OFF).
 *
 * Meshes queue at priority 6 and textures at 7, and FileSystemImpl serves in descending priority,
 * so meshes starve for the whole initAnimationMeshes barrier. Raising them collapses it.
 *
 * OFF BECAUSE IT LOSES. It is a transfer, not a saving: the ~8,000 textures it defers become what
 * world-load barrier #1 waits on, so whether it wins depends entirely on how long the player sits
 * at the menu. A partial raise is impossible -- all ~83 mesh tasks queue within three seconds and
 * initAnimationMeshes waits for every one. The measured sweep and the break-even are in the
 * mod's README.
 *
 * THE GATE IS IN JAVA ON PURPOSE. An off-switch must not live in a file the thing it switches off
 * can ship without -- a preloaded jar never loads the mod's Lua.
  */
@Patch(className = "zombie.fileSystem.FileSystemImpl", methodName = "runAsync")
public final class MeshPriority {

    public static final String TAG = "[FastLoading/meshprio]";

    // public: this body is inlined into zombie.fileSystem.FileSystemImpl, which then reads these
    // as its own. Anything private throws IllegalAccessError at runtime.
    public static final boolean ON =
            "on".equals(System.getProperty("fastloading.meshprio", "off"));

    /**
     * Above the texture block (7), deliberately BELOW DemandPriority.DEMAND (9). 1.3.0 used 9,
     * which collides: FileSystemImpl inserts on a strict `>`, so at 9 a texture the player is
     * waiting on could not pass the mesh backlog. Tuning.bandsOrdered pins the ordering.
     */
    public static final int MESH_PRIORITY = Tuning.MESH_BAND;

    /** Volatile: written once on the main thread, read on every asset-queueing thread. */
    public static volatile boolean bootDone;

    public static int raised;
    public static boolean announced;

    private MeshPriority() {}

    /**
     * Ends the boot phase. Called from BootProgress.MenuHandover's OnExit on MainScreenState.enter
     * so the mesh gate cannot drift out of step with the screen's own retirement.
     */
    /** Public so BootProgress can make this part assert itself at the menu handover. */
    public static String status() {
        return ON ? ("armed, " + raised + " mesh task(s) raised") : "off";
    }

    public static void endBoot() {
        if (bootDone) {
            return;
        }
        bootDone = true;
        if (raised > 0) {
            DebugLog.log(TAG + " boot phase ended, " + raised + " mesh task(s) raised;"
                         + " engine ordering restored");
        }
    }

    /**
     * Both runAsync overloads match by name, so this fires twice per task; the instanceof filters
     * the AsyncItem call out, so each task is raised once and the counter stays true.
     */
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object task) {
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
