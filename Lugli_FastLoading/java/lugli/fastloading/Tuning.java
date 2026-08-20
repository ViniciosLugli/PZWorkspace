package lugli.fastloading;

/** Sizing rules. Kept separate so they can be tested without a running game. */
final class Tuning {
    private Tuning() {}

    static final String TAG = "[FastLoading/assets]";
    static final long MIN_BUDGET = 64L * 1024 * 1024;
    static final long MAX_BUDGET = 1024L * 1024 * 1024;

    /**
     * Live direct-buffer bytes tolerated before an asset worker waits.
     * Vanilla hardcodes 50 MB, which one 2048px RGBA texture (~16 MB, ~22 MB with
     * mipmaps) blows through with four workers. MaxDirectMemorySize defaults to the
     * max heap, so scale off that instead of picking a number for one machine.
     */
    static long budgetBytes(long maxHeapBytes) {
        long b = maxHeapBytes / 8;
        if (b < MIN_BUDGET) return MIN_BUDGET;
        if (b > MAX_BUDGET) return MAX_BUDGET;
        return b;
    }

    /**
     * Asset pool size, or 0 to leave the stock pool alone.
     * Vanilla: cores <= 4 ? 2 : 4 (FileSystemImpl). Only ever raise it, and only on
     * machines with cores to spare.
     */
    static int poolTarget(int cores) {
        if (cores < 6) return 0;
        int t = cores - 2;
        if (t < 5) return 5;
        return t > 12 ? 12 : t;
    }

    /**
     * Should WatcherGate skip a recursive hot-reload watch registration for this path?
     *
     * Lives here, away from any zombie.* import, so the build can unit-test it. Getting it
     * wrong in the permissive direction only costs boot time; getting it wrong in the
     * restrictive direction silently stops a live-reload path the player may rely on, so
     * the rule is: skip ONLY a recognisable media tree, keep everything else, and never
     * skip the messaging folder that carries Trigger_*.xml.
     */
    static boolean isSkippableWatchRoot(String path, char separator) {
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
