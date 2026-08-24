package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.utils.DirectBufferAllocator;
import zombie.core.utils.WrappedBuffer;
import zombie.debug.DebugLog;

/**
 * Takes the direct-buffer allocation out of the global monitor.
 * -Dfastloading.bufalloc=on   (default OFF until measured)
 *
 * `DirectBufferAllocator.allocate` is:
 *
 *     synchronized (LOCK) {
 *         destroyDisposed();                       // O(n) sweep
 *         WrappedBuffer wrapped = new WrappedBuffer(size);
 *         ALL.add(wrapped);
 *     }
 *
 * and `new WrappedBuffer(size)` is `MemoryUtil.memAlloc(size)` FOLLOWED BY
 * `MemoryUtil.memSet(buf, 0)` -- a full zero-fill, executed **while holding the lock**. A 1024x1024
 * RGBA page is 4 MB, and `generateMipMaps` allocates ten more levels on top of it. Across the
 * 1,839 mounted world-tile pages that is on the order of **9 GB of memset inside one global
 * critical section**, contended by the 10 asset workers, the game thread and the render thread --
 * and `getBytesAllocated()` takes the same lock and walks the list twice, which `waitFileTask`
 * polls per worker.
 *
 * WHAT THIS CHANGES, AND WHAT IT DELIBERATELY DOES NOT
 *   Only the *scope of the lock*. The buffer is still allocated and still zero-filled, identically;
 *   it just happens outside the monitor, so workers stop serialising on each other's memset. There
 *   is no format change, no pixel change, and no change to what any caller observes.
 *
 *   Dropping the zero-fill as well would be a bigger win (mip levels are fully overwritten by the
 *   scaler, and a base page needs only its power-of-two padding zeroed) but it changes what a
 *   caller reads from a fresh buffer, and `allocate` serves the whole engine, not just textures.
 *   That is a separate, evidence-gated step -- not this one.
 *
 * ORDERING IS PRESERVED. `destroyDisposed()` still runs before the allocation (it is public and
 * takes the lock itself), and the `ALL.add` still happens under the lock. The only observable
 * difference is a microseconds-wide window in which a buffer exists but is not yet counted by
 * `getBytesAllocated()`, which can only make the asset throttle slightly *more* permissive -- never
 * less -- against a 768 MB budget.
 *
 * FAILS SAFE. `ALL` and `LOCK` are private statics, so they are resolved reflectively ONCE at
 * install; if that fails, the patch disables itself and never skips the engine body. The advice
 * only ever skips when it is certain it can produce the return value.
 *
 * See docs/09-world-load.md
 */
@Patch(className = "zombie.core.utils.DirectBufferAllocator", methodName = "allocate")
public final class BufferAlloc {

    public static final String TAG = "[FastLoading/bufalloc]";

    /** public: these bodies are inlined into zombie.core.utils.DirectBufferAllocator. */
    public static final boolean ON = "on".equals(System.getProperty("fastloading.bufalloc", "off"));

    public static Object lock;
    public static ArrayList<WrappedBuffer> all;
    public static boolean resolved;
    public static boolean broken;
    public static int served;
    public static boolean announced;

    private BufferAlloc() {}

    /**
     * Resolve the two private statics once. Returns false forever after any failure, so the engine
     * keeps its own implementation rather than us half-applying.
     */
    @SuppressWarnings("unchecked")
    public static synchronized boolean ready() {
        if (broken) {
            return false;
        }
        if (resolved) {
            return true;
        }
        try {
            Field fLock = DirectBufferAllocator.class.getDeclaredField("LOCK");
            fLock.setAccessible(true);
            Object l = fLock.get(null);
            Field fAll = DirectBufferAllocator.class.getDeclaredField("ALL");
            fAll.setAccessible(true);
            Object a = fAll.get(null);
            if (l == null || !(a instanceof ArrayList)) {
                broken = true;
                DebugLog.log(TAG + " disabled, unexpected engine shape");
                return false;
            }
            lock = l;
            all = (ArrayList<WrappedBuffer>) a;
            resolved = true;
            return true;
        } catch (Throwable t) {
            broken = true;
            DebugLog.log(TAG + " disabled, could not resolve allocator state: " + t);
            return false;
        }
    }

    /** true = skip the engine's synchronized body; exit() then supplies the return value. */
    @Patch.OnEnter(skipOn = true)
    public static boolean in() {
        return ON && !broken && ready();
    }

    @Patch.OnExit
    public static void out(@Patch.Argument(0) int size,
                           @Patch.Return(readOnly = false) WrappedBuffer ret) {
        if (!ON || broken || !resolved || ret != null) {
            // Either we did not skip, or the engine already produced a buffer. Leave it alone.
            return;
        }
        // Same order as the engine, minus the lock around the expensive part.
        DirectBufferAllocator.destroyDisposed();
        WrappedBuffer wrapped = new WrappedBuffer(size);
        synchronized (lock) {
            all.add(wrapped);
        }
        served++;
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " direct-buffer allocation moved out of the global lock");
        }
        ret = wrapped;
    }
}
