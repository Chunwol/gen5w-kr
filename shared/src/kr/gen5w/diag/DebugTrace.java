package kr.gen5w.diag;

import java.io.File;
import java.util.LinkedHashMap;

/** Switchable, bounded boundary observations. No strings from a phone or a route. */
public final class DebugTrace {
    public interface Sink { void write(String line); }
    private static final DebugTrace DEFAULT = new DebugTrace();
    private static final Sink STDERR = new Sink() {
        public void write(String line) { System.err.println("Gen5wTrace " + line); }
    };
    private static final File FLAG = new File("/data/nemesis/gen5wkr.debug-on");
    private static long checked;
    private static boolean enabled;
    private final LinkedHashMap<String, Stamp> stamps = new LinkedHashMap<String, Stamp>();
    private static final class Stamp {
        final long at; final String values;
        Stamp(long at, String values) { this.at = at; this.values = values; }
    }
    public static synchronized boolean enabled() {
        long now = System.nanoTime() / 1000000L;
        if (checked == 0 || now < checked || now - checked >= 500) {
            checked = now;
            try { enabled = FLAG.isFile() && FLAG.getCanonicalFile().equals(FLAG.getAbsoluteFile()); }
            catch (Exception unavailable) { enabled = false; }
        }
        return enabled;
    }
    public static void event(String code, long... values) {
        DEFAULT.emit(STDERR, enabled(), code, values, System.nanoTime() / 1000000L);
    }
    public synchronized boolean emit(Sink sink, boolean on, String code, long[] values, long now) {
        if (!on || sink == null || now < 0 || code == null || !code.matches("[a-zA-Z0-9_.-]{1,48}")
                || values == null || values.length > 8) return false;
        StringBuilder numbers = new StringBuilder();
        for (long value : values) { if (numbers.length() > 0) numbers.append(','); numbers.append(value); }
        String data = numbers.toString();
        Stamp old = stamps.get(code);
        if (old != null && old.values.equals(data) && now >= old.at && now - old.at < 1000) return false;
        if (old == null && stamps.size() >= 64) stamps.remove(stamps.keySet().iterator().next());
        stamps.put(code, new Stamp(now, data));
        try { sink.write("code=" + code + " monotonicMs=" + now + " values=" + data); return true; }
        catch (RuntimeException unavailable) { return false; }
    }
}
