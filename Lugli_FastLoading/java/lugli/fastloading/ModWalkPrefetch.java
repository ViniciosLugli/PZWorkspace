package lugli.fastloading;

import java.io.File;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;
import zombie.debug.DebugLog;
import zombie.gameStates.ChooseGameInfo;

/**
 * Walks every mod's file tree in parallel instead of one at a time. -Dfastloading.modwalk=off.
 *
 * loadMod runs once per installed mod and walks its trees serially, which is tens of thousands of
 * directory reads on a large list. Only the WALK is parallel: results are published to the engine
 * in the original order, so mod override precedence is unchanged.
 */
public final class ModWalkPrefetch {

    public static final String TAG = "[FastLoading/modwalk]";
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.modwalk"));

    // public: these bodies are inlined into zombie.* classes and read from there.
    public static final ConcurrentHashMap<String, Future<List<String>>> PENDING = new ConcurrentHashMap<>();
    public static volatile boolean started;
    public static volatile boolean broken;
    public static volatile boolean verified;
    public static volatile boolean bootDone;
    public static volatile int served;
    /** The loadMods pass the walks were computed for, and how far through it the engine is. */
    public static volatile List<String> bootMods;
    public static volatile int bootCalls;
    public static Field F_LOADLIST;

    /** A self-test on a handful of files is not evidence; hold out for a real tree. */
    public static final int MIN_VERIFY_ENTRIES = 200;

    private ModWalkPrefetch() {}

    /** For the menu handover line, so a part that did nothing says so. */
    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        if (!started) return "idle: no loadMod call reached it";
        return "ok, " + served + " mod tree(s) served from the pool"
             + (verified ? "" : ", never verified on a tree of " + MIN_VERIFY_ENTRIES + "+ entries");
    }

    /** Kicked off from the first loadMod call, which still runs normally. */
    public static void start() {
        if (!ON || started || broken || bootDone) return;
        started = true;
        try {
            List<String> modIDs = new ArrayList<>(ZomboidFileSystem.instance.getModIDs());
            bootMods = modIDs;
            int threads = PrefetchPool.threads();
            ExecutorService pool = PrefetchPool.create("FastLoading-modwalk", threads);

            int roots = 0;
            for (int i = 0; i < modIDs.size(); i++) {
                ChooseGameInfo.Mod mod = ChooseGameInfo.getAvailableModDetails(modIDs.get(i));
                if (mod == null) continue;
                roots += submit(pool, mod.getCommonDir());
                roots += submit(pool, mod.getVersionDir());
            }
            pool.shutdown();
            DebugLog.log(TAG + " walking " + roots + " mod trees on " + threads + " threads");
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " prefetch not started (" + t + ")");
        }
    }

    private static int submit(ExecutorService pool, String dir) {
        if (dir == null) return 0;
        final File root = new File(dir);
        String key = root.getAbsolutePath();
        if (PENDING.containsKey(key)) return 0;
        PENDING.put(key, pool.submit(() -> {
            List<String> out = new ArrayList<>();
            walk(root, out);
            return out;
        }));
        return 1;
    }

    /** Literal transcription of ZomboidFileSystem.searchFolders, minus the frame pumping. */
    public static void walk(File fo, List<String> out) {
        if (fo.isDirectory()) {
            String path = fo.getAbsolutePath().replace("\\", "/").replace("./", "");
            if (path.contains("media/maps/")) out.add(path);
            String[] names = fo.list();
            if (names == null) return;
            String base = fo.getAbsolutePath();
            for (String name : names) {
                walk(new File(base + File.separator + name), out);
            }
        } else {
            out.add(fo.getAbsolutePath().replace("\\", "/").replace("./", ""));
        }
    }

    /**
     * The walks are a snapshot of the loadMods pass that started them. Core.ResetLua (a server
     * join among them) and IngameState.exit run loadMods again, after mod files may have
     * changed, and a stale walk there changes the script file list the server checksums. So the
     * walks serve only that pass: each loadMod must be the next mod of bootMods, in order, and
     * the pass ends at the exit of its last loadMod, or at the first one that throws or deviates.
     */
    public static void enterMod(String modId) {
        start();
        if (bootDone || !started) return;
        List<String> boot = bootMods;
        int i = bootCalls;
        if (boot == null || i >= boot.size() || !boot.get(i).equals(modId)) {
            endBoot("loadMod(" + modId + ") is not call " + i + " of the boot pass");
            return;
        }
        bootCalls = i + 1;
    }

    public static void exitMod(Throwable thrown) {
        if (bootDone) return;
        if (thrown != null) {
            endBoot("loadMod threw " + thrown);
            return;
        }
        List<String> boot = bootMods;
        if (boot == null || bootCalls >= boot.size()) endBoot(null);
    }

    public static void endBoot(String why) {
        if (bootDone) return;
        bootDone = true;
        int left = PENDING.size();
        PENDING.clear();
        if (why != null || left > 0) {
            DebugLog.log(TAG + " boot walk disarmed after " + bootCalls + " loadMod call(s), "
                         + left + " unserved walk(s) discarded" + (why == null ? "" : " (" + why + ")"));
        }
    }

    /** true tells the advice to skip the engine's walk, because the pool already did it. */
    public static boolean serve(Object self, File fo) {
        if (!ON || broken || bootDone || PENDING.isEmpty()) return false;
        try {
            Future<List<String>> f = PENDING.remove(fo.getAbsolutePath());
            if (f == null) return false;

            List<String> result = f.get();

            // Verify EVERY root served until one is big enough to be real evidence. A
            // previous version stopped at the first root, which happened to hold 6 files
            // and proved nothing. Re-walking a small tree costs almost nothing, and this
            // decides mod override precedence, so it is worth being sure.
            if (!verified) {
                List<String> serial = new ArrayList<>();
                walk(fo, serial);
                if (!serial.equals(result)) {
                    broken = true;
                    DebugLog.log(TAG + " self-test FAILED (" + result.size() + " vs " + serial.size()
                                 + " entries), keeping the engine's walk");
                    return false;
                }
                if (serial.size() >= MIN_VERIFY_ENTRIES) {
                    verified = true;
                    DebugLog.log(TAG + " verified against the engine's walk on "
                                 + serial.size() + " entries");
                }
            }

            @SuppressWarnings("unchecked")
            List<String> loadList = (List<String>)list(self);
            loadList.addAll(result);
            served++;
            return true;
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, falling back to the engine's walk (" + t + ")");
            return false;
        }
    }

    private static Object list(Object self) throws Exception {
        if (F_LOADLIST == null) {
            F_LOADLIST = ZomboidFileSystem.class.getDeclaredField("loadList");
            F_LOADLIST.setAccessible(true);
        }
        return F_LOADLIST.get(self);
    }

    @Patch(className = "zombie.ZomboidFileSystem", methodName = "loadMod")
    public static class Kick {
        @Patch.OnEnter
        public static void in(@Patch.Argument(0) String modId) { ModWalkPrefetch.enterMod(modId); }

        @Patch.OnExit(onThrowable = Throwable.class)
        public static void out(@Patch.Thrown Throwable thrown) { ModWalkPrefetch.exitMod(thrown); }
    }

    @Patch(className = "zombie.ZomboidFileSystem", methodName = "searchFolders")
    public static class Serve {
        @Patch.OnEnter(skipOn = true)
        public static boolean in(@Patch.This Object self, @Patch.Argument(0) File fo) {
            return ModWalkPrefetch.serve(self, fo);
        }
    }
}
