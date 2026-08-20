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

    @LuaMethod(name = "FastLoading_WatcherGateStatus", global = true)
    public static String watcherGateStatus() {
        return WatcherGate.status();
    }
}
