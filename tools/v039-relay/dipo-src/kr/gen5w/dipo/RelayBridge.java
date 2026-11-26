package kr.gen5w.dipo;

import android.content.Intent;
import android.os.RemoteException;
import android.util.Log;
import com.daudio.app.dipo.telechips.CarPlayService;
import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2ListenerInfo;
import com.tcc.iap2.Iap2NotiMsg;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Locale;

/** Process-local component-5 handover for the exact V039 DiPO application. */
public final class RelayBridge {
    private static final int COMPONENT_USB = 1;
    private static final int COMPONENT_BT_CARPLAY = 4;
    private static final int COMPONENT_CARPLAY = 5;
    private static final int NOTI_IDENTIFICATION_ACCEPTED = 0;
    private static final int NOTI_TRANSPORT_IDENTIFIER = 24;
    private static final String TAG = "Gen5wWireless";
    private static final int LISTENER_CARPLAY_TRANSPORT = 2048;
    private static final int NOTI_CARPLAY_TRANSPORT = 81;
    private static final int MAX_PENDING = 64;
    private static final int MAX_PENDING_BYTES = 1024 * 1024;
    private static final String HOST_PACKAGE = "kr.gen5w.wirelesshost";
    private static final String HANDOVER_REQUESTED = "kr.gen5w.wireless.RELAY_HANDOVER_REQUESTED";
    private static final String HANDOVER_CONNECTED = "kr.gen5w.wireless.RELAY_HANDOVER_CONNECTED";
    private static final String HANDOVER_DISCONNECTED = "kr.gen5w.wireless.RELAY_HANDOVER_DISCONNECTED";

    private static final Object LOCK = new Object();
    private static final Object BINDER_CALLBACK_LOCK = new Object();
    private static final ArrayDeque<byte[]> PENDING = new ArrayDeque<byte[]>();
    private static IIap2Service service;
    private static IIap2Service binding;
    private static long bindingSequence;
    private static CarPlayService carPlay;
    private static boolean wireless;
    private static boolean requested;
    private static boolean connected;
    private static boolean present;
    private static boolean wired;
    private static boolean usb;
    /** Binder listener instance whose OEM connect callback actually marked DiPO connected. */
    private static Object dipoConnectedOwner;
    /** Binder listener instance with an active OEM connect call currently in flight. */
    private static Object dipoConnectingOwner;
    /** Monotonic token bumped on connect reservation and disconnect to fence stale completions. */
    private static long dipoListenerGeneration;
    /** Thread-local marker while a synthetic 4/5->1 wireless listener call is executing OEM original. */
    private static final ThreadLocal<Boolean> SYNTHETIC_USB = new ThreadLocal<Boolean>();
    /** Thread-local marker set when localConnected actually reaches OEM Hook.original(1, ...). */
    private static final ThreadLocal<Boolean> LOCAL_DELIVERED = new ThreadLocal<Boolean>();
    /** TransportListener has observed component 5 connected from Iap2Service. */
    private static boolean transportReady;
    /** Monotonic epoch bumped on each component-5 connect and retired on session end. */
    private static long transportEpoch;
    private static long retiredTransportEpoch;
    private static int pendingBytes;
    private static boolean draining;
    private static long generation;
    private static long startedGeneration = -1;
    /** Relay counters (diagnostics only): car->iAP2 queued/delivered/dropped, iAP2->car sent/dropped. */
    private static long carIn, carDelivered, carDropped, iapOut, iapDropped;

    private RelayBridge() {}

    /** Used only by V039's session-details reconnect path; null means keep stored identity. */
    public static String reconnectAddress(String iap, String session) {
        String selected = iap == null || iap.length() == 0 ? session : iap;
        return selected == null || selected.length() == 0 ? null : selected.toUpperCase(Locale.US);
    }

    public static void bind(IIap2Service value) {
        if (value == null) return;
        long sequence;
        long token;
        CarPlayService owner;
        synchronized (LOCK) {
            if (service == value || binding == value) return;
            if (service != null) {
                if (transportReady && transportEpoch > retiredTransportEpoch) retiredTransportEpoch = transportEpoch;
                connected = false; transportReady = false;
            }
            service = null;
            binding = value;
            sequence = ++bindingSequence;
        }
        try {
            Iap2ListenerInfo info = new Iap2ListenerInfo();
            info.onSetSupportType(LISTENER_CARPLAY_TRANSPORT);
            info.onSetListenerName("gen5wkr.cp5");
            boolean accepted = value.Iap2SvcInit(new TransportListener(sequence), info);
            synchronized (LOCK) {
                if (sequence != bindingSequence) return;
                binding = null;
                if (accepted) service = value;
                else {
                    bindingSequence++;
                    if (transportReady && transportEpoch > retiredTransportEpoch) retiredTransportEpoch = transportEpoch;
                    connected = false; transportReady = false;
                }
                owner = carPlay; token = generation;
            }
            if (!accepted) kr.gen5w.diag.SafeDiagnostic.failure("cp5.register.rejected", null);
            else {
                flushPending(value);
                notifySession(owner, token, HANDOVER_CONNECTED);
            }
        } catch (RemoteException failure) { registrationFailed(value, sequence, failure); }
        catch (RuntimeException failure) { registrationFailed(value, sequence, failure); }
    }
    private static void registrationFailed(IIap2Service value, long sequence, Exception failure) {
        synchronized (LOCK) {
            if (sequence == bindingSequence && binding == value) {
                binding = null; bindingSequence++;
                if (transportReady && transportEpoch > retiredTransportEpoch) retiredTransportEpoch = transportEpoch;
                connected = false; transportReady = false;
            }
        }
        kr.gen5w.diag.SafeDiagnostic.failure("cp5.register", failure);
    }

    /**
     * Entry of V039 DiPO's own iAP2 listener (e/g.connected). That listener only
     * enables notifications and activates DipoService.hH when serial != null and
     * component == 1. Atomically reserve an in-flight ticket per listener owner so
     * concurrent 4/5 callbacks cannot trigger duplicate CarPlay starts and a
     * concurrent disconnect invalidates stale connect completions before committing.
     */
    public static int prepareListenerConnected(Object owner, int component, String serial, long[] ticketOut) {
        if (ticketOut != null && ticketOut.length > 0) ticketOut[0] = 0L;
        if (serial == null) return component;
        int mapped = component;
        String eventLog = null;
        synchronized (LOCK) {
            if (component == COMPONENT_BT_CARPLAY) {
                if (dipoConnectedOwner == owner || dipoConnectingOwner == owner) {
                    mapped = -1;
                    eventLog = "path=dipo event=listener result=bluetooth-notify-on component=4";
                } else {
                    dipoConnectingOwner = owner;
                    long token = ++dipoListenerGeneration;
                    if (ticketOut != null && ticketOut.length > 0) ticketOut[0] = token;
                    mapped = COMPONENT_USB;
                    eventLog = "path=dipo event=listener result=bluetooth-as-phone component=4";
                }
            } else if (component == COMPONENT_CARPLAY) {
                if (dipoConnectedOwner != owner && dipoConnectingOwner != owner) {
                    dipoConnectingOwner = owner;
                    long token = ++dipoListenerGeneration;
                    if (ticketOut != null && ticketOut.length > 0) ticketOut[0] = token;
                    mapped = COMPONENT_USB;
                    eventLog = "path=dipo event=listener result=channel-as-phone component=5";
                } else {
                    mapped = -1;
                    eventLog = "path=dipo event=listener result=channel-notify-on component=5";
                }
            } else if (component == COMPONENT_USB) {
                dipoConnectingOwner = owner;
                long token = ++dipoListenerGeneration;
                if (ticketOut != null && ticketOut.length > 0) ticketOut[0] = token;
            }
        }
        if (eventLog != null) log(eventLog);
        return mapped;
    }

    public static Boolean enterBinderConnected(boolean syntheticUsb) {
        Boolean previous = SYNTHETIC_USB.get();
        SYNTHETIC_USB.set(Boolean.valueOf(syntheticUsb));
        return previous;
    }

    public static void exitBinderConnected(Boolean previous) {
        if (previous == null) SYNTHETIC_USB.remove();
        else SYNTHETIC_USB.set(previous);
    }

    public static Boolean beginLocalDeliveryTracking() {
        Boolean previous = LOCAL_DELIVERED.get();
        LOCAL_DELIVERED.set(Boolean.FALSE);
        return previous;
    }

    public static boolean consumeLocalDeliveryTracking(Boolean previous) {
        boolean delivered = Boolean.TRUE.equals(LOCAL_DELIVERED.get());
        if (previous == null) LOCAL_DELIVERED.remove();
        else LOCAL_DELIVERED.set(previous);
        return delivered;
    }

    public static void markLocalConnectedDelivered(int component) {
        if (component == COMPONENT_USB) LOCAL_DELIVERED.set(Boolean.TRUE);
    }

    /** Separate monitor serializing OEM binder connected/disconnected callbacks end-to-end. */
    public static Object binderCallbackLock() {
        return BINDER_CALLBACK_LOCK;
    }

    public static void finishListenerConnected(Object owner, int mapped, long token, boolean localDelivered) {
        synchronized (LOCK) {
            if (token == 0L || token != dipoListenerGeneration) return;
            if (dipoConnectingOwner == owner) dipoConnectingOwner = null;
            if (mapped == COMPONENT_USB && localDelivered) {
                dipoConnectedOwner = owner;
            }
        }
    }

    public static boolean isConnectedOwner(Object owner) {
        synchronized (LOCK) {
            return owner != null && dipoConnectedOwner == owner;
        }
    }

    /** Called when DiPO's binder listener actually processes a disconnect (not ignored). */
    public static void listenerDisconnected(Object owner, int component) {
        synchronized (LOCK) {
            if (component == COMPONENT_USB || component == COMPONENT_BT_CARPLAY || component == COMPONENT_CARPLAY) {
                if (owner == null || dipoConnectedOwner == owner || dipoConnectingOwner == owner) {
                    dipoListenerGeneration++;
                    dipoConnectingOwner = null;
                    if (owner == null || dipoConnectedOwner == owner) dipoConnectedOwner = null;
                }
            }
        }
    }

    /** DiPO's listener: the Bluetooth and channel sessions ending while wireless CarPlay runs are not a phone leaving. */
    public static boolean ignoreListenerDisconnect(int component) {
        boolean ignore;
        synchronized (LOCK) {
            ignore = (component == COMPONENT_BT_CARPLAY || component == COMPONENT_CARPLAY)
                    && present && !wired && !usb && (wireless || requested);
        }
        if (ignore) log("path=dipo event=listener result=ignore-disconnect component=" + component);
        return ignore;
    }

    /** DiPO's listener: the channel session's identification is not a new phone (it would restart AirPlay). */
    public static boolean dropListenerNotify(int what) {
        if (what != NOTI_IDENTIFICATION_ACCEPTED && what != NOTI_TRANSPORT_IDENTIFIER) return false;
        boolean drop;
        synchronized (LOCK) {
            drop = present && !wired && !usb && requested;
        }
        if (drop) log("path=dipo event=listener result=drop-notify what=" + what);
        return drop;
    }

    private static void log(String message) {
        try { Log.i(TAG, message); } catch (RuntimeException ignored) { }
    }

    /** First frames and then every 50th, so a live session stays readable in logcat. */
    private static void count(String kind, long n, int length, String state) {
        if (n <= 8 || n % 50 == 0) log("path=cp5 event=" + kind + " n=" + n + " len=" + length + " " + state);
    }

    private static String state() {
        return "present=" + present + " wireless=" + wireless + " wired=" + wired + " usb=" + usb
                + " requested=" + requested + " connected=" + connected + " service=" + (service != null)
                + " pending=" + PENDING.size();
    }

    /** Preserve the component-4 peer identity and consume only component 5. */
    public static boolean connected(int component, String value) {
        return connected(component, value, 0);
    }

    private static boolean connected(int component, String value, long sequence) {
        IIap2Service target;
        CarPlayService owner;
        long token;
        if (sequence != 0) log("path=cp5 event=iap2-connected component=" + component);
        synchronized (LOCK) {
            if (sequence != 0 && sequence != bindingSequence) return true;
        // Component 4 remains owned by the host-side adapter. The original
        // listener must still receive it, so return false for every non-5 event.
            if (component == COMPONENT_USB) {
                // DiPO's own listener sees the relay's wireless session as 1 (SYNTHETIC_USB).
                if (sequence == 0 && Boolean.TRUE.equals(SYNTHETIC_USB.get())) {
                    // Preserve usb=false while this binder thread delivers 4/5->1.
                } else {
                    usb = true;
                }
            }
            if (component != COMPONENT_CARPLAY) return false;
            transportReady = true;
            transportEpoch++;
            if (!present || wired || usb || !requested) return true;
            connected = true;
            target = service;
            owner = carPlay; token = generation;
        }
        flushPending(target);
        notifySession(owner, token, HANDOVER_CONNECTED);
        return true;
    }

    private static void flushPending(IIap2Service target) {
        synchronized (LOCK) {
            if (draining || PENDING.isEmpty() || target == null || target != service || !connected || !present || wired || usb) return;
            draining = true;
        }
        try {
            while (true) {
                byte[] frame;
                long token;
                synchronized (LOCK) {
                    if (target != service || !connected || !present || wired || usb || PENDING.isEmpty()) return;
                    frame = PENDING.removeFirst();
                    pendingBytes -= frame.length;
                    token = generation;
                }
                // The V039 iAP2 server (V200710.1) always returns false from this call,
                // even after passing the data on; only an exception means it was lost.
                try {
                    target.Iap2SvcTransportReadDone(frame, frame.length);
                    long n; String st;
                    synchronized (LOCK) { n = ++carDelivered; st = state(); }
                    count("car-to-iap2.delivered", n, frame.length, st);
                } catch (RemoteException failure) { abort(token, "cp5.transport", failure); return; }
                catch (RuntimeException failure) { abort(token, "cp5.transport", failure); return; }
            }
        } finally {
            synchronized (LOCK) { draining = false; target = service; }
            // A replacement session may have queued data while the old IPC returned.
            flushPending(target);
        }
    }

    private static void clearPending() { PENDING.clear(); pendingBytes = 0; }

    private static void abort(long token, String code, Exception failure) {
        CarPlayService owner;
        long sentAt;
        synchronized (LOCK) {
            if (token != generation || !present) return;
            owner = carPlay;
            if (transportReady && transportEpoch > retiredTransportEpoch) {
                retiredTransportEpoch = transportEpoch;
            }
            transportReady = false;
            present = false; requested = false; connected = false;
            clearPending();
            sentAt = android.os.SystemClock.elapsedRealtime();
        }
        kr.gen5w.diag.SafeDiagnostic.failure(code, failure);
        notifyOwner(owner, HANDOVER_DISCONNECTED, sentAt);
    }

    public static boolean disconnected(int component) {
        return disconnected(component, 0);
    }

    /** Process-local callback runs only when binderDisconnected allowed the disconnect through. */
    public static boolean localDisconnected(int component) {
        disconnected(component, 0);
        return false;
    }

    private static boolean disconnected(int component, long sequence) {
        CarPlayService owner;
        long token, eventAt;
        if (sequence != 0) log("path=cp5 event=iap2-disconnected component=" + component);
        synchronized (LOCK) {
            if (sequence != 0 && sequence != bindingSequence) return true;
            if (component == 1) usb = false;
            if (component != COMPONENT_CARPLAY) return false;
            boolean staleRetired = !connected && transportEpoch <= retiredTransportEpoch;
            transportReady = false;
            if (staleRetired) return true;
            connected = false;
            requested = false;
            clearPending();
            owner = carPlay; token = generation;
            eventAt = android.os.SystemClock.elapsedRealtime();
        }
        notifySession(owner, token, HANDOVER_DISCONNECTED, eventAt);
        return true;
    }

    public static void sessionCreated(CarPlayService value) {
        if (value == null) return;
        synchronized (LOCK) {
            carPlay = value;
            generation++;
            present = true;
            wired = false;
            wireless = false;
            requested = false;
            connected = false;
            carIn = carDelivered = carDropped = iapOut = iapDropped = 0;
            clearPending();
        }
    }

    /**
     * A wireless session is the handover: DiPO's own onSessionStarted then turns
     * Bluetooth off (onDisableBluetooth), so the phone's Bluetooth side ends seconds
     * later, possibly before any CarPlay-channel iAP2 data (car, 2026-11-12 19:01:59).
     * The host must already own the Wi-Fi session by then and start component 5.
     */
    public static void sessionStarted(CarPlayService owner, int transport) {
        boolean requestNow = false;
        boolean connectNow = false;
        IIap2Service target = null;
        long token;
        synchronized (LOCK) {
            if (!present || owner != carPlay) return;
            startedGeneration = generation;
            LOCK.notifyAll();
            wireless = transport == 1;
            wired = !wireless;
            if (wired) { requested = false; connected = false; clearPending(); }
            else if (!usb && !requested) {
                requested = true;
                requestNow = true;
                if (transportReady && service != null) {
                    connected = true;
                    connectNow = true;
                    target = service;
                }
            }
            token = generation;
        }
        if (requestNow) {
            log("path=dipo event=session result=wireless-handover");
            notifySession(owner, token, HANDOVER_REQUESTED);
        }
        if (connectNow) {
            flushPending(target);
            notifySession(owner, token, HANDOVER_CONNECTED);
        }
    }

    /** Keep the phone's Bluetooth link only for an active wireless CarPlay session. */
    public static boolean keepBluetoothForWireless() {
        synchronized (LOCK) {
            return present && wireless && !wired && !usb;
        }
    }

    public static void sessionFinalized(CarPlayService owner) {
        finalizeWirelessSession(owner);
    }

    /**
     * Finalizes the active session and, when a wireless CarPlay session had remapped a
     * BT/channel listener onto DiPO component 1 (with original disconnect suppressed during
     * handover), returns that listener so DipoAdapters can notify DiPO of component-1 end.
     */
    public static Object finalizeWirelessSession(CarPlayService owner) {
        return finalizeWirelessSession(owner, null);
    }

    public static Object finalizeWirelessSession(CarPlayService owner, long[] finalizeTicketOut) {
        if (finalizeTicketOut != null && finalizeTicketOut.length > 0) finalizeTicketOut[0] = 0L;
        Object disconnectedOwner = null;
        long sentAt = 0L;
        long endedGeneration;
        synchronized (LOCK) {
            if (carPlay != owner) return null;
            if (wireless && !wired && !usb && dipoConnectedOwner != null) {
                disconnectedOwner = dipoConnectedOwner;
            }
            if (transportReady && transportEpoch > retiredTransportEpoch) {
                retiredTransportEpoch = transportEpoch;
            }
            sentAt = android.os.SystemClock.elapsedRealtime();
            endedGeneration = generation;
            transportReady = false;
            present = false;
            requested = false;
            connected = false;
            wireless = false;
            dipoConnectedOwner = null;
            dipoConnectingOwner = null;
            long ticket = ++dipoListenerGeneration;
            if (disconnectedOwner != null && finalizeTicketOut != null && finalizeTicketOut.length > 0) {
                finalizeTicketOut[0] = ticket;
            }
            clearPending();
            if (carPlay == owner) carPlay = null;
        }
        // Stock CarPlayService.java:768-789 native finalize notifies session end, not camera visibility.
        boolean delivered = false;
        try {
            owner.sendBroadcast(new Intent(HANDOVER_DISCONNECTED).setPackage(HOST_PACKAGE)
                    .putExtra("sent_at", sentAt).putExtra("dipo_generation", endedGeneration));
            delivered = true; // broadcast enqueue succeeded; host logs actual receipt separately.
        } catch (RuntimeException failure) { kr.gen5w.diag.SafeDiagnostic.failure("cp5.finalize.notify", failure); }
        log("path=dipo event=session-finalized generation=" + endedGeneration + " time=" + sentAt
                + " disconnect-delivery=" + (delivered ? "enqueued" : "failed"));
        Log.i("Gen5wDrive", "D1|" + sentAt + "|1|40|" + endedGeneration + "|" + (delivered ? 1 : 0) + "|0|0|0|0");
        return disconnectedOwner;
    }

    /** True only if no newer DiPO connect reservation/session superseded the finalized one. */
    public static boolean shouldDeliverFinalizeDisconnect(Object owner, long finalizeTicket) {
        synchronized (LOCK) {
            return owner != null
                    && finalizeTicket != 0L
                    && dipoListenerGeneration == finalizeTicket
                    && dipoConnectedOwner == null
                    && dipoConnectingOwner == null;
        }
    }

    /** Stops/disconnects an active CarPlay session so split-screen or RHD changes renegotiate cleanly. */
    public static boolean requestCarPlayRestart() { return requestCarPlayRestartResult() == RESTART_REQUESTED; }

    public static final int RESTART_UNAVAILABLE = 0, RESTART_REQUESTED = 1, RESTART_REJECTED = 2,
            RESTART_APPLIED = 3, RESTART_NONE = 4;

    /** Await a replacement native session, never infer completion from elapsed sleep. */
    public static int requestCarPlayRestartAndWait(long timeoutMs) {
        // One restart at a time: the stock-update flag, the generation baseline and the single
        // fallback belong to this request only. The shell's am broadcast is a background ordered
        // broadcast (V039 ActivityManagerService.java:188 BROADCAST_BG_TIMEOUT = 60 s).
        synchronized (RESTART_LOCK) { return restartAndWaitLocked(timeoutMs); }
    }

    private static final Object RESTART_LOCK = new Object();

    private static int restartAndWaitLocked(long timeoutMs) {
        final long before;
        synchronized (LOCK) { before = generation; }
        lastRequestStockUpdate = false;
        int result = requestCarPlayRestartResult();
        if (result != RESTART_REQUESTED) return result;
        long total = Math.min(Math.max(timeoutMs, 0), 12000L);
        long start = System.nanoTime();
        if (lastRequestStockUpdate) {
            // DipoService.H(true) only posts message 0x44; E() may update the screen configuration and
            // return without bP() stop/recreate (DipoService.smali:37823-37908, 38066-38208). If no
            // replacement session follows, renegotiate once through the native disconnect path.
            if (awaitReplacement(before, start + Math.min(total, 3000L) * 1000000L)) return RESTART_APPLIED;
            CarPlayService target;
            synchronized (LOCK) { target = present && generation == before ? carPlay : null; }
            if (target != null) {
                log("path=dipo event=split-restart result=stock-update-no-restart fallback=disconnect");
                synchronized (LOCK) { if (!(present && generation == before && carPlay == target)) target = null; }
                int fallback = target == null ? RESTART_REQUESTED : disconnectForRestart(target);
                if (fallback != RESTART_REQUESTED) return fallback;
            }
        }
        return awaitReplacement(before, start + total * 1000000L) ? RESTART_APPLIED : RESTART_REQUESTED;
    }

    private static volatile boolean lastRequestStockUpdate;

    private static boolean awaitReplacement(long before, long deadline) {
        synchronized (LOCK) {
            while (!(present && generation > before && startedGeneration == generation)) {
                long remaining = deadline - System.nanoTime();
                if (remaining <= 0) return false;
                try { LOCK.wait(Math.max(1L, remaining / 1000000L)); }
                catch (InterruptedException stopped) { Thread.currentThread().interrupt(); return false; }
            }
        }
        return true;
    }

    /** NONE: no live session (nothing to renegotiate; the stored setting applies at the next connect). REJECTED: the session refused or failed to disconnect. */
    public static int requestCarPlayRestartResult() {
        CarPlayService target;
        synchronized (LOCK) {
            target = present ? carPlay : null;
        }
        if (target == null) {
            log("path=dipo event=split-restart result=no-active-session");
            return RESTART_NONE;
        }
        // V039 DipoService.java:2165 bC() singleton; :6616 H(true) -> message 68 -> E().
        // E's forced update uses bP()/nc() (DipoService.smali:38223-38232).
        try {
            Class<?> stock = Class.forName("com.daudio.app.dipo.service.DipoService", false, target.getClass().getClassLoader());
            java.lang.reflect.Method update = stock.getMethod("H", Boolean.TYPE);
            java.lang.reflect.Method singleton = stock.getMethod("bC");
            Object owner = singleton.invoke(null);
            if (owner == null) return RESTART_UNAVAILABLE;
            update.invoke(owner, Boolean.TRUE);
            lastRequestStockUpdate = true;
            log("path=dipo event=split-restart result=stock-requested");
            return RESTART_REQUESTED;
        } catch (ClassNotFoundException missing) {
            // Older variants without the stock configuration API retain the disconnect fallback.
        } catch (NoSuchMethodException missing) {
            // Only a missing API permits fallback; an invocation failure must not disconnect again.
        } catch (Exception failure) {
            kr.gen5w.diag.SafeDiagnostic.failure("dipo.split.configuration", failure);
            return RESTART_REJECTED;
        } catch (LinkageError unavailable) {
            return RESTART_UNAVAILABLE;
        }
        return disconnectForRestart(target);
    }

    private static int disconnectForRestart(CarPlayService target) {
        try {
            Object accepted = target.getClass().getMethod("disconnectCarPlay").invoke(target);
            // Stock CarPlayService.disconnectCarPlay() returns the CarPlayReturn enum (OK on success).
            boolean refused = (accepted instanceof Boolean && !((Boolean) accepted).booleanValue())
                    || (accepted instanceof Enum && !"OK".equals(((Enum<?>) accepted).name()));
            if (refused) {
                log("path=dipo event=split-restart result=disconnect-rejected");
                return RESTART_REJECTED;
            }
            log("path=dipo event=split-restart result=disconnect-requested");
            return RESTART_REQUESTED;
        } catch (NoSuchMethodException missing) {
            try {
                target.getClass().getMethod("stopCarPlay").invoke(target);
                log("path=dipo event=split-restart result=stop-requested");
                return RESTART_REQUESTED;
            } catch (Exception fallbackFailure) {
                kr.gen5w.diag.SafeDiagnostic.failure("dipo.split.restart", fallbackFailure);
                return RESTART_REJECTED;
            }
        } catch (Exception failure) {
            kr.gen5w.diag.SafeDiagnostic.failure("dipo.split.restart", failure);
            return RESTART_REJECTED;
        }
    }

    /** Bytes received by the native CarPlay channel become component-5 input. */
    public static boolean fromCarPlay(CarPlayService owner, byte[] data, int length) {
        if (owner == null || data == null || length <= 0 || length > data.length) return false;
        IIap2Service target;
        boolean sendNow;
        boolean requestNow = false;
        boolean connectNow = false;
        boolean overflow;
        long token;
        long n; String st;
        synchronized (LOCK) {
            if (!present || carPlay != owner || wired || usb) {
                n = ++carDropped; st = state();
                count("car-to-iap2.dropped", n, length, st);
                return false;
            }
            n = ++carIn;
            token = generation;
            overflow = PENDING.size() >= MAX_PENDING || length > MAX_PENDING_BYTES - pendingBytes;
            if (!requested) {
                requested = true;
                requestNow = true;
            }
            target = service;
            if (requested && !connected && transportReady && target != null) {
                connected = true;
                connectNow = true;
            }
            sendNow = connected && target != null;
            if (!overflow) { PENDING.addLast(Arrays.copyOf(data, length)); pendingBytes += length; }
        }
        synchronized (LOCK) { st = state(); }
        count("car-to-iap2.queued", n, length, st);
        if (overflow) { abort(token, "cp5.buffer.limit", null); return true; }
        if (requestNow) notifySession(owner, token, HANDOVER_REQUESTED);
        if (connectNow) notifySession(owner, token, HANDOVER_CONNECTED);
        if (!sendNow) return true;
        flushPending(target);
        return true;
    }

    /** Consume only notification 81 and write its blob through DiPO's public wrapper. */
    public static boolean fromIap2(int what, Iap2NotiMsg message) {
        return fromIap2(what, message, 0);
    }

    private static boolean fromIap2(int what, Iap2NotiMsg message, long sequence) {
        if (what != NOTI_CARPLAY_TRANSPORT) return false;
        CarPlayService target;
        long token;
        synchronized (LOCK) {
            // Notification 81 exists only for component 5, which only our handover starts.
            // The V039 server's onStartMain runs Iap2Main (it sends the link-detect
            // packet at once) before onSendConnected, so do not wait for connected(5).
            if ((sequence != 0 && sequence != bindingSequence) || service == null || !present || wired || usb || !(connected || requested)) {
                count("iap2-to-car.dropped", ++iapDropped, -1, state());
                return true;
            }
            target = carPlay;
            token = generation;
        }
        if (target == null || message == null) return true;
        Iap2NotiMsg.Iap2ObjGroup group = message.getItemGroup();
        if (group == null) return true;
        for (int i = 0; i < group.getItemCnt(); i++) {
            synchronized (LOCK) {
                if (token != generation || !present || wired || usb || !(connected || requested) || (sequence != 0 && sequence != bindingSequence)) return true;
            }
            Iap2NotiMsg.Iap2ObjItem item = group.getObjItem(i);
            if (item == null || item.getItemParamType() != Iap2NotiMsg.OBJ_BLOB) continue;
            byte[] frame = item.getItemByteArray();
            if (frame != null && frame.length > 0) {
                try {
                    target.iAPSendMessage(frame, frame.length);
                    long n; String st;
                    synchronized (LOCK) { n = ++iapOut; st = state(); }
                    count("iap2-to-car.sent", n, frame.length, st);
                }
                catch (RuntimeException failure) { log("path=cp5 event=iap2-to-car.failed " + failure); }
            }
        }
        return true;
    }

    private static void notifySession(CarPlayService owner, long token, String action) {
        notifySession(owner, token, action, 0L);
    }

    /** eventAt != 0: the time the event was recorded under LOCK by the caller (a later sample could post-date a newer attempt). */
    private static void notifySession(CarPlayService owner, long token, String action, long eventAt) {
        long sentAt;
        synchronized (LOCK) {
            if (owner != carPlay || token != generation || !present || wired || usb) return;
            if (HANDOVER_CONNECTED.equals(action) && (!connected || service == null)) return;
            if (HANDOVER_REQUESTED.equals(action) && !requested) return;
            if (HANDOVER_DISCONNECTED.equals(action) && connected) return;
            sentAt = eventAt != 0L ? eventAt : android.os.SystemClock.elapsedRealtime();
        }
        notifyOwner(owner, action, sentAt);
    }

    /** sentAt is taken when the event happened (under LOCK), so the receiver can ignore a notice older than the attempt it would cancel. */
    private static void notifyOwner(CarPlayService owner, String action, long sentAt) {
        if (owner == null) return;
        try {
            owner.sendBroadcast(new Intent(action).setPackage(HOST_PACKAGE).putExtra("sent_at", sentAt));
        } catch (RuntimeException ignored) { }
    }

    private static final class TransportListener extends IIap2Listener.Stub {
        private final long sequence;
        TransportListener(long sequence) { this.sequence = sequence; }
        public void connected(int component, String name) { RelayBridge.connected(component, name, sequence); }
        public void disconnected(int component) { RelayBridge.disconnected(component, sequence); }
        public void notify(int what, int arg1, int arg2, Iap2NotiMsg message) {
            RelayBridge.fromIap2(what, message, sequence);
        }
    }
}
