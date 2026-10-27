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
            // Never replace ordinary credentials. OEM sets mode 2; the paired
            // native implementation selects CP fields in command-local values.
            wifi.setWifiApEnabledForConnectivity(new WifiConfiguration(latest), true);
        }
    }
    private static void requireReady() throws Exception {
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
