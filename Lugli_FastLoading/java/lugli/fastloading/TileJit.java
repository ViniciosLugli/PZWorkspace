package lugli.fastloading;

import java.lang.management.ManagementFactory;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import javax.management.MBeanServer;
import javax.management.ObjectName;

import zombie.debug.DebugLog;

/**
 * Lets the JIT compile IsoWorld.LoadTileDefinitions. -Dfastloading.tilejit=off.
 *
 * On the HotSpot JIT the game ships with, C1 bails out of that one method ("out of virtual registers
 * in LIR generator") and C2's OSR compile of it takes ~12 s, longer than the tile pass, so the whole
 * pass runs in the interpreter. A compiler directive that turns off inlining INTO that method only
 * lets C1 finish and cuts C2 to ~4 s. Inlining policy cannot change what the method does.
 *
 * Installed through the DiagnosticCommand MBean (the in-process form of `jcmd Compiler.directives_add`),
 * on a daemon thread so JMX start-up stays off the boot path. Only needs to land before the world load.
 */
public final class TileJit {

    public static final String TAG = "[FastLoading/tilejit]";

    static final boolean ON = !"off".equals(System.getProperty("fastloading.tilejit", "on"));

    static final String DIRECTIVE = "[{ match: \"zombie/iso/IsoWorld.LoadTileDefinitions\","
            + " c1: { inline: \"-*.*\" }, c2: { inline: \"-*.*\" } }]";

    private static volatile String status = ON ? "pending" : "off";

    private TileJit() {}

    public static String status() {
        return status;
    }

    static void install() {
        if (!ON) return;
        Thread t = new Thread(TileJit::add, "FastLoading-tilejit");
        t.setDaemon(true);
        t.start();
    }

    private static void add() {
        long start = System.nanoTime();
        Path file = null;
        try {
            file = Files.createTempFile("fastloading-tilejit", ".json");
            Files.writeString(file, DIRECTIVE, StandardCharsets.UTF_8);
            MBeanServer server = ManagementFactory.getPlatformMBeanServer();
            ObjectName dcmd = new ObjectName("com.sun.management:type=DiagnosticCommand");
            Object out = server.invoke(dcmd, "compilerDirectivesAdd",
                    new Object[] {new String[] {file.toString()}}, new String[] {String[].class.getName()});
            String answer = String.valueOf(out).trim();
            long ms = (System.nanoTime() - start) / 1_000_000L;
            status = answer.startsWith("1 compiler directives added") ? "ok, directive added in " + ms + " ms"
                                                                       : "DEFECT: " + answer;
        } catch (Throwable e) {
            status = "unavailable, the engine's JIT behaviour stays: " + e;
        } finally {
            if (file != null) {
                try {
                    Files.deleteIfExists(file);
                } catch (Throwable ignored) {
                }
            }
        }
        DebugLog.log(TAG + " " + status);
    }
}
