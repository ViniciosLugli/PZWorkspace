package lugli.fastloading;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;
import zombie.debug.DebugLog;

/**
 * Gives LuaManager.loaded a hash index. -Dfastloading.luaindex=off.
 *
 * loaded is a public static ArrayList<String> and RunLuaInternal opens with
 * loaded.contains(filename), a linear scan that grows with every file already loaded.
 * The index mirrors the list; if the two ever disagree the patch falls back to the scan.
 */
public final class LuaLoadedIndex {

    public static final String TAG = "[FastLoading/luaindex]";
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.luaindex", "on"));

    public static boolean installed;
    public static long rebuilds;

    private LuaLoadedIndex() {}

    /** An ArrayList that answers contains() from a hash set. Semantics are otherwise identical. */
    public static final class Indexed extends ArrayList<String> {
        private final HashSet<String> index = new HashSet<>();

        private void rebuild() {
            index.clear();
            index.addAll(this);
            rebuilds++;
        }

        @Override
        public boolean contains(Object o) {
            if (index.size() != size()) {
                rebuild();          // something mutated us through a path we do not override
            }
            return index.contains(o);
        }

        @Override
        public boolean add(String s) {
            index.add(s);
            return super.add(s);
        }

        @Override
        public void add(int i, String s) {
            index.add(s);
            super.add(i, s);
        }

        @Override
        public boolean addAll(Collection<? extends String> c) {
            index.addAll(c);
            return super.addAll(c);
        }

        @Override
        public boolean addAll(int i, Collection<? extends String> c) {
            index.addAll(c);
            return super.addAll(i, c);
        }

        @Override
        public boolean remove(Object o) {
            boolean r = super.remove(o);
            rebuild();              // duplicates are possible; see the class doc
            return r;
        }

        @Override
        public String remove(int i) {
            String r = super.remove(i);
            rebuild();
            return r;
        }

        @Override
        public String set(int i, String s) {
            String r = super.set(i, s);
            rebuild();
            return r;
        }

        @Override
        public void clear() {
            super.clear();
            index.clear();
        }
    }

    /** public: the advice body is inlined into zombie.Lua.LuaManager and calls this from there. */
    public static void install() {
        if (!ON) {
            return;
        }
        try {
            ArrayList<String> cur = LuaManager.loaded;
            if (cur instanceof Indexed) {
                return;
            }
            Indexed idx = new Indexed();
            if (cur != null) {
                idx.addAll(cur);
            }
            LuaManager.loaded = idx;
            if (!installed) {
                installed = true;
                DebugLog.log(TAG + " LuaManager.loaded is now hash-indexed");
            }
        } catch (Throwable t) {
            // Never fatal: the engine's own ArrayList stays in place and behaviour is unchanged.
            DebugLog.log(TAG + " skipped (" + t + ")");
        }
    }

    /** init() assigns a fresh ArrayList at :1110, so replace it after that has happened. */
    @Patch(className = "zombie.Lua.LuaManager", methodName = "init")
    public static class Install {
        @Patch.OnExit
        public static void out() {
            LuaLoadedIndex.install();
        }
    }
}
