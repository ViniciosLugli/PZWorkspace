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
     * Ceiling on live decoded bytes while the MENU is up. -Dfastloading.menubudget=N.
     *
     * DEFAULT 0 (off) BECAUSE IT MEASURED NULL AND POSSIBLY WORSE. Three interleaved pairs,
     * 60 s menu dwell, 337 mods, 2026-08-26: worst front-end tick gap 67-171 ms at 256 MB against
     * 107-110 ms uncapped -- fully overlapping, no effect. World load went the other way, 45/48/47
     * against 39/48/39, and the mechanism for that is written below: pacing the menu budget paces
     * the vehicle warm, so work that used to finish during the dwell spills into the load.
     *
     * The hypothesis it was built to test -- that a 2,048 MB budget authorises ~10 s of queued
     * render work and that is the reported 8 s menu freeze -- is NOT disproven, because the test
     * could not create the condition. A quiet menu holds live bytes near 293 MB and never
     * approaches the ceiling. Reproducing it needs the burst a real screen makes:
     * -Ddev.probe.menustress=true opens the mod list and measures it.
     */
    public static final long MENU_BUDGET_MB = Long.getLong("fastloading.menubudget", 0L);

    /**
     * The budget to apply while the front end is ticking, which need not be the loading budget.
     *
     * THE IDEA. During a load a deep queue is invisible: a loading screen is in front of it, and
     * the big budget is worth 433 s on a 300+ list. At the menu the same budget is potentially a
     * visible freeze, because live bytes drain only as the render thread uploads them at ~205 MB/s
     * and the UI cannot draw until that flush returns -- so 2,048 MB authorises up to
     * ~10 s of render work. 256 MB would cap that at ~1.2 s.
     *
     * WHAT MEASUREMENT SAID. Null on the symptom, slightly negative on load. See MENU_BUDGET_MB
     * above for the bands. The reason the test did not settle the idea is that a quiet menu never
     * gets near the ceiling; only a screen that requests hundreds of textures at once does, and no
     * harness opened one. That is what -Ddev.probe.menustress=true was built to fix.
     *
     * THE COST that showed up instead: the vehicle warm is bulk work that runs at the menu on
     * purpose, and a smaller budget paces it, so work that used to finish during the dwell spills
     * into world load. That is the likeliest explanation for 45/48/47 against 39/48/39.
     *
     * RELATED, AND ALSO OFF: -Dfastloading.uploadcap caps the invoke-queue DEPTH rather than bytes,
     * and AssetThrottle records why it lost -- a worker parked in the gate still holds an in-flight
     * slot, so capping starves the request the player is waiting for. This parks on the same gate,
     * which may well be why it fared no better.
     *
     * Never above the loading budget: a "menu budget" that exceeded it would be a raise, not a cap.
     */
    public static long menuBudgetBytes(long loadingBudgetBytes, long overrideMB) {
        if (overrideMB <= 0L) {
            return loadingBudgetBytes;
        }
        long b = overrideMB * 1024L * 1024L;
        if (b < MIN_BUDGET) b = MIN_BUDGET;
        return b > loadingBudgetBytes ? loadingBudgetBytes : b;
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
     * The asset priority bands, all four here because this is the one file the unit tests can see;
     * everything else imports zombie.*. Split across two classes, meshband and demandband both
     * reached 9 without anything noticing.
     */
    public static final int BULK_BAND = Integer.getInteger("fastloading.bulkband", 3);

    /** Fixed by the engine: TextureIDAssetManager.startLoading queues every texture at 7. */
    public static final int TEXTURE_BAND = 7;

    /** Above the texture block, below demand -- see MeshPriority. */
    public static final int MESH_BAND = Integer.getInteger("fastloading.meshband", 8);

    /** Top of the range: what the player is waiting on right now. */
    public static final int DEMAND_BAND = Integer.getInteger("fastloading.demandband", 9);

    /**
     * Must stay strictly ordered: bulk < texture < mesh < demand. A collision is not a crash, it
     * is a slow load nobody can explain -- FileSystemImpl inserts on a strict `>` (:206-214), so
     * equal priorities never overtake and one intended promotion silently stops working. That
     * shipped once, at meshband=9.
     */
    public static boolean bandsOrdered(int bulk, int texture, int mesh, int demand) {
        return bulk < texture && texture < mesh && mesh < demand;
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

}
