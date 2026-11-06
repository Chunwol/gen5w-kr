package kr.gen5w.ui;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/** Reads a small text file without ever holding more than a fixed number of bytes or lines. */
public final class BoundedLines {
    private BoundedLines() { }

    /** @return the lines, or null when the file is missing, not a regular file or unreadable. */
    public static List<String> read(File file, int maxBytes, int maxLines) {
        if (file == null || maxBytes < 0 || maxLines < 0) return null;
        FileInputStream in = null;
        try {
            if (!file.isFile()) return null;
            in = new FileInputStream(file);
            byte[] buffer = new byte[maxBytes];
            int length = 0, got;
            while (length < maxBytes && (got = in.read(buffer, length, maxBytes - length)) > 0) length += got;
            String text = new String(buffer, 0, length, "UTF-8");
            List<String> lines = new ArrayList<String>();
            int start = 0;
            while (start < text.length() && lines.size() < maxLines) {
                int end = text.indexOf('\n', start);
                String line = end < 0 ? text.substring(start) : text.substring(start, end);
                if (line.endsWith("\r")) line = line.substring(0, line.length() - 1);
                lines.add(line);
                if (end < 0) break;
                start = end + 1;
            }
            return lines;
        } catch (IOException e) {
            return null;
        } catch (SecurityException e) {
            return null;
        } finally {
            if (in != null) try { in.close(); } catch (IOException ignored) { }
        }
    }
}
