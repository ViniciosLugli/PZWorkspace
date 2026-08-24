package lugli.fastloading;

import java.util.HashSet;
import java.util.Map;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.GameWindow;
import zombie.core.textures.Texture;
import zombie.fileSystem.FileSystem;

/**
 * Decodes world tile-pack pages while the player is on the main menu.
 * -Dfastloading.packwarm=on (default OFF: measured 17 s SLOWER at a realistic menu dwell).
 *
 * The engine mounts the packs at boot but decodes their pages lazily during world load. Warming
 * them only helps if the warm COMPLETES first: the world-load barrier waits on every queue at
 * every priority, so anything still in flight is time the load now waits for.
 */
public final class PackPageWarm {

    public static final String TAG = "[FastLoading/packwarm]";

    public static final boolean ON = "on".equals(System.getProperty("fastloading.packwarm", "off"));

    /** Safety valve: refuse to queue an implausible number of pages. */
    public static final int MAX_PAGES = 2000;

    /**
     * Priority for warmed pages. BELOW the FileTask default of 5, so a warm can never delay the
     * clothing XMLs that world-load barrier #1 waits on.
     *
     * This is the fix for why the first version of this made world load 17 s WORSE (82 -> 99 s):
     * `getSharedTexture` queues at priority 7, and 1,838 pages at priority 7 starved the
     * priority-5 clothing queue, pushing barrier #1 from 32 s to 73 s. Sibling `vehtex` gets away
     * with priority 7 only because its volume is far smaller.
     *
     * At a short dwell this now decodes almost nothing (correct -- there is no idle time to use);
     * at a long dwell it keeps the upside. It can no longer make a short-dwell load worse.
     */
    public static final int WARM_PRIORITY = 3;

    /**
     * Set for the duration of the warm loop and consumed by MeshPriority on `runAsync`.
     * `Texture.getSharedTexture` creates and queues the FileTask synchronously on this thread, so
     * a thread-local reaches the advice; the caller has no other way to set the priority.
     */
    public static final ThreadLocal<Boolean> WARMING = new ThreadLocal<>();

    private PackPageWarm() {}

    @LuaMethod(name = "FastLoading_WarmPackPages", global = true)
    public static String warm() {
        if (!ON) {
            return "off";
        }
        Map<String, FileSystem.SubTexture> all = GameWindow.texturePackTextures;
        if (all == null || all.isEmpty()) {
            return "no texture packs mounted";
        }
        HashSet<String> seenPages = new HashSet<>();
        int queued = 0;
        int skippedUi = 0;
        long t0 = System.currentTimeMillis();

        for (Map.Entry<String, FileSystem.SubTexture> e : all.entrySet()) {
            FileSystem.SubTexture sub = e.getValue();
            if (sub == null || sub.packName == null || sub.pageName == null) {
                continue;
            }
            // The seven first-frame UI packs are already loaded at boot (GameWindow:185-191);
            // touching them again is pure waste and would fight UiPriority.
            if (Tuning.isFirstFrameUiAsset("@pack@/" + sub.packName + "/" + sub.pageName)) {
                skippedUi++;
                continue;
            }
            if (!seenPages.add(sub.packName + "/" + sub.pageName)) {
                continue;
            }
            if (queued >= MAX_PAGES) {
                break;
            }
            // Queues the page decode on the asset pool; this call itself does not block.
            WARMING.set(Boolean.TRUE);
            try {
                Texture.getSharedTexture(e.getKey());
            } finally {
                WARMING.remove();
            }
            queued++;
        }
        return "queued " + queued + " page(s), skipped " + skippedUi
                + " first-frame UI sub-texture(s), in " + (System.currentTimeMillis() - t0) + " ms";
    }
}
