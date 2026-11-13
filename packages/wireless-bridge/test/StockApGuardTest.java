package kr.gen5w.wireless;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;

public final class StockApGuardTest {
    private static final String BOOT = "0123abcd-0000-1111-2222-333344445555";
    static final StockApGuard.Flush NO_FLUSH = new StockApGuard.Flush() { public void run() {} };

    public static void main(String[] args) throws Exception {
        attemptIsRecordedBeforeTheRequest();
        activeProjectionClearsWithOkAfterStableTime();
        failureClearsWithoutOkAndWaitsToo();
        unchangedRecordWhileStillInProgress();
        newAttemptRestartsTheStableWait();
        invalidBootIdFailsClosed();
        missingDirectoryFailsClosed();
        recordIsSealedAndFlushedBeforeTheAction();
        flushFailurePreventsTheActionAndKeepsTheRecordUntilSettled();
        writeFailurePreventsTheAction();
        linkedRecordFailsClosed();
        earlierRecordIsNeverReplaced();
        syncWaitIsBounded();
        syncExitStatusIsChecked();
        System.out.println("PASS StockApGuardTest");
    }

    static File dir() throws Exception { return Files.createTempDirectory("apguard").toFile(); }
    static String read(File f) throws Exception { return new String(Files.readAllBytes(f.toPath()), "US-ASCII").trim(); }
    static void check(boolean ok, String what) { if (!ok) throw new AssertionError(what); }
    static StockApGuard guard(File d) { return new StockApGuard(d, BOOT, NO_FLUSH); }
    static void expectIoFailure(StockApGuard g, String what) {
        try { g.begin(); } catch (IOException expected) { return; }
        throw new AssertionError(what);
    }

    static void attemptIsRecordedBeforeTheRequest() throws Exception {
        File d = dir();
        StockApGuard g = guard(d);
        g.begin();
        check(read(new File(d, StockApGuard.ATTEMPT)).equals(BOOT), "attempt holds the boot id");
        check(!new File(d, StockApGuard.ATTEMPT + ".tmp").exists(), "no temp file left");
    }

    static void activeProjectionClearsWithOkAfterStableTime() throws Exception {
        File d = dir();
        StockApGuard g = guard(d);
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
        StockApGuard g = guard(d);
        g.begin();
        g.observe(StockProjectionSession.Phase.FAILED, 5000);
        check(new File(d, StockApGuard.ATTEMPT).exists(), "failure still waits: OEM may still start the AP");
        g.observe(StockProjectionSession.Phase.IDLE, 5000 + StockApGuard.STABLE_MS);
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "cleared after the wait");
        check(!new File(d, StockApGuard.OK).exists(), "failure never records ok");
    }

    static void unchangedRecordWhileStillInProgress() throws Exception {
        File d = dir();
        StockApGuard g = guard(d);
        g.begin();
        g.observe(StockProjectionSession.Phase.CONNECT_REQUESTED, 0);
        g.observe(StockProjectionSession.Phase.WAITING_WIFI, 10 * StockApGuard.STABLE_MS);
        check(new File(d, StockApGuard.ATTEMPT).exists(), "in-progress attempt is never cleared");
        check(g.pending(), "still pending");
    }

    static void newAttemptRestartsTheStableWait() throws Exception {
        File d = dir();
        StockApGuard g = guard(d);
        g.begin();
        g.observe(StockProjectionSession.Phase.ACTIVE, 0);
        g.begin();
        g.observe(StockProjectionSession.Phase.WAITING_WIFI, StockApGuard.STABLE_MS);
        check(new File(d, StockApGuard.ATTEMPT).exists(), "newer attempt is not cleared by the older timer");
        check(!new File(d, StockApGuard.OK).exists(), "no ok for the newer attempt yet");
    }

    /** M6: no boot id means no durable record, so the AP request must not happen. */
    static void invalidBootIdFailsClosed() throws Exception {
        File d = dir();
        expectIoFailure(new StockApGuard(d, "../../x", NO_FLUSH), "unsafe boot id must refuse the request");
        expectIoFailure(new StockApGuard(d, null, NO_FLUSH), "missing boot id must refuse the request");
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "nothing written for a refused boot id");
        final int[] sent = {0};
        check(!new StockApGuard(d, null, NO_FLUSH).admit(new Runnable() { public void run() { sent[0]++; } }),
                "admit reports the refusal");
        check(sent[0] == 0, "no OEM action without a record");
    }

    static void missingDirectoryFailsClosed() throws Exception {
        expectIoFailure(new StockApGuard(null, BOOT, NO_FLUSH), "no files directory must refuse the request");
        File gone = new File(dir(), "absent");
        expectIoFailure(new StockApGuard(gone, BOOT, NO_FLUSH), "absent directory must refuse the request");
    }

    /** Order: temp fsync, rename, directory flush, then (and only then) the OEM action. */
    static void recordIsSealedAndFlushedBeforeTheAction() throws Exception {
        final File d = dir();
        final List<String> order = new ArrayList<String>();
        StockApGuard g = new StockApGuard(d, BOOT, new StockApGuard.Flush() { public void run() {
            order.add("flush:" + new File(d, StockApGuard.ATTEMPT).isFile() + ":" + new File(d, StockApGuard.ATTEMPT + ".tmp").exists());
        }});
        check(g.admit(new Runnable() { public void run() {
            order.add("send:" + new File(d, StockApGuard.ATTEMPT).isFile());
        }}), "successful record admits the action");
        check(order.toString().equals("[flush:true:false, send:true]"), "sealed record flushed before the action: " + order);
        check(g.pending(), "attempt pending after admission");
    }

    /** M6 proof: a flush failure must not send; the unconfirmed record is kept (fail closed). */
    static void flushFailurePreventsTheActionAndKeepsTheRecordUntilSettled() throws Exception {
        File d = dir();
        final int[] sent = {0};
        StockApGuard g = new StockApGuard(d, BOOT, new StockApGuard.Flush() { public void run() throws IOException {
            throw new IOException("injected sync failure");
        }});
        check(!g.admit(new Runnable() { public void run() { sent[0]++; } }), "flush failure refuses admission");
        check(sent[0] == 0, "no OEM action after a flush failure");
        check(new File(d, StockApGuard.ATTEMPT).isFile(), "possibly-unsynced record is never deleted early");
        g.observe(StockProjectionSession.Phase.CANCELLED, 0);
        g.observe(StockProjectionSession.Phase.CANCELLED, StockApGuard.STABLE_MS);
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "cleared by the ordinary settle path in the same boot");
        check(!new File(d, StockApGuard.OK).exists(), "never ok");
    }

    static void writeFailurePreventsTheAction() throws Exception {
        File d = dir();
        File tmp = new File(d, StockApGuard.ATTEMPT + ".tmp");
        check(tmp.mkdir(), "occupy the temp name with a directory");
        final int[] sent = {0};
        check(!guard(d).admit(new Runnable() { public void run() { sent[0]++; } }), "write failure refuses admission");
        check(sent[0] == 0, "no OEM action after a write failure");
        check(!new File(d, StockApGuard.ATTEMPT).exists(), "no record from a failed write");
    }

    static void linkedRecordFailsClosed() throws Exception {
        File d = dir();
        File outside = new File(dir(), "outside");
        try {
            Files.createSymbolicLink(new File(d, StockApGuard.ATTEMPT).toPath(), outside.toPath());
        } catch (UnsupportedOperationException | IOException | SecurityException noLinks) {
            System.out.println("SKIP linkedRecordFailsClosed (symbolic links unavailable)");
            return;
        }
        expectIoFailure(guard(d), "linked record must refuse the request");
        check(!outside.exists(), "nothing written through the link");
    }

    /** An unreviewed record (earlier boot, or not ours) is evidence: refuse, keep it byte-exact. */
    static void earlierRecordIsNeverReplaced() throws Exception {
        File d = dir();
        File record = new File(d, StockApGuard.ATTEMPT);
        Files.write(record.toPath(), "fedcba98-0000-1111-2222-333344445555\n".getBytes("US-ASCII"));
        final int[] sent = {0};
        check(!guard(d).admit(new Runnable() { public void run() { sent[0]++; } }), "earlier record refuses admission");
        check(sent[0] == 0, "no OEM action over unreviewed evidence");
        check(read(record).equals("fedcba98-0000-1111-2222-333344445555"), "earlier record untouched");
    }

    static class HungProcess extends Process {
        boolean destroyed;
        public OutputStream getOutputStream() { return new java.io.ByteArrayOutputStream(); }
        public InputStream getInputStream() { return new java.io.ByteArrayInputStream(new byte[0]); }
        public InputStream getErrorStream() { return new java.io.ByteArrayInputStream(new byte[0]); }
        public int waitFor() throws InterruptedException { throw new AssertionError("unbounded wait"); }
        public int exitValue() { if (!destroyed) throw new IllegalThreadStateException(); return 137; }
        public void destroy() { destroyed = true; }
    }

    static void syncWaitIsBounded() throws Exception {
        HungProcess p = new HungProcess();
        long start = System.nanoTime();
        try {
            StockApGuard.awaitExit(p, 200);
            throw new AssertionError("hung sync must fail");
        } catch (IOException expected) { }
        long ms = (System.nanoTime() - start) / 1000000L;
        check(p.destroyed, "hung sync is destroyed");
        check(ms >= 150 && ms < 5000, "bounded wait, took " + ms + " ms");
    }

    static void syncExitStatusIsChecked() throws Exception {
        HungProcess failed = new HungProcess();
        failed.destroyed = true; // exitValue 137 immediately
        try { StockApGuard.awaitExit(failed, 1000); throw new AssertionError("non-zero sync must fail"); }
        catch (IOException expected) { }
        Process ok = new HungProcess() { public int exitValue() { return 0; } };
        StockApGuard.awaitExit(ok, 1000);
    }
}
