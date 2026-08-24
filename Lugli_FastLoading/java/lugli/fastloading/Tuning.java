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
     * Vanilla hardcodes 50 MB. This was heap/8 capped at 1 GB, and that cap turned out to be the
     * single largest cost in the whole load: the asset workers spent 433 s asleep in the gate it
     * feeds on a 300+ mod list. The measured knee is 2 GB, above which it never binds.
     * MaxDirectMemorySize defaults to the max heap, so scale off that rather than picking a
     * number for one machine.
     */
    public static long budgetBytes(long maxHeapBytes) {
        long b = maxHeapBytes / 2;
        if (b < MIN_BUDGET) return MIN_BUDGET;
        if (b > MAX_BUDGET) return MAX_BUDGET;
        return b;
    }

    /**
     * The budget after -Dfastloading.assetbudget=N (megabytes); 0 or absent uses the rule above.
     * Deliberately allows values above MAX_BUDGET so the ceiling itself can be tested, but never
     * drops below vanilla's 50 MB.
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
     * that carries Trigger_*.xml.
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
