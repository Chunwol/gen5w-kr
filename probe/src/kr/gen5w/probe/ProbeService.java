package kr.gen5w.probe;

import android.app.Service;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2ListenerInfo;
import com.tcc.iap2.Iap2NotiMsg;

import java.util.List;

/**
 * Read-only probe: registers with the head unit's iAP2 server for route guidance
 * (listener type 0x1000) under its own name and logs every notification. It never
 * asks the phone for anything and never writes to the cluster.
 */
public final class ProbeService extends Service {
    static final String TAG = "Gen5wProbe";
    static final String LISTENER_NAME = "gen5wkr.probe";
    static final int TYPE_ROUTE_GUIDANCE = 0x1000;
    static final String IAP2_ACTION = "com.remote.service.IAP2SERVICE";
    static final long RETRY_MS = 5000;

    private LogFile log;
    private Handler io;
    private Handler main;
    private IIap2Service iap2;
    private boolean bound;
    private long notes;

    @Override
    public void onCreate() {
        super.onCreate();
        log = new LogFile(getFilesDir());
        HandlerThread t = new HandlerThread("probe-io");
        t.start();
        io = new Handler(t.getLooper());
        main = new Handler(Looper.getMainLooper());
        say("probe start");
        if (!hasLibrary()) {
            say("FAIL: shared library com.tcc.iap2 not available on this unit");
            return;
        }
        bind();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onDestroy() {
        say("probe stop (" + notes + " notifications)");
        if (bound) try { unbindService(conn); } catch (RuntimeException ignored) {}
        super.onDestroy();
    }

    private static boolean hasLibrary() {
        try {
            Class.forName("com.tcc.iap2.IIap2Service");
            return true;
        } catch (Throwable e) {
            return false;
        }
    }

    private void bind() {
        Intent i = new Intent(IAP2_ACTION);
        i.setPackage("com.tcc.iap2server");
        boolean ok;
        try {
            ok = bindService(i, conn, Context.BIND_AUTO_CREATE);
        } catch (RuntimeException e) {
            ok = false;
            say("bind error " + e);
        }
        bound = ok;
        say("bind iap2 service: " + ok);
        if (!ok) main.postDelayed(new Runnable() { public void run() { bind(); } }, RETRY_MS);
    }

    private final ServiceConnection conn = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            iap2 = IIap2Service.Stub.asInterface(service);
            register();
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            say("iap2 service gone - waiting for it to come back");
            iap2 = null;
        }
    };

    private void register() {
        try {
            Iap2ListenerInfo info = new Iap2ListenerInfo();
            info.onSetListenerName(LISTENER_NAME);
            info.onSetSupportType(TYPE_ROUTE_GUIDANCE);
            boolean ok = iap2.Iap2SvcInit(listener, info);
            say("register as " + LISTENER_NAME + " type 0x1000: " + ok
                    + " state=" + iap2.Iap2SvcGetState()
                    + " connected=" + iap2.Iap2SvcIsIap2Connected());
            components();
        } catch (Throwable e) {
            say("register error " + e);
        }
    }

    private void components() {
        try {
            int n = iap2.Iap2SvcGetRouteGuidanceRegisteredComponentCount();
            say("route guidance components: " + n);
        } catch (Throwable e) {
            say("component count error " + e);
        }
    }

    /** Runs on a binder thread: copy the message and hand it off, so the server is never held up. */
    private final IIap2Listener listener = new IIap2Listener.Stub() {
        @Override
        public void connected(final int type, final String name) {
            post("iap2 connected type=" + type + " name=" + name);
        }

        @Override
        public void disconnected(final int type) {
            post("iap2 disconnected type=" + type);
        }

        @Override
        public void notify(final int what, final int a, final int b, Iap2NotiMsg msg) {
            final List<Item> items;
            try {
                items = Convert.of(msg);
            } catch (Throwable e) {
                post("notify what=0x" + Integer.toHexString(what) + " read error " + e);
                return;
            }
            io.post(new Runnable() {
                public void run() {
                    notes++;
                    say("notify what=0x" + Integer.toHexString(what) + " a=" + a + " b=" + b + " " + Dump.line(items));
                }
            });
        }
    };

    private void post(final String s) {
        io.post(new Runnable() { public void run() { say(s); } });
    }

    private void say(String s) {
        Log.i(TAG, s);
        log.write(s);
    }
}
