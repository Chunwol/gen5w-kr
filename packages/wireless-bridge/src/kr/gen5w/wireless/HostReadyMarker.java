package kr.gen5w.wireless;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

/** A PID alone can be reused; bind readiness to this process in this boot. */
final class HostReadyMarker {
    static String content(int pid, String boot, String stat) throws IOException {
        if (pid <= 1 || boot == null || !boot.matches("[0-9a-f-]{8,64}")
                || stat == null || !stat.startsWith(pid + " (")) throw new IOException("invalid host identity");
        int end = stat.lastIndexOf(") ");
        if (end < 0) throw new IOException("invalid process stat");
        String[] fields = stat.substring(end + 2).trim().split("\\s+");
        if (fields.length < 20 || !fields[19].matches("[0-9]+")
                || "Z".equals(fields[0]) || "X".equals(fields[0])) throw new IOException("dead host identity");
        return pid + "\nboot_id=" + boot + "\nstarttime=" + fields[19] + "\n";
    }
    private static String line(String path) throws IOException {
        BufferedReader input = new BufferedReader(new FileReader(path));
        try { return input.readLine(); } finally { input.close(); }
    }
    static String current(int pid) throws IOException {
        return content(pid, line("/proc/sys/kernel/random/boot_id"), line("/proc/self/stat"));
    }
}
