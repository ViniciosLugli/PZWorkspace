package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.textures.Texture;
import zombie.debug.DebugLog;

/**
 * Holds the intro logos only until the menu's own textures are ready, capped.
 * -Dfastloading.logowait=<ms>   (default 0 = disabled, skip instantly as before)
 *
 * WHY THIS EXISTS
 *   The red/white checkerboard is Texture.getErrorTexture() (Texture.java:322-347, an 8x8
 *   checkerboard of 0xFF0000FF and 0xFFFFFFFF), substituted by Texture.bind():686 whenever a
 *   texture is bound for drawing before its data is ready. MainScreenState.preloadBackgroundTextures
 *   (:496-516) queues media/ui/Title*.png, but queuing is not loading: in vanilla the 5.5 s of
 *   logo fade is when they actually drained. LogoSkip deletes that window, so the menu can draw
 *   its background before the background exists.
 *
 *   This gives back the smallest part of that window that is actually needed: hold while the menu
 *   textures are unready, up to a hard cap, then go regardless.
 *
 * WHY A CAP IS MANDATORY
 *   Waiting on readiness alone would reintroduce an unbounded boot barrier -- exactly what this
 *   mod exists to remove. The cap bounds the worst case to a partial logo.
 *
 * READINESS IS TESTED THE WAY THE ENGINE TESTS IT
 *   Texture.bind() gates on !isDestroyed() && isValid() && isReady(); anything looser would
 *   declare victory while bind() still substitutes. getSharedTexture() may legitimately return
 *   null for a path in the nullTextures set, which is NOT a reason to wait forever -- null counts
 *   as ready. (This is Texture.getSharedTexture, which returns the texture directly; it does not
 *   have the NinePatchTexture.getSharedTexture first-call-returns-null defect.)
 *
 * DEFAULT 0, DELIBERATELY
 *   Any non-zero value trades boot time for visual correctness, and neither side has been
 *   measured on this machine yet. See docs/18-fastloading-internals.md#logowait
 */
@Patch(className = "zombie.gameStates.TISLogoState", methodName = "update")
public final class LogoWait {

    public static final String TAG = "[FastLoading/logowait]";

    /** public: these bodies are inlined into TISLogoState, which reads them as its own. */
    public static final int WAIT_MS = readWait();

    public static long firstUpdateAt;
    public static boolean released;
    public static boolean announced;

    private LogoWait() {}

    private static int readWait() {
        try {
            return Integer.parseInt(System.getProperty("fastloading.logowait", "0").trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /** The textures the menu draws first. Mirrors Texture.bind()'s own readiness test. */
    public static boolean menuTexturesReady() {
        return ready("media/ui/Title.png") && ready("media/ui/Title2.png");
    }

    private static boolean ready(String path) {
        Texture t = Texture.getSharedTexture(path);
        // null means the engine recorded it as a null texture: it will never become ready, and
        // waiting for it would burn the whole cap on every boot.
        return t == null || (!t.isDestroyed() && t.isValid() && t.isReady());
    }

    @Patch.OnEnter
    public static void enter(@Patch.This zombie.gameStates.TISLogoState state) {
        if (LogoSkip.KEEP || WAIT_MS <= 0 || released) {
            return;
        }
        long now = System.currentTimeMillis();
        if (firstUpdateAt == 0L) {
            firstUpdateAt = now;
        }
        long waited = now - firstUpdateAt;
        boolean ready = menuTexturesReady();
        if (ready || waited >= WAIT_MS) {
            released = true;
            state.stage = 3;
            if (!announced) {
                announced = true;
                DebugLog.log(TAG + " logos held " + waited + " ms of " + WAIT_MS
                        + " (menu textures " + (ready ? "ready" : "STILL NOT READY, cap hit") + ")");
            }
        }
    }
}
