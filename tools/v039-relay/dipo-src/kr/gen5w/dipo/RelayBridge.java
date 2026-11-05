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

/** Process-local component-5 handover for the exact V039 DiPO application. */
public final class RelayBridge {
    private static final int COMPONENT_BT = 4;
    private static final int COMPONENT_CARPLAY = 5;
    private static final int LISTENER_CARPLAY_TRANSPORT = 2048;
    private static final int NOTI_CARPLAY_TRANSPORT = 81;
    private static final int MAX_PENDING = 64;
    private static final String HOST_PACKAGE = "kr.gen5w.wirelesshost";
    private static final String HANDOVER_REQUESTED = "kr.gen5w.wireless.RELAY_HANDOVER_REQUESTED";
    private static final String HANDOVER_CONNECTED = "kr.gen5w.wireless.RELAY_HANDOVER_CONNECTED";
    private static final String HANDOVER_DISCONNECTED = "kr.gen5w.wireless.RELAY_HANDOVER_DISCONNECTED";

    private static final Object LOCK = new Object();
    private static final ArrayDeque<byte[]> PENDING = new ArrayDeque<byte[]>();
    private static IIap2Service service;
    private static CarPlayService carPlay;
    private static boolean wireless;
    private static boolean requested;
    private static boolean connected;

    private RelayBridge() {}

    public static void bind(IIap2Service value) {
        if (value == null) return;
        synchronized (LOCK) {
            if (service == value) return;
            service = value;
        }
        try {
            Iap2ListenerInfo info = new Iap2ListenerInfo();
            info.onSetSupportType(LISTENER_CARPLAY_TRANSPORT);
            info.onSetListenerName("gen5wkr.cp5");
            value.Iap2SvcInit(LISTENER, info);
        } catch (RemoteException ignored) { }
        catch (RuntimeException ignored) { }
    }

    /** Preserve the component-4 peer identity and consume only component 5. */
    public static boolean connected(int component, String value) {
        IIap2Service target = null;
        ArrayDeque<byte[]> ready = null;
        synchronized (LOCK) {
        // Component 4 remains owned by the host-side adapter. The original
        // listener must still receive it, so return false for every non-5 event.
            if (component != COMPONENT_CARPLAY) return false;
            connected = true;
            target = service;
            ready = new ArrayDeque<byte[]>(PENDING);
            PENDING.clear();
        }
        if (target != null) {
            while (!ready.isEmpty()) {
                byte[] frame = ready.removeFirst();
                try { target.Iap2SvcTransportReadDone(frame, frame.length); }
                catch (RemoteException ignored) { break; }
                catch (RuntimeException ignored) { break; }
            }
        }
        notifyHost(HANDOVER_CONNECTED);
        return true;
    }

    public static boolean disconnected(int component) {
        if (component != COMPONENT_CARPLAY) return false;
        synchronized (LOCK) {
            connected = false;
            requested = false;
            PENDING.clear();
        }
        notifyHost(HANDOVER_DISCONNECTED);
        return true;
    }

    public static void sessionCreated(CarPlayService value) {
        synchronized (LOCK) { carPlay = value; }
    }

    public static void sessionStarted(int transport) {
        synchronized (LOCK) { wireless = transport == 1; }
    }

    public static void sessionFinalized(CarPlayService owner) {
        synchronized (LOCK) {
            requested = false;
            connected = false;
            wireless = false;
            PENDING.clear();
            if (carPlay == owner) carPlay = null;
        }
        notifyHost(HANDOVER_DISCONNECTED);
    }

    /** Bytes received by the native CarPlay channel become component-5 input. */
    public static void fromCarPlay(CarPlayService owner, byte[] data, int length) {
        if (owner == null || data == null || length <= 0 || length > data.length) return;
        IIap2Service target;
        boolean sendNow;
        boolean requestNow = false;
        synchronized (LOCK) {
            if (!wireless) return;
            carPlay = owner;
            if (!requested) {
                requested = true;
                requestNow = true;
            }
            byte[] frame = Arrays.copyOf(data, length);
            target = service;
            sendNow = connected && target != null;
            if (!sendNow && PENDING.size() < MAX_PENDING) PENDING.addLast(frame);
            if (sendNow) data = frame;
        }
        if (requestNow) notifyHost(HANDOVER_REQUESTED);
        if (!sendNow) return;
        try { target.Iap2SvcTransportReadDone(data, data.length); }
        catch (RemoteException ignored) { }
        catch (RuntimeException ignored) { }
    }

    /** Consume only notification 81 and write its blob through DiPO's public wrapper. */
    public static boolean fromIap2(int what, Iap2NotiMsg message) {
        if (what != NOTI_CARPLAY_TRANSPORT) return false;
        CarPlayService target;
        synchronized (LOCK) { target = carPlay; }
        if (target == null || message == null) return true;
        Iap2NotiMsg.Iap2ObjGroup group = message.getItemGroup();
        if (group == null) return true;
        for (int i = 0; i < group.getItemCnt(); i++) {
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

    private static void notifyHost(String action) {
        CarPlayService owner;
        synchronized (LOCK) { owner = carPlay; }
        if (owner == null) return;
        try {
            owner.sendBroadcast(new Intent(action).setPackage(HOST_PACKAGE));
        } catch (RuntimeException ignored) { }
    }

    private static final IIap2Listener LISTENER = new IIap2Listener.Stub() {
        public void connected(int component, String name) { RelayBridge.connected(component, name); }
        public void disconnected(int component) { RelayBridge.disconnected(component); }
        public void notify(int what, int arg1, int arg2, Iap2NotiMsg message) {
            RelayBridge.fromIap2(what, message);
        }
    };
}
