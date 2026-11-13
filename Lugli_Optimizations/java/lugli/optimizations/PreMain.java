package lugli.optimizations;

/**
 * Phase.PREMAIN entry point, called only when the mod is preloaded: before this mod's patches
 * install, which is the moment their targets must already be loaded (Main.loadPatchTargets).
 * Nothing here may initialise a zombie.* class; DebugLog has no file open yet.
 */
public final class PreMain {

    private PreMain() {}

    public static void premain(String[] args) {
        Main.loadPatchTargets();
    }
}
