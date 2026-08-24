package lugli.fastloading;

import se.krka.kahlua.integration.annotations.LuaMethod;

/**
 * Lets the Lua side know the jar actually loaded. Without ZombieBuddy this class is
 * never loaded, so the global stays nil and the status panel reports the Java patches
 * as unavailable. More reliable than checking the mod list, which only proves
 * ZombieBuddy is subscribed.
 */
public class LuaBridge {

    @LuaMethod(name = "FastLoading_JavaActive", global = true)
    public static boolean javaActive() {
        return true;
    }

    @LuaMethod(name = "FastLoading_AssetBudgetMB", global = true)
    public static int assetBudgetMB() {
        return (int)(AssetThrottle.BUDGET >> 20);
    }

    @LuaMethod(name = "FastLoading_AssetPoolTarget", global = true)
    public static int assetPoolTarget() {
        return Tuning.poolTarget(Runtime.getRuntime().availableProcessors());
    }

    @LuaMethod(name = "FastLoading_LogoSkipped", global = true)
    public static boolean logoSkipped() {
        return !LogoSkip.KEEP;
    }

    /**
     * True when the script tokenizer disagreed with the engine's own and turned itself off.
     * That is a defect worth showing the player: it means a rewrite in this mod was wrong,
     * and it also switches the tile geometry prefetch off, since that prefetch is only safe
     * while our thread-safe stripComments is in place.
     */
    @LuaMethod(name = "FastLoading_ParseDefect", global = true)
    public static boolean parseDefect() {
        return ScriptParse.broken;
    }

    @LuaMethod(name = "FastLoading_ParseStatus", global = true)
    public static String parseStatus() {
        return ScriptParse.status();
    }

    /**
     * Called from the main menu. Ends the boot-only asset priority raise.
     *
     * MeshPriority is worth ~12 s at boot and about -24 s at every world load (measured, both
     * arms, 2026-08-22), because at boot initAnimationMeshes blocks on 79 meshes while at world
     * load nothing does and the raise merely reorders a queue whose consumers want the textures.
     */
    @LuaMethod(name = "FastLoading_EndBootPhase", global = true)
    public static String endBootPhase() {
        if (MeshPriority.bootDone) {
            return "already";
        }
        MeshPriority.bootDone = true;
        return "mesh priority raise disarmed after " + MeshPriority.raised + " raises";
    }

    /**
     * Read one of this mod's -D switches from Lua, e.g. FastLoading_Switch("gunidx", "on").
     *
     * Shared Lua runs on a dedicated server too, where this jar never loads and the global is
     * nil. Callers must treat a missing global as the default, not as "off".
     */
    @LuaMethod(name = "FastLoading_Switch", global = true)
    public static String switchValue(String name, String def) {
        if (name == null) {
            return def;
        }
        return System.getProperty("fastloading." + name, def);
    }

    /**
     * Asset-pipeline diagnostics. `blocked` non-zero means the direct-buffer budget was actually
     * reached, which can only happen when decoded images are queued waiting for the render thread
     * to upload them -- i.e. direct evidence that GL upload, not decode, is the bottleneck.
     */
    @LuaMethod(name = "FastLoading_AssetStats", global = true)
    public static String assetStats() {
        return "calls=" + AssetThrottle.totalCalls
             + " blocked=" + AssetThrottle.blockedCalls
             + " blockedMs=" + AssetThrottle.blockedMs
             + " pollMs=" + AssetThrottle.POLL_MS
             + " budgetMB=" + (AssetThrottle.BUDGET / (1024 * 1024))
             + " bufalloc=" + (BufferAlloc.ON ? BufferAlloc.served : -1);
    }

    /** Task-type census, -Dfastloading.census=on. Attributes a phase to real work, not a guess. */
    @LuaMethod(name = "FastLoading_Census", global = true)
    public static String census() {
        if (!MeshPriority.CENSUS) {
            return "off";
        }
        // Formatted HERE, not in MeshPriority: that class carries @Patch advice, and a comparator
        // or lambda there compiles to a synthetic the inlined body cannot reach. LuaBridge has no
        // advice, so ordinary Java is safe.
        StringBuilder sb = new StringBuilder();
        synchronized (MeshPriority.CENSUS_COUNTS) {
            java.util.ArrayList<String> names =
                    new java.util.ArrayList<>(MeshPriority.CENSUS_COUNTS.keySet());
            while (!names.isEmpty()) {
                String best = null;
                int bestN = -1;
                for (String n : names) {
                    int c = MeshPriority.CENSUS_COUNTS.get(n)[0];
                    if (c > bestN) {
                        bestN = c;
                        best = n;
                    }
                }
                sb.append(best).append('=').append(bestN).append(' ');
                names.remove(best);
            }
        }
        return sb.length() == 0 ? "(none)" : sb.toString().trim();
    }

    @LuaMethod(name = "FastLoading_WatcherGateStatus", global = true)
    public static String watcherGateStatus() {
        return WatcherGate.status();
    }
}
