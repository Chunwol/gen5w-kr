package kr.gen5w.wireless;

import java.util.Arrays;

/** Android-independent byte boundary between Broadcom SPP and iAP2 component 4. */
public final class BtRelayPipe {
    public static final int COMPONENT_BLUETOOTH_CARPLAY = 4;

    public enum Event {
        STARTED, PHONE_TO_IAP2, IAP2_TO_PHONE, PHONE_DISCONNECTED,
        IAP2_DISCONNECTED, IAP2_WRITE_FAILED, SPP_WRITE_FAILED,
        CLEANUP_FAILED, STOPPED, OWNER_REJECTED
    }

    public interface SppEndpoint {
        boolean write(byte[] payload, int length);
        void disconnect();
    }

    public interface Iap2Endpoint {
        boolean readDone(int component, byte[] payload, int length);
        void stop(int component);
    }

    /** Deliberately accepts only fixed categories and the fixed component, never peer data. */
    public interface Diagnostics { void event(Event event, int component); }

    private final SppEndpoint spp;
    private final Iap2Endpoint iap2;
    private final Diagnostics diagnostics;
    private final Object sppWrites = new Object();
    private final Object iap2Writes = new Object();
    private long ownerGeneration;
    private long lastGeneration;
    private boolean active;

    public BtRelayPipe(SppEndpoint spp, Iap2Endpoint iap2, Diagnostics diagnostics) {
        if (spp == null || iap2 == null || diagnostics == null) throw new IllegalArgumentException("endpoints");
        this.spp = spp;
        this.iap2 = iap2;
        this.diagnostics = diagnostics;
    }

    /** Claims the single pipe for a fresh lifecycle generation after SPP is connected. */
    public boolean attach(long generation) {
        boolean rejected;
        synchronized (this) {
            rejected = active || generation <= 0 || generation <= lastGeneration;
            if (!rejected) {
                ownerGeneration = generation;
                lastGeneration = generation;
                active = true;
            }
        }
        if (rejected) { event(Event.OWNER_REJECTED); return false; }
        event(Event.STARTED);
        return true;
    }

    public boolean phoneToIap2(long generation, byte[] payload, int length) {
        if (!valid(payload, length)) return false;
        byte[] frame = Arrays.copyOf(payload, length);
        synchronized (this) { if (!owns(generation)) return false; }
        boolean written;
        try {
            synchronized (iap2Writes) { written = iap2.readDone(COMPONENT_BLUETOOTH_CARPLAY, frame, frame.length); }
        } catch (RuntimeException e) { written = false; }
        synchronized (this) { if (!owns(generation)) return false; }
        if (!written) {
            event(Event.IAP2_WRITE_FAILED);
            stop(generation);
            return false;
        }
        event(Event.PHONE_TO_IAP2);
        return true;
    }

    public boolean iap2ToPhone(long generation, byte[] payload, int length) {
        if (!valid(payload, length)) return false;
        byte[] frame = Arrays.copyOf(payload, length);
        synchronized (this) { if (!owns(generation)) return false; }
        boolean written;
        try {
            synchronized (sppWrites) { written = spp.write(frame, frame.length); }
        } catch (RuntimeException e) { written = false; }
        synchronized (this) { if (!owns(generation)) return false; }
        if (!written) {
            event(Event.SPP_WRITE_FAILED);
            stop(generation);
            return false;
        }
        event(Event.IAP2_TO_PHONE);
        return true;
    }

    public boolean phoneDisconnected(long generation) {
        synchronized (this) { if (!owns(generation)) return false; }
        event(Event.PHONE_DISCONNECTED);
        return stop(generation);
    }

    public boolean iap2Disconnected(long generation) {
        synchronized (this) { if (!owns(generation)) return false; }
        event(Event.IAP2_DISCONNECTED);
        return stop(generation);
    }

    public boolean close(long generation) { return stop(generation); }

    public synchronized boolean isActive() { return active; }
    public synchronized long activeGeneration() { return active ? ownerGeneration : 0; }

    private boolean stop(long generation) {
        synchronized (this) {
            if (!owns(generation)) return false;
            active = false;
            ownerGeneration = 0;
        }
        cleanupEndpoints();
        return true;
    }

    private synchronized boolean owns(long generation) { return active && ownerGeneration == generation; }

    private static boolean valid(byte[] payload, int length) {
        return payload != null && length > 0 && length <= payload.length;
    }

    /** No endpoint or diagnostic callback runs while the ownership monitor is held. */
    private void cleanupEndpoints() {
        try { iap2.stop(COMPONENT_BLUETOOTH_CARPLAY); }
        catch (RuntimeException e) { event(Event.CLEANUP_FAILED); }
        try { spp.disconnect(); }
        catch (RuntimeException e) { event(Event.CLEANUP_FAILED); }
        event(Event.STOPPED);
    }

    private void event(Event event) {
        try { diagnostics.event(event, COMPONENT_BLUETOOTH_CARPLAY); }
        catch (RuntimeException ignored) { /* Diagnostics must not interrupt transport cleanup. */ }
    }
}
