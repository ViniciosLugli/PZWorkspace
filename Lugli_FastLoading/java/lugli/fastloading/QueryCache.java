package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;

/**
 * Answers a constant capability query without crossing to the render thread.
 * -Dfastloading.querycache=off.
 *
 * Core.allowOptionTextureCompression (Core.java:3460) is:
 *
 *     return RenderThread.invokeQueryOnRenderContext(
 *         () -> Display.capabilities.OpenGL33 || !System.getProperty("os.name").contains("OS X"));
 *
 * There is no GL call in that lambda -- it reads a cached capabilities field and a system
 * property, neither of which can change during a session. But invokeQueryOnRenderContext is the
 * BLOCKING form, so each call parks the game thread until the render thread reaches it, behind
 * every texture upload already queued.
 *
 * The options screen asks four or more times per open (MainOptions.lua:630, :637 -- which also
 * calls getOptionTextureCompression, itself another call at Core.java:3464 -- and :641). Measured
 * against a streaming asset queue that is seconds per round-trip.
 *
 * The first call runs for real and its answer is kept; every later call returns it directly.
 * Nothing else can change the result, so this cannot answer differently from the engine.
 */
public final class QueryCache {

    public static final String TAG = "[FastLoading/querycache]";

    // public: these bodies are inlined into zombie.core.Core, which then reads them from there.
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.querycache", "on"));

    /** -1 not yet known, 0 false, 1 true. */
    public static volatile int texCompression = -1;
    public static long served;
    public static long displayModeSkipped;
    public static volatile boolean announced;

    private QueryCache() {}

    /**
     * Skips the display-mode round-trip when the requested mode is already the current one.
     *
     * MainOptions:apply calls setResolutionAndFullScreen unconditionally (MainOptions.lua:481,
     * :502) even when nothing changed, and Core.setDisplayModeInternal (Core.java:1942-1946)
     * then early-outs on exactly this four-way test -- after the caller has already paid for a
     * blocking trip behind the texture-upload queue.
     *
     * The test is made on the REQUESTED values against the live display, which is what the
     * engine compares. An earlier attempt to do this from Lua was wrong and was discarded: at
     * that level the target resolution comes from a combo box, so comparing the current state
     * against itself would have silently swallowed a real resolution change.
     */
    @Patch(className = "zombie.core.Core", methodName = "setDisplayMode")
    public static class DisplayMode {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.Argument(0) int width,
                                    @Patch.Argument(1) int height,
                                    @Patch.Argument(2) boolean fullscreen) {
            if (!ON) {
                return false;
            }
            try {
                boolean same = org.lwjglx.opengl.Display.getWidth() == width
                        && org.lwjglx.opengl.Display.getHeight() == height
                        && org.lwjglx.opengl.Display.isFullscreen() == fullscreen
                        && org.lwjglx.opengl.Display.isBorderlessWindow()
                           == zombie.core.Core.getInstance().getOptionBorderlessWindow();
                if (same) {
                    displayModeSkipped++;
                    return true;
                }
            } catch (Throwable t) {
                return false;           // anything unexpected: let the engine do it
            }
            return false;
        }
    }

    @Patch(className = "zombie.core.Core", methodName = "allowOptionTextureCompression")
    public static class TextureCompression {

        /** Skip the real body once the answer is known; OnExit then supplies it. */
        @Patch.OnEnter(skipOn = true)
        public static boolean enter() {
            return ON && texCompression >= 0;
        }

        @Patch.OnExit
        public static void exit(@Patch.Return(readOnly = false) boolean allowed) {
            if (!ON) {
                return;
            }
            if (texCompression >= 0) {
                allowed = texCompression == 1;      // body was skipped: supply the kept answer
                served++;
                return;
            }
            texCompression = allowed ? 1 : 0;       // body ran: keep what the engine decided
            if (!announced) {
                announced = true;
                DebugLog.log(TAG + " texture-compression query answered without a render round-trip");
            }
        }
    }
}
