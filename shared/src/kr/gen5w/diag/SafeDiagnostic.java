package kr.gen5w.diag;

import java.util.LinkedHashMap;
import java.util.Map;

/** Fixed-code diagnostics: never format throwable messages or payload values. */
public final class SafeDiagnostic {
    public interface Sink { void write(String line); }
    private static final int MAX_KEYS = 64;
    private static final long INTERVAL_MS = 30000;
    private static final class Stamp {
        final long time, generation;
        final String type;
        Stamp(long time,long generation,String type) { this.time=time;this.generation=generation;this.type=type; }
    }
    private final LinkedHashMap<String,Stamp> stamps = new LinkedHashMap<String,Stamp>();

    public synchronized boolean emit(Sink sink, String code, Throwable error, long generation, long now) {
        if (sink == null || !token(code) || now < 0) return false;
        String type = error == null ? "unavailable" : error.getClass().getSimpleName();
        if (!token(type)) type="Exception";
        Stamp old=stamps.get(code);
        if (old != null && old.generation==generation && old.type.equals(type)
                && now>=old.time && now-old.time<INTERVAL_MS) return false;
        if (old == null && stamps.size()>=MAX_KEYS) {
            java.util.Iterator<Map.Entry<String,Stamp>> it=stamps.entrySet().iterator();
            it.next();it.remove();
        }
        stamps.put(code,new Stamp(now,generation,type));
        String line="ERR code="+code+" exception="+type+" generation="+generation+" uptimeMs="+now;
        try { sink.write(line);return true; }
        catch (RuntimeException ignored) { return false; }
        catch (LinkageError ignored) { return false; }
    }

    private static boolean token(String value) {
        if (value == null || value.length()==0 || value.length()>64) return false;
        for (int i=0;i<value.length();i++) {
            char c=value.charAt(i);
            if (!(c>='a'&&c<='z') && !(c>='A'&&c<='Z') && !(c>='0'&&c<='9') && c!='.' && c!='_' && c!='-') return false;
        }
        return true;
    }
}
