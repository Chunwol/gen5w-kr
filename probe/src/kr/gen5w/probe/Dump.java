package kr.gen5w.probe;

import java.util.List;

/** Turns a message into one log line: id:type=value, groups in [ ]. Pure Java (unit-tested on the JVM). */
public final class Dump {
    private static final String HEX = "0123456789abcdef";
    static final int MAX_BYTES = 96;
    static final int MAX_TEXT = 4000;

    private Dump() {}

    public static String line(List<Item> items) {
        StringBuilder sb = new StringBuilder();
        append(sb, items);
        if (sb.length() > MAX_TEXT) {
            sb.setLength(MAX_TEXT);
            sb.append("...(cut)");
        }
        return sb.toString();
    }

    private static void append(StringBuilder sb, List<Item> items) {
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) sb.append(' ');
            Item it = items.get(i);
            sb.append(Integer.toHexString(it.id)).append(':').append(it.type).append('=');
            value(sb, it);
        }
    }

    private static void value(StringBuilder sb, Item it) {
        if (!it.groups.isEmpty()) {
            for (int g = 0; g < it.groups.size(); g++) {
                sb.append('[');
                append(sb, it.groups.get(g));
                sb.append(']');
            }
        } else if (it.strings != null) {
            for (int k = 0; k < it.strings.length; k++) {
                if (k > 0) sb.append(',');
                sb.append('"').append(clean(it.strings[k])).append('"');
            }
        } else if (it.longs != null) {
            for (int k = 0; k < it.longs.length; k++) {
                if (k > 0) sb.append(',');
                sb.append(it.longs[k]);
            }
        } else if (it.ints != null) {
            for (int k = 0; k < it.ints.length; k++) {
                if (k > 0) sb.append(',');
                sb.append(it.ints[k]);
            }
        } else if (it.bytes != null) {
            sb.append("0x");
            int n = Math.min(it.bytes.length, MAX_BYTES);
            for (int k = 0; k < n; k++) {
                int b = it.bytes[k] & 0xff;
                sb.append(HEX.charAt(b >> 4)).append(HEX.charAt(b & 15));
            }
            if (it.bytes.length > n) sb.append("..(").append(it.bytes.length).append(')');
        } else {
            sb.append('-');
        }
    }

    /** Keeps one log line per message: no newlines, quotes escaped. */
    static String clean(String s) {
        if (s == null) return "";
        StringBuilder o = new StringBuilder(s.length());
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\n' || c == '\r') o.append(' ');
            else if (c == '"' || c == '\\') o.append('\\').append(c);
            else o.append(c);
        }
        return o.toString();
    }
}
