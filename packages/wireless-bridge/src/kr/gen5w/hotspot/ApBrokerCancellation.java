package kr.gen5w.hotspot;

import java.io.IOException;
import java.io.InputStream;

/** A broker request is valid only while its authenticated client stays connected. */
public final class ApBrokerCancellation implements ApProfiles.Guard {
    private volatile boolean cancelled;

    public ApBrokerCancellation(final InputStream input) {
        Thread watcher = new Thread(new Runnable() { public void run() {
            try { while (input.read() != -1) { } } catch (IOException ignored) { }
            cancelled = true;
        } }, "gen5w-ap-cancel");
        watcher.setDaemon(true);
        watcher.start();
    }

    @Override public void check() throws IOException {
        if (cancelled) throw new IOException("request cancelled");
    }
}
