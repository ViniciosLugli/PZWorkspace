package lugli.fastloading;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;
import zombie.tileDepth.TileDepthTextures;
import zombie.tileDepth.TilesetDepthTexture;

/**
 * Moves the depth-map PNG decode out of one global monitor.
 * -Dfastloading.tiledepth=off to disable.
 *
 * VALIDATED 2026-08-23. Correctness: the loaded tileset set is byte-identical to the stock
 * engine's -- 938 tilesets, fingerprint 881543175, zero diff on name/rows/columns/source across
 * merged and every per-mod TileDepthTextures (tools: Dev_TileDepthDump). Speed: world load 92 s
 * stock vs 83 s / 81 s with this, the difference landing in the asset barrier
 * (29.46 s -> 18.11 s), matching the loose hand-patched class it replaces (82 s / 18.49 s).
 *
 * TileDepthTextures$LoadTask.call is:
 *
 *     synchronized (this.textures) {                    // every worker, ONE object
 *         if (this.textures.tilesets.get(name) == null)
 *             this.textures.createTileset(name, true);  // decodes the PNG INSIDE the lock
 *     }
 *
 * Each task handles a different tileset, so the exclusion is only needed for the `tilesets`
 * HashMap access. The tasks are queued at priority 4 -- the lowest in the engine -- so they drain
 * last, i.e. inside the world-load barriers, with every pool thread piling onto that monitor.
 *
 * WORTH ~10 s OF WORLD LOAD, measured 2026-08-23 by un-shadowing the equivalent loose class:
 * 82 s patched vs 92 s stock, the difference landing in the asset barrier where these drain.
 *
 * WHY THIS IS SAFE TO SPLIT -- the part that had to be checked, not assumed:
 *   - `getTilesetRows(name, true)` is a pure read, but the map is NOT finished when workers run:
 *     `loadDepthTextureImages` puts entry k and submits task k in the SAME loop iteration
 *     (`TileDepthTextures.java:134-139`), so the main thread keeps inserting while earlier tasks
 *     execute. The read is therefore taken under `synchronized (textures)` -- the same monitor
 *     stock holds for the whole body -- so this patch is never a weaker guarantee than stock.
 *     (An earlier version of this comment claimed the map was fully populated before fan-out.
 *     That was wrong, and it would have widened a one-reader race to ten.)
 *   - That leaves `tilesets.put` as the single shared write on this path. It stays under
 *     `synchronized (textures)`, and so does every READ of that map -- reading a HashMap while
 *     another thread puts can spin forever during a resize.
 *   - The expensive `TilesetDepthTexture.load()` moves outside, guarded by a per-tileset lock so
 *     two workers never decode the same tileset.
 *
 * Semantics are preserved exactly, including the two easy-to-miss cases: rows == 0 stores NOTHING
 * (the engine's createTileset returns null without putting), and an exception from load() is
 * logged and the tileset is still stored.
 *
 * Reflection is needed for exactly three members: LoadTask.path and LoadTask.textures
 * (package-private fields of a package-private class) and TileDepthTextures.getTilesetRows /
 * .tilesets (private). Everything else -- TilesetDepthTexture's constructor, fileExists(), load(),
 * and getExistingTileset() -- is public API on public classes.
 *
 * See docs/09-world-load.md
 */
@Patch(className = "zombie.tileDepth.TileDepthTextures$LoadTask", methodName = "call")
public final class TileDepthLock {

    public static final String TAG = "[FastLoading/tiledepth]";

    /** public: these are read from a body inlined into zombie.tileDepth.TileDepthTextures$LoadTask. */
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.tiledepth", "on"));

    public static final ConcurrentHashMap<String, Object> LOCKS = new ConcurrentHashMap<>();
    public static volatile boolean broken;
    public static int handled;
    public static boolean announced;

    public static Field fPath;
    public static Field fTextures;
    public static Field fTilesets;
    public static Method mGetRows;
    public static Constructor<TilesetDepthTexture> ctor;

    private TileDepthLock() {}

    /** Resolve once. Any failure disables the patch rather than half-applying it. */
    public static synchronized boolean ready(Object task) {
        if (broken) {
            return false;
        }
        if (fPath != null) {
            return true;
        }
        try {
            fPath = task.getClass().getDeclaredField("path");
            fPath.setAccessible(true);
            fTextures = task.getClass().getDeclaredField("textures");
            fTextures.setAccessible(true);
            fTilesets = TileDepthTextures.class.getDeclaredField("tilesets");
            fTilesets.setAccessible(true);
            mGetRows = TileDepthTextures.class.getDeclaredMethod("getTilesetRows", String.class, boolean.class);
            mGetRows.setAccessible(true);
            ctor = TilesetDepthTexture.class.getConstructor(
                    TileDepthTextures.class, String.class, int.class, int.class, boolean.class);
            return true;
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, engine shape not as expected: " + t);
            return false;
        }
    }

    /** true = skip the engine's synchronized body, we did the work. */
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This Object task) {
        if (!ON || broken || !ready(task)) {
            return false;
        }
        try {
            Path path = (Path) fPath.get(task);
            TileDepthTextures textures = (TileDepthTextures) fTextures.get(task);
            String fileName = path.toFile().getName();
            String name = fileName.replaceFirst("DEPTH_", "").replace(".png", "");

            if (present(textures, name)) {
                return true;
            }
            // NO LAMBDA HERE. `computeIfAbsent(name, k -> new Object())` compiles the lambda to a
            // PRIVATE synthetic method (lambda$enter$0), and this body is inlined into
            // zombie.tileDepth.TileDepthTextures$LoadTask, which cannot reach it:
            //   IllegalAccessError: ... tried to access private method
            //   lugli.fastloading.TileDepthLock.lambda$enter$0
            // It is invoked through invokedynamic rather than a Method ref, so a checker that
            // scans member references does not see it either. Never use a lambda, method
            // reference, or anonymous class inside an advice body.
            Object lock = LOCKS.get(name);
            if (lock == null) {
                Object fresh = new Object();
                Object prev = LOCKS.putIfAbsent(name, fresh);
                lock = prev != null ? prev : fresh;
            }
            synchronized (lock) {
                if (present(textures, name)) {
                    return true;
                }
                // MUST hold `textures` for this read. `loadDepthTextureImages` does
                // `tilesetRows.put(...)` and `runAsync(loadTask)` in the SAME loop iteration
                // (TileDepthTextures.java:134-139), so the main thread is still inserting while
                // earlier tasks run -- workers do NOT merely read a finished map. Stock serialises
                // this read because the whole body is `synchronized (textures)`; taking the same
                // monitor for the read alone keeps that guarantee while leaving the expensive
                // decode outside. Without it this patch turns stock's one concurrent reader into
                // ten reading a plain HashMap mid-resize: a wrong `rows` builds a wrong-sized
                // tileset, which renders as a depth artefact rather than failing loudly.
                int rows;
                synchronized (textures) {
                    rows = (int) mGetRows.invoke(textures, name, true);
                }
                if (rows == 0) {
                    // Engine parity: createTileset returns null and stores nothing.
                    return true;
                }
                TilesetDepthTexture tileset = ctor.newInstance(textures, name, 8, rows, true);
                if (tileset.fileExists()) {
                    try {
                        tileset.load();
                    } catch (Exception ex) {
                        DebugLog.log(TAG + " load failed for " + name + ": " + ex);
                    }
                }
                store(textures, name, tileset);
            }
            handled++;
            if (!announced) {
                announced = true;
                DebugLog.log(TAG + " depth tilesets decode outside the global lock");
            }
            return true;
        } catch (Throwable t) {
            // Never leave a tileset unloaded: fall back to the engine for this task and all later
            // ones. A missing depth tileset is a visible rendering fault, not a silent one.
            broken = true;
            DebugLog.log(TAG + " disabled after error, engine path resumes: " + t);
            return false;
        }
    }

    @SuppressWarnings("unchecked")
    public static boolean present(TileDepthTextures textures, String name) throws Exception {
        synchronized (textures) {
            return ((HashMap<String, TilesetDepthTexture>) fTilesets.get(textures)).get(name) != null;
        }
    }

    @SuppressWarnings("unchecked")
    public static void store(TileDepthTextures textures, String name, TilesetDepthTexture t)
            throws Exception {
        synchronized (textures) {
            ((HashMap<String, TilesetDepthTexture>) fTilesets.get(textures)).put(name, t);
        }
    }
}
