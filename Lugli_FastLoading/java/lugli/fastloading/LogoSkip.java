package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;

/**
 * Skips the TIS and FMOD intro logos, which cost about 5.5 s and load nothing: they play after
 * every loading phase has finished. -Dfastloading.logo=keep.
 *
 * Uses the engine's own skip path rather than inventing one, so the state machine still advances
 * exactly as it would if the player had pressed a key.
 */
@Patch(className = "zombie.gameStates.TISLogoState", methodName = "enter")
public class LogoSkip {

    public static final String TAG = "[FastLoading/logo]";

    // public: this body is inlined into TISLogoState, which then reads it as its own.
    public static final boolean KEEP = "keep".equals(System.getProperty("fastloading.logo"));
    public static boolean announced;

    @Patch.OnExit
    public static void exit(@Patch.This zombie.gameStates.TISLogoState state) {
        if (KEEP) return;
        state.stage = 3;
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " intro logos skipped");
        }
    }
}
