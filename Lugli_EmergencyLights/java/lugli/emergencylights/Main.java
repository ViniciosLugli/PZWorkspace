package lugli.emergencylights;

/** ZombieBuddy entry point for Lugli - Emergency Lights. */
public final class Main {

    public static final String VERSION = "1.0.0";

    /** Bumped on every ADDITIVE release. Printed at load; no Lua global exposes it. */
    public static final int API = 1;

    private Main() {}

    /** MAIN phase, and the ONLY phase this mod participates in. */
    public static void main(String[] args) {
        System.out.println("[EmergencyLights] loaded, v" + VERSION + " api=" + API);
        WorldLight.announce();
        HeldPoint.announce();
    }

}
