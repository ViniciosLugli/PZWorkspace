package lugli.fastloading;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.stdlib.StringLib;
import zombie.debug.DebugLog;

/**
 * Lua pattern matching without pooled string pointers. -Dfastloading.luamatch=off.
 *
 * string.find, match, gmatch and gsub clone a StringPointer at nearly every pattern step. The
 * engine draws each clone from a synchronized pool, tracks it in a per-call list and hands the
 * whole list back when the call ends: two thirds of the main thread's string matching at boot
 * (JFR). Here a clone is a plain object the GC reclaims, so the list stays empty and the release
 * has nothing to return. Loading only: from StringLib.onLoadingFinished (the first IngameState)
 * on, the engine's own pool runs, so play is untouched.
 *
 * MUST match like the engine: a pooled pointer is reused only after the call that held it has
 * released it, so a fresh pointer is indistinguishable to the matcher, and nothing outside the
 * call keeps one.
 */
public final class LuaMatch {

    public static final String TAG = "[FastLoading/luamatch]";

    /** public: read from a body inlined into se.krka.kahlua.stdlib.StringLib$Allocations. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.luamatch", "on"));

    public static volatile boolean broken;
    private static volatile boolean inPlay;
    /** Racy on purpose: a status figure, not a gate. */
    private static long unpooled;

    private static final VarHandle OWNER = ownerHandle();

    private LuaMatch() {}

    private static VarHandle ownerHandle() {
        try {
            return MethodHandles.privateLookupIn(StringLib.StringPointer.class, MethodHandles.lookup())
                    .findVarHandle(StringLib.StringPointer.class, "allocations",
                                   Class.forName("se.krka.kahlua.stdlib.StringLib$Allocations"));
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, engine path resumes: StringPointer.allocations unreadable: " + t);
            return null;
        }
    }

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return (unpooled == 0 ? "ok, no pattern match yet" : "ok, " + unpooled + " pointer(s) left to the GC")
               + (inPlay ? ", engine pool in play" : "");
    }

    /** True = the engine's pooled allocation is skipped and exit() supplies the pointer. */
    public static boolean skip() {
        return ON && !broken && !inPlay;
    }

    public static void loadingFinished() {
        inPlay = true;
    }

    /** Owner set as the engine sets it: getClone() allocates through it. */
    public static StringLib.StringPointer fresh(Object allocations) {
        StringLib.StringPointer pointer = new StringLib.StringPointer();
        OWNER.set(pointer, allocations);
        unpooled++;
        return pointer;
    }

    /** A skipped body returns null; the engine's own allocation never does. */
    @Patch(className = "se.krka.kahlua.stdlib.StringLib$Allocations", methodName = "allocStringPointer")
    public static final class Hook {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter() {
            return LuaMatch.skip();
        }

        @Patch.OnExit
        public static void exit(@Patch.This Object allocations,
                                @Patch.Return(readOnly = false) StringLib.StringPointer pointer) {
            if (pointer == null) pointer = LuaMatch.fresh(allocations);
        }
    }

    @Patch(className = "se.krka.kahlua.stdlib.StringLib", methodName = "onLoadingFinished")
    public static final class InPlay {
        @Patch.OnExit
        public static void exit() {
            LuaMatch.loadingFinished();
        }
    }
}
