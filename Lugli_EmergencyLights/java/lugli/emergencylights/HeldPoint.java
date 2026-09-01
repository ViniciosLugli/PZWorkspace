package lugli.emergencylights;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoGameCharacter;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.iso.Vector3;

/** WHERE A CHARACTER'S HAND ACTUALLY IS, handed to Lua. */
public final class HeldPoint {

    /** -Dlugli.emergencylights.heldpoint=off disables the bridge; Lua sees the globals absent and adapts. */
    public static final boolean ENABLED =
        !"off".equals(System.getProperty("lugli.emergencylights.heldpoint"));

    private static final String TAG = "[EmergencyLights/heldpoint] ";

    /** The bone every primary-hand item hangs from. */
    private static final String PRIMARY_HAND_BONE = "Bip01_Prop1";

    /** How long the flare's mesh is along its own axis, in model units. */
    private static final float FLARE_TIP = 0.19F;

    /** Reused across calls. Single-threaded by contract -- see the thread note on point(). */
    private static final Vector3 SCRATCH = new Vector3();

    private static float lastX, lastY, lastZ;
    private static float baseX, baseY, baseZ;
    private static boolean lastOk;
    private static boolean warned;

    /** MUST STAY NO-ARG and concrete, or the globals vanish. See Light's constructor note. */
    private HeldPoint() {}

    static void announce() {
        System.out.println(TAG + (ENABLED
            ? "ready, primary hand bone " + PRIMARY_HAND_BONE
            : "disabled by -Dlugli.emergencylights.heldpoint=off"));
    }

    /** Resolve the tip of the item in this character's primary hand, into SCRATCH. */
    private static boolean point(IsoGameCharacter chr) {
        if (!ENABLED || chr == null) return false;

        try {
            if (chr.isSeatedInVehicle()) return false;
            if (!chr.hasActiveModel()) return false;
            if (!chr.hasAnimationPlayer()) return false;

            AnimationPlayer ap = chr.getAnimationPlayer();
            if (ap == null || !ap.hasSkinningData()) return false;
            if (ap.isBoneTransformsNeedFirstFrame()) return false;

            int bone = ap.getSkinningBoneIndex(PRIMARY_HAND_BONE, -1);
            if (bone < 0 || bone >= ap.getModelTransformsCount()) return false;

            // THE TIP: bonePos + boneLocalYAxis * length, then into iso world coordinates.
            Model.boneYDirectionToWorldCoords(chr, bone, SCRATCH, FLARE_TIP);
            lastX = SCRATCH.x;
            lastY = SCRATCH.y;
            lastZ = SCRATCH.z;

            // AND THE BASE, at zero length along the same axis.
            Model.boneYDirectionToWorldCoords(chr, bone, SCRATCH, 0.0F);
            baseX = SCRATCH.x;
            baseY = SCRATCH.y;
            baseZ = SCRATCH.z;
            return true;
        } catch (Throwable t) {
            // NEVER THROW INTO LUA. A dead bridge must dim the mod that uses it, not break it --
            // and once only, because this is called from a per-frame draw.
            if (!warned) {
                warned = true;
                System.out.println(TAG + "failed, falling back to the caller's own offset: " + t);
            }
            return false;
        }
    }

    /** Resolve the point and report whether there is an answer. */
    @LuaMethod(name = "LugliELHeldPointResolve", global = true)
    public static boolean resolve(IsoGameCharacter chr) {
        lastOk = point(chr);
        return lastOk;
    }

    @LuaMethod(name = "LugliELHeldPointX", global = true)
    public static float x() { return lastX; }

    @LuaMethod(name = "LugliELHeldPointY", global = true)
    public static float y() { return lastY; }

    @LuaMethod(name = "LugliELHeldPointZ", global = true)
    public static float z() { return lastZ; }

    // The BASE of the item, on the same bone axis. Subtract these from the tip for its direction.
    @LuaMethod(name = "LugliELHeldPointBaseX", global = true)
    public static float baseX() { return baseX; }

    @LuaMethod(name = "LugliELHeldPointBaseY", global = true)
    public static float baseY() { return baseY; }

    @LuaMethod(name = "LugliELHeldPointBaseZ", global = true)
    public static float baseZ() { return baseZ; }
}
