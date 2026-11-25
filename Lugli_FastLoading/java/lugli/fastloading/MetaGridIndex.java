package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.Set;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.iso.BuildingDef;
import zombie.iso.IsoMetaCell;
import zombie.iso.IsoMetaGrid;
import zombie.iso.IsoWorld;
import zombie.iso.RoomDef;
import zombie.iso.RoomID;
import zombie.iso.BuildingID;

/**
 * Two linear scans the world load runs once per element, replaced by identity indexes.
 * -Dfastloading.metaindex=off.
 *
 * Basements.addBasementBuildingDefsToMetaGrid adds each basement building to IsoMetaGrid.buildings
 * unless ArrayList.contains finds it there: one scan of ~18,000 buildings per basement.
 * BuildingRoomsEditor.checkBuildingAndRoomIDs looks every room of every building up in its cell's
 * room list with ArrayList.indexOf. Neither BuildingDef nor RoomDef overrides equals, so both
 * scans are identity lookups, and an identity set or first-index map answers them exactly.
 *
 * MUST keep every other step of both methods in the engine's order, with the engine's calls: the
 * replacements below are the engine bodies with only the lookup changed. The room check only
 * logs, and its first cell is also run through indexOf and compared; one difference turns the part
 * off.
 */
public final class MetaGridIndex {

    public static final String TAG = "[FastLoading/metaindex]";

    /** public: read from bodies inlined into zombie.basements.Basements and BuildingRoomsEditor. */
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.metaindex", "on"));

    public static volatile boolean broken;
    public static boolean roomsValidated;
    public static long basementPasses;
    public static long cellsChecked;

    /** Lookups answered by the engine's scan and compared with the index before it is trusted. */
    static final int CHECKED_LOOKUPS = 256;
    static int basementChecks;
    static int roomChecks;

    private static Field fBuildingDefs;
    private static Field fMergedRooms;
    private static Field fMergedDef;
    private static Field fMergedRoomList;
    private static Field fMergedEmpty;

    private MetaGridIndex() {}

    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return "ok, " + basementPasses + " basement pass(es), " + cellsChecked + " cell room check(s) indexed"
                + (roomsValidated ? ", checked against the engine" : "");
    }

    /** True = the engine's addBasementBuildingDefsToMetaGrid ran here and its body is skipped. */
    @SuppressWarnings("unchecked")
    public static boolean basements(Object basements) {
        if (broken) return false;
        ArrayList<BuildingDef> defs;
        HashMap<BuildingDef, Object> merged;
        try {
            resolveBasements(basements.getClass());
            defs = (ArrayList<BuildingDef>) fBuildingDefs.get(basements);
            merged = (HashMap<BuildingDef, Object>) fMergedRooms.get(basements);
            if (defs == null || merged == null) return false;
        } catch (Throwable t) {
            disable("basements fields unreadable", t);
            return false;
        }
        // Past this point the engine's side effects have started, so a failure is rethrown rather
        // than handed back to an engine body that would apply them a second time.
        IsoMetaGrid metaGrid = IsoWorld.instance.getMetaGrid();
        Set<BuildingDef> present = Collections.newSetFromMap(new IdentityHashMap<>(metaGrid.buildings.size() * 2));
        present.addAll(metaGrid.buildings);
        int added = 0;
        for (int i = 0; i < defs.size(); i++) {
            BuildingDef buildingDef = defs.get(i);
            int cellX = buildingDef.x / 256;
            int cellY = buildingDef.y / 256;
            IsoMetaCell metaCell = metaGrid.getCellData(cellX, cellY);
            if (metaCell != null) {
                metaCell.addRooms(buildingDef.rooms, cellX * 256, cellY * 256);
                metaCell.addRooms(buildingDef.emptyoutside, cellX * 256, cellY * 256);
                metaGrid.addRoomsToAdjacentCells(buildingDef);
                boolean add;
                if (broken || basementChecks < CHECKED_LOOKUPS) {
                    // The engine's own answer decides while validating, so a mismatch costs nothing.
                    add = !metaGrid.buildings.contains(buildingDef);
                    if (!broken && add != !present.contains(buildingDef)) {
                        disable("building set differs from ArrayList.contains", null);
                    }
                    basementChecks++;
                    if (add) present.add(buildingDef);
                } else {
                    add = present.add(buildingDef);
                }
                if (add) {
                    metaGrid.buildings.add(buildingDef);
                    added++;
                }
            }
        }
        try {
            for (Object mergedRooms1 : merged.values()) {
                BuildingDef buildingDef = (BuildingDef) fMergedDef.get(mergedRooms1);
                ArrayList<RoomDef> rooms = (ArrayList<RoomDef>) fMergedRoomList.get(mergedRooms1);
                ArrayList<RoomDef> emptyoutside = (ArrayList<RoomDef>) fMergedEmpty.get(mergedRooms1);
                int cellX = buildingDef.x / 256;
                int cellY = buildingDef.y / 256;
                IsoMetaCell metaCell = metaGrid.getCellData(cellX, cellY);
                if (metaCell != null) {
                    metaCell.addRooms(rooms, cellX * 256, cellY * 256);
                    metaCell.addRooms(emptyoutside, cellX * 256, cellY * 256);
                    metaGrid.addRoomsToAdjacentCells(buildingDef, rooms);
                    metaGrid.addRoomsToAdjacentCells(buildingDef, emptyoutside);
                }
            }
        } catch (IllegalAccessException e) {
            throw new IllegalStateException(TAG + " merged rooms unreadable", e);
        }
        merged.clear();
        if (basementPasses++ == 0) {
            DebugLog.log(TAG + " basements: " + defs.size() + " building(s), " + added + " added to the grid, "
                         + Math.min(basementChecks, CHECKED_LOOKUPS) + " checked against ArrayList.contains"
                         + (broken ? ", MISMATCH" : ""));
        }
        return true;
    }

    private static synchronized void resolveBasements(Class<?> c) throws ReflectiveOperationException {
        if (fBuildingDefs != null) return;
        Field defs = c.getDeclaredField("buildingDefs");
        Field merged = c.getDeclaredField("mergedRooms");
        Class<?> m = Class.forName("zombie.basements.Basements$MergedRooms", false, c.getClassLoader());
        Field def = m.getDeclaredField("buildingDef");
        Field rooms = m.getDeclaredField("rooms");
        Field empty = m.getDeclaredField("emptyoutside");
        for (Field f : new Field[] {defs, merged, def, rooms, empty}) f.setAccessible(true);
        fMergedDef = def;
        fMergedRoomList = rooms;
        fMergedEmpty = empty;
        fMergedRooms = merged;
        fBuildingDefs = defs;
    }

    /** True = the engine's checkBuildingAndRoomIDs(IsoMetaCell) ran here and its body is skipped. */
    public static boolean rooms(IsoMetaCell metaCell) {
        if (broken) return false;
        try {
            Map<RoomDef, Integer> index = new IdentityHashMap<>(metaCell.roomList.size() * 2);
            for (int i = 0; i < metaCell.roomList.size(); i++) {
                index.putIfAbsent(metaCell.roomList.get(i), i);
            }
            if (!roomsValidated) {
                for (BuildingDef buildingDef : metaCell.buildings) {
                    if (!sameIndex(metaCell, index, buildingDef.getRooms())
                            || !sameIndex(metaCell, index, buildingDef.getEmptyOutside())) {
                        disable("room index differs from indexOf", null);
                        return false;
                    }
                }
                if (roomChecks >= CHECKED_LOOKUPS) {
                    roomsValidated = true;
                    DebugLog.log(TAG + " room index identical to indexOf over " + roomChecks
                                 + " lookup(s), fast path on");
                }
            }
            checkCell(metaCell, index);
            cellsChecked++;
            return true;
        } catch (Throwable t) {
            disable("room check failed", t);
            return false;
        }
    }

    private static boolean sameIndex(IsoMetaCell metaCell, Map<RoomDef, Integer> index, ArrayList<RoomDef> rooms) {
        for (RoomDef roomDef : rooms) {
            Integer fast = index.get(roomDef);
            if ((fast == null ? -1 : fast) != metaCell.roomList.indexOf(roomDef)) return false;
            roomChecks++;
        }
        return true;
    }

    /** The engine's checkBuildingAndRoomIDs(IsoMetaCell) with indexOf answered by `index`. */
    private static void checkCell(IsoMetaCell metaCell, Map<RoomDef, Integer> index) {
        int cellX = metaCell.getX();
        int cellY = metaCell.getY();
        for (int i = 0; i < metaCell.buildings.size(); i++) {
            BuildingDef buildingDef = metaCell.buildings.get(i);
            long expected = BuildingID.makeID(cellX, cellY, i);
            if (expected != buildingDef.id) {
                DebugType.General.error("buildingDef.ID=%d expected=%d", new Object[] {buildingDef.id, expected});
            }
            checkRooms(cellX, cellY, index, buildingDef.getRooms());
            checkRooms(cellX, cellY, index, buildingDef.getEmptyOutside());
        }
        for (int i = 0; i < metaCell.roomList.size(); i++) {
            RoomDef roomDef = metaCell.roomList.get(i);
            long expected = RoomID.makeID(cellX, cellY, i);
            if (expected != roomDef.id) {
                DebugType.General.error("roomDef.ID=%d expected=%d", new Object[] {roomDef.id, expected});
            }
        }
        if (metaCell.roomList.size() != metaCell.rooms.size()) {
            DebugType.General.error("lotHeader.RoomList.size()=%d IsoMetaCell.Rooms.size()=%d",
                    new Object[] {metaCell.roomList.size(), metaCell.rooms.size()});
        }
    }

    private static void checkRooms(int cellX, int cellY, Map<RoomDef, Integer> index, ArrayList<RoomDef> rooms) {
        for (RoomDef roomDef : rooms) {
            Integer found = index.get(roomDef);
            int i = found == null ? -1 : found;
            if (i == -1) {
                DebugType.General.error("roomDef missing from IsoMetaCell.RoomList");
            }
            long expected = RoomID.makeID(cellX, cellY, i);
            if (expected != roomDef.id) {
                DebugType.General.error("roomDef.ID=%d expected=%d", new Object[] {roomDef.id, expected});
            }
        }
    }

    public static void disable(String why, Throwable t) {
        if (broken) return;
        broken = true;
        DebugLog.log(TAG + " disabled, engine path resumes: " + why + (t == null ? "" : ": " + t));
    }

    @Patch(className = "zombie.basements.Basements", methodName = "addBasementBuildingDefsToMetaGrid")
    public static final class Basement {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This Object basements) {
            return MetaGridIndex.ON && MetaGridIndex.basements(basements);
        }
    }

    /** checkBuildingAndRoomIDs() and (IsoMetaCell) share the name, so both are patched: dispatch on the arguments. */
    @Patch(className = "zombie.buildingRooms.BuildingRoomsEditor", methodName = "checkBuildingAndRoomIDs")
    public static final class Rooms {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.AllArguments Object[] args) {
            if (!MetaGridIndex.ON || args == null || args.length != 1 || !(args[0] instanceof IsoMetaCell)) {
                return false;
            }
            return MetaGridIndex.rooms((IsoMetaCell) args[0]);
        }
    }
}
