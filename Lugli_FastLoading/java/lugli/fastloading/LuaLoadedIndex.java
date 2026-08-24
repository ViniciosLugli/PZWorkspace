package lugli.fastloading;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;
import zombie.debug.DebugLog;

/**
 * Gives `LuaManager.loaded` a hash index. -Dfastloading.luaindex=off
 *
 * `LuaManager.loaded` is a `public static ArrayList<String>` (`LuaManager.java:1044`) and
 * `RunLuaInternal` opens with `if (loaded.contains(filename))` (`:1345`) -- a LINEAR SCAN of a
 * list that grows to one entry per Lua file. Boot on this list runs 13,444 `RunLua` calls over
 * 6,358 distinct files, so the misses each pay a full scan and the `require()` re-entries pay
 * half of one. It also runs during play: every `require()` goes through the same check.
 *
 * The field is public and its type is `ArrayList<String>`, so it can simply be replaced with an
 * `ArrayList` SUBCLASS that keeps a parallel `HashSet` and answers `contains` from it. No engine
 * member is added or changed, which matters because retransformation cannot add fields.
 *
 * WHY A SUBCLASS AND NOT A DIFFERENT COLLECTION
 *   Every consumer uses the `List` contract, including two that are exposed to Lua:
 *   `:1079` clear, `:1345` contains, `:1393` add, `:3701` and `:3710` remove,
 *   `:3933` size and `:3938` get(n). A subclass keeps indexing, iteration order and
 *   duplicates-by-position exactly as they were.
 *
 * WHY REMOVE AND CLEAR REBUILD RATHER THAN UPDATE
 *   The list can hold the same string twice: the guard at `:1345` tests the SEPARATOR-NORMALISED
 *   `filename`, while `:1393` stores the ORIGINAL `orig`. When those differ the same file can be
 *   appended twice, and a plain `HashSet.remove` would then drop an entry the list still holds,
 *   making `contains` answer false for something present -- which would silently re-run a Lua
 *   file. Removals happen only on reload, so rebuilding there is cheap and exact.
 *
 * SELF-HEALING
 *   Anything that mutates the list through a path not overridden here (an iterator, a subList)
 *   would desynchronise the set. `contains` therefore compares sizes first and rebuilds on any
 *   disagreement, so the answer is always the list's answer.
 *
 * WHY IT IS INSTALLED AT init() EXIT
 *   `LuaManager.init` assigns `loaded = new ArrayList<>()` at `:1110`, which would discard an
 *   earlier replacement.
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
