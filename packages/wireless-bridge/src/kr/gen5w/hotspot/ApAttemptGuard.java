package kr.gen5w.hotspot;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

/** Durable admission before a driver start; failure must not start the radio. */
final class ApAttemptGuard {
    interface Flush { void run() throws IOException; }
    interface Starter { Process start() throws IOException; }
    /** Upper bound for the directory flush; a stuck sync refuses the radio start. */
    static final long SYNC_TIMEOUT_MS = 8000L;
    static void record(File directory, String boot) throws IOException {
        // fsync(file) precedes rename. Flush the directory rename as well
        // before loading the radio driver, which may reset a faulty unit.
        record(directory, boot, syncFlush(new Starter() { public Process start() throws IOException {
            return Runtime.getRuntime().exec(new String[] {"/system/bin/sync"});
        }}, SYNC_TIMEOUT_MS));
    }
    static void record(File directory, String boot, Flush flush) throws IOException {
        if (boot == null || !boot.matches("[0-9a-f-]{8,64}") || !directory.isDirectory()
                || !directory.getCanonicalFile().equals(directory.getAbsoluteFile()))
            throw new IOException("AP restart guard unavailable");
        File temporary = new File(directory, "attempt.tmp");
        File target = new File(directory, "attempt");
        if (!temporary.getCanonicalFile().equals(temporary.getAbsoluteFile())
                || !target.getCanonicalFile().equals(target.getAbsoluteFile()))
            throw new IOException("AP restart guard linked");
        FileOutputStream out = new FileOutputStream(temporary);
        try { out.write((boot + "\n").getBytes("US-ASCII")); out.getFD().sync(); }
        finally { out.close(); }
        if (!temporary.renameTo(target)) throw new IOException("AP restart guard seal failed");
        // On failure the sealed record stays: its durability is unknown, so the
        // next boot must still see it. The caller never reaches the radio call.
        flush.run();
    }
    /** Runs the started process to a zero exit within timeoutMs (API 19: no waitFor(timeout)). */
    static Flush syncFlush(final Starter starter, final long timeoutMs) {
        return new Flush() { public void run() throws IOException { awaitExit(starter.start(), timeoutMs); } };
    }
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
                    throw new IOException("AP guard sync interrupted", e);
                }
            }
        } finally {
            try { process.getInputStream().close(); } catch (IOException ignored) { }
            try { process.getErrorStream().close(); } catch (IOException ignored) { }
        }
    }
}
