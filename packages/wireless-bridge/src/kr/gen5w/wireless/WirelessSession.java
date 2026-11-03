package kr.gen5w.wireless;

/** Serialized transport ownership and retry policy; no Android dependencies. */
public final class WirelessSession {
    /** Try the other advertised iAP service after a socket connection failure. */
    public static int selectIapService(boolean caff, boolean cafe, int lastFailed) {
        if (caff && cafe) return lastFailed == 1 ? 2 : 1;
        if (caff) return 1;
        if (cafe) return 2;
        return 0;
    }
    /** Never log the exception message: it can contain a phone identifier. */
    public static String socketErrorKind(String message) {
        if (message == null) return "unknown";
        String m = message.toLowerCase(java.util.Locale.US);
        if (m.contains("closed") && m.contains("timeout")) return "closed-or-timeout";
        if (m.contains("refused")) return "refused";
        if (m.contains("timeout") || m.contains("timed out")) return "timeout";
        if (m.contains("service discovery")) return "service-discovery";
        if (m.contains("read failed")) return "read-failed";
        return "other";
    }
    /** The Android USB device-mode state is independent of a host CarPlay cable. */
    public static final class WiredSignal {
        private boolean attached;
        public void event(String action, boolean appleDevice) {
            if ("android.hardware.usb.action.CARPLAY_DEVICE_ATTACHED".equals(action)) attached=true;
            else if ("android.hardware.usb.action.CARPLAY_DEVICE_DETACHED".equals(action) ||
                    ("android.hardware.usb.action.USB_DEVICE_DETACHED".equals(action) && appleDevice)) attached=false;
        }
        public boolean attached() { return attached; }
    }
    public interface Port {
        void open(long generation, String address);
        void start(long generation);
        void close(long generation, boolean stopNative);
        void authenticated(long generation);
    }
    /** A cancelled worker may close its own resource, but cannot publish into a new lease. */
    public static final class Resource<T> {
        private long ticket=-1;
        private T value;
        public synchronized T reserve(long next) { T old=value;value=null;ticket=next;return old; }
        public synchronized boolean attach(long owner,T resource) {
            if(ticket!=owner || value!=null)return false;
            value=resource;return true;
        }
        public synchronized boolean current(long owner) { return ticket==owner && owner>=0; }
        public synchronized T get(long owner) { return current(owner)?value:null; }
        public synchronized boolean owns(long owner,T resource) { return current(owner) && value==resource; }
        public synchronized T detach(long owner) {
            if(!current(owner))return null;
            T old=value;value=null;ticket=-1;return old;
        }
    }
    public static boolean projectionListening(String line) {
        if(line==null)return false;
        String[] fields=line.trim().split("\\s+");
        return fields.length>3 && fields[1].endsWith(":1B58") && "0A".equals(fields[3]);
    }
    public static boolean wiredConfiguration(String value) {
        if (value == null) return false;
        for (String token : value.split(",")) if ("carplay_connect".equals(token.trim())) return true;
        return false;
    }
    public enum Phase { IDLE, CONNECTING, AUTHENTICATING, READY }
    private final Port port;
    private String candidate;
    private boolean available, wired, foreign, nativeOwned;
    private long generation, deadline, next;
    private int failures;
    private Phase phase=Phase.IDLE;
    public WirelessSession(Port port) { this.port=port; }
    public long generation() { return generation; }
    public Phase phase() { return phase; }
    public boolean current(long ticket) { return phase!=Phase.IDLE && generation==ticket; }
    public void candidate(String address, long now) {
        if (address==null || address.equals(candidate)) return;
        // Discovery also runs during retry backoff. Keep ownership until lost(),
        // otherwise two linked phones repeatedly reset the failure count/timer.
        if (candidate!=null) return;
        candidate=address; failures=0; next=now;
    }
    public void lost(String address, long now) {
        if (address==null || !address.equals(candidate)) return;
        stop(); candidate=null; failures=0; next=now;
    }
    public void environment(boolean server, boolean cable, boolean otherSession, long now) {
        available=server; wired=cable; foreign=otherSession;
        if (!server || cable || otherSession) { stop(!cable && !otherSession); next=Math.max(next,now+2000); }
    }
    public void tick(long now) {
        if (phase!=Phase.IDLE && now>=deadline && phase!=Phase.READY) { failed(generation,now); return; }
        if (phase==Phase.IDLE && available && !wired && !foreign && candidate!=null && now>=next) {
            phase=Phase.CONNECTING; generation++; deadline=now+60000;
            port.open(generation,candidate);
        }
    }
    public void socket(long ticket,long now) {
        if (!current(ticket) || phase!=Phase.CONNECTING) return;
        if (now>=deadline) { failed(ticket,now); return; }
        phase=Phase.AUTHENTICATING; nativeOwned=true; deadline=now+45000;
        port.start(ticket);
    }
    public void authenticated(long ticket,long now) {
        if(current(ticket) && phase==Phase.AUTHENTICATING && now>=deadline){failed(ticket,now);return;}
        authenticated(ticket);
    }
    public void authenticated(long ticket) {
        if (!current(ticket) || phase!=Phase.AUTHENTICATING) return;
        phase=Phase.READY; failures=0; port.authenticated(ticket);
    }
    public void failed(long ticket,long now) {
        if (!current(ticket)) return;
        stop(); failures=Math.min(6,failures+1); next=now+Math.min(60000,2000L<<(failures-1));
    }
    public void shutdown() { stop(); candidate=null; available=false; }
    private void stop() { stop(true); }
    private void stop(boolean allowNativeStop) {
        if (phase==Phase.IDLE) return;
        long old=generation; boolean owned=nativeOwned;
        phase=Phase.IDLE; nativeOwned=false; generation++;
        port.close(old,owned && allowNativeStop);
    }
}
