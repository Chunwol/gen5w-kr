package kr.gen5w.core;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;

/** Read only the OEM guidance flag. Never query destinations or location. */
final class StockGuidance {
    static final int UNKNOWN = -1, IDLE = 0, ACTIVE = 1;
    static final String SOCKET = "gen5wkr.hud.owner";

    int read() {
        LocalSocket socket = new LocalSocket();
        try {
            socket.connect(new LocalSocketAddress(SOCKET));
            socket.setSoTimeout(250);
            if (socket.getPeerCredentials().getUid() != 1000) return UNKNOWN;
            socket.getOutputStream().write('?');
            int value = socket.getInputStream().read();
            return value == '0' ? IDLE : value == '1' ? ACTIVE : UNKNOWN;
        } catch (java.io.IOException e) {
            return UNKNOWN;
        } catch (RuntimeException e) {
            return UNKNOWN;
        } finally {
            try { socket.close(); } catch (java.io.IOException ignored) { }
        }
    }
}
