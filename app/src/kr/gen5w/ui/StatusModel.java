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
    private final String boot;
    private final String adbHealth, adbResult;
    private final String host, relay, backend, version, wlan;
    private final boolean apguardOff, wired;
    private final String why;
    private final String whyRaw; // the supervisor's own line (English), or "" when none or unknown
    private final String swWireless, swTimer, swBluelink, swAdb; // on / off / unknown
    private final String removed; // "<number>:<working|done|failed|none>[:<package id>]"
    private final String saved; // "<number>:<usb|nousb|fail|working|none>"
    private boolean portable, portableDisabled;
    private String swDebug = UNKNOWN;
    private String dongle = UNKNOWN;
    private boolean twoGhzOnly;
    public String switchDebug() { return swDebug; }
    /** The dongle service's state this boot: ready, waiting, loading, failed, blocked, 2g or unknown. */
    public String dongle() { return dongle; }
    /** The Wi-Fi this install chose, as shown on the screen. */
    public String wifiTypeText() {
        if (backend.equals("builtin")) return "내장 Wi-Fi";
        if (backend.equals("dongle")) return "USB 동글";
        return backend.equals("none") ? "없음 (무선 사용 불가)" : "확인 못 함";
    }
    /** What the driver needs from the user right now, in the words the screen shows. */
    public String dongleText() {
        if (backend.equals("builtin")) return "해당 없음 (이 차는 내장 Wi-Fi)";
        if (backend.equals("none")) return twoGhzOnly ? "2.4GHz 전용 동글. 5GHz 동글로 다시 설치하세요" : "지원 동글 없음. 5GHz 동글을 꽂고 다시 설치하세요";
        if (!backend.equals("dongle")) return "확인 못 함";
        if (dongle.equals("ready")) return "연결됨";
        if (dongle.equals("waiting")) return "5GHz 지원 동글을 꽂아 주세요";
        if (dongle.equals("loading")) return "드라이버 준비 중";
        if (dongle.equals("failed")) return "드라이버 실패. 동글을 뽑았다 다시 꽂으세요";
        if (dongle.equals("blocked")) return "재시작 보호로 멈춤. 동글을 뽑았다 다시 꽂으세요";
        if (dongle.equals("2g")) return "2.4GHz 전용 동글. 5GHz 동글을 꽂아 주세요";
        return "동글 방식으로 설치됨 (설치 때 정함)";
    }
    public boolean portable() { return portable; }
    public boolean portableRemovalDone() { return portable && portableDisabled && removed.matches("[0-9]+:done"); }
    private RecoveryStatus recovery = RecoveryStatus.parse(null);
    public RecoveryStatus recovery() { return recovery; }

    private StatusModel(boolean readable, long ts, long now, String host, String relay, String backend,
            String version, boolean apguardOff, boolean wired, String why, String whyRaw,
            String swWireless, String swTimer, String swBluelink, String swAdb, String saved, String removed, String wlan, String boot, String adbHealth, String adbResult) {
        this.readable = readable; this.ts = ts; this.now = now; this.host = host; this.relay = relay;
        this.backend = backend; this.version = version; this.apguardOff = apguardOff; this.wired = wired;
        this.why = why; this.whyRaw = whyRaw;
        this.swWireless = swWireless; this.swTimer = swTimer; this.swBluelink = swBluelink; this.swAdb = swAdb; this.saved = saved; this.removed = removed; this.wlan = wlan;
        this.boot = boot;
        this.adbHealth = adbHealth;
        this.adbResult = adbResult;
    }

    public static StatusModel unreadable() {
        return new StatusModel(false, -1, 0, UNKNOWN, UNKNOWN, UNKNOWN, "", false, false, "", "", UNKNOWN, UNKNOWN, UNKNOWN, UNKNOWN, "0:none", "0:none", UNKNOWN, "", UNKNOWN, "0:none");
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
        StatusModel parsed = new StatusModel(true, ts, nowSeconds, host,
                choice(value(statusLines, "relay"), "on", "off"),
                backend.length() == 0 ? UNKNOWN : backend, value(statusLines, "version"),
                "off".equals(value(statusLines, "apguard")), "yes".equals(value(statusLines, "wired")),
                reason(host, logLines), reasonRaw(host, logLines),
                choice(value(statusLines, "sw_wireless"), "on", "off"),
                choice(value(statusLines, "sw_timer"), "on", "off"),
                choice(value(statusLines, "sw_bluelink"), "on", "off"),
                choice(value(statusLines, "sw_adb"), "on", "off"),
                value(statusLines, "saved").length() == 0 ? "0:none" : value(statusLines, "saved"),
                value(statusLines, "removed").length() == 0 ? "0:none" : value(statusLines, "removed"),
                choice(value(statusLines, "wlan"), "present", "missing"), value(statusLines, "boot"),
                value(statusLines, "adb_health"), value(statusLines, "adb_result"));
        parsed.portableDisabled = "0".equals(value(statusLines, "portable_enabled"));
        parsed.portable = "0".equals(value(statusLines, "portable_enabled")) || "1".equals(value(statusLines, "portable_enabled"));
        parsed.recovery = RecoveryStatus.parse(statusLines);
        parsed.swDebug = choice(value(statusLines, "sw_debug"), "on", "off");
        String dongle = value(statusLines, "dongle");
        parsed.dongle = dongle.matches("ready|waiting|loading|failed|blocked|2g") ? dongle : UNKNOWN;
        parsed.twoGhzOnly = "2g-only".equals(value(statusLines, "wifi_why"));
        return parsed;
    }

    /** The bridge supervisor's own last explanation line, only while the host is not running; null when none. */
    private static String lastWait(String host, List<String> logLines) {
        if (!host.equals("dead") || logLines == null) return null;
        String last = null;
        for (String line : logLines) {
            if (line == null || !line.startsWith("bridge|")) continue;
            String raw = line.substring("bridge|".length());
            if (raw.startsWith("WAIT bridge:") || raw.startsWith("FAIL bridge:")) last = raw;
        }
        return last;
    }

    private static String reason(String host, List<String> logLines) {
        if (!host.equals("dead")) return "";
        String last = lastWait(host, logLines);
        return last == null ? "원인을 확인하지 못했습니다" : LogTranslator.translate(last);
    }

    private static String reasonRaw(String host, List<String> logLines) {
        String last = lastWait(host, logLines);
        return last == null ? "" : last;
    }

    public boolean readable() { return readable; }
    public String bootId() { return boot; }
    public String adbHealth() { return adbHealth; }
    public String adbResult() { return adbResult; }
    /** Heartbeats are observations, not proof of route reception or physical display output. */
    public static String hudOwner(List<String> lines, long nowSeconds) {
        if (lines == null || lines.size() != 1) return "NO_RESPONSE";
        String[] fields = lines.get(0).split(" ");
        if (fields.length != 2) return "NO_RESPONSE";
        try {
            long at = Long.parseLong(fields[0]);
            if (at < 0 || nowSeconds < at || nowSeconds - at > 5) return "NO_RESPONSE";
        } catch (NumberFormatException e) { return "NO_RESPONSE"; }
        String owner = fields[1];
        return owner.equals("UNKNOWN") || owner.equals("STOCK") || owner.equals("AA") || owner.equals("CARPLAY")
                ? owner : "NO_RESPONSE";
    }
    /** Recheck elapsed uptime at action time: a parsed model can age while the screen stays open. */
    public boolean canControl(long nowSeconds) {
        return readable && SwitchRequest.validBoot(boot) && ts >= 0
                && nowSeconds >= ts - SKEW_SECONDS && nowSeconds - ts <= STALE_SECONDS;
    }
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
    /** Whether the car's Wi-Fi interface exists right now: present / missing / unknown. */
    public String wlan() { return wlan; }
    /** State of the screen switch as the collector saw the marker: on, off or unknown. */
    public String switchWireless() { return swWireless; }
    public String switchTimer() { return swTimer; }
    public String switchBluelink() { return swBluelink; }
    public String switchAdb() { return swAdb; }
    /** Last diagnosis save as the collector reported it, "<number>:<result>". */
    public String savedState() { return saved; }
    /** Last in-car removal, "<number>:<result>[:<package id>]". */
    public String removedState() { return portable && !portableDisabled && removed.matches("[0-9]+:done") ? "0:none" : removed; }
    public boolean apguardOff() { return apguardOff; }
    public boolean wiredOnly() { return wired; }
    public String why() { return why; }
    /** The same reason as the supervisor wrote it (English), for the English screen. */
    public String whyRaw() { return whyRaw; }
}
