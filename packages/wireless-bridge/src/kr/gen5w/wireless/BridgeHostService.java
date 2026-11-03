package kr.gen5w.wireless;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;
import android.os.Process;
import java.io.File;
import java.io.FileOutputStream;

/** Android-managed process for Bluetooth receivers and OEM PhoneProjection requests. */
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
        try {
            File marker = new File(getFilesDir(), "bridge-ready");
            FileOutputStream out = new FileOutputStream(marker);
            try { out.write((Integer.toString(Process.myPid()) + "\n").getBytes("US-ASCII")); }
            finally { out.close(); }
        } catch (Exception e) {
            Log.e("gen5w-wireless", "host readiness marker failure: " + e.getClass().getName());
            stopSelf();
        }
        return START_NOT_STICKY;
    }
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        new File(getFilesDir(), "bridge-ready").delete();
        if (bridge != null) bridge.shutdown();
        super.onDestroy();
    }
}
