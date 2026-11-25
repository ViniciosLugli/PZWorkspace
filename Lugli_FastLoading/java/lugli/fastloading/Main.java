package lugli.fastloading;

import zombie.debug.DebugLog;

/**
 * ZombieBuddy entry point.
 *
 * ZombieBuddy calls `PreMain.premain` when the mod is preloaded (Phase.PREMAIN) and
 * `Main.main(String[])` at the regular Java mod load (Phase.MAIN), each BEFORE that phase installs
 * this mod's patches (`Loader.ApplyPatchesFromPackage`). Both make the patch targets visible to the
 * install pass; see loadPatchTargets. The @LuaMethod bridge is exposed by ZombieBuddy's Exposer
 * from the package scan, not by this class.
 */
public final class Main {

    /**
     * Patch targets that must already be LOADED when ZombieBuddy installs this mod's patches.
     *
     * ZombieBuddy retransforms every target class loaded at install time and leaves the rest to
     * the new-load transformer. A target that loads DURING the install is caught by neither:
     * measured on 42.22.2 with -Xlog:class+load, retransforming TextureIDAssetManager resolves
     * startLoading's types, which loads these four inside the transformer, and Byte Buddy does not
     * transform a class whose load its own transformer triggered. DxtPrep and DemandPriority then
     * never wove. Loading them first puts them on the retransform list.
     *
     * `initialize = false`: LOAD the class, do not run its static initialiser, which would reorder
     * engine initialisation.
     */
    private static final String[] PATCH_TARGETS = {
        "zombie.fileSystem.FileTask",
        "zombie.asset.AssetTask_RunFileTask",
        "zombie.asset.FileTask_LoadImageData",
        "zombie.asset.FileTask_LoadPackImage",
        "zombie.tileDepth.TileDepthTexture",
        "zombie.iso.IsoMetaGrid",
        "zombie.basements.Basements",
        "zombie.buildingRooms.BuildingRoomsEditor",
        "zombie.core.textures.PNGDecoder",
        "se.krka.kahlua.stdlib.StringLib$Allocations",
        "se.krka.kahlua.stdlib.StringLib",
    };

    static void loadPatchTargets() {
        for (String name : PATCH_TARGETS) {
            try {
                Class.forName(name, false, Main.class.getClassLoader());
            } catch (Throwable t) {
                System.out.println("[FastLoading] could NOT load " + name + " for patching: " + t);
            }
        }
    }

    /**
     * The status of a part whose engine call runs before a regular Java mod loads (the mod-folder
     * scan, its watcher registration): on a launch without ZombieBuddy preload it never fires.
     */
    public static final String NEEDS_PRELOAD =
            "idle: needs ZombieBuddy preload, the engine ran this before the jar loaded";

    private Main() {}

    public static void main(String[] args) {
        loadPatchTargets();
        TileJit.install();
        DebugLog.log("[FastLoading] loaded; Lua bridge available");
    }
}
