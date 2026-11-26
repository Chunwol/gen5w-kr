package kr.gen5w.ui;

/**
 * Pure-Java value snapshot for stock PhoneProjection Settings.System keys that become hidden
 * from the stock settings menu once wireless projection features are declared.
 */
public class ProjectionSettings {
    public static final String KEY_CP_SPLIT = "cp_split";
    public static final String KEY_AA_SPLIT = "aa_split";
    public static final String KEY_CP_ENABLE = "cp_enable";
    public static final String KEY_AA_ENABLE = "aa_enable";
    public static final String KEY_CP_RHD = "cp_rhd";

    private static final String UNKNOWN = "unknown";

    public static final class Snapshot extends ProjectionSettings {
        private Snapshot(String cpSplit, String aaSplit, String cpEnable, String aaEnable, String cpRhd) {
            super(cpSplit, aaSplit, cpEnable, aaEnable, cpRhd);
        }

        public static Snapshot unknown() {
            return new Snapshot(UNKNOWN, UNKNOWN, UNKNOWN, UNKNOWN, UNKNOWN);
        }

        /** Normalizes raw Settings.System ints (null or < 0 means unset) matching stock V039 getters (off when unset). */
        public static Snapshot fromValues(
                Integer cpSplit, Integer aaSplit, Integer cpEnable, Integer aaEnable, Integer cpRhd) {
            return new Snapshot(
                    toState(cpSplit),
                    toState(aaSplit),
                    toState(cpEnable),
                    toState(aaEnable),
                    toState(cpRhd));
        }
    }

    private final String cpSplit;
    private final String aaSplit;
    private final String cpEnable;
    private final String aaEnable;
    private final String cpRhd;

    protected ProjectionSettings(String cpSplit, String aaSplit, String cpEnable, String aaEnable, String cpRhd) {
        this.cpSplit = cpSplit;
        this.aaSplit = aaSplit;
        this.cpEnable = cpEnable;
        this.aaEnable = aaEnable;
        this.cpRhd = cpRhd;
    }

    public static Snapshot unknown() {
        return Snapshot.unknown();
    }

    public static Snapshot fromValues(
            Integer cpSplit, Integer aaSplit, Integer cpEnable, Integer aaEnable, Integer cpRhd) {
        return Snapshot.fromValues(cpSplit, aaSplit, cpEnable, aaEnable, cpRhd);
    }

    private static String toState(Integer value) {
        return value != null && value.intValue() == 1 ? "on" : "off";
    }

    public static boolean isTerminalResult(String token, String result) {
        return token != null && result != null
                && (result.equals(token + ":ok") || result.startsWith(token + ":failed"));
    }

    public static boolean isTimedOut(String token, boolean writeFailed, long elapsedMs, long timeoutMs, String result) {
        return token != null && !writeFailed && !isTerminalResult(token, result)
                && (elapsedMs < 0 || elapsedMs >= timeoutMs);
    }

    public static boolean isPending(String token, boolean writeFailed, long elapsedMs, long timeoutMs, String result) {
        return token != null && !writeFailed && elapsedMs >= 0 && elapsedMs < timeoutMs
                && !isTerminalResult(token, result);
    }

    public static String effectiveState(String key, String pendingKey, String pendingState, boolean pending, ProjectionSettings current) {
        if (pending && key != null && key.equals(pendingKey) && ("on".equals(pendingState) || "off".equals(pendingState))) {
            return pendingState;
        }
        return current == null ? UNKNOWN : current.state(key);
    }

    public String cpSplit() { return cpSplit; }
    public String aaSplit() { return aaSplit; }
    public String cpEnable() { return cpEnable; }
    public String aaEnable() { return aaEnable; }
    public String cpRhd() { return cpRhd; }

    public String state(String key) {
        if (KEY_CP_SPLIT.equals(key)) return cpSplit;
        if (KEY_AA_SPLIT.equals(key)) return aaSplit;
        if (KEY_CP_ENABLE.equals(key)) return cpEnable;
        if (KEY_AA_ENABLE.equals(key)) return aaEnable;
        if (KEY_CP_RHD.equals(key)) return cpRhd;
        return UNKNOWN;
    }
}
