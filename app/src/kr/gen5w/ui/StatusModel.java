package kr.gen5w.ui;

import java.util.List;

/** What the INFO page shows, parsed from the snapshot and log files. Free of Android types. */
// Times are seconds since boot (the collector writes /proc/uptime), not wall-clock time: the car's clock may be unset.
public final class StatusModel {
    static final long STALE_SECONDS = 60;
    static final long SKEW_SECONDS = 5;
    private static final String UNKNOWN = "unknown";

    private final boolean readable;
    private final long ts;          // -1 when missing or not a number
    private final long now;
    private final String host, relay, backend, version;
    private final boolean apguardOff, wired;
    private final String why;

    private StatusModel(boolean readable, long ts, long now, String host, String relay, String backend,
            String version, boolean apguardOff, boolean wired, String why) {
        this.readable = readable; this.ts = ts; this.now = now; this.host = host; this.relay = relay;
        this.backend = backend; this.version = version; this.apguardOff = apguardOff; this.wired = wired;
        this.why = why;
    }

    public static StatusModel unreadable() {
        return new StatusModel(false, -1, 0, UNKNOWN, UNKNOWN, UNKNOWN, "", false, false, "");
    }

    private static String value(List<String> lines, String key) {
        String prefix = key + "=";
        for (String line : lines) if (line != null && line.startsWith(prefix)) return line.substring(prefix.length());
        return "";
    }

    private static String choice(String value, String a, String b) {
        return value.equals(a) || value.equals(b) ? value : UNKNOWN;
    }

    /** @param logLines "source|raw line" entries, oldest first; may be null */
    public static StatusModel parse(List<String> statusLines, List<String> logLines, long nowSeconds) {
        if (statusLines == null) return unreadable();
        long ts = -1;
        try { ts = Long.parseLong(value(statusLines, "ts")); } catch (NumberFormatException e) { ts = -1; }
        String host = choice(value(statusLines, "host"), "alive", "dead");
        String backend = value(statusLines, "backend");
        return new StatusModel(true, ts, nowSeconds, host,
                choice(value(statusLines, "relay"), "on", "off"),
                backend.length() == 0 ? UNKNOWN : backend, value(statusLines, "version"),
                "off".equals(value(statusLines, "apguard")), "yes".equals(value(statusLines, "wired")),
                reason(host, logLines));
    }

    /** The bridge supervisor's own last explanation, only while the host is not running. */
    private static String reason(String host, List<String> logLines) {
        if (!host.equals("dead")) return "";
        String last = null;
        if (logLines != null) {
            for (String line : logLines) {
                if (line == null || !line.startsWith("bridge|")) continue;
                String raw = line.substring("bridge|".length());
                if (raw.startsWith("WAIT bridge:") || raw.startsWith("FAIL bridge:")) last = raw;
            }
        }
        return last == null ? "원인을 확인하지 못했습니다" : LogTranslator.translate(last);
    }

    public boolean readable() { return readable; }
    /**
     * ts and now are both seconds since boot. A snapshot from a later uptime than now is a
     * leftover from an earlier boot, so it counts as stale too.
     */
    public boolean stale() { return !readable || ts < 0 || now - ts > STALE_SECONDS || ts - now > SKEW_SECONDS; }
    /** Seconds since the snapshot was written, or -1 when unknown or from an earlier boot. */
    public long ageSeconds() { return ts < 0 || ts > now + SKEW_SECONDS ? -1 : Math.max(0, now - ts); }
    public String host() { return host; }
    public String relay() { return relay; }
    public String backend() { return backend; }
    public String bridgeVersion() { return version; }
    public boolean apguardOff() { return apguardOff; }
    public boolean wiredOnly() { return wired; }
    public String why() { return why; }
}
