package kr.gen5w.hotspot;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

/** Detects reparenting if the NEMESIS supervisor is force-killed. */
public final class ApBrokerParent {
    private ApBrokerParent() { }
    public static int parse(String stat) {
        if (stat == null) return -1;
        int end = stat.lastIndexOf(") ");
        if (end < 0) return -1;
        String[] fields = stat.substring(end + 2).trim().split("\\s+");
        if (fields.length < 2) return -1;
        try { int pid = Integer.parseInt(fields[1]); return pid > 0 ? pid : -1; }
        catch (NumberFormatException e) { return -1; }
    }
    public static int current() {
        try {
            BufferedReader reader = new BufferedReader(new FileReader("/proc/self/stat"));
            try { return parse(reader.readLine()); } finally { reader.close(); }
        } catch (IOException e) { return -1; }
    }
}
