package kr.gen5w.hotspot;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

/** Durable admission before a driver start; failure must not start the radio. */
final class ApAttemptGuard {
    interface Flush { void run() throws IOException; }
    static void record(File directory, String boot) throws IOException {
        record(directory, boot, new Flush() { public void run() throws IOException {
            // fsync(file) precedes rename. Flush the directory rename as well
            // before loading the radio driver, which may reset a faulty unit.
            Process sync = Runtime.getRuntime().exec(new String[] {"/system/bin/sync"});
            try { if (sync.waitFor() != 0) throw new IOException("AP guard sync failed"); }
            catch (InterruptedException e) {
                Thread.currentThread().interrupt(); throw new IOException("AP guard sync interrupted", e);
            }
        }});
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
        flush.run();
    }
}
