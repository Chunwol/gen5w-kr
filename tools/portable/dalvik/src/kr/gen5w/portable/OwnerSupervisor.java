package kr.gen5w.portable;

import java.io.BufferedReader;
import java.io.FileReader;
import java.lang.reflect.InvocationTargetException;

/** Runs the existing authored stock-navigation reader only while its parent lives. */
public final class OwnerSupervisor {
    private OwnerSupervisor() {}
    private static int nativePpid() {
        try {
            Class<?> libcore = Class.forName("libcore.io.Libcore");
            Object os = libcore.getField("os").get(null);
            if (os != null) {
                Object value = os.getClass().getMethod("getppid").invoke(os);
                if (value instanceof Number) return ((Number) value).intValue();
            }
        } catch (Throwable ignored) { }
        return -1;
    }
    private static int parent() {
        int ppid = nativePpid();
        if (ppid > 0) return ppid;
        try {
            BufferedReader reader = new BufferedReader(new FileReader("/proc/self/stat"));
            try {
                String stat = reader.readLine();
                int end = stat == null ? -1 : stat.lastIndexOf(") ");
                if (end < 0) return -1;
                String[] fields = stat.substring(end + 2).trim().split("\\s+");
                return fields.length < 2 ? -1 : Integer.parseInt(fields[1]);
            } finally { reader.close(); }
        } catch (Exception unavailable) { return -1; }
    }
    public static void main(String[] args) throws Throwable {
        if (args.length != 1) throw new IllegalArgumentException("parent PID required");
        final int expected = Integer.parseInt(args[0]);
        if (expected <= 1 || parent() != expected) throw new IllegalStateException("parent mismatch");
        Thread watcher = new Thread(new Runnable() {
            public void run() {
                int readErrors = 0;
                while (true) {
                    int actual = parent();
                    if (actual > 0) {
                        readErrors = 0;
                        if (actual != expected) System.exit(0);
                    } else if (++readErrors >= 3) {
                        System.exit(0);
                    }
                    try { Thread.sleep(500); } catch (InterruptedException ignored) { }
                }
            }
        }, "gen5w-portable-owner-parent");
        watcher.setDaemon(true);
        watcher.start();
        try {
            Class.forName("kr.gen5w.core.StockOwner").getMethod("main", String[].class)
                .invoke(null, new Object[]{new String[0]});
        } catch (InvocationTargetException failure) { throw failure.getCause(); }
    }
}
