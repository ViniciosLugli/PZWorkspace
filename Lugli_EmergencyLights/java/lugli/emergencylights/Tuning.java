package lugli.emergencylights;

/** Pure logic, deliberately free of any `zombie.*` import so the build can unit-test it without the game on
 * the classpath. */
public final class Tuning {

    private Tuning() {}

    /** Is a float safe to hand to a native function? */
    public static boolean isFinite(double v) {
        return !Double.isNaN(v) && !Double.isInfinite(v);
    }

    /** Clamp a colour channel into the range a torch may take, which is 0..1 RAW. */
    public static double clampChannel(double v) {
        if (Double.isNaN(v) || v < 0.0) {
            return 0.0;
        }
        return v > 1.0 ? 1.0 : v;
    }

    /** THE OTHER ID NAMESPACE, and it is not the torch one. */
    public static final int ROOM_LIGHT_BASE = 100000;
    public static final int WORLD_BASE = 1000000;
    public static final int WORLD_SLOTS = 256;

    /** Map a caller's handle onto a real world-light id, or -1 when the handle is out of range. */
    public static int worldLightId(int handle, int base, int slots) {
        if (handle < 0 || handle >= slots) {
            return -1;
        }
        return base + handle;
    }

    /** Have the engine's own light allocators climbed far enough to reach our range? */
    public static boolean engineLightIdsReach(int nextLamppostId, int nextRoomLightId, int base) {
        return nextLamppostId >= base || ROOM_LIGHT_BASE + nextRoomLightId >= base;
    }

    /** A radius the native light layer can carry: whole tiles, at least one. */
    public static int clampRadius(double v) {
        if (Double.isNaN(v) || v < 1.0) {
            return 1;
        }
        if (v > 64.0) {
            return 64;
        }
        return (int) Math.floor(v + 0.5);
    }

    /** A world coordinate the native light layer can carry: a whole tile, floored, never absurd. */
    public static int clampCoord(double v) {
        if (Double.isNaN(v)) {
            return 0;
        }
        if (v < -1.0e7) {
            return -10000000;
        }
        if (v > 1.0e7) {
            return 10000000;
        }
        return (int) Math.floor(v);
    }
}
