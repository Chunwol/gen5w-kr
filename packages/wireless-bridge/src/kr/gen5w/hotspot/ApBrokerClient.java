package kr.gen5w.hotspot;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.util.Log;
import java.io.IOException;
import java.net.SocketTimeoutException;

/** Requests AP setup without transferring the saved Wi-Fi credentials. */
public final class ApBrokerClient {
    private ApBrokerClient() { }
    public static void ensure(ApProfiles.Guard guard) throws Exception {
        request('E', guard);
    }
    public static void stop(ApProfiles.Guard guard) throws Exception {
        request('D', guard);
    }
    private static void request(int operation, ApProfiles.Guard guard) throws Exception {
        LocalSocket socket = new LocalSocket();
        String stage = "connect";
        try {
            guard.check();
            socket.connect(new LocalSocketAddress(ApBroker.SOCKET));
            stage = "peer-check";
            if (socket.getPeerCredentials().getUid() != 1000)
                throw new SecurityException("untrusted AP broker");
            socket.setSoTimeout(200);
            socket.getOutputStream().write(operation);
            socket.getOutputStream().flush();
            stage = "response";
            while (true) {
                guard.check();
                try {
                    int response = socket.getInputStream().read();
                    if (response != 'O') throw new IOException("AP setup unavailable");
                    guard.check();
                    return;
                } catch (SocketTimeoutException ignored) { }
            }
        } catch (Exception e) {
            Log.i("Gen5wWireless", "AP broker failure stage=" + stage + " type=" + e.getClass().getName());
            throw e;
        } finally { try { socket.close(); } catch (IOException ignored) { } }
    }
}
