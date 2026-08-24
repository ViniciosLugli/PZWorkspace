package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.asset.Asset;

/**
 * Queues the textures the FIRST drawn frame needs ahead of the rest.
 * -Dfastloading.uiprio=on   (default OFF, see below)
 *
 * TextureIDAssetManager.startLoading sets EVERY texture task to priority 7, menu icons and world
 * tiles alike. FileSystemImpl serves strictly by descending priority, so the handful of UI
 * textures sit behind the whole ~7,968-task block and can still be unready when the menu draws --
 * which is what makes a checkbox tick or the menu background appear late, or briefly render as
 * the error texture.
 *
 * WHY A HINT AND NOT A DIRECT MATCH
 *   The obvious place is the existing MeshPriority advice on FileSystemImpl.runAsync, but the
 *   task that carries the menu background is FileTask_LoadPackImage, whose packName/imageName are
 *   PACKAGE-PRIVATE in zombie.asset and which does not override getErrorMessage(). Advice is
 *   inlined into zombie.fileSystem.FileSystemImpl, so those fields are unreadable there.
 *
 *   startLoading still has the answer, on the Asset itself: a pack texture's path is
 *   "@pack@/<packName>/<pageName>" (Texture.java:130) and Asset.getPath() is public. It calls
 *   assetTask.execute() SYNCHRONOUSLY on the same thread that reaches runAsync, so a
 *   thread-local hint set here is read by that advice a moment later.
 *
 * WHY CONSUME-ON-READ RATHER THAN A finally
 *   MeshPriority CLEARS the hint when it reads it. If this advice's OnExit were ever skipped, a
 *   stale hint could otherwise promote an unrelated task indefinitely; consuming bounds the
 *   damage to nothing, because the very next runAsync takes it. OnExit still clears it for the
 *   case where execute() never reaches runAsync.
 *
 * DEFAULT OFF, DELIBERATELY
 *   Reordering costs nothing in total work, but this project's own record is that removing a
 *   blocker MOVES the wait rather than deleting it, and this has NOT been A/B'd end to end yet
 *   (the machine was below its commit guard). Ship it off, measure both arms, then flip.
 *   See docs/18-fastloading-internals.md#uipriority
 */
@Patch(className = "zombie.core.textures.TextureIDAssetManager", methodName = "startLoading")
public final class UiPriority {

    public static final String TAG = "[FastLoading/uiprio]";

    /** public: these bodies are inlined into engine classes, which read them as their own. */
    public static final boolean ON = "on".equals(System.getProperty("fastloading.uiprio", "off"));

    /** Above the 7 every texture gets, below the 9 animation meshes get. */
    public static final int UI_PRIORITY = 8;

    /** Set for the duration of one startLoading call; consumed by MeshPriority on runAsync. */
    public static final ThreadLocal<Boolean> HINT = new ThreadLocal<>();

    public static int raised;
    public static boolean announced;

    private UiPriority() {}

    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object asset) {
        if (!ON || MeshPriority.bootDone) {
            return;
        }
        if (asset instanceof Asset a && a.getPath() != null
                && Tuning.isFirstFrameUiAsset(a.getPath().getPath())) {
            HINT.set(Boolean.TRUE);
        }
    }

    @Patch.OnExit
    public static void exit() {
        HINT.remove();
    }
}
