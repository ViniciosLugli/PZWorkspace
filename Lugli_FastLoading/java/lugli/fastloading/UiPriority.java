package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.asset.Asset;

/**
 * Queues the textures the first drawn frame needs ahead of the rest.
 * -Dfastloading.uiprio=on (default OFF).
 *
 * startLoading gives every texture task the same priority, so the menu's own icons queue behind
 * thousands of world textures. Only the packs the menu actually draws are promoted; promoting
 * more would just move the whole texture block up and undo the mesh ordering.
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
