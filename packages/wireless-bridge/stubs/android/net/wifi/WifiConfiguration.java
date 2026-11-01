package android.net.wifi;
/** compile-only: the fields we read/write on the hotspot config. */
public class WifiConfiguration {
    public String SSID;
    public String preSharedKey;
    public String ConnectivitySSID;
    public String ConnectivityPSK;
    public int apMode;
    public WifiConfiguration() {}
    public WifiConfiguration(WifiConfiguration c) {}
    public int getAuthType() { throw new RuntimeException("stub"); }
}
