package kr.gen5w.wireless;

import java.util.Arrays;

/** Pure bridge between DiPO's process-local iAP callback and iAP2 component 5. */
public final class CarPlayHandoverPipe {
    public static final int COMPONENT_CARPLAY_CHANNEL = 5;

    public enum Event {
        STARTED, DIPO_TO_IAP2, IAP2_TO_DIPO,
        DIPO_DISCONNECTED, IAP2_DISCONNECTED,
        IAP2_WRITE_FAILED, DIPO_WRITE_FAILED,
        CLEANUP_FAILED, STOPPED, OWNER_REJECTED
    }

    public enum StopReason { REQUESTED, WIRED, FOREIGN_OWNER, DIPO_DISCONNECTED, IAP2_DISCONNECTED, SHUTDOWN }

    public interface Iap2Endpoint {
        boolean readDone(int component, byte[] payload, int length);
        void stop(int component);
    }

    public interface DipoEndpoint {
        boolean receive(byte[] payload, int length);
        void close();
    }

    /** Fixed event categories only; this boundary cannot log identifiers or frame bytes. */
    public interface Diagnostics {
        void event(Event event, int component);
    }

    private final Object ownership = new Object();
    private final Iap2Endpoint iap2;
    private final DipoEndpoint dipo;
    private final Diagnostics diagnostics;
    private long ownerGeneration;
    private long lastGeneration;
    private int inFlight;
    private boolean active;
    private boolean closing;
    private boolean cleanupDone;

    public CarPlayHandoverPipe(Iap2Endpoint iap2, DipoEndpoint dipo, Diagnostics diagnostics) {
        if (iap2 == null || dipo == null || diagnostics == null) throw new IllegalArgumentException("endpoints");
        this.iap2 = iap2;
        this.dipo = dipo;
        this.diagnostics = diagnostics;
    }

    public boolean attach(long generation) {
        boolean claimed = false;
        synchronized (ownership) {
            if (!active && !closing && generation > 0 && generation > lastGeneration) {
                ownerGeneration = generation;
                lastGeneration = generation;
                active = true;
                cleanupDone = false;
                claimed = true;
            }
        }
        event(claimed ? Event.STARTED : Event.OWNER_REJECTED);
        return claimed;
    }

    /** DiPO's native outbound iAP message becomes component-5 transport input. */
    public boolean dipoToIap2(long generation, byte[] payload, int length) {
        if (!beginForward(generation, payload, length)) return false;
        byte[] frame = Arrays.copyOf(payload, length);
        boolean written;
        try { written = iap2.readDone(COMPONENT_CARPLAY_CHANNEL, frame, frame.length); }
        catch (RuntimeException e) { written = false; }
        boolean stillOwner = finishForward(generation);
        if (!written) {
            terminate(generation, Event.IAP2_WRITE_FAILED);
            return false;
        }
        if (!stillOwner) return false;
        event(Event.DIPO_TO_IAP2);
        return true;
    }

    /** Component-5 transport input is delivered to DiPO's process-local native receive boundary. */
    public boolean iap2ToDipo(long generation, byte[] payload, int length) {
        if (!beginForward(generation, payload, length)) return false;
        byte[] frame = Arrays.copyOf(payload, length);
        boolean written;
        try { written = dipo.receive(frame, frame.length); }
        catch (RuntimeException e) { written = false; }
        boolean stillOwner = finishForward(generation);
        if (!written) {
            terminate(generation, Event.DIPO_WRITE_FAILED);
            return false;
        }
        if (!stillOwner) return false;
        event(Event.IAP2_TO_DIPO);
        return true;
    }

    public boolean iap2Disconnected(long generation) {
        return terminate(generation, Event.IAP2_DISCONNECTED);
    }

    public boolean dipoDisconnected(long generation) {
        return terminate(generation, Event.DIPO_DISCONNECTED);
    }

    public boolean cancel(long generation, StopReason reason) {
        if (reason == StopReason.IAP2_DISCONNECTED) return iap2Disconnected(generation);
        if (reason == StopReason.DIPO_DISCONNECTED) return dipoDisconnected(generation);
        return terminate(generation, Event.STOPPED);
    }

    public boolean isActive() {
        synchronized (ownership) { return active; }
    }

    public long activeGeneration() {
        synchronized (ownership) { return active ? ownerGeneration : 0; }
    }

    private boolean beginForward(long generation, byte[] payload, int length) {
        synchronized (ownership) {
            if (!active || ownerGeneration != generation || payload == null || length <= 0 || length > payload.length) {
                return false;
            }
            inFlight++;
            return true;
        }
    }

    private boolean finishForward(long generation) {
        synchronized (ownership) {
            if (ownerGeneration != generation || inFlight <= 0) return false;
            inFlight--;
            boolean stillOwner = active && !closing;
            releaseIfComplete();
            return stillOwner;
        }
    }

    private boolean terminate(long generation, Event reason) {
        synchronized (ownership) {
            if (!active || ownerGeneration != generation || closing) return false;
            active = false;
            closing = true;
            cleanupDone = false;
        }
        if (reason != Event.STOPPED) event(reason);
        try { iap2.stop(COMPONENT_CARPLAY_CHANNEL); }
        catch (RuntimeException e) { event(Event.CLEANUP_FAILED); }
        try { dipo.close(); }
        catch (RuntimeException e) { event(Event.CLEANUP_FAILED); }
        event(Event.STOPPED);
        synchronized (ownership) {
            cleanupDone = true;
            releaseIfComplete();
        }
        return true;
    }

    private void releaseIfComplete() {
        if (closing && cleanupDone && inFlight == 0) {
            closing = false;
            ownerGeneration = 0;
        }
    }

    private void event(Event event) {
        try { diagnostics.event(event, COMPONENT_CARPLAY_CHANNEL); }
        catch (RuntimeException ignored) { /* Diagnostic failure cannot interrupt forwarding or teardown. */ }
    }
}
