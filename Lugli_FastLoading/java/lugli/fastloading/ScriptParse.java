package lugli.fastloading;

import java.util.ArrayList;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLog;

/**
 * Two fixes to zombie.scripting.ScriptParser, the tokenizer every script, tile geometry, seam,
 * seating and font file passes through. -Dfastloading.parse=off restores the engine's.
 *
 * 1. stripComments is NOT THREAD SAFE: one static StringBuilder serves every caller, so two
 *    threads inside it destroy each other's buffer. Most callers catch and log, so the failure
 *    is silent. Any off-thread parsing anywhere depends on this fix being active.
 * 2. parseTokens re-copies the remainder of the file per item, which is quadratic in file size.
 *
 * A wrong tokenizer does not crash, it changes what items are. The replacement is run against
 * the engine's own on real input and disables itself on the first disagreement.
 */
public final class ScriptParse {

    public static final String TAG = "[FastLoading/parse]";
    public static final boolean ON = !"off".equals(System.getProperty("fastloading.parse"));

    /** Differential checks to run before trusting the fast path. */
    public static final int VERIFY_CALLS = 400;
    /** ...at least one of which must be this big, or the check has proved nothing. */
    public static final int VERIFY_CHARS = 100000;
    /**
     * Hard ceiling on differential checks. Verifying every call would double the tokenizer's cost,
     * so the check runs on a sample and stops once the replacement has proved itself.
     */
    public static final int VERIFY_CEILING = 4000;

    // public: these bodies are inlined into zombie.* classes and accessed from there.
    public static volatile boolean broken;
    public static int tokenChecks, stripChecks;
    public static int tokenBigSeen, stripBigSeen;
    public static boolean announced;
    public static long tokenCalls, stripCalls, stripSkipped;

    private ScriptParse() {}

    // ---- stripComments ------------------------------------------------------------------

    /**
     * The original algorithm with the buffer owned by this call.
     * Line for line from ScriptParser.stripComments; only the builder changed.
     */
    public static String strip(String totalFile) {
        if (totalFile == null) return null;
        if (totalFile.indexOf("*/") < 0) return totalFile;

        StringBuilder sb = new StringBuilder(totalFile);
        int end = sb.lastIndexOf("*/");

        while (end != -1) {
            int start = sb.lastIndexOf("/*", end - 1);
            if (start == -1) break;

            int innerCommentEnd = sb.lastIndexOf("*/", end - 1);
            while (innerCommentEnd > start) {
                int innerCommentStart = start;
                start = sb.lastIndexOf("/*", start - 2);
                if (start == -1) break;
                innerCommentEnd = sb.lastIndexOf("*/", innerCommentStart - 2);
            }
            if (start == -1) break;

            sb.replace(start, end + 2, "");
            end = sb.lastIndexOf("*/", start);
        }

        return sb.toString();
    }

    // ---- parseTokens --------------------------------------------------------------------

    /**
     * Identical scan to the original, with a moving base offset rather than a fresh
     * substring of the remainder each round.
     */
    public static ArrayList<String> tokens(String s) {
        ArrayList<String> tokens = new ArrayList<>();
        if (s == null) return tokens;
        int base = 0;

        while (true) {
            int depth = 0;
            int o = base;
            int c = base;
            if (s.indexOf('}', base + 1) == -1) {
                String tail = s.substring(base).trim();
                if (!tail.isEmpty()) tokens.add(tail);
                return tokens;
            }

            do {
                o = s.indexOf('{', o + 1);
                c = s.indexOf('}', c + 1);
                if ((c >= o || c == -1) && o != -1) {
                    c = o;
                    depth++;
                } else {
                    o = c;
                    depth--;
                }
            } while (depth > 0);

            // Unbalanced braces. The original spins here forever, so hand it back rather
            // than reproducing an engine hang inside our own code.
            if (o < 0) throw new IllegalStateException("unbalanced braces");

            tokens.add(s.substring(base, o + 1).trim());
            base = o + 1;
        }
    }

    // ---- the originals, for the differential check --------------------------------------

    /**
     * ScriptParser.stripComments verbatim, on a local builder. Used only by the self-test,
     * so the comparison is against the original ALGORITHM without reintroducing the race.
     */
    public static String stripReference(String totalFile) {
        StringBuilder sb = new StringBuilder();
        sb.append(totalFile);
        int end = sb.lastIndexOf("*/");
        while (end != -1) {
            int start = sb.lastIndexOf("/*", end - 1);
            if (start == -1) break;
            int innerCommentEnd = sb.lastIndexOf("*/", end - 1);
            while (innerCommentEnd > start) {
                int innerCommentStart = start;
                start = sb.lastIndexOf("/*", start - 2);
                if (start == -1) break;
                innerCommentEnd = sb.lastIndexOf("*/", innerCommentStart - 2);
            }
            if (start == -1) break;
            sb.replace(start, end + 2, "");
            end = sb.lastIndexOf("*/", start);
        }
        return sb.toString();
    }

    /** ScriptParser.parseTokens verbatim. */
    public static ArrayList<String> tokensReference(String totalFile) {
        ArrayList<String> tokens = new ArrayList<>();
        while (true) {
            int depth = 0;
            int nextindexOfOpen = 0;
            int nextindexOfClosed = 0;
            if (totalFile.indexOf("}", nextindexOfOpen + 1) == -1) {
                if (!totalFile.trim().isEmpty()) tokens.add(totalFile.trim());
                return tokens;
            }
            do {
                nextindexOfOpen = totalFile.indexOf("{", nextindexOfOpen + 1);
                nextindexOfClosed = totalFile.indexOf("}", nextindexOfClosed + 1);
                if ((nextindexOfClosed >= nextindexOfOpen || nextindexOfClosed == -1)
                        && nextindexOfOpen != -1) {
                    nextindexOfClosed = nextindexOfOpen;
                    depth++;
                } else {
                    nextindexOfOpen = nextindexOfClosed;
                    depth--;
                }
            } while (depth > 0);
            if (nextindexOfOpen < 0) throw new IllegalStateException("unbalanced braces");
            tokens.add(totalFile.substring(0, nextindexOfOpen + 1).trim());
            totalFile = totalFile.substring(nextindexOfOpen + 1);
        }
    }

    // ---- entry points called from the inlined advice ------------------------------------

    public static String doStrip(String totalFile) {
        stripCalls++;
        String out = strip(totalFile);
        if (out == totalFile) stripSkipped++;

        if (wantCheck(stripChecks, stripBigSeen, "stripComments")) {
            stripChecks++;
            if (totalFile != null && totalFile.length() >= VERIFY_CHARS) stripBigSeen++;
            String ref = stripReference(totalFile);
            if (!ref.equals(out)) {
                broken = true;
                DebugLog.log(TAG + " DEFECT: stripComments disagreed, reverting to the engine's own");
                return ref;
            }
        }
        announce();
        return out;
    }

    public static ArrayList<String> doTokens(String totalFile) {
        tokenCalls++;
        ArrayList<String> out = tokens(totalFile);

        if (wantCheck(tokenChecks, tokenBigSeen, "parseTokens")) {
            tokenChecks++;
            if (totalFile != null && totalFile.length() >= VERIFY_CHARS) tokenBigSeen++;
            ArrayList<String> ref = tokensReference(totalFile);
            if (!ref.equals(out)) {
                broken = true;
                DebugLog.log(TAG + " DEFECT: parseTokens disagreed, reverting to the engine's own");
                return ref;
            }
        }
        announce();
        return out;
    }

    public static boolean weakEvidenceReported;

    // Sample early and often, then taper: a defect shows up on the first few files or not at all.
    public static boolean wantCheck(int checks, int bigSeen, String what) {
        if (checks >= VERIFY_CEILING) {
            if (bigSeen == 0 && !weakEvidenceReported) {
                weakEvidenceReported = true;
                DebugLog.log(TAG + " " + what + " verified on " + checks
                             + " calls but never saw an input of " + VERIFY_CHARS
                             + "+ chars; continuing on weaker evidence than intended");
            }
            return false;
        }
        return checks < VERIFY_CALLS || bigSeen == 0;
    }

    public static void announce() {
        if (announced) return;
        announced = true;
        DebugLog.log(TAG + " script tokenizer: per-call buffer (thread safe) and linear token scan");
    }

    /** Called from the status bridge so a failed install is visible rather than silent. */
    public static String status() {
        if (!ON) return "off";
        if (broken) return "DEFECT";
        return "ok, " + stripCalls + " strips (" + stripSkipped + " with no comment to strip), "
               + tokenCalls + " tokenizations; verified on "
               + stripBigSeen + "/" + tokenBigSeen + " large inputs";
    }

    // ---- patches ------------------------------------------------------------------------

    /**
     * Replacing stripComments is what makes the tile geometry prefetch safe. It must stay
     * installed for as long as TileGeometryPrefetch exists; see the class comment.
     */
    @Patch(className = "zombie.scripting.ScriptParser", methodName = "stripComments")
    public static class Strip {
        @Patch.OnEnter(skipOn = true)
        public static boolean in(@Patch.Argument(0) String totalFile) {
            return ON && !broken && totalFile != null;
        }

        @Patch.OnExit
        public static void out(@Patch.Argument(0) String totalFile,
                               @Patch.Return(readOnly = false) String ret) {
            if (!ON || broken || totalFile == null) return;
            try {
                ret = ScriptParse.doStrip(totalFile);
            } catch (Throwable t) {
                broken = true;
                DebugLog.log(TAG + " stripComments disabled (" + t + ")");
                ret = ScriptParse.stripReference(totalFile);
            }
        }
    }

    @Patch(className = "zombie.scripting.ScriptParser", methodName = "parseTokens")
    public static class Tokens {
        @Patch.OnEnter(skipOn = true)
        public static boolean in(@Patch.Argument(0) String totalFile) {
            return ON && !broken && totalFile != null;
        }

        @Patch.OnExit
        public static void out(@Patch.Argument(0) String totalFile,
                               @Patch.Return(readOnly = false) ArrayList<String> ret) {
            if (!ON || broken || totalFile == null) return;
            try {
                ret = ScriptParse.doTokens(totalFile);
            } catch (Throwable t) {
                broken = true;
                DebugLog.log(TAG + " parseTokens disabled (" + t + ")");
                ret = ScriptParse.tokensReference(totalFile);
            }
        }
    }
}
