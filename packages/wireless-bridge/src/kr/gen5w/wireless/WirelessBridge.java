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
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
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
    final Map<String, Long> falseConnectionSince = new LinkedHashMap<String, Long>();
    final ExecutorService oemCalls = Executors.newFixedThreadPool(2);
    volatile boolean cable;
    volatile boolean shuttingDown;
    volatile ProjectionWifiAccess.ApProgress apProgress = ProjectionWifiAccess.ApProgress.UNKNOWN;
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
        registerAction("android.net.wifi.WIFI_AP_STATE_CHANGED");
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
            if ("android.net.wifi.WIFI_AP_STATE_CHANGED".equals(action)) {
                apProgress = ProjectionWifiAccess.classifyApState(i.getIntExtra("wifi_state", -1));
                event("wifi", apResult(apProgress));
            }
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
                falseConnectionSince.clear();
                session.lost(null, now());
                log("path=stock event=cancel reason=bluetooth-off");
            } else if ("com.hkmc.intent.action.SYSTEM_POWERON".equals(action)) {
                linked.clear();
                falseConnectionSince.clear();
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
            falseConnectionSince.clear();
            if (session.candidate() != null) session.lost(null, now());
            return;
        }
        String hfp = null;
        try { hfp = (String) adapter.getClass().getMethod("getConnectedHfpAddr").invoke(adapter); }
        catch (Exception ignored) {}
        List<BluetoothCandidateScan.Device> devices = new ArrayList<BluetoothCandidateScan.Device>();
        for (BluetoothDevice device : adapter.getBondedDevices()) {
            if (device == null) continue;
            final BluetoothDevice bonded = device;
            devices.add(new BluetoothCandidateScan.Device() {
                public String address() { return bonded.getAddress(); }
                public Boolean isConnected() {
                    try {
                        return (Boolean) bonded.getClass().getMethod("isConnected").invoke(bonded);
                    } catch (Exception ignored) {
                        return null;
                    }
                }
            });
        }
        BluetoothCandidateScan.reconcile(linked, falseConnectionSince, devices, hfp, session, now());
    }

    void connected(BluetoothDevice device) {
        if (device == null || device.getBondState() != BluetoothDevice.BOND_BONDED) return;
        DriveLog.bridge(2, 1, 0, 0, 0, 0, 0);
        String address = device.getAddress();
        linked.add(address);
        falseConnectionSince.remove(address.toUpperCase(java.util.Locale.US));
        offerCandidate();
    }

    void disconnected(BluetoothDevice device) {
        if (device == null) return;
        DriveLog.bridge(2, 0, 0, 0, 0, 0, 0);
        String address = device.getAddress();
        BluetoothCandidateScan.disconnected(linked, falseConnectionSince, address, session, now());
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
                    StockProjectionSession.Observation projection = PhoneProjectionAccess.inspect(
                            new PhoneProjectionAccess.ServiceProvider() {
                                public Object get(String name) { return context.getSystemService(name); }
                            }, context, address);
                    ProjectionWifiAccess.CredentialStatus status = inspectWifiCredentials();
                    StockProjectionSession.WifiCredentialState credentials =
                            status == ProjectionWifiAccess.CredentialStatus.PRESENT
                            ? StockProjectionSession.WifiCredentialState.PRESENT
                            : status == ProjectionWifiAccess.CredentialStatus.MISSING
                            ? StockProjectionSession.WifiCredentialState.MISSING
                            : StockProjectionSession.WifiCredentialState.UNKNOWN;
                    final StockProjectionSession.Observation state = new StockProjectionSession.Observation(
                            projection.result, projection.serviceAvailable, projection.profileType,
                            projection.profileState, projection.active, projection.connecting,
                            projection.otherActive, credentials, apState(apProgress));
                    main.post(new Runnable() {
                        public void run() {
                            if (!session.current(generation) || shuttingDown) return;
                            event("platform", state.profileType == PhoneProjectionAccess.TYPE_CARPLAY
                                    ? "platform-carplay" : state.profileType == PhoneProjectionAccess.TYPE_ANDROID_AUTO
                                    ? "platform-android-auto" : "platform-unknown");
                            event("profile", profileResult(state.profileState));
                            event("wifi", state.credentials == StockProjectionSession.WifiCredentialState.PRESENT
                                    ? "wifi-credentials-present" : state.credentials == StockProjectionSession.WifiCredentialState.MISSING
                                    ? "wifi-credentials-missing" : "wifi-credentials-unknown");
                            session.inspected(generation, state, now());
                        }
                    });
                }
            });
        } catch (RuntimeException e) {
            main.post(new Runnable() {
                public void run() { session.inspected(generation, new StockProjectionSession.Observation(
                        StockProjectionSession.Result.INVOCATION, false, false, false), now()); }
            });
        }
    }

    public void bootstrap(final long generation, final String address) {
        try {
            oemCalls.execute(new Runnable() {
                public void run() {
                    final StockProjectionSession.BootstrapResult[] result = {
                        StockProjectionSession.BootstrapResult.CANCELLED
                    };
                    session.dispatchIfBootstrapAllowed(generation, address, now(),
                            new StockProjectionSession.RequestAction() {
                                public void send() {
                                    if (shuttingDown || cable) return;
                                    result[0] = PhoneProjectionAccess.bootstrap(
                                            new PhoneProjectionAccess.ServiceProvider() {
                                                public Object get(String name) { return context.getSystemService(name); }
                                            }, context, new PhoneProjectionAccess.ActionSender() {
                                                public boolean send(String action, String packageName, String extra, String value) {
                                                    sendOemAction(action, packageName, extra, value);
                                                    return true;
                                                }
                                            }, address);
                                }
                            });
                    main.post(new Runnable() {
                        public void run() { session.bootstrapped(generation, result[0], now()); }
                    });
                }
            });
        } catch (RuntimeException e) {
            main.post(new Runnable() {
                public void run() { session.bootstrapped(generation,
                        StockProjectionSession.BootstrapResult.INVOCATION, now()); }
            });
        }
    }

    public void requestConnect(final long generation, final String address, final int profileType) {
        try {
            oemCalls.execute(new Runnable() {
                public void run() {
                    final StockProjectionSession.RequestResult result = PhoneProjectionAccess.requestCurrentProfile(
                            new PhoneProjectionAccess.ServiceProvider() {
                                public Object get(String name) { return context.getSystemService(name); }
                            }, context, new PhoneProjectionAccess.ActionSender() {
                                public boolean send(final String action, final String packageName,
                                        final String extra, final String value) {
                                    final boolean[] sent = {false};
                                    session.dispatchIfRequestAllowed(generation, address, now(),
                                            new StockProjectionSession.RequestAction() {
                                                public void send() {
                                                    if (shuttingDown || cable) return;
                                                    sendOemAction(action, packageName, extra, value);
                                                    sent[0] = true;
                                                }
                                            });
                                    return sent[0];
                                }
                            }, address);
                    main.post(new Runnable() {
                        public void run() { session.requested(generation, result, now()); }
                    });
                }
            });
        } catch (RuntimeException e) {
            main.post(new Runnable() {
                public void run() { session.requested(generation,
                        StockProjectionSession.RequestResult.INVOCATION, now()); }
            });
        }
    }

    private ProjectionWifiAccess.CredentialStatus inspectWifiCredentials() {
        try {
            return ProjectionWifiAccess.inspect(context.getSystemService("wifi")).status;
        } catch (RuntimeException e) {
            return ProjectionWifiAccess.CredentialStatus.UNKNOWN;
        }
    }

    private void sendOemAction(String action, String packageName, String extra, String value) {
        Intent intent = new Intent(action);
        intent.setPackage(packageName);
        intent.putExtra(extra, value);
        context.sendBroadcast(intent);
    }

    private static int apState(ProjectionWifiAccess.ApProgress progress) {
        switch (progress) {
            case OFF: return 11;
            case ENABLING: return 12;
            case READY: return 13;
            case FAILED: return 14;
            default: return 0;
        }
    }

    private static String apResult(ProjectionWifiAccess.ApProgress progress) {
        switch (progress) {
            case OFF: return "wifi-ap-off";
            case ENABLING: return "wifi-ap-enabling";
            case READY: return "wifi-ap-ready";
            case FAILED: return "wifi-ap-failed";
            default: return "wifi-ap-unknown";
        }
    }

    private static String profileResult(StockProjectionSession.ProfileState profile) {
        switch (profile) {
            case READY: return "profile-ready";
            case MISSING: return "profile-missing";
            case DISABLED: return "profile-disabled";
            case AUTO_CONNECT_DISABLED: return "auto-connect-disabled";
            case UNSUPPORTED: return "profile-unsupported";
            default: return "profile-unknown";
        }
    }

    public void event(String name, String result) {
        log("path=stock event=" + safe(name) + " result=" + safe(result));
        int nameCode = eventCode(name);
        int resultCode = resultCode(result);
        if (nameCode != 0 && resultCode != 0) DriveLog.bridge(1, nameCode, resultCode, 0, 0, 0, 0);
    }

    private static int eventCode(String name) {
        if ("candidate".equals(name)) return 1;
        if ("cancel".equals(name)) return 2;
        if ("result".equals(name)) return 3;
        if ("service".equals(name)) return 4;
        if ("progress".equals(name)) return 5;
        if ("request".equals(name)) return 6;
        if ("bootstrap".equals(name)) return 7;
        if ("platform".equals(name)) return 8;
        if ("profile".equals(name)) return 9;
        if ("wifi".equals(name)) return 10;
        return 0;
    }

    private static int resultCode(String result) {
        if ("ready".equals(result)) return 1;
        if ("acl-lost".equals(result)) return 2;
        if ("wired".equals(result)) return 3;
        if ("foreign".equals(result)) return 4;
        if ("timeout".equals(result)) return 5;
        if ("unavailable".equals(result)) return 6;
        if ("projection-active".equals(result)) return 7;
        if ("connecting".equals(result)) return 8;
        if ("foreign-active".equals(result)) return 9;
        if ("stale-request".equals(result)) return 10;
        if ("oem-action-sent".equals(result)) return 11;
        if ("shutdown".equals(result)) return 12;
        if ("invocation".equals(result)) return 13;
        if ("service-unavailable".equals(result)) return 14;
        if ("method-unavailable".equals(result)) return 15;
        if ("security".equals(result)) return 16;
        if ("profile-unavailable".equals(result)) return 17;
        if ("profile-mismatch".equals(result)) return 18;
        if ("profile-disabled".equals(result)) return 19;
        if ("auto-connect-disabled".equals(result)) return 20;
        if ("cancelled".equals(result)) return 21;
        if ("platform-carplay".equals(result)) return 22;
        if ("platform-android-auto".equals(result)) return 23;
        if ("platform-unknown".equals(result)) return 24;
        if ("profile-ready".equals(result)) return 25;
        if ("profile-missing".equals(result)) return 26;
        if ("profile-unknown".equals(result)) return 27;
        if ("profile-unsupported".equals(result)) return 28;
        if ("oem-requested".equals(result)) return 29;
        if ("profile-bootstrap-timeout".equals(result)) return 30;
        if ("wifi-ap-timeout".equals(result)) return 31;
        if ("projection-timeout".equals(result)) return 32;
        if ("request-timeout".equals(result)) return 33;
        if ("wifi-credentials-unavailable".equals(result)) return 34;
        if ("wifi-credentials-present".equals(result)) return 35;
        if ("wifi-credentials-missing".equals(result)) return 36;
        if ("wifi-credentials-unknown".equals(result)) return 37;
        if ("wifi-ap-off".equals(result)) return 38;
        if ("wifi-ap-enabling".equals(result)) return 39;
        if ("wifi-ap-ready".equals(result)) return 40;
        if ("wifi-ap-failed".equals(result)) return 41;
        if ("wifi-ap-unknown".equals(result)) return 42;
        return 0;
    }

    void shutdown() {
        if (shuttingDown) return;
        shuttingDown = true;
        session.shutdown();
        linked.clear();
        falseConnectionSince.clear();
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
        if (eventCode(value) != 0 || resultCode(value) != 0) return value;
        return StockProjectionSession.safeDiagnosticToken(value);
    }
    static void log(String message) { Log.i(TAG, message); }
}
