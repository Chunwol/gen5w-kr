package kr.gen5w.hotspot;

import android.net.LocalServerSocket;
import android.net.wifi.IWifiManager;
import android.net.wifi.WifiConfiguration;
import android.os.SystemClock;
import java.io.BufferedReader;
import java.io.FileReader;

/** Shared adapter used by the bridge and explicit helper command. The abstract
 * socket is a cross-process mutex only: no clients, protocol, or credential IO.
 */
public final class AndroidWifiAp implements ApProfiles.Port {
    private final IWifiManager wifi;
    private final Object mutationLock;
    private final ApProfiles.Guard guard;
    private LocalServerSocket lock;
    public AndroidWifiAp(IWifiManager wifi) {
        this(wifi, new Object(), new ApProfiles.Guard() { public void check() { } });
    }
    public AndroidWifiAp(IWifiManager wifi, Object mutationLock, ApProfiles.Guard guard) {
        this.wifi = wifi; this.mutationLock = mutationLock; this.guard = guard;
    }
    public void lock(ApProfiles.Guard guard) throws Exception {
        requireReady();
        requireWpa2(wifi.getWifiApConfiguration());
        long end = now() + 5000;
        do {
            guard.check();
            try { lock = new LocalServerSocket("gen5wkr.ap.control"); return; }
            catch (java.io.IOException occupied) { pause(); }
        } while (now() < end);
        throw new Exception("AP controller busy");
    }
    public void unlock() {
        if (lock != null) try { lock.close(); } catch (java.io.IOException ignored) { }
        lock = null;
    }
    private static ApProfiles.Profile profile(WifiConfiguration config) {
        return config == null ? null : new ApProfiles.Profile(config.SSID, config.preSharedKey,
                config.ConnectivitySSID, config.ConnectivityPSK, config.apMode);
    }
    public ApProfiles.Profile configuration() throws Exception { return profile(wifi.getWifiApConfiguration()); }
    public int state() throws Exception { return wifi.getWifiApEnabledState(); }
    public int mode() throws Exception { return wifi.getWifiApMode(); }
    public void disable() throws Exception {
        synchronized (mutationLock) {
            guard.check(); requireReady(); requireWpa2(wifi.getWifiApConfiguration());
            wifi.setWifiApEnabledForConnectivity(null, false);
        }
    }
    public void enable(ApProfiles.Profile desired) throws Exception {
        synchronized (mutationLock) {
            guard.check(); requireReady();
            WifiConfiguration latest = wifi.getWifiApConfiguration();
            requireWpa2(latest);
            ApProfiles.Profile fresh = profile(latest);
            if (!same(fresh.carplaySsid, desired.carplaySsid) || !same(fresh.carplayKey, desired.carplayKey))
                throw new Exception("CarPlay settings changed");
            WifiConfiguration start = new WifiConfiguration(latest);
            ordinarySsid = null; ordinaryKey = null;
            if (!profileReady()) {
                // Match mode (services.odex stays stock): stock NetworkManagementService
                // starts the AP with SSID/preSharedKey, so carry the CarPlay values
                // there. The stock start also saves them as the ordinary hotspot
                // values; remember the ordinary pair to save it back afterwards.
                if (latest.SSID != null && latest.preSharedKey != null
                        && !(latest.SSID.equals(fresh.carplaySsid) && latest.preSharedKey.equals(fresh.carplayKey))) {
                    ordinarySsid = latest.SSID; ordinaryKey = latest.preSharedKey;
                    carplaySsid = fresh.carplaySsid; carplayKey = fresh.carplayKey;
                }
                start.SSID = fresh.carplaySsid;
                start.preSharedKey = fresh.carplayKey;
            }
            // Profile mode: OEM sets mode 2; the paired native implementation
            // selects CP fields in command-local values, ordinary values untouched.
            markAttempt();
            wifi.setWifiApEnabledForConnectivity(start, true);
            clearBootRestore();
        }
    }
    /** AP start guard. Stock Korean firmware never loads the Wi-Fi driver, so the
     * first AP start is also the first driver load on the car. Before each start,
     * record this boot's id; clear it after a clean failure, or once the AP has
     * stayed up for STABLE_MS. A record left from an earlier boot means the unit
     * restarted during an AP start; the root supervisor counts those and turns
     * wireless off after several in a row (service.sh). Best effort only. */
    static final String GUARD_DIR = "/data/nemesis/gen5wkr.apguard";
    static final long STABLE_MS = 45000;
    private static int attemptGeneration;
    private static synchronized void markAttempt() {
        attemptGeneration++;
        String boot = bootId();
        if (boot == null || !guardDir()) return;
        writeSync(GUARD_DIR + "/attempt", boot);
    }
    public void transitionDone(boolean ok) {
        restoreOrdinary();
        final int generation;
        synchronized (AndroidWifiAp.class) { generation = attemptGeneration; }
        if (!ok) { clearAttempt(generation, false); return; }
        Thread t = new Thread(new Runnable() { public void run() {
            try { Thread.sleep(STABLE_MS); } catch (InterruptedException e) { return; }
            clearAttempt(generation, true);
        } }, "gen5wkr-ap-guard");
        t.setDaemon(true);
        t.start();
    }
    private static synchronized void clearAttempt(int generation, boolean ok) {
        if (generation != attemptGeneration || !guardDir()) return;
        if (ok) writeSync(GUARD_DIR + "/ok", "ok");
        new java.io.File(GUARD_DIR + "/attempt").delete();
    }
    private static boolean guardDir() {
        try {
            java.io.File dir = new java.io.File(GUARD_DIR);
            return dir.isDirectory() && dir.getCanonicalPath().equals(GUARD_DIR);
        } catch (java.io.IOException e) { kr.gen5w.diag.SafeDiagnostic.failure("ap.guard.directory",e);return false; }
    }
    private static String bootId() {
        try {
            BufferedReader r = new BufferedReader(new FileReader("/proc/sys/kernel/random/boot_id"));
            try {
                String id = r.readLine();
                return id != null && id.matches("[0-9a-f-]{8,64}") ? id : null;
            } finally { r.close(); }
        } catch (Exception e) { kr.gen5w.diag.SafeDiagnostic.failure("ap.guard.boot",e);return null; }
    }
    private static void writeSync(String path, String value) {
        java.io.File tmp = new java.io.File(path + ".tmp");
        try {
            java.io.FileOutputStream out = new java.io.FileOutputStream(tmp);
            try { out.write((value + "\n").getBytes("UTF-8")); out.getFD().sync(); } finally { out.close(); }
            if (!tmp.renameTo(new java.io.File(path))) { kr.gen5w.diag.SafeDiagnostic.failure("ap.guard.rename",null);tmp.delete(); }
        } catch (Exception e) { kr.gen5w.diag.SafeDiagnostic.failure("ap.guard.write",e);tmp.delete(); }
    }
    /** Match mode: the stock AP start stored the CarPlay name and key as the
     * ordinary hotspot values. Once the start has finished (the store write
     * happens before the AP comes up), save the user's ordinary pair back. Only
     * the stored values change; the running AP keeps the CarPlay values. Skipped
     * if anything else changed the stored settings meanwhile. Never throws: a
     * failure here must not stop the CarPlay AP. */
    private String ordinarySsid, ordinaryKey, carplaySsid, carplayKey;
    private void restoreOrdinary() {
        synchronized (mutationLock) {
            String ssid = ordinarySsid, key = ordinaryKey;
            ordinarySsid = null; ordinaryKey = null;
            if (ssid == null || key == null) return;
            try {
                WifiConfiguration now = wifi.getWifiApConfiguration();
                if (now == null || !carplaySsid.equals(now.SSID) || !carplayKey.equals(now.preSharedKey)
                        || !carplaySsid.equals(now.ConnectivitySSID) || !carplayKey.equals(now.ConnectivityPSK)) return;
                WifiConfiguration saved = new WifiConfiguration(now);
                saved.SSID = ssid; saved.preSharedKey = key;
                wifi.setWifiApConfiguration(saved);
            } catch (Exception e) { kr.gen5w.diag.SafeDiagnostic.failure("ap.profile.restore",e); }
        }
    }
    /** Stock WifiService saves "AP on" (Settings.Global wifi_ap_on) and, with the
     * wireless features present, starts the AP from system_server during the next
     * boot. Clear it so the AP only starts from this bridge, after boot completes.
     * Nothing else reads the value. Best effort; runs off the caller's thread. */
    private static void clearBootRestore() {
        Thread t = new Thread(new Runnable() { public void run() {
            try {
                Process p = new ProcessBuilder("/system/bin/settings", "put", "global", "wifi_ap_on", "0")
                        .redirectErrorStream(true).start();
                p.getOutputStream().close();
                java.io.InputStream out = p.getInputStream();
                byte[] buf = new byte[256];
                while (out.read(buf) >= 0) { }
                int code=p.waitFor();
                if (code!=0) kr.gen5w.diag.SafeDiagnostic.failure("ap.bootRestore.exit."+code,null);
            } catch (Exception e) { kr.gen5w.diag.SafeDiagnostic.failure("ap.bootRestore.command",e); }
        } }, "gen5wkr-ap-boot-clear");
        t.setDaemon(true);
        t.start();
    }
    /** Match mode: the installer chose to keep services.odex stock. */
    static final String MATCH_MARKER = "/data/nemesis/gen5wkr.ap-match";
    private static void requireReady() throws Exception {
        if (profileReady()) return;
        if (matchMode()) return;
        throw new Exception("AP control not ready");
    }
    private static boolean matchMode() {
        try {
            BufferedReader marker = new BufferedReader(new FileReader(MATCH_MARKER));
            try { return "match".equals(marker.readLine()) && marker.readLine() == null; }
            finally { marker.close(); }
        } catch (Exception e) { return false; }
    }
    private static boolean profileReady() {
        try { requireProfileReady(); return true; } catch (Exception e) { return false; }
    }
    private static void requireProfileReady() throws Exception {
        BufferedReader marker = new BufferedReader(new FileReader("/data/nemesis/gen5wkr.ap-profile-ready"));
        try {
            BufferedReader boot = new BufferedReader(new FileReader("/proc/sys/kernel/random/boot_id"));
            try {
                String current = boot.readLine();
                if (!"ready".equals(marker.readLine()) || current == null || current.length() == 0
                        || !current.equals(marker.readLine()) || marker.readLine() != null)
                    throw new Exception("Native AP profile selection not ready");
            } finally { boot.close(); }
        } finally { marker.close(); }
    }
    private static void requireWpa2(WifiConfiguration config) throws Exception {
        // V039 NetworkManagementService maps auth type 4 to wpa2-psk.
        // Preserve the stock security policy; do not turn an open ordinary AP
        // into an open CarPlay AP or silently rewrite the user's security mode.
        String factoryAuth = (String)Class.forName("android.os.SystemProperties")
                .getMethod("get", String.class).invoke(null, "wifi.info.auth");
        if (config == null || !ApProfiles.securitySupported(config.getAuthType(), factoryAuth))
            throw new Exception("WPA2 AP settings without factory auth override required");
    }
    public long now() { return SystemClock.elapsedRealtime(); }
    public void pause() throws InterruptedException { Thread.sleep(250); }
    private static boolean same(String a, String b) { return a == null ? b == null : a.equals(b); }
}
