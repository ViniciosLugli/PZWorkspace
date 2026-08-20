package lugli.fastloading;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.util.Locale;

import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.debug.DebugLog;

/**
 * Hoists a redundant syscall out of the Lua directory walk.
 *
 * LuaManager.searchFolders calls fo.getCanonicalFile() INSIDE its child loop, so a
 * directory with N entries pays N identical path-resolution syscalls. Across 337 mods,
 * three subdirectories each, and every intermediate folder, that is tens of thousands of
 * redundant Windows syscalls. It is why LoadDirBase costs 6.4 s while only 1.1 s of that
 * is Lua compilation and 0.8 s execution.
 *
 * This is a behaviour-identical transform: the canonical path is computed once per
 * directory instead of once per child. The child File is still built from the parent's
 * canonical path, exactly as the original does, so the resulting list is the same.
 * ScriptManager.searchFolders does not have this bug; it uses getAbsolutePath.
 *
 * Invariant to check after any change here: the Lua file set must be unchanged, which
 * shows up as an identical LuaCompiler.loadis call count.
 */
@me.zed_0xff.zombie_buddy.Patch(className = "zombie.Lua.LuaManager", methodName = "searchFolders")
public final class LuaScan {

    public static final String TAG = "[FastLoading/luascan]";
    public static boolean announced;
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.luascan"));
    public static boolean broken;
    public static int files;

    private LuaScan() {}

    /** true tells the inlined advice to skip the original walk. */
    @me.zed_0xff.zombie_buddy.Patch.OnEnter(skipOn = true)
    public static boolean enter(@me.zed_0xff.zombie_buddy.Patch.Argument(0) URI base,
                                @me.zed_0xff.zombie_buddy.Patch.Argument(1) File fo) {
        return scan(base, fo);
    }

    public static boolean scan(URI base, File fo) {
        if (!ON || broken) return false;
        try {
            walk(base, fo);
            if (!announced) {
                announced = true;
                DebugLog.log(TAG + " lua directory walk: one path resolution per directory");
            }
            return true;
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, falling back to the original (" + t + ")");
            return false;
        }
    }

    private static void walk(URI base, File fo) throws IOException {
        if (fo.isDirectory()) {
            String[] names = fo.list();
            if (names == null) return;
            String canon = fo.getCanonicalFile().getAbsolutePath();
            for (String name : names) {
                walk(base, new File(canon + File.separator + name));
            }
        } else if (fo.getAbsolutePath().toLowerCase().endsWith(".lua")) {
            String rel = ZomboidFileSystem.instance.getRelativeFile(base, fo.getAbsolutePath());
            LuaManager.loadList.add(rel.toLowerCase(Locale.ENGLISH));
            files++;
        }
    }
}
