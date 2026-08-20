package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.skinnedmodel.model.FileTask_LoadMesh;
import zombie.debug.DebugLog;

/**
 * Fixes a priority inversion that cost about 11.6 seconds of every boot.
 *
 * ModelManager.initAnimationMeshes blocks the main thread until 79 animation meshes are
 * ready. Those tasks are queued at priority 6 (MeshAssetManager.startLoading) while the
 * texture packs queue roughly 7,968 tasks at priority 7 (TextureIDAssetManager).
 * FileSystemImpl keeps 16 tasks in flight and inserts pending work in descending priority
 * order, so every texture jumps ahead of every mesh and the meshes are starved for the
 * whole barrier. Measured queue depth during the wait: 5,633 pending on average, peaking
 * at 10,759.
 *
 * Raising the mesh tasks above textures takes initAnimationMeshes from 12,020 ms to
 * 398 ms. The textures are not needed to reach the main menu; they keep loading in the
 * background while the player is in it.
 *
 * runAsync is overloaded (FileTask and AsyncItem) and ZombieBuddy matches by name, so the
 * argument is taken as Object and type-checked rather than declared.
 */
@Patch(className = "zombie.fileSystem.FileSystemImpl", methodName = "runAsync")
public class MeshPriority {

    public static final String TAG = "[FastLoading/meshprio]";

    /** Above the 7 that TextureIDAssetManager uses, below nothing else in the engine. */
    public static final int MESH_PRIORITY = 9;

    // public: this body is inlined into FileSystemImpl, which then reads them as its own.
    public static int raised;
    public static boolean announced;

    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object task) {
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
