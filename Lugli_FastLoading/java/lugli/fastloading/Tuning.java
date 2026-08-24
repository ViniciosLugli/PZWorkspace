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

}
