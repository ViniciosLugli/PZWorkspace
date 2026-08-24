package lugli.fastloading;

import java.lang.reflect.Field;
import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.utils.DirectBufferAllocator;
import zombie.core.utils.WrappedBuffer;
import zombie.debug.DebugLog;

/**
 * Allocates direct buffers outside DirectBufferAllocator's global monitor.
 * -Dfastloading.bufalloc=on (default off: measured no change).
 *
 * The engine holds the lock across memAlloc plus a full memSet of the buffer. This does the
 * same work with only the ALL.add inside the lock. ALL and LOCK are private statics, resolved
 * reflectively once; if that fails the patch disables itself and never skips the engine body.
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
