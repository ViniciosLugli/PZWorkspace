package lugli.fastloading;

import java.io.File;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;
import zombie.core.Core;
import zombie.debug.DebugLog;
import zombie.gameStates.ChooseGameInfo;

/**
 * Builds every installed mod folder's ChooseGameInfo.Mod on a pool instead of one at a time.
 * -Dfastloading.modinfo=off.
 *
 * The first mod id lookup at boot (ChooseGameInfo.getModDetails) reads every installed mod folder
 * in turn, Workshop items first, and each Mod constructor resolves ten canonical paths: about
 * 2.4 ms a folder, so ~0.95 s for 402 folders, on the main thread with nothing painting. That
 * constructor reads only the file system and immutable statics, so the same objects are built in
 * parallel and put into the engine's own cache (ZomboidFileSystem.modDirToMod), which
 * getModInfoForDir consults first. mod.info is still parsed by the engine, in the engine's order.
 */
public final class ModInfoPrefetch {

    public static final String TAG = "[FastLoading/modinfo]";
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.modinfo"));

    private static boolean ran;
    private static String result = Main.NEEDS_PRELOAD;

    private ModInfoPrefetch() {}

    /** For the menu handover line, so a part that did nothing says why. */
    public static String status() {
        return ON ? result : "off";
    }

    private static void report(String line) {
        result = line;
        DebugLog.log(TAG + " " + line);
    }

    public static void run() {
        if (ran) return;
        ran = true;
        if (!ON) {
            report("off");
            return;
        }
        try {
            if (!Core.optionModsEnabled) {
                report("idle: mods are disabled in the options");
                return;
            }
            List<String> dirs = new ArrayList<>();
            ZomboidFileSystem.instance.getAllModFolders(dirs);
            Map<String, ChooseGameInfo.Mod> cache = engineCache();
            List<String> todo = new ArrayList<>();
            for (String d : dirs) {
                if (!cache.containsKey(d)) todo.add(d);
            }
            if (todo.size() < 2) {
                report("idle: " + todo.size() + " mod folder(s) to read");
                return;
            }

            long t0 = System.nanoTime();
            int threads = PrefetchPool.threads();
            ExecutorService pool = PrefetchPool.create("FastLoading-modinfo", threads);
            List<Future<ChooseGameInfo.Mod>> pending = new ArrayList<>(todo.size());
            for (String d : todo) pending.add(pool.submit(() -> new ChooseGameInfo.Mod(d)));
            pool.shutdown();
            ChooseGameInfo.Mod[] built = new ChooseGameInfo.Mod[todo.size()];
            for (int i = 0; i < built.length; i++) built[i] = pending.get(i).get();
            long ms = (System.nanoTime() - t0) / 1_000_000L;

            String why = differs(built[0], new ChooseGameInfo.Mod(todo.get(0)));
            if (why != null) {
                report("DEFECT: a pooled build differs from the engine's (" + why
                        + "), every folder left to the engine");
                return;
            }
            for (int i = 0; i < built.length; i++) cache.putIfAbsent(todo.get(i), built[i]);
            report(built.length + " mod folders resolved on " + threads
                    + " threads in " + ms + " ms.");
        } catch (Throwable t) {
            report("DEFECT: " + t + ", every folder left to the engine");
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, ChooseGameInfo.Mod> engineCache() throws ReflectiveOperationException {
        Field f = ZomboidFileSystem.class.getDeclaredField("modDirToMod");
        f.setAccessible(true);
        return (Map<String, ChooseGameInfo.Mod>) f.get(ZomboidFileSystem.instance);
    }

    /**
     * null when the two builds agree on every field the constructor sets; otherwise the first
     * difference.
     *
     * One folder is enough because the constructor is a pure function of its dir and the file
     * system: it touches no shared mutable state (getModVersionDirName reads only immutable
     * version statics, PZFolder.set only the JDK's thread-safe canonicalisation). What a pooled
     * build can get wrong is therefore the same for every folder, an environment difference such
     * as an unset static, and the first folder exposes it. A folder changing on disk mid-boot
     * would mislead the engine's own serial build identically.
     */
    private static String differs(ChooseGameInfo.Mod a, ChooseGameInfo.Mod b) {
        if (!Objects.equals(a.dir, b.dir)) return "dir";
        if (!Objects.equals(a.getSource(), b.getSource())) return "source";
        if (!Objects.equals(a.commonDir, b.commonDir)) return "commonDir";
        if (!Objects.equals(a.versionDir, b.versionDir)) return "versionDir";
        if (!Objects.equals(a.getWorkshopID(), b.getWorkshopID())) return "workshopId";
        ZomboidFileSystem.PZModFolder[] fa = {a.baseFile, a.mediaFile, a.actionGroupsFile, a.animSetsFile, a.animsXFile};
        ZomboidFileSystem.PZModFolder[] fb = {b.baseFile, b.mediaFile, b.actionGroupsFile, b.animSetsFile, b.animsXFile};
        for (int i = 0; i < fa.length; i++) {
            if (!same(fa[i].common, fb[i].common) || !same(fa[i].version, fb[i].version)) return "folder " + i;
        }
        return null;
    }

    private static boolean same(ZomboidFileSystem.PZFolder a, ZomboidFileSystem.PZFolder b) {
        File ca = a.canonicalFile, cb = b.canonicalFile;
        return Objects.equals(ca, cb) && Objects.equals(a.lowercaseUri, b.lowercaseUri);
    }

    /**
     * GameWindow.init calls this immediately before loadMods("default"), once per boot. It is the
     * seam because loadMods itself is overloaded (String and List), and ZombieBuddy has woven the
     * wrong overload of an overloaded target before.
     */
    @Patch(className = "zombie.ZomboidFileSystem", methodName = "resetDefaultModsForNewRelease")
    public static class Boot {
        @Patch.OnExit
        public static void exit() {
            ModInfoPrefetch.run();
        }
    }
}
