package lugli.fastloading;

import java.util.concurrent.ConcurrentHashMap;

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

    // public: both advice bodies are inlined into engine classes, which then access
    // these from their own class. Anything private throws IllegalAccessError.
    public static final ConcurrentHashMap<String, Shader> CACHE = new ConcurrentHashMap<>();

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
            if (cached == null) return false;
            model.effect = cached;
            return true;
        }
    }
}
