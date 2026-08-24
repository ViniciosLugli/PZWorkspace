package lugli.fastloading;

import java.util.HashSet;
import java.util.Map;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.GameWindow;
import zombie.core.textures.Texture;
import zombie.fileSystem.FileSystem;

/**
 * Starts the world tile-pack page decode while the player is on the main menu.
 * -Dfastloading.packwarm=on   (default OFF, unmeasured)
 *
 * GameWindow.enter() (:633-656) only MOUNTS the world texture packs -- LoadTexturePack (:893-903)
 * calls fileSystem.mountTexturePack, which reads the pack INDEX and nothing else. The page PNGs
 * load lazily on the first getSharedTexture for a sub-texture, and the first thing that asks is
 * world load: IsoWorld.LoadTileDefinitions -> IsoSpriteManager -> IsoSprite.LoadSingleTexture
 * (:393-397) -> Texture.getSharedTexture. So 1,839 mounted 1024x1024 pages are queued ~9 s into
 * the load, and barrier #2 (GameLoadingState:973) waits for every one.
 *
 * That barrier was still 18.29 s on a run with a 71 s menu dwell and a 0.03 s front gap -- i.e.
 * with the entire boot backlog already drained. The residual is work the world load itself
 * queues, and this is the bulk of it.
 *
 * Same shape and same rationale as VehicleTextureWarm, which measured 63 -> 57.5 s with
 * non-overlapping bands: the work is not removed, it is started while the player is reading the
 * menu instead of while they are waiting for a world.
 *
 * WHY LUA-INVOKED AND NOT A @Patch: identical reason to VehicleTextureWarm -- a
 * MainScreenState.update advice silently never installed. Menu Lua always runs.
 *
 * ONE TASK PER PAGE, NOT PER TILE. The TextureID AssetPath is "@pack@/<pack>/<page>"
 * (Texture.java:132) and AssetManager.load dedupes by path, so touching a single sub-texture
 * pulls its whole page exactly once. This groups by (packName, pageName) and touches one
 * representative per page.
 *
 * RE-RUNNABLE ON PURPOSE. IngameState.exit() -> loadModPackFiles -> setTexturePackLookup ->
 * Texture.onTexturePacksChanged() (GameWindow.java:885) clears s_sharedTextureTable when you go
 * back to the menu. The decoded assets survive in AssetManager, so a second run is a cheap
 * lookup re-walk rather than a re-decode -- but it must be allowed to happen, so this does NOT
 * latch a done flag the way VehicleTextureWarm does.
 *
 * See docs/18-fastloading-internals.md#packwarm
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
