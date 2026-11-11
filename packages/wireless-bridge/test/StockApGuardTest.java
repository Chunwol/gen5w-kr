package kr.gen5w.wireless;

import java.io.File;
import java.nio.file.Files;

public final class StockApGuardTest {
    private static final String BOOT = "0123abcd-0000-1111-2222-333344445555";

    public static void main(String[] args) throws Exception {
        attemptIsRecordedBeforeTheRequest();
        activeProjectionClearsWithOkAfterStableTime();
        failureClearsWithoutOkAndWaitsToo();
        unchangedRecordWhileStillInProgress();
        newAttemptRestartsTheStableWait();
        invalidBootIdWritesNothing();
        System.out.println("PASS StockApGuardTest");
    }

    static File dir() throws Exception { return Files.createTempDirectory("apguard").toFile(); }
    static String read(File f) throws Exception { return new String(Files.readAllBytes(f.toPath()), "US-ASCII").trim(); }
    static void check(boolean ok, String what) { if (!ok) throw new AssertionError(what); }

    static void attemptIsRecordedBeforeTheRequest() throws Exception {
        File d = dir();
        StockApGuard g = new StockApGuard(d, BOOT);
        g.begin();
        check(read(new File(d, StockApGuard.ATTEMPT)).equals(BOOT), "attempt holds the boot id");
        check(!new File(d, StockApGuard.ATTEMPT + ".tmp").exists(), "no temp file left");
    }

    static void activeProjectionClearsWithOkAfterStableTime() throws Exception {
        File d = dir();
        StockApGuard g = new StockApGuard(d, BOOT);
        g.begin();
        g.observe(StockProjectionSession.Phase.WAITING_WIFI, 0);
        g.observe(StockProjectionSession.Phase.ACTIVE, 1000);
        g.observe(StockProjectionSession.Phase.ACTIVE, 1000 + StockApGuard.STABLE_MS - 1);
        check(new File(d, StockApGuard.ATTEMPT).exists(), "kept until stable");
        check(!new File(d, StockApGuard.OK).exists(), "no ok before stable");
        g.observe(StockProjectionSession.Phase.ACTIVE, 1000 + StockApGuard.STABLE_MS);
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "cleared after stable");
        check(new File(d, StockApGuard.OK).exists(), "ok recorded");
        check(!g.pending(), "settled");
    }

    static void failureClearsWithoutOkAndWaitsToo() throws Exception {
        File d = dir();
        StockApGuard g = new StockApGuard(d, BOOT);
        g.begin();
        g.observe(StockProjectionSession.Phase.FAILED, 5000);
        check(new File(d, StockApGuard.ATTEMPT).exists(), "failure still waits: OEM may still start the AP");
        g.observe(StockProjectionSession.Phase.IDLE, 5000 + StockApGuard.STABLE_MS);
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "cleared after the wait");
        check(!new File(d, StockApGuard.OK).exists(), "failure never records ok");
    }

    static void unchangedRecordWhileStillInProgress() throws Exception {
        File d = dir();
        StockApGuard g = new StockApGuard(d, BOOT);
        g.begin();
        g.observe(StockProjectionSession.Phase.CONNECT_REQUESTED, 0);
        g.observe(StockProjectionSession.Phase.WAITING_WIFI, 10 * StockApGuard.STABLE_MS);
        check(new File(d, StockApGuard.ATTEMPT).exists(), "in-progress attempt is never cleared");
        check(g.pending(), "still pending");
    }

    static void newAttemptRestartsTheStableWait() throws Exception {
        File d = dir();
        StockApGuard g = new StockApGuard(d, BOOT);
        g.begin();
        g.observe(StockProjectionSession.Phase.ACTIVE, 0);
        g.begin();
        g.observe(StockProjectionSession.Phase.WAITING_WIFI, StockApGuard.STABLE_MS);
        check(new File(d, StockApGuard.ATTEMPT).exists(), "newer attempt is not cleared by the older timer");
        check(!new File(d, StockApGuard.OK).exists(), "no ok for the newer attempt yet");
    }

    static void invalidBootIdWritesNothing() throws Exception {
        File d = dir();
        StockApGuard g = new StockApGuard(d, "../../x");
        g.begin();
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "unsafe boot id is not written");
        new StockApGuard(d, null).begin();
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "missing boot id writes nothing");
    }
}
