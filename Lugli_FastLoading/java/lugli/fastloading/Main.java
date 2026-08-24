package lugli.fastloading;

import zombie.debug.DebugLog;

/**
 * ZombieBuddy entry point.
 *
 * WITHOUT THIS CLASS THE LUA BRIDGE DOES NOT EXIST. ZombieBuddy looks for a static method
 * taking String[] on <javaPkgName>.Main. If it is missing the patches still install, but no
 * @LuaMethod is exposed, so every bridge global is nil and the status panel wrongly reports
 * the Java side as unavailable.
 *
 * Nothing here may touch zombie.* at premain: the game classes are on the classpath but not
 * initialised, and loading one early would change static-initialiser order.
 */
public final class Main {

    private Main() {}

    /** Agent premain, before zombie.gameStates.MainScreenState.main. No zombie.* here. */
    public static void premain(String[] args) {
        System.out.println("[FastLoading] premain: patches install before the game's main class");
        // A media-tree prefetch lived here and was removed: it worked, but three separate
        // measurements showed no effect, and it needed a duplicate of ModWalkPrefetch.walk kept
        // byte-identical or mod override precedence would shift.
    }

    /** The normal path, from inside ZomboidFileSystem.loadMods. */
    public static void main(String[] args) {
        DebugLog.log("[FastLoading] loaded; Lua bridge available");
    }
}
