package kr.gen5w.wireless;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;

/**
 * Restart guard for the stock path. A stock connection request makes the OEM
 * PhoneProjection start the AP (and so load the Wi-Fi driver), which the relay
 * broker's guard in AndroidWifiAp never sees. Before each such request this
 * durably records the boot id in the host's own files directory; ap.sh check
 * treats any record left behind as an unfinished AP start and withholds
 * wireless until an operator reviews and archives it (ap.sh classify/rearm).
 *
 * Admission is fail-closed, matching the broker's ApAttemptGuard: when the
 * record cannot be written, fsynced, renamed into place and the rename flushed
 * (bounded /system/bin/sync), no OEM action is sent.
 *
 * The record is cleared STABLE_MS after the attempt settles: with "ap-ok" when
 * the projection became active, without it otherwise. Failures wait too, because
 * the OEM may still be starting the AP after this side stopped waiting.
 */
final class StockApGuard {
    static final long STABLE_MS = 45000L;
    static final long SYNC_TIMEOUT_MS = 8000L;
    static final String ATTEMPT = "ap-attempt";
    static final String OK = "ap-ok";

    interface Flush { void run() throws IOException; }

    /** Flushes the directory rename; bounded so a stuck sync never hangs the caller. */
    static final Flush SYSTEM_SYNC = new Flush() {
        public void run() throws IOException {
            awaitExit(Runtime.getRuntime().exec(new String[] {"/system/bin/sync"}), SYNC_TIMEOUT_MS);
        }
    };

    private final File dir;
    private final String bootId;
    private final Flush flush;
    private boolean pending;
    private boolean settled;
    private boolean active;
    private long clearAt;

    StockApGuard(File dir, String bootId) { this(dir, bootId, SYSTEM_SYNC); }

    StockApGuard(File dir, String bootId, Flush flush) {
        this.dir = dir;
        this.bootId = bootId != null && bootId.matches("[0-9a-f-]{8,64}") ? bootId : null;
        this.flush = flush;
    }

    /**
     * Call just before sending an OEM action that can start the AP. Returns only
     * after the record is durable; throws when it is not, and then the caller
     * must not send. A record that was renamed into place but not confirmed
     * flushed stays pending and is cleared by observe() like any other attempt.
     */
    void begin() throws IOException {
        synchronized (this) {
            if (dir == null || bootId == null || flush == null) throw new IOException("stock AP guard unavailable");
            File target = new File(dir, ATTEMPT);
            File temporary = new File(dir, ATTEMPT + ".tmp");
            if (!dir.isDirectory() || !unlinked(dir) || !unlinked(target) || !unlinked(temporary))
                throw new IOException("stock AP guard missing or linked");
            if (target.exists()) {
                // This boot's own pending record is reused (it was flushed when
                // written). Anything else is unreviewed evidence: never replace it.
                if (!target.isFile() || !(bootId + "\n").equals(readSmall(target)))
                    throw new IOException("unreviewed AP attempt record present");
            } else {
                try {
                    FileOutputStream out = new FileOutputStream(temporary);
                    try { out.write((bootId + "\n").getBytes("US-ASCII")); out.getFD().sync(); }
                    finally { out.close(); }
                } catch (IOException e) {
                    temporary.delete();
                    throw e;
                }
                if (!temporary.renameTo(target)) {
                    temporary.delete();
                    throw new IOException("stock AP guard seal failed");
                }
            }
            pending = true;
            settled = false;
            active = false;
            clearAt = 0;
        }
        // Outside the monitor: observe() runs on the main thread every second.
        flush.run();
    }

    /** Records first; runs the action only when the record is durable. */
    boolean admit(Runnable action) {
        try {
            begin();
        } catch (IOException e) {
            return false;
        } catch (RuntimeException e) {
            return false;
        }
        action.run();
        return true;
    }

    /** Call regularly with the session phase; clears the record once the attempt has settled. */
    synchronized void observe(StockProjectionSession.Phase phase, long now) {
        if (!pending) return;
        if (!settled) {
            if (phase == StockProjectionSession.Phase.ACTIVE) {
                settled = true;
                active = true;
            } else if (!inProgress(phase)) {
                settled = true;
            } else {
                return;
            }
            clearAt = now + STABLE_MS;
            return;
        }
        if (now < clearAt) return;
        pending = false;
        if (dir == null) return;
        if (active) write(OK, "ok");
        new File(dir, ATTEMPT).delete();
    }

    synchronized boolean pending() { return pending; }

    private static boolean inProgress(StockProjectionSession.Phase phase) {
        return phase == StockProjectionSession.Phase.INSPECTING ||
                phase == StockProjectionSession.Phase.BOOTSTRAP_REQUESTED ||
                phase == StockProjectionSession.Phase.WAITING_PROFILE ||
                phase == StockProjectionSession.Phase.CONNECT_REQUESTED ||
                phase == StockProjectionSession.Phase.WAITING_WIFI;
    }

    private static String readSmall(File file) throws IOException {
        java.io.FileInputStream in = new java.io.FileInputStream(file);
        try {
            byte[] buffer = new byte[129];
            int length = 0, read;
            while (length < buffer.length && (read = in.read(buffer, length, buffer.length - length)) > 0) length += read;
            return new String(buffer, 0, length, "US-ASCII");
        } finally {
            in.close();
        }
    }

    private static boolean unlinked(File file) throws IOException {
        return file.getCanonicalFile().equals(file.getAbsoluteFile());
    }

    /** Waits at most timeoutMs for a zero exit; destroys the process otherwise. */
    static void awaitExit(Process process, long timeoutMs) throws IOException {
        long deadline = System.nanoTime() + timeoutMs * 1000000L;
        try {
            process.getOutputStream().close();
            while (true) {
                try {
                    int code = process.exitValue();
                    if (code != 0) throw new IOException("AP guard sync failed: " + code);
                    return;
                } catch (IllegalThreadStateException running) {
                    if (System.nanoTime() - deadline >= 0) {
                        process.destroy();
                        throw new IOException("AP guard sync timed out");
                    }
                }
                try {
                    Thread.sleep(20);
                } catch (InterruptedException e) {
                    process.destroy();
                    Thread.currentThread().interrupt();
                    throw new IOException("AP guard sync interrupted");
                }
            }
        } finally {
            try { process.getInputStream().close(); } catch (IOException ignored) { }
            try { process.getErrorStream().close(); } catch (IOException ignored) { }
        }
    }

    // Success marker only; losing it never admits anything (the attempt record decides).
    private void write(String name, String value) {
        File tmp = new File(dir, name + ".tmp");
        try {
            FileOutputStream out = new FileOutputStream(tmp);
            try { out.write((value + "\n").getBytes("US-ASCII")); out.getFD().sync(); }
            finally { out.close(); }
            if (!tmp.renameTo(new File(dir, name))) tmp.delete();
        } catch (Exception e) {
            tmp.delete();
        }
    }

    static String readBootId() {
        try {
            BufferedReader r = new BufferedReader(new FileReader("/proc/sys/kernel/random/boot_id"));
            try { return r.readLine(); } finally { r.close(); }
        } catch (Exception e) {
            return null;
        }
    }
}
