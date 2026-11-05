package kr.gen5w.hotspot;

import android.content.Context;
import android.net.Credentials;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.wifi.IWifiManager;
import android.os.Looper;
import android.os.Process;
import android.os.ServiceManager;
import android.util.Log;
import java.io.IOException;
import java.io.InputStream;

/** System-UID AP helper. No credentials or arbitrary commands cross the socket. */
public final class ApBroker {
    public static final String SOCKET = "gen5wkr.ap.broker.v1";
    public static final String HOST = "kr.gen5w.wirelesshost";
    private static final ApProfiles profiles = new ApProfiles();

    public static void main(String[] args) throws Exception {
        try { serve(args); }
        catch (Exception e) {
            Log.e("gen5w-wireless", "AP broker startup failure: " + e.getClass().getName());
            throw e;
        }
    }

    private static void serve(String[] args) throws Exception {
        if (Process.myUid() != 1000 || args.length != 1) System.exit(1);
        final int supervisor;
        try { supervisor = Integer.parseInt(args[0]); }
        catch (NumberFormatException e) { throw new SecurityException("invalid supervisor PID"); }
        if (supervisor <= 1 || ApBrokerParent.current() != supervisor)
            throw new SecurityException("supervisor unavailable");
        Thread parentWatcher = new Thread(new Runnable() { public void run() {
            while (true) {
                try { Thread.sleep(200); } catch (InterruptedException ignored) { }
                if (ApBrokerParent.current() != supervisor) System.exit(1);
            }
        } }, "gen5w-ap-parent");
        parentWatcher.setDaemon(true);
        parentWatcher.start();
        Looper.prepareMainLooper();
        Class<?> type = Class.forName("android.app.ActivityThread");
        Object thread = type.getMethod("systemMain").invoke(null);
        Context context = (Context) type.getMethod("getSystemContext").invoke(thread);
        final int hostUid = context.getPackageManager().getApplicationInfo(HOST, 0).uid;
        if (hostUid < 10000) throw new SecurityException("invalid host UID");
        final LocalServerSocket server = new LocalServerSocket(SOCKET);
        while (true) {
            final LocalSocket client = server.accept();
            try {
                Credentials peer = client.getPeerCredentials();
                if (peer.getUid() != hostUid) { client.close(); continue; }
                client.setSoTimeout(1000);
                final InputStream in = client.getInputStream();
                final int operation = in.read();
                if (!ApBrokerPolicy.allowed(hostUid, peer.getUid(), operation)) {
                    client.close();
                    continue;
                }
                client.setSoTimeout(0);
                new Thread(new Runnable() { public void run() { handle(client, in, operation); } },
                        "gen5w-ap-request").start();
            } catch (IOException e) { try { client.close(); } catch (IOException ignored) { } }
        }
    }

    private static void handle(final LocalSocket client, final InputStream in, int operation) {
        final ApProfiles.Guard guard = new ApBrokerCancellation(in);
        try {
            IWifiManager wifi = IWifiManager.Stub.asInterface(ServiceManager.getService("wifi"));
            if (wifi == null) throw new IOException("wifi unavailable");
            AndroidWifiAp port = new AndroidWifiAp(wifi, profiles, guard);
            if (operation == 'E') profiles.ensure(port, guard);
            else profiles.stop(port, guard);
            guard.check();
            client.getOutputStream().write('O');
            client.getOutputStream().flush();
        } catch (Exception e) {
            Log.e("gen5w-wireless", "AP broker failure: " + e.getClass().getName());
            try { client.getOutputStream().write('F'); } catch (IOException ignoredAgain) { }
        } finally { try { client.close(); } catch (IOException ignored) { } }
    }
}
