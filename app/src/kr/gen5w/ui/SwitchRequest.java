package kr.gen5w.ui;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

/**
 * The switch request file the screen leaves for the root collector service. Only fixed words are
 * written ("wireless|timer|bluelink" = "on|off"); the collector accepts nothing else. The file is
 * replaced as a whole (temp file + rename). Free of Android types.
 */
public final class SwitchRequest {
    public static final String FILE = "ui-request";

    private SwitchRequest() { }

    /** A value other than "on" or "off" (for example "unknown") is left out of the file. */
    static String content(String wireless, String timer, String bluelink, String adb, String save, String remove) {
        StringBuilder b = new StringBuilder();
        line(b, "wireless", wireless);
        line(b, "timer", timer);
        line(b, "bluelink", bluelink);
        // adb is a one-time command ("on:<number>" / "off:<number>"): a new number is applied once, so the
        // file left over from before a reboot cannot switch Wi-Fi adb on again.
        if (adb != null && adb.matches("(on|off):[0-9]{1,10}")) b.append("adb=").append(adb).append('\n');
        if (save != null && save.matches("[0-9]{1,10}")) b.append("save=").append(save).append('\n');
        if (remove != null && remove.matches("[0-9]{1,10}")) b.append("remove=").append(remove).append('\n');
        return b.toString();
    }

    private static void line(StringBuilder b, String key, String value) {
        if ("on".equals(value) || "off".equals(value)) b.append(key).append('=').append(value).append('\n');
    }

    private static final Object LOCK = new Object();

    /** Per-activity generation gate: scheduling order cannot overwrite the latest intent. */
    public static final class Writer {
        private long latest;
        private boolean closed;
        public synchronized long issue() { return closed ? -1 : ++latest; }
        public synchronized void close() { closed = true; latest++; }
        public synchronized boolean writeRecovery(long sequence, File dir, long now, long expires, String boot, String token) {
            if (closed || sequence <= 0 || sequence != latest || now < 0 || expires < now
                    || expires-now > 30 || expires > 999999999L || !validBoot(boot)
                    || token == null || !token.matches("[0-9]{1,10}") || dir == null || !dir.isDirectory()) return false;
            synchronized (LOCK) {
                return writeLocked(dir,null,null,null,null,null,null,
                        "boot="+boot+"\nexpires="+expires+"\nrecovery="+token+"\n");
            }
        }
        public synchronized boolean write(long sequence, File dir, long now, long expires, String boot,
                String wireless, String timer, String bluelink, String adb, String save, String remove) {
            if (closed || sequence <= 0 || sequence != latest || now < 0 || expires < now
                    || expires - now > 30 || expires > 999999999L || !validBoot(boot)
                    || dir == null || !dir.isDirectory()) return false;
            synchronized (LOCK) {
                return writeLocked(dir, wireless, timer, bluelink, adb, save, remove,
                        "boot=" + boot + "\nexpires=" + expires + "\n");
            }
        }
    }

    static boolean validBoot(String boot) {
        return boot != null && boot.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");
    }

    /**
     * @param adb "on:<digits>" or "off:<digits>" (a new number asks for one change), or null
     * @param remove digits only (a new number asks the collector to remove every package except the core app), or null
     * @param save digits only (a new number asks the collector for one diagnosis save), or null
     * @return false when the file could not be written
     */
    public static boolean write(File filesDir, String wireless, String timer, String bluelink, String adb, String save, String remove) {
        if (filesDir == null || !filesDir.isDirectory()) return false;
        synchronized (LOCK) { return writeLocked(filesDir, wireless, timer, bluelink, adb, save, remove, ""); }
    }

    private static boolean writeLocked(File filesDir, String wireless, String timer, String bluelink, String adb, String save, String remove, String envelope) {
        File tmp = new File(filesDir, FILE + ".tmp");
        File target = new File(filesDir, FILE);
        try {
            FileOutputStream out = new FileOutputStream(tmp);
            try { out.write((envelope + content(wireless, timer, bluelink, adb, save, remove)).getBytes("UTF-8")); }
            finally { out.close(); }
            // Android replaces the target atomically; some desktop systems refuse, so retry once after deleting it.
            if (!tmp.renameTo(target) && !(target.delete() && tmp.renameTo(target))) {
                kr.gen5w.diag.SafeDiagnostic.failure("ui.request.rename",null);
                tmp.delete(); return false;
            }
            return true;
        } catch (IOException e) {
            kr.gen5w.diag.SafeDiagnostic.failure("ui.request.write",e);
            tmp.delete();
            return false;
        }
    }
}
