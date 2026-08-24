package lugli.fastloading;

/** Sizing rules. Kept separate so they can be tested without a running game. */
public final class Tuning {
    private Tuning() {}

    public static final String TAG = "[FastLoading/assets]";
    public static final long MIN_BUDGET = 64L * 1024 * 1024;
    public static final long MAX_BUDGET = 2048L * 1024 * 1024;

    /**
     * Live direct-buffer bytes tolerated before an asset worker waits.
     *
     * Vanilla hardcodes 50 MB, which one 2048px RGBA texture (~16 MB, ~22 MB with mipmaps) blows
     * through with four workers. MaxDirectMemorySize defaults to the max heap, so scale off that
     * rather than picking a number for one machine.
     *
     * WAS heap/8 CAPPED AT 1 GB, AND THAT WAS THE SINGLE LARGEST COST IN THE WHOLE LOAD.
     * On a 6 GB heap it gave 768 MB, and one world load spent **433.7 seconds of asset-worker
     * time asleep** in the gate it feeds (blocked on 21 % of calls). Measured end to end, cap 16,
     * 5 s menu dwell, interleaved arms, world load / launch-to-playing / blocked ms:
     *
     *      768 MB   54-55 s   87.2-89.1 s   433,716 ms      &lt;- the old default
     *     1024 MB   50    s   83.3-83.9 s   352-379,000 ms
     *     2048 MB   38-39 s   71.5-72.8 s   134-141,000 ms  &lt;- the knee
     *     4096 MB   40    s   73.7      s
     *
     * 4096 is no better than 2048, so peak live direct-buffer usage on a 337-mod list is around
     * 2 GB and a budget above that simply never binds. Hence heap/2 capped at 2 GB: this machine
     * gets the full 2 GB, a stock 3 GB heap gets 1.5 GB, and the cap keeps peak direct memory at
     * or under half of MaxDirectMemorySize (which itself defaults to the max heap).
     *
     * The budget is a THROTTLE THRESHOLD, not an allocation -- raising it does not reserve
     * anything, it only stops workers sleeping sooner. It does raise peak live bytes, which is
     * why the heap/2 term stays.
     */
    public static long budgetBytes(long maxHeapBytes) {
        long b = maxHeapBytes / 2;
        if (b < MIN_BUDGET) return MIN_BUDGET;
        if (b > MAX_BUDGET) return MAX_BUDGET;
        return b;
    }

    /**
     * The budget actually used, after -Dfastloading.assetbudget=N (megabytes).
     *
     * WHY THIS OVERRIDE EXISTS. Measured 2026-08-23 on the 300+ mod list, one world load:
     *
     *     [DevAssetStats] calls=12865 blocked=2695 blockedMs=433716 pollMs=20 budgetMB=768
     *
     * 433.7 SECONDS of asset-worker time asleep inside waitFileTask, on 21 % of calls -- roughly
     * half of all worker time available across boot plus load. That is why the workers measure at
     * 15-25 % of a core, why throughput sits at ~250 tasks/s whatever else changes, and why
     * raising the in-flight cap 16 to 48 made worker CPU FALL rather than rise: a deeper queue
     * means more live decoded buffers, which means more crossings of this very gate.
     *
     * The gate is OURS. Vanilla's is 50 MB polled every 20 ms; we raised it to heap/8 capped at
     * 1 GB, which on a 6 GB heap is 768 MB -- and it is still being hit constantly. So the ceiling
     * is a thing to measure, not to assume. MAX_BUDGET stays where it is because it is the sizing
     * rule for shipping; this override deliberately allows values above it for an experiment.
     *
     * 0 or absent = the computed value. Never below vanilla's 50 MB, whatever is asked for.
     */
    public static long effectiveBudgetBytes(long maxHeapBytes, long overrideMB) {
        if (overrideMB <= 0L) {
            return budgetBytes(maxHeapBytes);
        }
        long b = overrideMB * 1024L * 1024L;
        return b < MIN_BUDGET ? MIN_BUDGET : b;
    }

    /**
     * Asset pool size, or 0 to leave the stock pool alone.
     * Vanilla: cores <= 4 ? 2 : 4 (FileSystemImpl). Only ever raise it, and only on
     * machines with cores to spare.
     */
    public static int poolTarget(int cores) {
        if (cores < 6) return 0;
        int t = cores - 2;
        if (t < 5) return 5;
        return t > 12 ? 12 : t;
    }

    /**
     * Should WatcherGate skip a recursive hot-reload watch registration for this path?
     *
     * Lives here, away from any zombie.* import, so the build can unit-test it. Getting it wrong
     * permissively only costs boot time; getting it wrong restrictively silently stops a
     * live-reload path, so: skip ONLY a recognisable media tree, and never the messaging folder
     * that carries Trigger_*.xml. See docs/18-fastloading-internals.md#watchergate-scope
     */
    public static boolean isSkippableWatchRoot(String path, char separator) {
        if (path == null || path.isEmpty()) return false;
        // Normalise BOTH separators, not just the platform one. The engine builds paths by
        // concatenation and they routinely arrive mixed ("E:/PZ\media\scripts"), so keying
        // off File.separatorChar alone would leave half of them unmatched. A unit test caught
        // exactly that.
        String p = path.replace(separator, '/').replace('\\', '/')
                       .toLowerCase(java.util.Locale.ENGLISH);
        if (p.endsWith("/messaging") || p.contains("/messaging/")) return false;
        return p.endsWith("/media") || p.contains("/media/");
    }

    /**
     * Is this asset one of the textures the FIRST drawn frame needs?
     *
     * GameWindow.java:185-191 loads exactly seven packs, then calls
     * MainScreenState.preloadBackgroundTextures() at :195. Those, plus loose files under
     * media/ui/, are what the menu draws before anything else exists. Everything else -- the
     * world packs at :639-647 especially -- must NOT match: promoting those would just move the
     * whole texture block up and undo the mesh ordering.
     *
     * ONE ARGUMENT, BECAUSE THE PATH ALREADY CARRIES THE PACK NAME. Texture.java:130 builds a
     * pack TextureID's path as "@pack@/<packName>/<pageName>", and Asset.getPath() is public --
     * so there is no need to reach for TextureID.assetParams.subTexture, which is
     * package-private in zombie.core.textures and therefore unreachable from this package even
     * though the inlined advice would be allowed to read it. Texture.java:508 uses the "@pack/"
     * spelling for the Texture-level asset, so both prefixes are accepted.
     *
     * Lives here, free of zombie.* imports, so the build can unit-test it.
     * See docs/18-fastloading-internals.md#uipriority
     */
    public static boolean isFirstFrameUiAsset(String path) {
        if (path == null || path.isEmpty()) return false;
        // Same both-separators rule as isSkippableWatchRoot: engine paths arrive mixed.
        String p = path.replace('\\', '/').toLowerCase(java.util.Locale.ENGLISH);
        int from = -1;
        if (p.startsWith("@pack@/")) from = 7;
        else if (p.startsWith("@pack/")) from = 6;
        if (from >= 0) {
            int end = p.indexOf('/', from);
            String pack = end < 0 ? p.substring(from) : p.substring(from, end);
            return pack.equals("ui") || pack.equals("ui2") || pack.equals("iconsmoveables")
                || pack.equals("radioicons") || pack.equals("apcomui")
                || pack.equals("mechanics") || pack.equals("weatherfx");
        }
        return p.startsWith("media/ui/") || p.contains("/media/ui/");
    }
}
