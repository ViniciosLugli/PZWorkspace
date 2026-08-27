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
             + " budgetMB=" + (AssetThrottle.BUDGET / (1024 * 1024));
    }

    @LuaMethod(name = "FastLoading_WatcherGateStatus", global = true)
    public static String watcherGateStatus() {
        return WatcherGate.status();
    }

    /**
     * Priority-merge counters. Reported from Lua as well as at the menu handover, because the
     * boot line alone cannot separate the world-load half -- MergeStat snapshots boot, so this
     * string minus that snapshot is the load.
     */
    @LuaMethod(name = "FastLoading_MergeStat", global = true)
    public static String mergeStat() {
        return MergeStat.status();
    }

    /**
     * Deferred-icon counters. `resolved` climbing while the player opens containers is the part
     * working; `resolved` at zero with `deferred` high means nothing has asked for an icon yet,
     * which at the menu is correct and in play is a defect.
     */
    @LuaMethod(name = "FastLoading_LazyIcon", global = true)
    public static String lazyIcon() {
        return LazyIcon.status();
    }
}
