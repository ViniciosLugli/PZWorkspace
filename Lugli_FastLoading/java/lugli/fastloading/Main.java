package lugli.fastloading;

import zombie.debug.DebugLog;

/**
 * ZombieBuddy entry point.
 *
 * ZombieBuddy calls `<javaPkgName>.Main.main(String[])` at the regular Java mod load
 * (`Loader.try_call_main`, Phase.MAIN); the agent-time phase would call a separate
 * `<javaPkgName>.PreMain.premain`, which this mod does not need: preloading installs the patches
 * whether or not an entry point exists. The @LuaMethod bridge is exposed by
 * ZombieBuddy's Exposer from the package scan, not by this class.
 */
public final class Main {

    /**
     * The status of a part whose engine call runs before a regular Java mod loads (the mod-folder
     * scan, its watcher registration): on a launch without ZombieBuddy preload it never fires.
     */
    public static final String NEEDS_PRELOAD =
            "idle: needs ZombieBuddy preload, the engine ran this before the jar loaded";

    private Main() {}

    public static void main(String[] args) {
        DebugLog.log("[FastLoading] loaded; Lua bridge available");
    }
}
