package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.textures.Texture;
import zombie.debug.DebugLog;

/**
 * Holds the intro logos only until the menu's textures are ready, then skips them.
 * -Dfastloading.logowait=<ms>, default 0 (disabled, skip immediately as LogoSkip does).
 *
 * A compromise for machines where skipping outright shows an unpainted menu for a moment.
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
