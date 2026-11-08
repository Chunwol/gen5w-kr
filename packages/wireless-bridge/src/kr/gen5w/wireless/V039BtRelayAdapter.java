package kr.gen5w.wireless;

import android.bluetooth.BluetoothDevice;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.os.RemoteException;
import com.broadcom.bt.hfdevice.hfbtcm.HfDeviceBTCMManager;
import com.broadcom.bt.hfdevice.hfbtcm.HfDeviceStatusListener;
import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2ListenerInfo;
import com.tcc.iap2.Iap2NotiMsg;
import java.util.Arrays;

/**
 * Exact V039 component-4 transport adapter. It uses the OEM Broadcom SPP
 * manager and the OEM iAP2 Binder; it never opens an RFCOMM socket itself.
 */
public final class V039BtRelayAdapter implements BtRelayPipe.SppEndpoint, BtRelayPipe.Iap2Endpoint {
    public static final int COMPONENT_BT_TRANSPORT = 4;
    public static final int NOTI_BT_TRANSPORT_DATA = 80;
    public static final int LISTENER_EXTERNAL_BT_TRANSPORT = 1024;
    private static final int SPP_CONNECTED = 2;
    private static final String IAP2_PACKAGE = "com.tcc.iap2server";
    private static final String IAP2_ACTION = "com.remote.service.IAP2SERVICE";
    private static final String COMPONENT_EXTRA = "com.telechips.android.iap2.component";

    public interface Listener {
        void ready();
        void sppConnected(long generation);
        void iap2Connected(long generation, int component);
        void disconnected(long generation, int component);
        void failed(long generation, Failure failure);
    }

    public enum Failure { BTCM_UNAVAILABLE, IAP2_UNAVAILABLE, SPP_CONNECT, IAP2_START, TRANSPORT }

    private final Context context;
    private final Listener listener;
    private final Object lock = new Object();
    private HfDeviceBTCMManager btcm;
    private IIap2Service iap2;
    private BtRelayPipe pipe;
    private String address;
    private long generation;
    private boolean bound;
    private boolean registered;

    public V039BtRelayAdapter(Context context, Listener listener, BtRelayPipe.Diagnostics diagnostics) {
        if (context == null || listener == null || diagnostics == null) throw new IllegalArgumentException("relay");
        this.context = context;
        this.listener = listener;
        this.pipe = new BtRelayPipe(this, this, diagnostics);
    }

    /** Binds only to the two stock services proven present in V039. */
    public boolean open() {
        try {
            synchronized (lock) {
                if (bound) return true;
                bound = context.bindService(new Intent(IAP2_ACTION).setPackage(IAP2_PACKAGE), iap2Connection,
                        Context.BIND_AUTO_CREATE);
            }
            HfDeviceBTCMManager manager = HfDeviceBTCMManager.getLocalBTCMService(context, btcmService);
            synchronized (lock) { if (manager != null) btcm = manager; }
            registerBtcmIfReady();
            signalReadyIfComplete();
            return bound;
        } catch (RuntimeException e) {
            listener.failed(0, Failure.BTCM_UNAVAILABLE);
            return false;
        }
    }

    /** Starts one generation after the controller has selected a CarPlay candidate. */
    public boolean connect(long ownerGeneration, String candidateAddress) {
        HfDeviceBTCMManager manager;
        if (ownerGeneration <= 0 || candidateAddress == null || candidateAddress.length() == 0) return false;
        synchronized (lock) {
            if (generation != 0 || btcm == null || iap2 == null) return false;
            generation = ownerGeneration;
            address = candidateAddress;
            manager = btcm;
        }
        boolean result;
        boolean alreadyConnected = false;
        try {
            alreadyConnected = manager.IbtcmIsSppConnectedDevice(candidateAddress);
            result = alreadyConnected || manager.IbtcmSppConnect(candidateAddress);
        } catch (RuntimeException e) { kr.gen5w.diag.SafeDiagnostic.failure("bt.spp.connect",e,ownerGeneration);result = false; }
        if (!result) fail(ownerGeneration, Failure.SPP_CONNECT);
        else if (alreadyConnected && pipe.attach(ownerGeneration)) listener.sppConnected(ownerGeneration);
        return result;
    }

    public boolean startIap2(long ownerGeneration, int component) {
        String serial;
        synchronized (lock) {
            if (generation != ownerGeneration || address == null || iap2 == null ||
                    (component != COMPONENT_BT_TRANSPORT && component != 5)) return false;
            serial = address;
        }
        try {
            Intent intent = new Intent(IAP2_ACTION).setPackage(IAP2_PACKAGE);
            intent.putExtra(COMPONENT_EXTRA, component);
            intent.putExtra("serial", serial);
            if (context.startService(intent) == null) {
                fail(ownerGeneration, Failure.IAP2_START);
                return false;
            }
            return true;
        } catch (RuntimeException e) {
            kr.gen5w.diag.SafeDiagnostic.failure("bt.iap.start",e,ownerGeneration);
            fail(ownerGeneration, Failure.IAP2_START);
            return false;
        }
    }

    public boolean write(byte[] payload, int length) {
        HfDeviceBTCMManager manager; String peer;
        synchronized (lock) { manager = btcm; peer = address; }
        if (manager == null || peer == null || payload == null || length <= 0 || length > payload.length) return false;
        try { return manager.IbtcmSppOutPutStreamWrite(peer, Arrays.copyOf(payload, length)); }
        catch (RuntimeException e) { kr.gen5w.diag.SafeDiagnostic.failure("bt.spp.write",e,generation);return false; }
    }

    public boolean readDone(int component, byte[] payload, int length) {
        IIap2Service service;
        synchronized (lock) { service = iap2; }
        if (service == null || component != 4 || payload == null || length <= 0 || length > payload.length) return false;
        try { return service.Iap2SvcTransportReadDone(Arrays.copyOf(payload, length), length); }
        catch (RemoteException e) { kr.gen5w.diag.SafeDiagnostic.failure("bt.iap.read",e,generation);return false; }
    }

    public void stop(int component) {
        long owner;
        synchronized (lock) { owner = generation; }
        if (component != COMPONENT_BT_TRANSPORT && component != 5) return;
        // close marks the pipe inactive before calling this endpoint again. Let
        // that nested call stop OEM transport exactly once, then release owner.
        if (component == COMPONENT_BT_TRANSPORT && owner != 0 && pipe.close(owner)) return;
        try {
            Intent intent = new Intent(IAP2_ACTION).setPackage(IAP2_PACKAGE);
            intent.putExtra(COMPONENT_EXTRA, -component);
            context.startService(intent);
        } catch (RuntimeException e) { kr.gen5w.diag.SafeDiagnostic.failure("bt.iap.stop",e,owner); }
        if (component == COMPONENT_BT_TRANSPORT && owner != 0) clear(owner);
    }

    /** Releases our local owner even if SPP timed out before component 4 started.
     * BTCM retains the physical SPP link; no reviewed per-owner disconnect API exists here.
     */
    public void disconnect() {
        long owner;
        synchronized (lock) { owner = generation; }
        if (owner == 0) return;
        pipe.close(owner);
        clear(owner);
        android.util.Log.i("Gen5wWireless", "path=relay event=cleanup result=local-owner-released-oem-spp-retained");
    }

    public void close() {
        long owner;
        synchronized (lock) { owner = generation; }
        if (owner != 0) pipe.close(owner);
        HfDeviceBTCMManager manager;
        synchronized (lock) { manager = btcm; }
        if (manager != null && registered) {
            try { manager.unregisterHfDeviceStatusListener(btcmListener); } catch (RuntimeException ignored) { }
        }
        try { if (bound) context.unbindService(iap2Connection); } catch (RuntimeException ignored) { }
        synchronized (lock) {
            btcm = null; iap2 = null; address = null; generation = 0; bound = false; registered = false;
        }
    }

    private final HfDeviceBTCMManager.BTCMServiceListener btcmService =
            new HfDeviceBTCMManager.BTCMServiceListener() {
        public void onBTCMServiceConnected() { registerBtcmIfReady(); signalReadyIfComplete(); }
        public void onBTCMServiceDisconnected() {
            long owner; synchronized (lock) { owner = generation; btcm = null; registered = false; }
            if (owner != 0) fail(owner, Failure.BTCM_UNAVAILABLE);
        }
    };

    private final HfDeviceStatusListener btcmListener = new HfDeviceStatusListener() {
        @Override public void onBTCMSppStatusChanged(BluetoothDevice device, int status) {
            long owner;
            synchronized (lock) {
                if (!matches(device)) return;
                owner = generation;
            }
            if (status == SPP_CONNECTED) {
                if (pipe.attach(owner)) listener.sppConnected(owner);
            } else if (owner != 0 && pipe.isActive()) {
                pipe.phoneDisconnected(owner);
                listener.disconnected(owner, 4);
                clear(owner);
            }
        }

        @Override public void onBTCMSppInPutStreamChanged(BluetoothDevice device, byte[] buffer, int length) {
            long owner;
            synchronized (lock) { if (!matches(device)) return; owner = generation; }
            if (!pipe.phoneToIap2(owner, buffer, length)) listener.failed(owner, Failure.TRANSPORT);
        }
    };

    private final ServiceConnection iap2Connection = new ServiceConnection() {
        public void onServiceConnected(ComponentName name, IBinder binder) {
            IIap2Service service = IIap2Service.Stub.asInterface(binder);
            if (service == null) { listener.failed(0, Failure.IAP2_UNAVAILABLE); return; }
            try {
                Iap2ListenerInfo info = new Iap2ListenerInfo();
                info.onSetSupportType(LISTENER_EXTERNAL_BT_TRANSPORT);
                info.onSetListenerName("gen5wkr.bt");
                if (!service.Iap2SvcInit(iap2Listener, info)) {
                    listener.failed(0, Failure.IAP2_UNAVAILABLE); return;
                }
                synchronized (lock) { iap2 = service; }
                signalReadyIfComplete();
            } catch (RemoteException e) { listener.failed(0, Failure.IAP2_UNAVAILABLE); }
        }
        public void onServiceDisconnected(ComponentName name) {
            long owner; synchronized (lock) { owner = generation; iap2 = null; }
            if (owner != 0) fail(owner, Failure.IAP2_UNAVAILABLE);
        }
    };

    private final IIap2Listener iap2Listener = new IIap2Listener.Stub() {
        public void connected(int component, String serial) {
            long owner; synchronized (lock) { owner = generation; }
            if (owner != 0 && component == COMPONENT_BT_TRANSPORT) listener.iap2Connected(owner, component);
        }
        public void disconnected(int component) {
            long owner; synchronized (lock) { owner = generation; }
            if (owner != 0 && component == COMPONENT_BT_TRANSPORT) {
                if (pipe.isActive()) pipe.iap2Disconnected(owner);
                listener.disconnected(owner, component);
                clear(owner);
            }
        }
        public void notify(int what, int a1, int a2, Iap2NotiMsg msg) {
            if (what != NOTI_BT_TRANSPORT_DATA || msg == null) return;
            long owner; synchronized (lock) { owner = generation; }
            try {
                Iap2NotiMsg.Iap2ObjGroup group = msg.getItemGroup();
                if (group == null) return;
                for (int i = 0; i < group.getItemCnt(); i++) {
                    Iap2NotiMsg.Iap2ObjItem item = group.getObjItem(i);
                    if (item == null || item.getItemParamType() != Iap2NotiMsg.OBJ_BLOB) continue;
                    byte[] data = item.getItemByteArray();
                    if (data != null && data.length > 0 && !pipe.iap2ToPhone(owner, data, data.length)) {
                        listener.failed(owner, Failure.TRANSPORT); return;
                    }
                }
            } catch (RuntimeException e) { listener.failed(owner, Failure.TRANSPORT); }
        }
    };

    private void registerBtcmIfReady() {
        HfDeviceBTCMManager manager;
        synchronized (lock) { if (btcm == null || registered) return; manager = btcm; }
        try {
            manager.registerHfDeviceStatusListener(btcmListener);
            synchronized (lock) { registered = true; }
        } catch (RuntimeException e) { listener.failed(0, Failure.BTCM_UNAVAILABLE); }
    }

    private void signalReadyIfComplete() {
        synchronized (lock) { if (btcm == null || iap2 == null || !registered) return; }
        listener.ready();
    }

    private boolean matches(BluetoothDevice device) {
        return device != null && address != null && address.equals(device.getAddress()) && generation != 0;
    }

    private void fail(long owner, Failure failure) {
        if (owner != 0 && pipe.isActive()) pipe.close(owner);
        clear(owner);
        listener.failed(owner, failure);
    }

    private void clear(long owner) {
        synchronized (lock) {
            if (generation == owner) { generation = 0; address = null; }
        }
    }
}
