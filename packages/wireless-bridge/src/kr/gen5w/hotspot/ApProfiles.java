package kr.gen5w.hotspot;

/** One radio, two saved credential sets. The paired native implementation uses
 * CarPlay credentials only in the live AP command, preserving ordinary settings.
 * Credentials stay in memory and are never included in result messages.
 */
public final class ApProfiles {
    public static final int DISABLED = 11, ENABLED = 13, CONNECTIVITY = 2;
    public interface Guard { void check() throws Exception; }
    public interface Port {
        void lock(Guard guard) throws Exception;
        void unlock();
        Profile configuration() throws Exception;
        int state() throws Exception;
        int mode() throws Exception;
        void disable() throws Exception;
        void enable(Profile desired) throws Exception;
        /** The AP start that enable() began has finished: ok after the AP is up
         * in connectivity mode, !ok after a clean failure. */
        void transitionDone(boolean ok) throws Exception;
        long now();
        void pause() throws Exception;
    }
    public static final class Profile {
        public final String ssid, key, carplaySsid, carplayKey;
        public final int mode;
        public Profile(String ssid, String key, String carplaySsid, String carplayKey, int mode) {
            this.ssid = ssid; this.key = key; this.carplaySsid = carplaySsid;
            this.carplayKey = carplayKey; this.mode = mode;
        }
        public boolean carplayReady() {
            return ssidSafe(carplaySsid) && keySafe(carplayKey);
        }
    }
    /** netd writes the SSID into hostapd.conf as "ssid=%s": 1 to 32 bytes, and no
     * control characters, so a value can never add or break a config line. */
    static boolean ssidSafe(String ssid) {
        if (ssid == null || ssid.length() == 0) return false;
        for (int i = 0; i < ssid.length(); i++) {
            char c = ssid.charAt(i);
            if (c < 0x20 || c == 0x7f) return false;
        }
        try { return ssid.getBytes("UTF-8").length <= 32; } catch (java.io.UnsupportedEncodingException e) { return false; }
    }
    /** WPA2 passphrase: 8 to 63 printable ASCII characters. */
    static boolean keySafe(String key) {
        if (key == null || key.length() < 8 || key.length() > 63) return false;
        for (int i = 0; i < key.length(); i++) {
            char c = key.charAt(i);
            if (c < 0x20 || c > 0x7e) return false;
        }
        return true;
    }
    private String liveSsid, liveKey;

    /** Exact OEM auth type 4 is WPA2. A factory override takes a different native
     * command branch, so all nonempty or unreadable overrides are unsupported.
     */
    public static boolean securitySupported(int authType, String factoryAuth) {
        return authType == 4 && "".equals(factoryAuth);
    }

    /** Returns true only after establishing a new AP, false for a known AP.
     * A new process cannot infer live credentials from the saved ordinary SSID.
     */
    public synchronized boolean ensure(Port port, Guard guard) throws Exception {
        port.lock(guard);
        try {
            guard.check();
            Profile ordinary = port.configuration();
            if (ordinary == null || !ordinary.carplayReady()) throw new Exception("CarPlay settings unavailable");
            if (port.state() == ENABLED && port.mode() == CONNECTIVITY
                    && same(liveSsid, ordinary.carplaySsid) && same(liveKey, ordinary.carplayKey)) return false;
            liveSsid = null; liveKey = null;
            boolean attempted = false;
            try {
                if (port.state() != DISABLED) {
                    guard.check(); port.disable(); waitState(port, guard, DISABLED, 15000);
                }
                guard.check();
                Profile latest = port.configuration();
                if (latest == null || !same(latest.carplaySsid, ordinary.carplaySsid)
                        || !same(latest.carplayKey, ordinary.carplayKey)) throw new Exception("CarPlay settings changed");
                attempted = true; port.enable(latest);
                waitState(port, guard, ENABLED, 20000);
                guard.check();
                if (port.mode() != CONNECTIVITY) throw new ApRejectedException();
                port.transitionDone(true);
            } catch (Exception failure) {
                kr.gen5w.diag.SafeDiagnostic.failure("ap.transition",failure);
                if (attempted) try { port.transitionDone(false); } catch (Exception e) { kr.gen5w.diag.SafeDiagnostic.failure("ap.transition.cleanup",e); }
                // Cleanup is another guarded radio operation. An expired
                // generation must never stop the AP of its replacement.
                if (attempted) try {
                    guard.check();
                    if (port.mode() == CONNECTIVITY && port.state() != DISABLED) {
                        port.disable(); waitState(port, guard, DISABLED, 15000);
                    }
                } catch (Exception e) { kr.gen5w.diag.SafeDiagnostic.failure("ap.rollback",e); }
                throw failure;
            }
            liveSsid = ordinary.carplaySsid; liveKey = ordinary.carplayKey;
            return true;
        } finally { port.unlock(); }
    }
    public synchronized void stop(Port port, Guard guard) throws Exception {
        port.lock(guard);
        try {
            guard.check();
            if (port.state() != DISABLED && port.mode() == CONNECTIVITY) {
                port.disable();
                waitState(port, guard, DISABLED, 15000);
            }
            liveSsid = null;
            liveKey = null;
        } finally { port.unlock(); }
    }
    private static void waitState(Port port, Guard guard, int state, long timeout) throws Exception {
        long end = port.now() + timeout;
        do {
            guard.check();
            if (port.state() == state) return;
            port.pause();
        } while (port.now() < end);
        throw new java.util.concurrent.TimeoutException("AP transition timed out");
    }
    private static final class ApRejectedException extends Exception { }
    private static boolean same(String a, String b) { return a == null ? b == null : a.equals(b); }
}
