package lugli.fastloading;

/**
 * Which game states the boot overlay may paint over.
 *
 * Second line of defence behind BootProgress.retire(). The latch says when to stop; this says
 * where it must never draw regardless. Both exist because an off-switch must not live in a file
 * the thing it switches off can ship without.
 *
 * Matches on the class NAME so the class stays free of zombie.* imports and can be unit-tested
 * without the game on the classpath, as BootPhases and Tuning are. This failure is cosmetic and so ships
 * easily: an overlay that paints one state too late still "works".
 */
public final class BootScreenGate {

    /**
     * GameWindow.initShared builds the list as TISLogoState, TermsOfServiceState, MainScreenState
     * (GameWindow.java:223-227). MainScreenState is allowed because the handover paint happens
     * inside its enter(), and GameStateMachine assigns `current` BEFORE calling enter()
     * (GameStateMachine.java:35-38, :88-92), so the state is already set for that last frame.
     *
     * TermsOfServiceState is REFUSED. On a profile that has never accepted the terms
     * (options.ini termsOfServiceVersion=-1, every fresh install) ISTermsOfServiceUI.lua:175
     * marks the state created and it Remains until the player clicks Accept. The overlay used
     * to be allowed there because an accepted profile passes through in one frame; on a fresh
     * one it painted "98% 6/7" over the invisible dialog for as long as the player waited,
     * which reads as a hang in the mod. The accepted case loses one black frame, which the
     * state's own render() presents anyway.
     */
    private static final String[] ALLOWED = {
        "zombie.gameStates.TISLogoState",
        "zombie.gameStates.MainScreenState",
    };

    private BootScreenGate() {}

    /**
     * @param stateClassName GameWindow.states.current's class name, or null when there is none.
     *
     * NULL MEANS BOOT, and is allowed: GameStateMachine.update() is not reached until
     * GameWindow.logic() (GameWindow.java:364), long after the loading text starts.
     *
     * ANYTHING UNRECOGNISED IS REFUSED. Naming the three states this bug painted over and
     * defaulting to allow would let any mod that pushes a state of its own inherit the same bug.
     * The set a boot screen may cover is small and closed; the set it must not cover is open.
     */
    public static boolean paintAllowed(String stateClassName) {
        if (stateClassName == null) {
            return true;
        }
        for (String s : ALLOWED) {
            if (s.equals(stateClassName)) {
                return true;
            }
        }
        return false;
    }
}
