package lugli.fastloading;

import java.util.concurrent.ConcurrentHashMap;

import zombie.debug.DebugLog;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.shader.Shader;

/**
 * Caches compiled model shaders. -Dfastloading.shadercache=off.
 *
 * Model.CreateShader hops to the render thread and blocks for about a frame even when the shader
 * is already compiled, and animal definitions alone do that hundreds of times. A cache hit needs
 * no GL context, so it can answer on the calling thread.
 */
public class ShaderCache {

    public static final String TAG = "[FastLoading/shadercache]";

    // public: both advice bodies are inlined into engine classes, which then access
    // these from their own class. Anything private throws IllegalAccessError.
    public static final ConcurrentHashMap<String, Shader> CACHE = new ConcurrentHashMap<>();

    /**
     * Plain longs, incremented from an inlined advice on whatever thread compiles a model, so
     * they undercount slightly under contention. They exist to answer "did this part run at
     * all", which they do exactly, not to be a profiler.
     */
    public static long hits;
    public static long misses;

    /** public: read by the advice body, which runs as zombie.core.skinnedmodel.model.Model. */
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.shadercache", "on"));

    public static String key(String name, boolean isStatic, boolean instanced) {
        return name + (isStatic ? "|s" : "|d") + (instanced ? "|i" : "|n");
    }

    /** The cache warms itself from whatever the engine hands out. */
    @Patch(className = "zombie.core.skinnedmodel.shader.ShaderManager", methodName = "getOrCreateShader")
    public static class Record {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String name,
                                @Patch.Argument(1) boolean isStatic,
                                @Patch.Argument(2) boolean instanced,
                                @Patch.Return Shader shader) {
            if (name != null && shader != null) {
                CACHE.put(key(name, isStatic, instanced), shader);
            }
        }
    }

    /** A miss returns false and lets the original run, which then records the result. */
    @Patch(className = "zombie.core.skinnedmodel.model.Model", methodName = "CreateShader")
    public static class FastPath {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This Model model, @Patch.Argument(0) String name) {
            if (!ON || name == null) return false;
            Shader cached = CACHE.get(key(name, model.isStatic, false));
            if (cached == null) {
                misses++;
                report();
                return false;
            }
            hits++;
            report();
            model.effect = cached;
            return true;
        }
    }

    /**
     * The menu line below reports the BOOT state only, and the phase this cache exists for --
     * loadAnimalDefinitions -- runs during world load, after it. So the counters also report
     * every 32nd operation, which is the only way a run can show whether the cache is still
     * serving once the world starts loading.
     *
     * public: called from an advice body inlined into zombie.core.skinnedmodel.model.Model.
     */
    public static void report() {
        long n = hits + misses;
        if ((n & 31L) == 0L) {
            DebugLog.log(TAG + " " + status());
        }
    }

    /**
     * Reported at the menu handover because an ON-by-default part that logs nothing cannot be
     * asserted from any run, and this project has already shipped one that was dead for a whole
     * release while looking healthy. A zero-hit line is a defect report, not noise.
     */
    public static String status() {
        if (!ON) {
            return "off";
        }
        return hits + " hit(s), " + misses + " miss(es), " + CACHE.size() + " shader(s) cached";
    }
}
