package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;
import zombie.scripting.ScriptBucketCollection;
import zombie.scripting.ScriptManager;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ScriptModule;

/**
 * ScriptManager.FindItem without its dead fallback loop. -Dfastloading.finditem=off.
 *
 * On a miss the engine walks every script module but re-queries the ORIGINAL module each time
 * (`module.getItem`, not `m.getItem`), so it repeats one failed, pure lookup once per module and
 * returns null. With ~500 modules on a heavy list that is most of the loot distribution parse,
 * which runs on the world-load thread. Removing the loop returns the same item in every case;
 * "fixing" it to `m` would not, because items would start resolving across modules.
 *
 * MUST return exactly what the engine returns: the first VALIDATE calls run the engine and compare
 * its result with this one by identity; one difference turns the part off.
 */
public final class ItemLookup {

    public static final String TAG = "[FastLoading/finditem]";

    /** public: these are read from a body inlined into zombie.scripting.ScriptManager. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.finditem", "on"));

    public static volatile boolean broken;

    private static final int VALIDATE = 256;
    public static final AtomicInteger VALIDATED = new AtomicInteger();
    public static final AtomicLong FAST = new AtomicLong();
    public static final AtomicLong MISSES = new AtomicLong();

    /** This lookup's answer during a validated call, for the exit advice to compare. */
    public static final ThreadLocal<Object[]> PENDING = new ThreadLocal<>();

    public static ScriptManager owner;
    public static ScriptBucketCollection<?> items;

    private ItemLookup() {}

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return "ok, " + FAST.get() + " lookup(s) without the dead loop (" + MISSES.get() + " miss(es)), "
                + VALIDATED.get() + " checked against the engine";
    }

    /** True = `found[0]` is the answer and the engine body is skipped. */
    public static boolean enter(ScriptManager manager, String name, boolean moduleDefaultsToBase) {
        PENDING.set(null);
        RESULT.set(null);
        if (broken || name == null) return false;
        try {
            Item found = find(manager, name, moduleDefaultsToBase);
            if (VALIDATED.get() < VALIDATE) {
                PENDING.set(new Object[] {found});
                return false;
            }
            FAST.incrementAndGet();
            if (found == null) MISSES.incrementAndGet();
            RESULT.set(new Object[] {found});
            return true;
        } catch (Throwable t) {
            disable("lookup failed", t);
            return false;
        }
    }

    /** The answer a skipped call returns, boxed so that a null answer still marks the skip. */
    public static final ThreadLocal<Object[]> RESULT = new ThreadLocal<>();

    /** Exit advice: the skipped call's answer, else the engine's own after validating it. */
    public static Item exit(String name, Item engine) {
        Object[] skipped = RESULT.get();
        if (skipped != null) {
            RESULT.set(null);
            return (Item) skipped[0];
        }
        validate(name, engine);
        return engine;
    }

    private static void validate(String name, Item engine) {
        Object[] ours = PENDING.get();
        if (ours == null) return;
        PENDING.set(null);
        if (ours[0] != engine) {
            disable("differs from the engine for \"" + name + "\": engine " + engine + ", ours " + ours[0], null);
            return;
        }
        if (VALIDATED.incrementAndGet() == VALIDATE) {
            DebugLog.log(TAG + " " + VALIDATE + " lookups identical to the engine, fast path on");
        }
    }

    /** The engine's FindItem(String, boolean) minus the fallback loop. */
    static Item find(ScriptManager manager, String name, boolean moduleDefaultsToBase) throws ReflectiveOperationException {
        if (name.contains(".")) {
            ScriptBucketCollection<?> bucket = bucket(manager);
            if (bucket.hasFullType(name)) {
                return (Item) bucket.getFullType(name);
            }
        }
        ScriptModule module = manager.getModule(name, moduleDefaultsToBase);
        if (module == null) return null;
        return module.getItem(ScriptManager.getItemName(name));
    }

    private static ScriptBucketCollection<?> bucket(ScriptManager manager) throws ReflectiveOperationException {
        if (owner != manager) {
            Field f = ScriptManager.class.getDeclaredField("items");
            f.setAccessible(true);
            items = (ScriptBucketCollection<?>) f.get(manager);
            owner = manager;
        }
        return items;
    }

    public static void disable(String why, Throwable t) {
        if (broken) return;
        broken = true;
        DebugLog.log(TAG + " disabled, engine path resumes: " + why + (t == null ? "" : ": " + t));
    }

    @Patch(className = "zombie.scripting.ScriptManager", methodName = "FindItem")
    public static final class Hook {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This ScriptManager manager, @Patch.Argument(0) String name,
                                    @Patch.Argument(1) boolean moduleDefaultsToBase) {
            return ItemLookup.ON && ItemLookup.enter(manager, name, moduleDefaultsToBase);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String name, @Patch.Return(readOnly = false) Item item) {
            if (ItemLookup.ON) item = ItemLookup.exit(name, item);
        }
    }
}
