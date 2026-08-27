package lugli.fastloading;

import me.zed_0xff.zombie_buddy.Patch;

import zombie.debug.DebugLog;

/**
 * Caps texture DIMENSIONS, including tile-pack pages. -Dfastloading.texcap=N (default 0, off).
 *
 * WHY REMOVING BYTES AND NOT REORDERING THEM
 *   A load is bound by the rate texture reaches the GPU, not by any thread being busy. Reordering
 *   when bytes move has measured null every time it has been tried; removing bytes is the only
 *   thing that has ever moved the number. This removes bytes.
 *
 * THE TWO-BIT OMISSION IT FIXES
 *   TextureID.limitMaxSize (:330-344) already downscales, using an existing mip level, on the
 *   WORKER thread -- off the render thread that is the constraint. It is gated on flags 128 or 256:
 *
 *       int flags = this.assetParams.flags;
 *       if ((flags & 384) == 0) { return data; }
 *
 *   Only model textures (ModelManager.java:1354) and vehicles (BaseVehicle.java:596,612) ever set
 *   those bits. Every texture-pack mount produces 68, 64 or 2 (GameWindow.java:636-653,
 *   ChooseGameInfo.java:265-286), so the guard fires and **pack pages are never capped at all** --
 *   the vanilla "Texture Size" option cannot touch them. Pack pages are the single largest
 *   category of upload bytes in a launch.
 *
 * WHY IT CARRIES ITS OWN SIZE INSTEAD OF READING THE OPTION
 *   Reusing Core.getMaxTextureSize() alone would make this measurable only by editing the user's
 *   graphics settings, which are theirs. -Dfastloading.texcap=N overrides the returned cap while
 *   the switch is on, so an A/B needs no settings change and nothing is left altered afterwards.
 *
 * IT IS A VISIBLE QUALITY CHANGE and ships OFF. Smaller pages mean blurrier tiles. This exists to
 * give the trade to whoever wants it, not to take it on their behalf.
 */
public final class TextureCap {

    public static final String TAG = "[FastLoading/texcap]";

    // public: both advice bodies are inlined into engine classes, which read these as their own.
    /** Maximum texture dimension in pixels, or 0 to leave the engine alone. */
    public static final int CAP = Integer.getInteger("fastloading.texcap", 0);
    public static final boolean ON = CAP > 0;

    public static volatile long packMounts;
    private static volatile boolean announced;

    private TextureCap() {}

    /**
     * Unconditional on the first call, before any other guard: a part that only reports when it
     * finds something cannot be told from one that never attached. Three defects in this mod hid
     * exactly there.
     */
    public static void announce() {
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " armed: texture dimensions capped at " + CAP
                         + " px, tile packs included");
        }
    }

    public static String status() {
        if (!ON) return "off";
        return "cap " + CAP + " px, " + packMounts + " pack mount(s) opted in";
    }

    /**
     * Adds the "obey the max texture size" bit to every texture-pack mount, which is the only
     * reason pack pages escape limitMaxSize today.
     */
    @Patch(className = "zombie.fileSystem.FileSystemImpl", methodName = "getTexturePackFlags")
    public static class PackFlags {
        @Patch.OnExit
        public static void exit(@Patch.Return(readOnly = false) int flags) {
            if (TextureCap.ON) {
                TextureCap.announce();
                TextureCap.packMounts++;
                flags = flags | 128;
            }
        }
    }

    /**
     * The cap itself. Flag 128 routes through getMaxTextureSize, so overriding it here is what
     * makes the switch self-contained -- model textures already honour this path, and pack pages
     * now join them.
     */
    @Patch(className = "zombie.core.Core", methodName = "getMaxTextureSize")
    public static class MaxSize {
        @Patch.OnExit
        public static void exit(@Patch.Return(readOnly = false) int size) {
            if (TextureCap.ON && (size <= 0 || TextureCap.CAP < size)) {
                size = TextureCap.CAP;
            }
        }
    }
}
