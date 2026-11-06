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
    static String content(String wireless, String timer, String bluelink) {
        StringBuilder b = new StringBuilder();
        line(b, "wireless", wireless);
        line(b, "timer", timer);
        line(b, "bluelink", bluelink);
        return b.toString();
    }

    private static void line(StringBuilder b, String key, String value) {
        if ("on".equals(value) || "off".equals(value)) b.append(key).append('=').append(value).append('\n');
    }

    /** @return false when the file could not be written */
    public static boolean write(File filesDir, String wireless, String timer, String bluelink) {
        if (filesDir == null || !filesDir.isDirectory()) return false;
        File tmp = new File(filesDir, FILE + ".tmp");
        File target = new File(filesDir, FILE);
        try {
            FileOutputStream out = new FileOutputStream(tmp);
            try { out.write(content(wireless, timer, bluelink).getBytes("UTF-8")); }
            finally { out.close(); }
            // Android replaces the target atomically; some desktop systems refuse, so retry once after deleting it.
            if (!tmp.renameTo(target) && !(target.delete() && tmp.renameTo(target))) { tmp.delete(); return false; }
            return true;
        } catch (IOException e) {
            tmp.delete();
            return false;
        }
    }
}
