package lugli.fastloading;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The boot phase model behind the loading screen: which phase we are in, and how far through.
 *
 * WHY A LEARNED MODEL AND NOT A COUNTER
 *   The engine announces eight phases via GameWindow.DoLoadingText, but they are wildly uneven --
 *   on a large mod list the script and Lua phases dominate and the texture-pack phase repeats once
 *   per pack. A bar driven by "phase 3 of 8" would sit still for twenty seconds and then jump,
 *   which is worse than no bar. So each phase's duration is recorded and reused next boot: the
 *   first run is a rough estimate, every run after is shaped like the machine's real boot.
 *
 * Free of zombie.* imports so the build can unit-test it.
 */
public final class BootPhases {

    /**
     * Ordered by the sequence the engine ACTUALLY announces, read out of a real boot log rather
     * than inferred from source line numbers -- the first version had clothing after lua and was
     * wrong. Observed:
     *
     *   Loading Mods -> UI_Loading_Texturepack -> Loading Translations -> Loading UI texture pack
     *   ... -> Loading Scripts -> Loading Clothing -> Loading Lua -> Loading Tiles2x texture pack
     *   ... -> Models and Animations -> OnGameBoot
     */
    public static final String[] ORDER = {
        "mods", "translations", "scripts", "clothing", "lua", "models", "boot"
    };

    /**
     * What the player reads. The engine's own strings are not usable: several arrive as raw
     * translation keys -- a real boot draws the literal text "UI_Loading_Texturepack" -- and the
     * texture-pack phase announces a different pack name dozens of times, which flickers.
     */
    public static final String[] LABELS = {
        "Loading mods", "Loading translations", "Loading scripts",
        "Loading clothing", "Loading Lua", "Loading models and animations", "Starting up"
    };

    public static String labelFor(int index) {
        return index < 0 || index >= LABELS.length ? "Loading" : LABELS[index];
    }

    /** Fallback weights, used only until a real boot has been recorded. Sum need not be 1. */
    private static final double[] FALLBACK = { 0.15, 0.02, 0.17, 0.02, 0.14, 0.41, 0.09 };

    private final Map<String, Long> durations = new LinkedHashMap<>();
    private int index = -1;
    private long phaseStart;
    private long bootStart;

    /**
     * Maps an engine loading string to a phase key.
     *
     * Matched on distinctive substrings rather than equality: the engine passes these through
     * Translator, so the visible text is localised and differs per language, while the
     * translation KEYS it looks up do not. Falls back to null, which leaves the phase unchanged
     * rather than resetting the bar.
     */
    public static String keyFor(String text) {
        if (text == null) {
            return null;
        }
        String t = text.toLowerCase(java.util.Locale.ROOT);
        // ORDER MATTERS, and it is not obvious: "Models and Animations" contains "mod", so a
        // mods-first test classifies the second-to-last phase as the first one and the bar jumps
        // backwards at the end of every boot. The specific phases are therefore tested first and
        // "mods" is left until last. A unit test caught this; nothing in game would have.
        if (t.contains("model") || t.contains("anim")) return "models";
        if (t.contains("translation")) return "translations";
        // NOT A PHASE. Texture packs are announced throughout boot -- one before translations
        // and dozens more after Lua -- so treating them as a step made the bar skip translations
        // entirely and flicker its label early on. Returning null leaves the phase unchanged.
        if (t.contains("texture")) return null;
        if (t.contains("script")) return "scripts";
        if (t.contains("lua")) return "lua";
        if (t.contains("cloth")) return "clothing";
        if (t.contains("boot") || t.equals("__final__")) return "boot";
        if (t.contains("mod")) return "mods";
        return null;
    }

    public static int indexOf(String key) {
        if (key == null) {
            return -1;
        }
        for (int i = 0; i < ORDER.length; i++) {
            if (ORDER[i].equals(key)) {
                return i;
            }
        }
        return -1;
    }

    public void begin(long now) {
        bootStart = now;
        phaseStart = now;
    }

    /**
     * Advances to a phase. Returns true only when the phase actually moved forward.
     *
     * MONOTONIC BY CONSTRUCTION, and that is not a nicety. Texture packs are announced
     * throughout boot -- before translations and again after Lua -- so a plain "set the index"
     * sends the bar from step 6 back to step 3 midway through, which is exactly what a player
     * sees as the bar jumping backwards. A progress bar that can retreat is worse than none.
     */
    public boolean enter(String key, long now) {
        int i = indexOf(key);
        if (i < 0 || i <= index) {
            return false;
        }
        if (index >= 0) {
            durations.put(ORDER[index], Math.max(1L, now - phaseStart));
        }
        index = i;
        phaseStart = now;
        return true;
    }

    public int currentIndex() {
        return index;
    }

    public String currentKey() {
        return index < 0 ? null : ORDER[index];
    }

    public long elapsedMs(long now) {
        return bootStart == 0L ? 0L : now - bootStart;
    }

    /** Weight of a phase as a share of the whole boot, from the learned table or the fallback. */
    private double weight(int i, Map<String, Long> learned, double total) {
        Long d = learned.get(ORDER[i]);
        if (d != null && total > 0.0) {
            return d / total;
        }
        return FALLBACK[i];
    }

    /**
     * Fraction complete, 0..1, monotonic. Never returns 1.0 -- the bar reaching the end before
     * the menu appears reads as a hang, so it saturates just short.
     */
    public double fraction(Map<String, Long> learned, long now) {
        if (index < 0) {
            return 0.0;
        }
        double total = 0.0;
        for (String k : ORDER) {
            Long d = learned.get(k);
            if (d != null) {
                total += d;
            }
        }
        double done = 0.0;
        for (int i = 0; i < index; i++) {
            done += weight(i, learned, total);
        }
        double span = weight(index, learned, total);
        Long expect = learned.get(ORDER[index]);
        if (expect != null && expect > 0L) {
            double within = (now - phaseStart) / (double) expect;
            if (within > 1.0) {
                within = 1.0;
            }
            done += span * within;
        } else {
            done += span * 0.5;         // no history: sit mid-phase rather than pretend
        }
        double scale = 0.0;
        for (int i = 0; i < ORDER.length; i++) {
            scale += weight(i, learned, total);
        }
        if (scale > 0.0) {
            done /= scale;
        }
        if (done < 0.0) return 0.0;
        return done > 0.985 ? 0.985 : done;
    }

    public Map<String, Long> recorded(long now) {
        Map<String, Long> out = new LinkedHashMap<>(durations);
        if (index >= 0) {
            out.put(ORDER[index], Math.max(1L, now - phaseStart));
        }
        return out;
    }

    // ------------------------------------------------------------------ persistence

    public static Path storePath(String userHome) {
        return Paths.get(userHome, "Zomboid", "fastloading-boot.txt");
    }

    public static Map<String, Long> load(Path p) {
        Map<String, Long> out = new LinkedHashMap<>();
        try {
            if (!Files.exists(p)) {
                return out;
            }
            for (String line : Files.readAllLines(p, StandardCharsets.UTF_8)) {
                int eq = line.indexOf('=');
                if (eq <= 0) {
                    continue;
                }
                String k = line.substring(0, eq).trim();
                if (indexOf(k) < 0) {
                    continue;
                }
                try {
                    long v = Long.parseLong(line.substring(eq + 1).trim());
                    if (v > 0L && v < 600000L) {
                        out.put(k, v);
                    }
                } catch (NumberFormatException ignored) {
                    // a corrupt line just means that phase has no history
                }
            }
        } catch (IOException | RuntimeException ignored) {
            out.clear();
        }
        return out;
    }

    public static void save(Path p, Map<String, Long> durations) {
        try {
            StringBuilder sb = new StringBuilder(256);
            for (String k : ORDER) {
                Long v = durations.get(k);
                if (v != null) {
                    sb.append(k).append('=').append(v).append('\n');
                }
            }
            if (sb.length() > 0) {
                Files.createDirectories(p.getParent());
                Files.write(p, sb.toString().getBytes(StandardCharsets.UTF_8));
            }
        } catch (IOException | RuntimeException ignored) {
            // a boot screen must never be the reason a launch fails
        }
    }
}
