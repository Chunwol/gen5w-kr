package kr.gen5w.probe;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** Appends lines to probe.log in the app's files dir; keeps probe.log.1 .. .4 (2 MB each). */
final class LogFile {
    static final long MAX = 2L * 1024 * 1024;
    static final int KEEP = 4;
    private final File dir;
    private final SimpleDateFormat time = new SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US);

    LogFile(File dir) { this.dir = dir; }

    synchronized void write(String text) {
        File f = new File(dir, "probe.log");
        if (f.length() > MAX) rotate(f);
        String line = time.format(new Date()) + " " + text + "\n";
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(f, true);
            out.write(line.getBytes("UTF-8"));
        } catch (IOException ignored) {
        } finally {
            if (out != null) try { out.close(); } catch (IOException ignored) {}
        }
    }

    private void rotate(File f) {
        new File(dir, "probe.log." + KEEP).delete();
        for (int i = KEEP - 1; i >= 1; i--) new File(dir, "probe.log." + i).renameTo(new File(dir, "probe.log." + (i + 1)));
        f.renameTo(new File(dir, "probe.log.1"));
    }
}
