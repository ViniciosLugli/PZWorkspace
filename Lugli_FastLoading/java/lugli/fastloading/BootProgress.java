package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.Core;
import zombie.core.SpriteRenderer;
import zombie.core.fonts.AngelCodeFont;
import zombie.debug.DebugLog;
import zombie.ui.TextManager;
import zombie.ui.UIFont;

/**
 * Keeps the window alive and drawing while boot loads. -Dfastloading.progress=off.
 *
 * GameWindow.DoLoadingText only writes to the log, so for the ten-odd seconds of script and Lua
 * loading the window is frozen and the OS may mark it unresponsive. This pumps messages and draws
 * the phase name the engine already announced.
 */
public final class BootProgress {

    public static final String TAG = "[FastLoading/progress]";

    /**
     * -Dfastloading.progress=off draws nothing. Separate from the `off` latch below, which is
     * the failure containment: one is the operator's choice, the other is this class deciding
     * it is unsafe to keep drawing, and collapsing them would make a crash look like a setting.
     */
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.progress", "on"));

    /** Frame budget. Each frame costs about 4 ms, so this is well under 1% of the phase. */
    public static final long INTERVAL_MS = 150L;

    // public: these bodies are inlined into zombie.* classes, which then access them there.
    public static volatile String phase = "";
    public static volatile int counter;
    public static volatile long lastFrame;
    public static volatile boolean off;
    public static volatile boolean drew;

    private BootProgress() {}

    /**
     * How long after the last announced phase this keeps drawing. A cap, so a missed final phase
     * cannot leave the overlay up forever.
     */
    public static final long PHASE_IDLE_MS = 30000L;

    public static volatile long lastPhaseAt;

    /** Latches whatever the engine last announced, so the drawn text matches the log. */
    public static void note(String text) {
        if (text == null || text.isEmpty()) return;
        phase = text;
        counter = 0;
        lastPhaseAt = System.currentTimeMillis();
    }

    public static void tick() {
        if (!ON || off) return;
        counter++;
        long now = System.currentTimeMillis();
        if (lastPhaseAt == 0L || now - lastPhaseAt > PHASE_IDLE_MS) return;
        if (now - lastFrame < INTERVAL_MS) return;
        lastFrame = now;
        try {
            draw();
            if (!drew) {
                drew = true;
                DebugLog.log(TAG + " drawing loading frames during script and Lua load");
            }
        } catch (Throwable t) {
            off = true;
            DebugLog.log(TAG + " display disabled (" + t + ")");
        }
    }

    public static void draw() {
        TextManager tm = TextManager.instance;
        if (tm == null) return;
        AngelCodeFont font = tm.getFontFromEnum(UIFont.NewLarge);
        if (font == null) return;

        Core core = Core.getInstance();
        int w = core.getScreenWidth();
        int h = core.getScreenHeight();
        if (w <= 0 || h <= 0) return;

        core.StartFrame();
        core.EndFrame();
        core.StartFrameUI();
        SpriteRenderer.instance.renderi(null, 0, 0, w, h, 0.0F, 0.0F, 0.0F, 1.0F, null);
        tm.DrawStringCentre(font, w / 2.0, h / 2.0, phase + "   " + counter, 1.0, 1.0, 1.0, 1.0);
        core.EndFrameUI();
    }

    @Patch(className = "zombie.GameWindow", methodName = "DoLoadingText")
    public static class Phase {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String text) {
            BootProgress.note(text);
        }
    }

    /** Called once per Lua file, roughly 7,300 times, so the throttle does the real work. */
    @Patch(className = "zombie.Lua.LuaManager", methodName = "RunLua")
    public static class LuaFile {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.tick();
        }
    }
}
