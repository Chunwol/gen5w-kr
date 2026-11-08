package kr.gen5w.diag;

import java.util.LinkedHashMap;
import java.util.Map;

/** Fixed-code diagnostics: never format throwable messages or payload values. */
public final class SafeDiagnostic {
    public interface Sink { void write(String line); }
    private static final int MAX_KEYS = 64;
    private static final long INTERVAL_MS = 30000;
    private static final SafeDiagnostic DEFAULT = new SafeDiagnostic();
    private static final Sink STDERR = new Sink() {
        public void write(String line) { System.err.println("Gen5wDiag " + line); }
    };
    public static boolean failure(String code, Throwable error) { return failure(code,error,0); }
    public static boolean failure(String code, Throwable error, long generation) {
        // Monotonic process clock, correlated to boot/uptime by the collector.
        return DEFAULT.emit(STDERR,code,error,generation,System.nanoTime()/1000000L);
    }
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
        String reason=reason(error);
        String identity=type+":"+reason;
        Stamp old=stamps.get(code);
        if (old != null && old.generation==generation && old.type.equals(identity)
                && now>=old.time && now-old.time<INTERVAL_MS) return false;
        if (old == null && stamps.size()>=MAX_KEYS) {
            java.util.Iterator<Map.Entry<String,Stamp>> it=stamps.entrySet().iterator();
            it.next();it.remove();
        }
        stamps.put(code,new Stamp(now,generation,identity));
        String line="ERR code="+code+" exception="+type+" reason="+reason+" generation="+generation+" monotonicMs="+now;
        try { sink.write(line);return true; }
        catch (RuntimeException ignored) { return false; }
        catch (LinkageError ignored) { return false; }
    }

    private static String reason(Throwable error) {
        try {
            for(int depth=0;error!=null&&depth<4;depth++,error=error.getCause()) {
                String type=error.getClass().getSimpleName();
                String message=error.getMessage();
                // Only classifications escape; the message itself never does.
                if(error instanceof SecurityException) return "permission";
                if(type.contains("Timeout")) return "timeout";
                if(type.equals("ApRejectedException")) return "rejected";
                if(error instanceof java.util.concurrent.CancellationException) return "cancelled";
                if(message!=null) {
                    if(message.contains("Permission denied")||message.contains("Operation not permitted")) return "permission";
                    if(message.contains("No space left")||message.contains("ENOSPC")) return "no-space";
                    if(message.contains("Read-only file system")||message.contains("EROFS")) return "read-only";
                    if(message.contains("Device or resource busy")||message.contains("EBUSY")) return "busy";
                    if(message.contains("Input/output error")||message.contains("EIO")) return "io";
                }
                if(error instanceof java.io.FileNotFoundException) return "missing";
                if(error instanceof LinkageError) return "linkage";
                if(type.equals("RemoteException")) return "binder";
            }
        } catch(RuntimeException ignored) { }
        return "unknown";
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
