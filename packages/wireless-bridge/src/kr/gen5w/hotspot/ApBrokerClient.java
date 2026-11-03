package kr.gen5w.hotspot;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import java.io.IOException;
import java.net.SocketTimeoutException;

/** Requests AP setup without transferring the saved Wi-Fi credentials. */
public final class ApBrokerClient {
    private ApBrokerClient() { }
    public static void ensure(ApProfiles.Guard guard) throws Exception {
        LocalSocket socket = new LocalSocket();
        try {
            guard.check();
            socket.connect(new LocalSocketAddress(ApBroker.SOCKET));
            if (socket.getPeerCredentials().getUid() != 1000)
                throw new SecurityException("untrusted AP broker");
            socket.setSoTimeout(200);
            socket.getOutputStream().write('E');
            socket.getOutputStream().flush();
            while (true) {
                guard.check();
                try {
                    int response = socket.getInputStream().read();
                    if (response != 'O') throw new IOException("AP setup unavailable");
                    guard.check();
                    return;
                } catch (SocketTimeoutException ignored) { }
            }
        } finally { try { socket.close(); } catch (IOException ignored) { } }
    }
}
