package android.net.wifi;
import android.os.IBinder;
/** compile-only: only the hotspot calls we use. */
public interface IWifiManager {
    WifiConfiguration getWifiApConfiguration() throws Exception;
    int getWifiApEnabledState() throws Exception;
    int getWifiApMode() throws Exception;
    void setWifiApEnabledForConnectivity(WifiConfiguration c, boolean enabled) throws Exception;
    void setWifiApConfiguration(WifiConfiguration c) throws Exception;
    abstract class Stub {
        public static IWifiManager asInterface(IBinder b) { throw new RuntimeException("stub"); }
    }
}
