package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;

/**
 * The TIS and FMOD intro logos cost about 5.5 s and nothing loads behind them: they run
 * after "Game booting", once every loading phase has finished.
 *
 * This takes the engine's own skip path rather than inventing one. TISLogoState.update
 * already sets stage = 3 when the player clicks or presses Enter, Space or Escape; the
 * stage 3 branch then sees alpha at 0, sets noRender and returns Continue. Setting the
 * same field on entry reaches the menu one frame later.
 *
 * enter() still runs first, so UIManager.suspend is set and the matching exit() clears it.
 *
 * The Indie Stone disable the logos in their own dev builds: DebugOptions
 * uiDisableLogoState defaults to true, but GameWindow only honours it when Core.debug is
 * set, so a normal launch always plays them.
 *
 * Launch with -Dfastloading.logo=keep to watch them anyway.
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
        // With -Dfastloading.logowait set, LogoWait decides when to release instead: skipping
        // here would end the state before it ever had a chance to hold.
        if (LogoWait.WAIT_MS > 0) return;
        state.stage = 3;
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " intro logos skipped");
        }
    }
}
