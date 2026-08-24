package lugli.fastloading;

import zombie.debug.DebugLog;

/**
 * ZombieBuddy entry point.
 *
 * WITHOUT THIS CLASS THE MOD'S LUA BRIDGE DOES NOT EXIST.
 *
 * `Loader.try_call_main` looks for a static method taking `String[]` on `<javaPkgName>.Main`,
 * calling `premain` for `Phase.PREMAIN` and `main` for `Phase.MAIN`. When it is absent the log
 * says exactly that -- `[ZB] trying to load lugli.fastloading.Main: null` -- and carries on, so
 * the patches still install and every timing figure this mod reports stays correct.
 *
 * What silently does NOT happen is Lua exposure. No `lugli.*` class ever appeared in a
 * `[ZB] Exposing class to Lua:` line across every log on this machine, while `ZBBetterFPS`,
 * `PeekAViewMod` and `ZombieBuddy` -- all of which ship a Main -- appear in every one. So every
 * `@LuaMethod` in `LuaBridge` resolved to nil, and `FastLoading_Status.lua` took its
 * `type(FastLoading_JavaActive) ~= "function"` branch and told the player
 * **"needs ZombieBuddy (Java patches inactive)"** on a machine where ZombieBuddy was installed
 * and every Java patch was demonstrably running.
 *
 * `Lugli_Dev` has always had a Main, which is why its bridge globals (`Dev_BenchScenario`,
 * `Dev_ErrorTexReport`) work and this mod's never did. The two mod.info files are otherwise
 * identical in their java keys.
 *
 * Nothing here may touch `zombie.*` at PREMAIN: the game classes are on the classpath but not
 * initialised, and loading one early could change static-initialiser order. Hence stdout there
 * (which lands in console.txt) and DebugLog only in the MAIN phase.
 */
public final class Main {

    private Main() {}

    /** Agent premain, before zombie.gameStates.MainScreenState.main. No zombie.* here. */
    public static void premain(String[] args) {
        System.out.println("[FastLoading] premain: patches install before the game's main class");
        // A media-tree prefetch was tried here and REMOVED. It worked -- it served the root
        // and passed the serial self-test -- but three measurements (block A/B, the same A/B
        // with the arms reversed, and an interleaved run) all showed no effect, and it required
        // a second copy of ModWalkPrefetch.walk that had to stay byte-identical or mod override
        // precedence would shift. Maintenance hazard for no measured gain. See
        // docs/11-boot-time.md.
    }

    /** The normal path, from inside ZomboidFileSystem.loadMods. */
    public static void main(String[] args) {
        DebugLog.log("[FastLoading] loaded; Lua bridge available");
    }
}
