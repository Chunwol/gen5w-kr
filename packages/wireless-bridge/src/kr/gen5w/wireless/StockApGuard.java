package kr.gen5w.wireless;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;

/**
 * Restart guard for the stock path. A stock connection request makes the OEM
 * PhoneProjection start the AP (and so load the Wi-Fi driver), which the relay
 * broker's guard in AndroidWifiAp never sees. Before each such request this
 * records the boot id in the host's own files directory; the root supervisor
 * (service.sh apguard_boot) counts a record left from an earlier boot as a
 * restart during an AP start and turns wireless off after several in a row.
 *
 * The record is cleared STABLE_MS after the attempt settles: with "ap-ok" when
 * the projection became active, without it otherwise. Failures wait too, because
 * the OEM may still be starting the AP after this side stopped waiting.
 */
final class StockApGuard {
    static final long STABLE_MS = 45000L;
    static final String ATTEMPT = "ap-attempt";
    static final String OK = "ap-ok";

    private final File dir;
    private final String bootId;
    private boolean pending;
    private boolean settled;
    private boolean active;
    private long clearAt;

    StockApGuard(File dir, String bootId) {
        this.dir = dir;
        this.bootId = bootId != null && bootId.matches("[0-9a-f-]{8,64}") ? bootId : null;
    }

    /** Call just before sending an OEM action that can start the AP. */
    synchronized void begin() {
        pending = true;
        settled = false;
        active = false;
        clearAt = 0;
        if (dir == null || bootId == null) return;
        write(ATTEMPT, bootId);
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
