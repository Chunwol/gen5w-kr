package kr.gen5w.dipo;

import android.content.Intent;
import android.os.RemoteException;
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
    private static final int COMPONENT_CARPLAY = 5;
    private static final int LISTENER_CARPLAY_TRANSPORT = 2048;
    private static final int NOTI_CARPLAY_TRANSPORT = 81;
    private static final int MAX_PENDING = 64;
    private static final int MAX_PENDING_BYTES = 1024 * 1024;
    private static final String HOST_PACKAGE = "kr.gen5w.wirelesshost";
    private static final String HANDOVER_REQUESTED = "kr.gen5w.wireless.RELAY_HANDOVER_REQUESTED";
    private static final String HANDOVER_CONNECTED = "kr.gen5w.wireless.RELAY_HANDOVER_CONNECTED";
    private static final String HANDOVER_DISCONNECTED = "kr.gen5w.wireless.RELAY_HANDOVER_DISCONNECTED";

    private static final Object LOCK = new Object();
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
    private static int pendingBytes;
    private static boolean draining;
    private static long generation;

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
            if (service != null) connected = false;
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
                else { bindingSequence++; connected = false; }
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
                binding = null; bindingSequence++; connected = false;
            }
        }
        kr.gen5w.diag.SafeDiagnostic.failure("cp5.register", failure);
    }

    /** Preserve the component-4 peer identity and consume only component 5. */
    public static boolean connected(int component, String value) {
        return connected(component, value, 0);
    }

    private static boolean connected(int component, String value, long sequence) {
        IIap2Service target;
        CarPlayService owner;
        long token;
        synchronized (LOCK) {
            if (sequence != 0 && sequence != bindingSequence) return true;
        // Component 4 remains owned by the host-side adapter. The original
        // listener must still receive it, so return false for every non-5 event.
            if (component == 1) usb = true;
            if (component != COMPONENT_CARPLAY) return false;
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
                try {
                    if (!target.Iap2SvcTransportReadDone(frame, frame.length)) {
                        abort(token, "cp5.transport.rejected", null); return;
                    }
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
        synchronized (LOCK) {
            if (token != generation || !present) return;
            owner = carPlay;
            present = false; requested = false; connected = false;
            clearPending();
        }
        kr.gen5w.diag.SafeDiagnostic.failure(code, failure);
        notifyOwner(owner, HANDOVER_DISCONNECTED);
    }

    public static boolean disconnected(int component) {
        return disconnected(component, 0);
    }

    private static boolean disconnected(int component, long sequence) {
        CarPlayService owner;
        long token;
        synchronized (LOCK) {
            if (sequence != 0 && sequence != bindingSequence) return true;
            if (component == 1) usb = false;
            if (component != COMPONENT_CARPLAY) return false;
            connected = false;
            requested = false;
            clearPending();
            owner = carPlay; token = generation;
        }
        notifySession(owner, token, HANDOVER_DISCONNECTED);
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
            clearPending();
        }
    }

    public static void sessionStarted(CarPlayService owner, int transport) {
        synchronized (LOCK) {
            if (!present || owner != carPlay) return;
            wireless = transport == 1;
            wired = !wireless;
            if (wired) { requested = false; connected = false; clearPending(); }
        }
    }

    public static void sessionFinalized(CarPlayService owner) {
        synchronized (LOCK) {
            if (carPlay != owner) return;
            present = false;
            requested = false;
            connected = false;
            wireless = false;
            clearPending();
            if (carPlay == owner) carPlay = null;
        }
        try { owner.sendBroadcast(new Intent(HANDOVER_DISCONNECTED).setPackage(HOST_PACKAGE)); }
        catch (RuntimeException failure) { kr.gen5w.diag.SafeDiagnostic.failure("cp5.finalize.notify", failure); }
    }

    /** Bytes received by the native CarPlay channel become component-5 input. */
    public static void fromCarPlay(CarPlayService owner, byte[] data, int length) {
        if (owner == null || data == null || length <= 0 || length > data.length) return;
        IIap2Service target;
        boolean sendNow;
        boolean requestNow = false;
        boolean overflow;
        long token;
        synchronized (LOCK) {
            if (!present || carPlay != owner || wired || usb) return;
            token = generation;
            overflow = PENDING.size() >= MAX_PENDING || length > MAX_PENDING_BYTES - pendingBytes;
            if (!requested) {
                requested = true;
                requestNow = true;
            }
            target = service;
            sendNow = connected && target != null;
            if (!overflow) { PENDING.addLast(Arrays.copyOf(data, length)); pendingBytes += length; }
        }
        if (overflow) { abort(token, "cp5.buffer.limit", null); return; }
        if (requestNow) notifySession(owner, token, HANDOVER_REQUESTED);
        if (!sendNow) return;
        flushPending(target);
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
            if ((sequence != 0 && sequence != bindingSequence) || service == null || !present || wired || usb || !connected) return true;
            target = carPlay;
            token = generation;
        }
        if (target == null || message == null) return true;
        Iap2NotiMsg.Iap2ObjGroup group = message.getItemGroup();
        if (group == null) return true;
        for (int i = 0; i < group.getItemCnt(); i++) {
            synchronized (LOCK) {
                if (token != generation || !present || wired || usb || !connected || (sequence != 0 && sequence != bindingSequence)) return true;
            }
            Iap2NotiMsg.Iap2ObjItem item = group.getObjItem(i);
            if (item == null || item.getItemParamType() != Iap2NotiMsg.OBJ_BLOB) continue;
            byte[] frame = item.getItemByteArray();
            if (frame != null && frame.length > 0) {
                try { target.iAPSendMessage(frame, frame.length); }
                catch (RuntimeException ignored) { }
            }
        }
        return true;
    }

    private static void notifySession(CarPlayService owner, long token, String action) {
        synchronized (LOCK) {
            if (owner != carPlay || token != generation || !present || wired || usb) return;
            if (HANDOVER_CONNECTED.equals(action) && (!connected || service == null)) return;
            if (HANDOVER_REQUESTED.equals(action) && !requested) return;
            if (HANDOVER_DISCONNECTED.equals(action) && connected) return;
        }
        notifyOwner(owner, action);
    }

    private static void notifyOwner(CarPlayService owner, String action) {
        if (owner == null) return;
        try {
            owner.sendBroadcast(new Intent(action).setPackage(HOST_PACKAGE));
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
