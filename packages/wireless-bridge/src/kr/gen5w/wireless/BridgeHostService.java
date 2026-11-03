package kr.gen5w.wireless;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

/** Android-managed process for registered receivers and iAP2 binding. */
public final class BridgeHostService extends Service {
    private WirelessBridge bridge;

    @Override public void onCreate() {
        super.onCreate();
        bridge = new WirelessBridge(this);
        try { bridge.run(); }
        catch (RuntimeException e) {
            // Keep the exception type visible in the privacy-filtered diagnostic.
            Log.e("gen5w-wireless", "startup failure: " + e.getClass().getName());
            throw e;
        }
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        return START_NOT_STICKY;
    }
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        if (bridge != null) bridge.shutdown();
        super.onDestroy();
    }
}
