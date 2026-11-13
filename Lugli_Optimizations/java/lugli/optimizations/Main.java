package lugli.optimizations;

/**
 * ZombieBuddy entry point for Lugli - Optimizations.
 *
 * SCOPE, deliberately narrow: changes to the GAME ENGINE's own per-frame work that are
 * independent of any mod, revert cleanly, and are proven not to alter what is drawn. Nothing here
 * targets another mod's behaviour and nothing changes a user-facing game setting.
 *
 * Every part follows the same contract:
 *   - it can be turned off individually with a -Dlugli.opt.* property;
 *   - it carries a runtime self-test and DISARMS ITSELF rather than risk a visual defect;
 *   - it reports whether its advice actually installed -- see PatchAudit.
 *
 * DEFAULTS. A part that is OFF has not earned ON yet.
 *
 *   windgate    fast     ON   -- the headline part
 *   zextents    fast     ON   -- exact and self-verifying, but far under the noise floor
 *   roomindex   fast     ON   -- the same shape
 *   uistagger   off      OFF  -- real on its own metric, but the frame-time bands overlap
 *   chunklua    observe  OFF  -- counts only; `spread` is lossless but its frame-time bands overlap
 *
 * Measured results and the conditions attached to them live in the README, not here.
 *
 * ZombieBuddy calls `PreMain.premain` when the mod is preloaded (Phase.PREMAIN, before this mod's
 * patches install) and `Main.main` at the regular Java mod load (Phase.MAIN). Both make the patch
 * targets visible to the install pass; see loadPatchTargets.
 */
public final class Main {

    public static final String VERSION = "1.0.0";

    private Main() {}

    /**
     * Patch targets that must already be LOADED when ZombieBuddy installs this mod's patches.
     *
     * ZombieBuddy retransforms every target class that is loaded at install time, and leaves the
     * rest to the new-load transformer. A target that loads DURING the install is caught by
     * neither: measured on 42.22.2 with -Xlog:class+load, retransforming IsoRoom resolves its
     * types, which loads IsoCell inside the transformer, and Byte Buddy does not transform a class
     * whose load its own transformer triggered. IsoCell.updateInternal then never wove, and with
     * it the chunklua drain. Loading the targets first puts them on the retransform list.
     *
     * `initialize = false`: LOAD the class, do not run its static initialiser, which would
     * reorder engine initialisation (the trap that makes FileSystemImpl unpatchable).
     */
    private static final String[] PATCH_TARGETS = {
        "zombie.iso.IsoCell",
        "zombie.iso.areas.IsoRoom",
        "zombie.iso.IsoChunkMap",
    };

    static void loadPatchTargets() {
        for (String name : PATCH_TARGETS) {
            try {
                Class.forName(name, false, Main.class.getClassLoader());
                System.out.println("[Lugli/Opt] loaded for patching: " + name);
            } catch (Throwable t) {
                System.out.println("[Lugli/Opt] could NOT load " + name + ": " + t);
            }
        }
    }

    /** MAIN phase: the normal path, from inside ZomboidFileSystem.loadMods. */
    public static void main(String[] args) {
        loadPatchTargets();
        System.out.println("[Lugli/Opt] loaded, v" + VERSION
                + "  windgate=" + WindGate.MODE);
    }
}
