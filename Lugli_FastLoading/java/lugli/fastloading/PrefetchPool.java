package lugli.fastloading;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** The boot prefetch pools: daemon threads, so a stuck walk can never hold the JVM open. */
final class PrefetchPool {

    private PrefetchPool() {}

    /** See Tuning.prefetchThreads. */
    static final int THREADS =
            Tuning.prefetchThreads(Tuning.HOST.cores, Integer.getInteger("fastloading.iothreads"));

    static int threads() {
        return THREADS;
    }

    static ExecutorService create(String threadName, int threads) {
        return Executors.newFixedThreadPool(threads, r -> {
            Thread t = new Thread(r, threadName);
            t.setDaemon(true);
            return t;
        });
    }
}
