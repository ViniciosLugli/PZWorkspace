package lugli.fastloading;

import java.util.HashMap;
import java.util.Map;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.Core;
import zombie.core.SpriteRenderer;
import zombie.core.Translator;
import zombie.core.fonts.AngelCodeFont;
import zombie.core.textures.AnimatedTexture;
import zombie.core.textures.AnimatedTextures;
import zombie.debug.DebugLog;
import zombie.ui.TextManager;
import zombie.ui.UIFont;

/**
 * The loading screen: progress bar, phase name and the walking figure, drawn while boot runs.
 * -Dfastloading.progress=off.
 *
 * GameWindow.DoLoadingText only writes to the log, so vanilla leaves the window frozen for most
 * of boot and the OS can mark it unresponsive.
 *
 * TWO WAYS TO PAINT, and both are needed. draw() creates a frame, for the stretches where nothing
 * else presents one. paintInto() fills a frame someone else is about to present -- ModelManager's
 * mesh poll loop presents an empty frame every ~10 ms through the longest phase of boot, so
 * competing with it blinks, while filling it costs no extra frames.
 *
 * PUMPED FROM SEVEN PLACES because no single one covers boot: each phase is driven by different
 * engine code, and any stretch without a pump is a frozen screen.
 */
public final class BootProgress {

    public static final String TAG = "[FastLoading/progress]";

    /**
     * -Dfastloading.progress=off draws nothing. Separate from the `off` latch, which is failure
     * containment: one is the operator's choice, the other is this class deciding it is unsafe
     * to keep drawing, and collapsing them would make a crash look like a setting.
     */
    public static final boolean ON =
            !"off".equals(System.getProperty("fastloading.progress", "on"));

    public static final long INTERVAL_MS = Long.getLong("fastloading.progressms", 80L);

    /**
     * Safety net only, for a boot that dies or never announces its last phase. The screen
     * normally retires when the front end starts ticking, via AssetThrottle.menuBeat. A short
     * value here is a bug: single phases legitimately run for tens of seconds.
     */
    public static final long PHASE_IDLE_MS = Long.getLong("fastloading.progressidle", 120000L);

    /**
     * The engine's photosensitivity notice: >0 shows it on our screen for that long, 0 hides it,
     * -1 leaves the engine to draw its own frame exactly as vanilla does.
     */
    public static final long WARNING_MS = Long.getLong("fastloading.warningms", 0L);
    public static final int WARNING_LINES = 8;

    /** The world-loading screen's own figure, so both match and replacement art is picked up. */
    public static final String WALK_TEXTURE =
            System.getProperty("fastloading.walktexture", "media/ui/Progress/MaleWalk2.png");

    /**
     * Bounded pumping of the asset queue, purely so the figure arrives early rather than two
     * thirds of the way through boot. Strictly bounded: retiring assets does mipmap scaling and
     * GL uploads on the main thread, and doing it freely costs seconds of boot.
     */
    public static final long PUMP_INTERVAL_MS = Long.getLong("fastloading.artpumpms", 300L);
    public static final long PUMP_WINDOW_MS = Long.getLong("fastloading.artpumpwindow", 8000L);

    // public: these bodies are inlined into zombie.* classes, which then read them from there.
    public static final BootPhases PHASES = new BootPhases();
    public static volatile Map<String, Long> learned;
    public static volatile long lastPhaseAt;
    public static volatile long lastFrame;
    public static volatile long warningUntil;
    public static volatile boolean off;
    public static volatile boolean painting;
    public static volatile boolean drew;
    public static volatile boolean saved;
    public static volatile boolean reported;
    public static volatile AnimatedTexture walkTex;
    public static volatile long walkReadyAtMs = -1L;
    public static long lastPumpAt;
    public static int pumpCalls;

    /** Not volatile: a sampling counter on a hot single-threaded path. */
    public static int tokenCalls;

    // Timeline, reported once at the end. Every failure this screen has had was "nothing painted
    // during window X", and the longest gap names that window directly.
    public static long drawCount;
    public static long lastDrawAt;
    public static long maxGapMs;
    public static String maxGapPhase = "-";

    private BootProgress() {}

    public static boolean warningVisible(long now) {
        return WARNING_MS > 0L && warningUntil != 0L && now < warningUntil;
    }

    /** Latches what the engine announced and advances the phase model. */
    public static void note(String text) {
        if (text == null || text.isEmpty()) {
            return;
        }
        long now = System.currentTimeMillis();
        if (learned == null) {
            learned = BootPhases.load(BootPhases.storePath(System.getProperty("user.home")));
            PHASES.begin(now);
            requestWalkTexture();
        }
        lastPhaseAt = now;
        String key = BootPhases.keyFor(text);
        if (PHASES.enter(key, now)) {
            DebugLog.log(TAG + " phase " + (PHASES.currentIndex() + 1) + "/"
                         + BootPhases.ORDER.length + " " + key
                         + " at " + (PHASES.elapsedMs(now) / 1000.0) + "s");
        }
        if ("boot".equals(key)) {
            persist();
        }
    }

    /** Records this boot's timings so the next boot's bar is shaped like the real thing. */
    public static void persist() {
        if (saved || learned == null) {
            return;
        }
        saved = true;
        BootPhases.save(BootPhases.storePath(System.getProperty("user.home")),
                        PHASES.recorded(System.currentTimeMillis()));
    }

    public static void report() {
        if (!ON || reported) {
            return;
        }
        reported = true;
        long now = System.currentTimeMillis();
        StringBuilder sb = new StringBuilder(256);
        sb.append(TAG).append(" boot ").append(PHASES.elapsedMs(now) / 1000.0)
          .append("s, ").append(drawCount).append(" frames, longest unpainted gap ")
          .append(maxGapMs).append(" ms in ").append(maxGapPhase)
          .append(", art pumps ").append(pumpCalls)
          .append(", walk art ready after ").append(walkReadyAtMs / 1000L).append("s; phases");
        Map<String, Long> rec = PHASES.recorded(now);
        for (String k : BootPhases.ORDER) {
            Long v = rec.get(k);
            if (v != null) {
                sb.append(' ').append(k).append('=').append(v / 1000.0).append('s');
            }
        }
        DebugLog.log(sb.toString());
    }

    public static void countFrame(long now) {
        if (lastDrawAt != 0L) {
            long gap = now - lastDrawAt;
            if (gap > maxGapMs) {
                maxGapMs = gap;
                maxGapPhase = PHASES.currentKey() == null ? "-" : PHASES.currentKey();
            }
        }
        lastDrawAt = now;
        drawCount++;
    }

    public static void tick() {
        if (!ON || off) return;
        long now = System.currentTimeMillis();
        if (lastPhaseAt == 0L || now - lastPhaseAt > PHASE_IDLE_MS) return;
        if (now - lastFrame < INTERVAL_MS) return;
        lastFrame = now;
        pumpAssets(now);
        try {
            countFrame(now);
            draw();
            if (!drew) {
                drew = true;
                DebugLog.log(TAG + " drawing the loading screen");
            }
        } catch (Throwable t) {
            off = true;
            DebugLog.log(TAG + " display disabled (" + t + ")");
        }
    }

    /** Draws now, for the boundaries where the next scheduled frame is too late to matter. */
    public static void forceDraw() {
        if (!ON || off) return;
        lastFrame = 0L;
        tick();
    }

    /** Owns a frame. Used where nothing else in boot is presenting one. */
    public static void draw() {
        Core core = Core.getInstance();
        if (core == null) return;
        painting = true;
        try {
            core.StartFrame();
            core.EndFrame();
            core.StartFrameUI();
            body(System.currentTimeMillis());
            core.EndFrameUI();
        } finally {
            painting = false;
        }
    }

    /**
     * Fills a frame the engine is already presenting. Deliberately unthrottled: the rate has to
     * match whoever is presenting, or their empty frames show through as blinking.
     */
    public static void paintInto() {
        if (!ON || off || painting || lastPhaseAt == 0L) {
            return;
        }
        long now = System.currentTimeMillis();
        if (now - lastPhaseAt > PHASE_IDLE_MS) {
            return;
        }
        lastFrame = now;
        try {
            painting = true;
            countFrame(now);
            body(now);
        } catch (Throwable t) {
            off = true;
            DebugLog.log(TAG + " display disabled (" + t + ")");
        } finally {
            painting = false;
        }
    }

    /** The content. Assumes a UI frame is open; never opens or closes one. */
    public static void body(long now) {
        Core core = Core.getInstance();
        if (core == null) return;
        int w = core.getScreenWidth();
        int h = core.getScreenHeight();
        if (w <= 0 || h <= 0) return;
        SpriteRenderer sr = SpriteRenderer.instance;
        if (sr == null) return;

        // The ground goes down BEFORE anything can bail out. The font is briefly null while
        // TextManager rebuilds it, and returning early there left the engine's frame empty --
        // which is a black flash, not merely a missing label.
        sr.renderi(null, 0, 0, w, h, 0.055F, 0.062F, 0.078F, 1.0F, null);

        TextManager tm = TextManager.instance;
        if (tm == null) return;
        AngelCodeFont big = tm.getFontFromEnum(UIFont.NewLarge);
        if (big == null) return;
        AngelCodeFont small = tm.getFontFromEnum(UIFont.Small);
        if (small == null) small = big;

        double frac = PHASES.fraction(learned == null ? new HashMap<String, Long>() : learned, now);
        int step = Math.max(1, PHASES.currentIndex() + 1);
        boolean warn = warningVisible(now);

        int barW = Math.max(240, Math.min(620, (int) (w * 0.44)));
        int barX = (w - barW) / 2;
        int barY = (int) (h * 0.72);        // fixed, so nothing shifts when the notice clears
        int fill = (int) (barW * frac);

        if (warn) {
            int lineHeight = small.getLineHeight();
            double y = h / 2.0 - 4.0 * lineHeight;
            for (int i = 1; i <= WARNING_LINES; i++) {
                tm.DrawStringCentre(small, w / 2.0, y,
                                    Translator.getText("UI_EpilepsyWarning_" + i),
                                    0.88, 0.89, 0.92, 1.0);
                y += lineHeight;
            }
        } else {
            AnimatedTexture walk = walkTexture();
            if (walk != null && walk.getWidth() > 0 && walk.getHeight() > 0) {
                if (walkReadyAtMs < 0L) {
                    walkReadyAtMs = PHASES.elapsedMs(now);
                }
                int fw = 196;
                int fh = (int) (walk.getHeight() * (196.0F / walk.getWidth()));
                if (fh > 0) {
                    walk.render((w - fw) / 2, barY - 96 - fh, fw, fh, 1.0F, 1.0F, 1.0F, 0.66F);
                }
            }
        }

        sr.renderi(null, barX, barY, barW, 6, 0.16F, 0.17F, 0.20F, 1.0F, null);
        if (fill > 0) {
            sr.renderi(null, barX, barY, fill, 6, 0.85F, 0.42F, 0.16F, 1.0F, null);
        }

        // Our own label, never the engine's string: several arrive as raw translation keys, and
        // the texture-pack one announces a different pack name dozens of times.
        tm.DrawStringCentre(big, w / 2.0, barY - 44.0,
                            BootPhases.labelFor(PHASES.currentIndex()), 0.92, 0.93, 0.95, 1.0);

        long tenths = PHASES.elapsedMs(now) / 100L;
        String detail = (int) (frac * 100.0) + "%      " + step + " / " + BootPhases.ORDER.length
                        + "      " + (tenths / 10L) + "." + (tenths % 10L) + "s";
        tm.DrawStringCentre(small, w / 2.0, barY + 16.0, detail, 0.52, 0.55, 0.60, 1.0);
    }

    /**
     * The figure, held once drawable.
     *
     * AnimatedTextures caches by RESOLVED path, and that mapping changes as mods register -- so
     * the same call returns one instance early in boot and a different, unloaded one later.
     * Keeping the instance that became ready is what stops it vanishing mid-boot.
     */
    public static AnimatedTexture walkTexture() {
        AnimatedTexture held = walkTex;
        if (held != null && held.isReady()) {
            return held;
        }
        try {
            AnimatedTexture fresh = AnimatedTextures.getTexture(WALK_TEXTURE);
            if (fresh != null && fresh.isReady()) {
                walkTex = fresh;
                return fresh;
            }
        } catch (Throwable ignored) {
            // Cosmetic; the bar does not depend on it.
        }
        return held;
    }

    /** Queued at the first phase and promoted, or it waits behind the whole boot backlog. */
    public static void requestWalkTexture() {
        try {
            DemandPriority.boost = true;
            AnimatedTextures.getTexture(WALK_TEXTURE);
        } catch (Throwable ignored) {
            // Cosmetic.
        } finally {
            DemandPriority.boost = false;
        }
    }

    public static void pumpAssets(long now) {
        if (walkReadyAtMs >= 0L || PUMP_INTERVAL_MS <= 0L) return;
        if (PHASES.elapsedMs(now) > PUMP_WINDOW_MS || now - lastPumpAt < PUMP_INTERVAL_MS) return;
        lastPumpAt = now;
        pumpCalls++;
        try {
            if (zombie.GameWindow.fileSystem != null) {
                zombie.GameWindow.fileSystem.updateAsyncTransactions();
            }
        } catch (Throwable ignored) {
            // Cosmetic.
        }
    }

    // ---------------------------------------------------------------- engine hooks

    /** Suppresses the engine's standalone notice frame; body() draws the text instead. */
    @Patch(className = "zombie.GameWindow", methodName = "doEpilepsyWarningText")
    public static class EpilepsyWarning {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter() {
            if (!ON || WARNING_MS < 0L) {
                return false;
            }
            if (WARNING_MS > 0L) {
                warningUntil = System.currentTimeMillis() + WARNING_MS;
            }
            BootProgress.forceDraw();
            return true;
        }
    }

    @Patch(className = "zombie.core.Core", methodName = "EndFrameUI")
    public static class FramePaint {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.paintInto();
        }
    }

    /** MainScreenState.enter builds the whole front end with nothing painting; hold the screen. */
    @Patch(className = "zombie.gameStates.MainScreenState", methodName = "enter")
    public static class MenuHandover {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.note("__final__");
            BootProgress.forceDraw();
            BootProgress.report();
        }
    }

    @Patch(className = "zombie.GameWindow", methodName = "DoLoadingText")
    public static class Phase {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String text) {
            BootProgress.note(text);
            BootProgress.tick();
        }
    }

    /** Mod enumeration: the first phase, during which nothing else runs. */
    @Patch(className = "zombie.ZomboidFileSystem", methodName = "loadMod")
    public static class ModPump {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.tick();
        }
    }

    @Patch(className = "zombie.Lua.LuaManager", methodName = "RunLua")
    public static class LuaFile {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.tick();
        }
    }

    @Patch(className = "zombie.scripting.ScriptManager", methodName = "LoadFile")
    public static class ScriptFile {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.tick();
        }
    }

    /** Covers every parser, not just script files: sprite models, customization, tile geometry. */
    @Patch(className = "zombie.scripting.ScriptParser", methodName = "parseTokens")
    public static class ParserPump {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.tick();
        }
    }

    /** The script phase keeps building objects long after the files are read. */
    @Patch(className = "zombie.scripting.ScriptManager", methodName = "CreateFromToken")
    public static class TokenPump {
        @Patch.OnEnter
        public static void enter() {
            if ((++tokenCalls & 255) == 0) {
                BootProgress.tick();
            }
        }
    }

    /** The model and animation phase, which polls here while meshes load. */
    @Patch(className = "zombie.fileSystem.FileSystemImpl", methodName = "updateAsyncTransactions")
    public static class AssetPump {
        @Patch.OnEnter
        public static void enter() {
            BootProgress.tick();
        }
    }
}
