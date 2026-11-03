package kr.gen5w.wireless;

import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import java.lang.reflect.Method;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Requests and observes V039 OEM PhoneProjection; it owns no CarPlay transport. */
public final class WirelessBridge implements StockProjectionSession.Port {
    static final String TAG = "Gen5wWireless";
    final Context context;
    final Handler main;
    final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
    final StockProjectionSession session = new StockProjectionSession(this);
    final Set<String> linked = new LinkedHashSet<String>();
    final ExecutorService oemCalls = Executors.newFixedThreadPool(2);
    volatile boolean cable;
    volatile boolean shuttingDown;
    boolean eventsRegistered;
    boolean stopRegistered;

    WirelessBridge(Context context) {
        this.context = context;
        this.main = new Handler(Looper.getMainLooper());
    }

    void run() {
        registerAction(BluetoothDevice.ACTION_ACL_CONNECTED);
        registerAction(BluetoothDevice.ACTION_ACL_DISCONNECTED);
        registerAction(BluetoothAdapter.ACTION_STATE_CHANGED);
        registerAction("android.bluetooth.headsetclient.profile.action.CONNECTION_STATE_CHANGED");
        registerAction("android.hardware.usb.action.CARPLAY_DEVICE_ATTACHED");
        registerAction("android.hardware.usb.action.CARPLAY_DEVICE_DETACHED");
        registerAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        registerAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        registerAction("android.hardware.usb.action.USB_STATE");
        registerAction("com.hkmc.intent.action.SYSTEM_POWERON");
        IntentFilter stop = new IntentFilter("kr.gen5w.wireless.STOP_BRIDGE");
        stop.addAction(Intent.ACTION_SHUTDOWN);
        try {
            context.registerReceiver(stopReceiver, stop, "android.permission.SHUTDOWN", main);
            stopRegistered = true;
        } catch (RuntimeException e) {
            log("path=stock event=receiver result=stop-unavailable");
        }
        refreshWired();
        scan();
        main.post(tick);
        log("path=stock event=service result=started");
    }

    void registerAction(String action) {
        try {
            context.registerReceiver(events, new IntentFilter(action), null, main);
            eventsRegistered = true;
        } catch (RuntimeException e) {
            // One protected/unsupported action must not restart the whole bridge.
            log("path=stock event=receiver result=action-unavailable");
        }
    }

    final Runnable tick = new Runnable() {
        public void run() {
            if (shuttingDown) return;
            refreshWired();
            scan();
            session.environment(cable, false, now());
            session.tick(now());
            main.postDelayed(this, 1000L);
        }
    };

    final BroadcastReceiver stopReceiver = new BroadcastReceiver() {
        public void onReceive(Context c, Intent i) { shutdown(); }
    };

    final BroadcastReceiver events = new BroadcastReceiver() {
        public void onReceive(Context c, Intent i) {
            String action = i.getAction();
            BluetoothDevice device = (BluetoothDevice) i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
            if (BluetoothDevice.ACTION_ACL_CONNECTED.equals(action)) {
                connected(device);
            } else if (BluetoothDevice.ACTION_ACL_DISCONNECTED.equals(action)) {
                disconnected(device);
            } else if (action != null && action.endsWith("profile.action.CONNECTION_STATE_CHANGED")) {
                int state = i.getIntExtra("android.bluetooth.profile.extra.STATE", -1);
                if (device != null && state == 2) connected(device);
            } else if ("android.hardware.usb.action.CARPLAY_DEVICE_ATTACHED".equals(action)) {
                refreshWired();
            } else if ("android.hardware.usb.action.CARPLAY_DEVICE_DETACHED".equals(action)) {
                refreshWired();
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action) ||
                    UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                UsbDevice usb = (UsbDevice) i.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                if (usb != null && (usb.getVendorId() == 0x05ac || usb.getVendorId() == 0x18d1) &&
                        UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action)) cable = true;
                refreshWired();
            } else if ("android.hardware.usb.action.USB_STATE".equals(action)) {
                refreshWired();
            } else if (BluetoothAdapter.ACTION_STATE_CHANGED.equals(action) &&
                    i.getIntExtra(BluetoothAdapter.EXTRA_STATE, 0) != BluetoothAdapter.STATE_ON) {
                linked.clear();
                session.lost(null, now());
                log("path=stock event=cancel reason=bluetooth-off");
            } else if ("com.hkmc.intent.action.SYSTEM_POWERON".equals(action)) {
                linked.clear();
                session.lost(null, now());
                log("path=stock event=reset reason=system-power-on");
            }
            refreshWired();
            session.environment(cable, false, now());
            scan();
            session.tick(now());
        }
    };

    void scan() {
        if (adapter == null || !adapter.isEnabled()) {
            linked.clear();
            if (session.candidate() != null) session.lost(null, now());
            return;
        }
        String hfp = null;
        try { hfp = (String) adapter.getClass().getMethod("getConnectedHfpAddr").invoke(adapter); }
        catch (Exception ignored) {}
        Set<String> connectedNow = new LinkedHashSet<String>();
        for (BluetoothDevice device : adapter.getBondedDevices()) {
            if (device == null) continue;
            String address = device.getAddress();
            boolean connected = linked.contains(address) || (hfp != null && address.equalsIgnoreCase(hfp));
            if (!connected) {
                try { connected = ((Boolean) device.getClass().getMethod("isConnected").invoke(device)).booleanValue(); }
                catch (Exception ignored) {}
            }
            if (connected) connectedNow.add(address);
        }
        linked.retainAll(connectedNow);
        linked.addAll(connectedNow);
        offerCandidate();
    }

    void connected(BluetoothDevice device) {
        if (device == null || device.getBondState() != BluetoothDevice.BOND_BONDED) return;
        linked.add(device.getAddress());
        offerCandidate();
    }

    void disconnected(BluetoothDevice device) {
        if (device == null) return;
        String address = device.getAddress();
        linked.remove(address);
        if (address.equals(session.candidate())) session.lost(address, now());
        offerCandidate();
    }

    void offerCandidate() {
        if (session.candidate() != null || linked.isEmpty()) return;
        for (String address : linked) {
            session.candidate(address, now());
            break;
        }
    }

    void refreshWired() {
        boolean present = false;
        try {
            UsbManager usb = (UsbManager) context.getSystemService(Context.USB_SERVICE);
            if (usb != null) for (UsbDevice device : usb.getDeviceList().values()) {
                if (device != null && (device.getVendorId() == 0x05ac || device.getVendorId() == 0x18d1)) {
                    present = true;
                    break;
                }
            }
        } catch (RuntimeException ignored) {}
        try {
            Method get = Class.forName("android.os.SystemProperties").getMethod("get", String.class);
            present |= wiredConfiguration((String) get.invoke(null, "sys.usb.config"));
            present |= wiredConfiguration((String) get.invoke(null, "sys.usb.state"));
        } catch (Exception ignored) {}
        cable = present;
    }

    public void inspect(final long generation, final String address) {
        try {
            oemCalls.execute(new Runnable() {
                public void run() {
                    final StockProjectionSession.Observation state = PhoneProjectionAccess.inspect(
                            new PhoneProjectionAccess.ServiceProvider() {
                                public Object get(String name) { return context.getSystemService(name); }
                            }, address);
                    main.post(new Runnable() {
                        public void run() { session.inspected(generation, state, now()); }
                    });
                }
            });
        } catch (RuntimeException e) {
            session.inspected(generation, new StockProjectionSession.Observation(
                    StockProjectionSession.Result.INVOCATION, false, false, false), now());
        }
    }

    public void requestConnect(final long generation, final String address) {
        try {
            oemCalls.execute(new Runnable() {
                public void run() {
                    final StockProjectionSession.RequestResult result = PhoneProjectionAccess.requestCurrentProfile(
                            new PhoneProjectionAccess.ServiceProvider() {
                                public Object get(String name) { return context.getSystemService(name); }
                            }, context, new PhoneProjectionAccess.ActionSender() {
                                public boolean send(final String action, final String packageName,
                                        final String extra, final String value) {
                                    if (shuttingDown || cable) return false;
                                    return session.dispatchIfRequestAllowed(generation, address, now(),
                                            new StockProjectionSession.RequestAction() {
                                                public void send() {
                                                    Intent intent = new Intent(action);
                                                    intent.setPackage(packageName);
                                                    intent.putExtra(extra, value);
                                                    context.sendBroadcast(intent);
                                                }
                                            });
                                }
                            }, address);
                    main.post(new Runnable() {
                        public void run() { session.requested(generation, result, now()); }
                    });
                }
            });
        } catch (RuntimeException e) {
            session.requested(generation, StockProjectionSession.RequestResult.INVOCATION, now());
        }
    }

    public void event(String name, String result) {
        log("path=stock event=" + safe(name) + " result=" + safe(result));
    }

    void shutdown() {
        if (shuttingDown) return;
        shuttingDown = true;
        session.shutdown();
        main.removeCallbacks(tick);
        oemCalls.shutdownNow();
        if (eventsRegistered) try { context.unregisterReceiver(events); } catch (RuntimeException ignored) {}
        if (stopRegistered) try { context.unregisterReceiver(stopReceiver); } catch (RuntimeException ignored) {}
        if (context instanceof Service) ((Service) context).stopSelf();
    }

    static long now() { return SystemClock.elapsedRealtime(); }
    static boolean wiredConfiguration(String value) {
        if (value == null) return false;
        for (String token : value.split(",")) if ("carplay_connect".equals(token.trim())) return true;
        return false;
    }
    static String safe(String value) {
        if ("candidate".equals(value) || "cancel".equals(value) || "service".equals(value) ||
                "state".equals(value) || "request".equals(value) || "result".equals(value) ||
                "progress".equals(value)) return value;
        if ("ready".equals(value) || "acl-lost".equals(value) || "wired".equals(value) ||
                "foreign".equals(value) || "shutdown".equals(value) || "invoked".equals(value) ||
                "service-unavailable".equals(value) || "method-unavailable".equals(value) ||
                "security".equals(value) || "invocation".equals(value) || "timeout".equals(value) ||
                "projection-active".equals(value) || "foreign-active".equals(value) ||
                "connecting".equals(value) ||
                "stale-request".equals(value) ||
                "unavailable".equals(value) || "gate-denied".equals(value) ||
                "oob-supported".equals(value) || "oob-unavailable".equals(value) ||
                "oob-unknown".equals(value)) return value;
        return "other";
    }
    static void log(String message) { Log.i(TAG, message); }
}
