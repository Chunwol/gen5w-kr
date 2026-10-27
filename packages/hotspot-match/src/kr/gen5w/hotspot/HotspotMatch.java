package kr.gen5w.hotspot;

import android.net.wifi.IWifiManager;
import android.os.ServiceManager;

/** System-uid helper. check observes stored profiles and runtime state only;
 * explicit apply shares the bridge controller and preserves ordinary settings.
 * No credential values are printed, logged, or persisted by this helper.
 */
public final class HotspotMatch {
    private static boolean same(String a, String b) { return a == null ? b == null : a.equals(b); }

    public static void main(String[] args) {
        try { run(args); }
        catch (Exception e) { System.out.println("RESULT error ap-service-unavailable"); System.exit(5); }
        catch (LinkageError e) { System.out.println("RESULT error ap-api-unavailable"); System.exit(5); }
    }
    private static void run(String[] args) throws Exception {
        String mode = args.length > 0 ? args[0] : "check";
        if (args.length > 1 || (!"check".equals(mode) && !"apply".equals(mode))) {
            System.out.println("RESULT error invalid-command"); System.exit(2); return;
        }
        IWifiManager wifi = IWifiManager.Stub.asInterface(ServiceManager.getService("wifi"));
        if (wifi == null) { System.out.println("RESULT error no-wifi-service"); System.exit(2); return; }
        AndroidWifiAp port = new AndroidWifiAp(wifi);
        ApProfiles.Profile profile = port.configuration();
        if (profile == null) { System.out.println("RESULT error no-ap-config"); System.exit(2); return; }
        System.out.println("observed saved_profiles_distinct="
                + (!same(profile.ssid, profile.carplaySsid) || !same(profile.key, profile.carplayKey))
                + " carplay_ssid_set=" + (profile.carplaySsid != null && profile.carplaySsid.length() > 0)
                + " carplay_psk_len=" + (profile.carplayKey == null ? -1 : profile.carplayKey.length())
                + " ap_state=" + port.state() + " ap_mode=" + port.mode()
                + " active_credentials_unverified=true");
        if (!profile.carplayReady()) {
            System.out.println("RESULT error carplay-settings-missing"); System.exit(3); return;
        }
        if ("check".equals(mode)) { System.out.println("RESULT ready"); return; }
        try {
            boolean changed = new ApProfiles().ensure(port, new ApProfiles.Guard() { public void check() { } });
            System.out.println("RESULT " + (changed ? "applied" : "known-active"));
        } catch (Exception e) {
            // Exception text from OEM services may contain configuration values.
            System.out.println("RESULT error ap-operation-failed"); System.exit(5);
        }
    }
}
