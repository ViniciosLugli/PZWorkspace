package lugli.fastloading;

import java.util.List;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.function.UnaryOperator;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;
import zombie.debug.DebugLog;

/**
 * Gives LuaManager.loaded a hash index. -Dfastloading.luaindex=off.
 *
 * loaded is a public static List<String> and RunLuaInternal opens with
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

    /** For the menu handover line, so a part that did nothing says so. */
    public static String status() {
        if (!ON) return "off";
        return installed ? "ok, " + rebuilds + " index rebuild(s)" : "idle: LuaManager.init never reached it";
    }

    /**
     * An ArrayList that answers contains() from a hash index. Semantics are otherwise identical.
     *
     * The index is a multiset (count per entry), not a set: loaded can hold the same file twice,
     * and a set would then be smaller than the list forever, so the size check below would rebuild
     * on every later lookup and cost more than the scan it replaces.
     */
    public static final class Indexed extends ArrayList<String> {
        private final HashMap<String, Integer> counts = new HashMap<>();
        private int indexed;

        private void inc(String s) {
            counts.merge(s, 1, Integer::sum);
            indexed++;
        }

        private void dec(Object o) {
            Integer n = counts.get(o);
            if (n == null) return;
            if (n == 1) counts.remove(o); else counts.put((String) o, n - 1);
            indexed--;
        }

        private void rebuild() {
            counts.clear();
            indexed = 0;
            for (String s : this) inc(s);
            rebuilds++;
        }

        @Override
        public boolean contains(Object o) {
            if (indexed != size()) {
                rebuild();          // something mutated us through a path we do not override
            }
            return counts.containsKey(o);
        }

        @Override
        public boolean add(String s) {
            inc(s);
            return super.add(s);
        }

        @Override
        public void add(int i, String s) {
            super.add(i, s);
            inc(s);
        }

        @Override
        public boolean addAll(Collection<? extends String> c) {
            for (String s : c) inc(s);
            return super.addAll(c);
        }

        @Override
        public boolean addAll(int i, Collection<? extends String> c) {
            for (String s : c) inc(s);
            return super.addAll(i, c);
        }

        @Override
        public boolean remove(Object o) {
            boolean r = super.remove(o);
            if (r) dec(o);
            return r;
        }

        @Override
        public String remove(int i) {
            String r = super.remove(i);
            dec(r);
            return r;
        }

        @Override
        public String set(int i, String s) {
            String r = super.set(i, s);
            dec(r);
            inc(s);
            return r;
        }

        @Override
        public void replaceAll(UnaryOperator<String> op) {
            super.replaceAll(op);
            rebuild();
        }

        @Override
        public void clear() {
            super.clear();
            counts.clear();
            indexed = 0;
        }
    }

    /** public: the advice body is inlined into zombie.Lua.LuaManager and calls this from there. */
    public static void install() {
        if (!ON) {
            return;
        }
        try {
            List<String> cur = LuaManager.loaded;
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

    /** init() assigns a fresh ArrayList at :1113, so replace it after that has happened. */
    @Patch(className = "zombie.Lua.LuaManager", methodName = "init")
    public static class Install {
        @Patch.OnExit
        public static void out() {
            LuaLoadedIndex.install();
        }
    }
}
