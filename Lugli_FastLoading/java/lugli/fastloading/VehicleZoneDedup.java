package lugli.fastloading;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.iso.IsoMetaGrid;
import zombie.iso.zones.VehicleZone;

/**
 * IsoMetaGrid.checkVehiclesZones in one hashed pass. -Dfastloading.vehiclezones=off.
 *
 * The engine drops every vehicle zone whose rectangle repeats an earlier one by comparing each
 * zone with every zone before it, and vanilla doMapZones calls it once per map directory. On a
 * heavy list that is ~0.25 s a directory, several seconds on the world-loading thread.
 *
 * MUST leave the list exactly as the engine does: first occurrence of each (x, y, h, w) kept, in
 * order, the same list object. The first call runs the engine too and compares element by element;
 * one difference turns the part off.
 */
public final class VehicleZoneDedup {

    public static final String TAG = "[FastLoading/vehiclezones]";

    /** public: read from a body inlined into zombie.iso.IsoMetaGrid. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.vehiclezones", "on"));

    public static volatile boolean broken;
    public static volatile boolean validated;
    public static long fast;
    public static long removed;

    /** The fast result of the call being validated, for the exit advice. */
    public static List<VehicleZone> pending;

    private VehicleZoneDedup() {}

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return "ok, " + fast + " pass(es) hashed, " + removed + " duplicate zone(s) dropped"
                + (validated ? ", checked against the engine" : "");
    }

    private record Key(int x, int y, int h, int w) {}

    /** True = the list is already deduplicated here and the engine body is skipped. */
    public static boolean enter(IsoMetaGrid grid) {
        pending = null;
        if (broken) return false;
        try {
            ArrayList<VehicleZone> zones = grid.vehiclesZones;
            if (!validated) {
                pending = dedup(new ArrayList<>(zones), false);
                return false;
            }
            int before = zones.size();
            List<VehicleZone> kept = dedup(zones, true);
            if (kept.size() != before) {
                zones.clear();
                zones.addAll(kept);
                removed += before - kept.size();
            }
            fast++;
            return true;
        } catch (Throwable t) {
            disable("dedup failed", t);
            return false;
        }
    }

    public static void exit(IsoMetaGrid grid) {
        List<VehicleZone> ours = pending;
        if (ours == null) return;
        pending = null;
        ArrayList<VehicleZone> engine = grid.vehiclesZones;
        if (engine.size() != ours.size()) {
            disable("engine kept " + engine.size() + " zone(s), ours " + ours.size(), null);
            return;
        }
        for (int i = 0; i < ours.size(); i++) {
            if (engine.get(i) != ours.get(i)) {
                disable("zone " + i + " differs from the engine", null);
                return;
            }
        }
        validated = true;
        DebugLog.log(TAG + " identical to the engine over " + engine.size() + " zone(s), fast path on");
    }

    /** The engine's rule: a zone repeating an earlier kept zone's rectangle is dropped and logged. */
    static List<VehicleZone> dedup(List<VehicleZone> zones, boolean log) {
        HashMap<Key, VehicleZone> first = new HashMap<>(zones.size() * 2);
        ArrayList<VehicleZone> kept = new ArrayList<>(zones.size());
        for (VehicleZone a : zones) {
            Key key = new Key(a.getX(), a.getY(), a.h, a.w);
            VehicleZone b = first.putIfAbsent(key, a);
            if (b == null) {
                kept.add(a);
            } else if (log) {
                DebugType.Vehicle.debugln("checkVehiclesZones: ERROR! Zone '" + a.name + "':'" + a.type + "' ("
                        + a.x + ", " + a.y + ") duplicate with Zone '" + b.name + "':'" + b.type + "' ("
                        + b.x + ", " + b.y + ")");
            }
        }
        return kept;
    }

    public static void disable(String why, Throwable t) {
        if (broken) return;
        broken = true;
        DebugLog.log(TAG + " disabled, engine path resumes: " + why + (t == null ? "" : ": " + t));
    }

    @Patch(className = "zombie.iso.IsoMetaGrid", methodName = "checkVehiclesZones")
    public static final class Hook {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This IsoMetaGrid grid) {
            return VehicleZoneDedup.ON && VehicleZoneDedup.enter(grid);
        }

        @Patch.OnExit
        public static void exit(@Patch.This IsoMetaGrid grid) {
            if (VehicleZoneDedup.ON) VehicleZoneDedup.exit(grid);
        }
    }
}
