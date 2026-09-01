package lugli.emergencylights;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.iso.IsoLightSource;
import zombie.iso.IsoRoomLight;
import zombie.GameTime;
import zombie.iso.IsoWorld;
import zombie.iso.LightingJNI;

/** The engine's WORLD light, handed to Lua. */
public final class WorldLight {

    /** -Dlugli.emergencylights.worldlight=off disables the bridge; Lua sees the globals absent and adapts. */
    public static final boolean ENABLED =
        !"off".equals(System.getProperty("lugli.emergencylights.worldlight"));

    private static final String TAG = "[EmergencyLights/worldlight] ";

    /** The engine biases every light's z by +32 on the way to native. */
    private static final int Z_BIAS = 32;

    /** `localToBuilding` -- the id of the building a light is confined to, or -1 for none. */
    private static final int NO_BUILDING = -1;

    /** WHAT EACH LIVE LIGHT IS, so this library can put it back. */
    private static final double[][] live = new double[Tuning.WORLD_SLOTS][];

    /** WHO OWNS EACH SLOT. null means free. See Light.owners -- the reasoning is identical. */
    private static final String[] owners = new String[Tuning.WORLD_SLOTS];

    private static boolean worldWasUp;
    private static boolean warned;
    private static boolean idsExhausted;

    /** MUST STAY NO-ARG and concrete, or all seven globals vanish. See Light's constructor note. */
    private WorldLight() {}

    static void announce() {
        System.out.println(TAG + (ENABLED
            ? "ready, " + Tuning.WORLD_SLOTS + " slot(s) from id " + Tuning.WORLD_BASE
            : "disabled by -Dlugli.emergencylights.worldlight=off"));
    }

    /** Is it safe to call into the native lighting layer right now? */
    private static boolean ready() {
        if (!ENABLED) {
            return false;
        }
        if (!LightingJNI.init) {
            if (!warned) {
                warned = true;
                System.out.println(TAG + "lighting not initialised (server, or not started yet)");
            }
            return false;
        }

        boolean up;
        try {
            up = IsoWorld.instance != null && IsoWorld.instance.getCell() != null;
        } catch (Throwable t) {
            up = false;
        }

        if (!up) {
            worldWasUp = false;
            return false;
        }

        if (!worldWasUp) {
            worldWasUp = true;
            // A new world resets the engine's allocators, so a range that was exhausted in the
            // last one is clear again in this one.
            idsExhausted = false;
            reassert();
        }
        return true;
    }

    /** Have the engine's own allocators climbed into our range? */
    private static boolean idsAreSafe() {
        if (idsExhausted) {
            return false;
        }
        int lamppost;
        int roomLight;
        try {
            lamppost = IsoLightSource.nextId;
            roomLight = IsoRoomLight.nextId;
        } catch (Throwable t) {
            return true;
        }
        if (Tuning.engineLightIdsReach(lamppost, roomLight, Tuning.WORLD_BASE)) {
            idsExhausted = true;
            System.out.println(TAG + "engine light ids reached " + Tuning.WORLD_BASE
                               + " (lamppost=" + lamppost + ", room=" + roomLight
                               + "); refusing to place, because sharing an id is silent both ways");
            return false;
        }
        return true;
    }

    /** Put every remembered light back after the world destroyed them. */
    private static void reassert() {
        int n = 0;
        for (int h = 0; h < live.length; h++) {
            double[] p = live[h];
            if (p != null) {
                // Not placed any more: native threw the light away with everything else.
                p[7] = 0.0;
                if (place(h, p)) {
                    n++;
                }
            }
        }
        if (n > 0) {
            System.out.println(TAG + "re-established " + n + " light(s) after a world change");
        }
    }

    /** Tell the engine a light source changed, the way every vanilla add and remove does. */
    private static void noteChanged() {
        try {
            if (GameTime.instance != null) {
                GameTime.instance.lightSourceUpdate = 100.0F;
            }
        } catch (Throwable t) {
            // A hint, not a requirement. If the field ever moves, the light still works.
        }
    }

    /** The one place that registers a light with native. Everything else records intent. */
    private static boolean place(int handle, double[] p) {
        int id = Tuning.worldLightId(handle, Tuning.WORLD_BASE, Tuning.WORLD_SLOTS);
        if (id < 0 || !idsAreSafe()) {
            return false;
        }
        try {
            LightingJNI.addLight(id,
                                 (int) p[0], (int) p[1], (int) p[2] + Z_BIAS,
                                 (int) p[6],
                                 (float) p[3], (float) p[4], (float) p[5],
                                 NO_BUILDING,
                                 p[8] != 0.0);
            p[7] = 1.0;
            noteChanged();
            return true;
        } catch (Throwable t) {
            // NEVER THROW INTO LUA. A dead bridge must dim the mod that uses it, not break it.
            System.out.println(TAG + "addLight failed: " + t);
            return false;
        }
    }

    /** Take one light out of native, if it is in there. */
    private static void unplace(int handle, double[] p) {
        if (p == null || p[7] == 0.0) {
            return;
        }
        p[7] = 0.0;
        int id = Tuning.worldLightId(handle, Tuning.WORLD_BASE, Tuning.WORLD_SLOTS);
        if (id < 0) {
            return;
        }
        try {
            LightingJNI.removeLight(id);
            noteChanged();
        } catch (Throwable t) {
            System.out.println(TAG + "removeLight failed: " + t);
        }
    }

    /** Claim a slot. Returns a handle, or -1 when every slot is taken. */
    @LuaMethod(name = "LugliELWorldLightAcquire", global = true)
    public static int acquire(String owner) {
        if (!ENABLED || owner == null || owner.isEmpty()) {
            return -1;
        }
        for (int h = 0; h < Tuning.WORLD_SLOTS; h++) {
            if (owners[h] == null) {
                owners[h] = owner;
                live[h] = null;
                return h;
            }
        }
        System.out.println(TAG + "no free slot for " + owner + "; all "
                           + Tuning.WORLD_SLOTS + " are in use");
        return -1;
    }

    /** Place or move one light. Idempotent: calling it again on the same handle updates in place. */
    @LuaMethod(name = "LugliELWorldLightSet", global = true)
    public static boolean set(int handle, double x, double y, double z,
                              double r, double g, double b, double radius) {
        if (!ready() || handle < 0 || handle >= Tuning.WORLD_SLOTS || owners[handle] == null) {
            return false;
        }

        // EVERY NUMBER IS CHECKED BEFORE IT CROSSES THE JNI BOUNDARY. Past this point there is no
        // exception to catch: a NaN from an ordinary Lua arithmetic slip becomes undefined
        // behaviour in native code, and the failure mode is a dead process, not a wrong light.
        if (!Tuning.isFinite(x) || !Tuning.isFinite(y) || !Tuning.isFinite(z)
            || !Tuning.isFinite(radius)) {
            return false;
        }

        int ix = Tuning.clampCoord(x);
        int iy = Tuning.clampCoord(y);
        int iz = Tuning.clampCoord(z);
        int ir = Tuning.clampRadius(radius);
        double cr = Tuning.clampChannel(r);
        double cg = Tuning.clampChannel(g);
        double cb = Tuning.clampChannel(b);

        double[] p = live[handle];
        if (p == null) {
            p = new double[9];
            p[8] = 1.0;                                   // active, until someone says otherwise
            live[handle] = p;
        }

        boolean moved = p[7] == 0.0
            || (int) p[0] != ix || (int) p[1] != iy || (int) p[2] != iz || (int) p[6] != ir;
        boolean recoloured = p[3] != cr || p[4] != cg || p[5] != cb;

        p[0] = ix; p[1] = iy; p[2] = iz;
        p[3] = cr; p[4] = cg; p[5] = cb;
        p[6] = ir;

        if (moved) {
            unplace(handle, p);
            return place(handle, p);
        }
        if (recoloured) {
            return colourNow(handle, p);
        }
        return true;
    }

    private static boolean colourNow(int handle, double[] p) {
        int id = Tuning.worldLightId(handle, Tuning.WORLD_BASE, Tuning.WORLD_SLOTS);
        if (id < 0) {
            return false;
        }
        try {
            LightingJNI.setLightColor(id, (float) p[3], (float) p[4], (float) p[5]);
            return true;
        } catch (Throwable t) {
            System.out.println(TAG + "setLightColor failed: " + t);
            return false;
        }
    }

    /** Take one light away. Safe for a handle that was never set. Internal: release() calls it. */
    private static void remove(int handle) {
        if (handle < 0 || handle >= Tuning.WORLD_SLOTS) {
            return;
        }
        double[] p = live[handle];
        live[handle] = null;
        if (!ready()) {
            return;
        }
        unplace(handle, p);
    }

    /** Give a slot back and put its light out. Safe on a handle that was never acquired. */
    @LuaMethod(name = "LugliELWorldLightRelease", global = true)
    public static void release(int handle) {
        if (handle < 0 || handle >= Tuning.WORLD_SLOTS) {
            return;
        }
        owners[handle] = null;
        remove(handle);
    }

    /** Give back EVERY slot one owner holds, and return how many that was. */
    @LuaMethod(name = "LugliELWorldLightReleaseOwner", global = true)
    public static int releaseOwner(String owner) {
        if (owner == null || owner.isEmpty()) {
            return 0;
        }
        int n = 0;
        for (int h = 0; h < Tuning.WORLD_SLOTS; h++) {
            if (owner.equals(owners[h])) {
                release(h);
                n++;
            }
        }
        if (n > 0) {
            System.out.println(TAG + "reclaimed " + n + " orphaned slot(s) for " + owner);
        }
        return n;
    }

}
