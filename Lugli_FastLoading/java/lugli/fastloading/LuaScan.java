package lugli.fastloading;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.util.Locale;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.debug.DebugLog;

/**
 * Hoists a redundant syscall out of the Lua directory walk. -Dfastloading.luascan=off.
 *
 * LuaManager.searchFolders calls getCanonicalFile() inside its child loop, so a directory with N
 * entries pays N identical path resolutions. Resolving the parent once gives the same result.
 */
@Patch(className = "zombie.Lua.LuaManager", methodName = "searchFolders")
public final class LuaScan {

    public static final String TAG = "[FastLoading/luascan]";
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.luascan"));
    public static boolean announced;
    public static boolean broken;
    public static int files;

    private LuaScan() {}

    /** For the menu handover line, so a part that did nothing says so. */
    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return files == 0 ? "idle: no Lua directory walk reached it" : "ok, " + files + " Lua file(s) listed";
    }

    /** true tells the inlined advice to skip the original walk. */
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.Argument(0) URI base, @Patch.Argument(1) File fo) {
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
