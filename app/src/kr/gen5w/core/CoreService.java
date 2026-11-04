package kr.gen5w.core;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.net.Credentials;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Process;
import android.util.Log;
import com.hkmc.cluster.NavigationCluster;
import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2ListenerInfo;
import com.tcc.iap2.Iap2NotiMsg;
import java.util.List;
import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.AaRouteCache;
import kr.gen5w.hud.GuidanceParser;
import kr.gen5w.hud.GuidanceDiagnostics;
import kr.gen5w.hud.GuidanceSession;
import kr.gen5w.hud.GuidanceRequest;
import kr.gen5w.hud.HudVariant;
import kr.gen5w.hud.LaneFrame;
import kr.gen5w.hud.Maneuver;
import kr.gen5w.hud.NotificationEpoch;
import kr.gen5w.hud.NativeWarningSupport;
import kr.gen5w.hud.TurnFrame;
import kr.gen5w.probe.Convert;
import kr.gen5w.probe.Item;

/** Receives route guidance under our own listener name and submits TP frames
 * through the stock cluster API. Requests the advertised route stream after
 * registration, without stopping shared stock guidance. No raw CAN or route
 * names/phone identifiers in logs. All route state is serialized on io.
 */
public final class CoreService extends Service {
    private static final String TAG = "Gen5wCore";
    private static final String PERM_HUD_INPUT = "kr.gen5w.permission.HUD_INPUT";
    private static final long RETRY_MS = 5000;
    private static final int AA_SOCKET_TIMEOUT_MS = 1000;
    private static final int AA_SOCKET_MAX_LINES = 16;
    private HandlerThread worker;
    private Handler io, main;
    private volatile boolean stopping;
    private boolean bound;
    private boolean registered;
    private IIap2Service iap2;
    private GuidanceSession session;
    private NavigationCluster cluster;
    private StockGuidance stockGuidance;
    private final AaRouteCache aaRoute = new AaRouteCache();
    private String ownerState; // worker thread only
    private final NotificationEpoch epoch = new NotificationEpoch();
    private long outputEpoch = -1; // accessed only on io
    private int routeSourceCode; // worker thread; numeric diagnostics only
    private final GuidanceRequest guidanceRequest = new GuidanceRequest(); // main only

    @Override public void onCreate() {
        super.onCreate();
        main = new Handler(getMainLooper());
        worker = new HandlerThread("gen5w-route"); worker.start();
        io = new Handler(worker.getLooper());
        io.post(new Runnable() {
            public void run() {
                purgeLegacyDebugLogs();
                recordWarningCapability();
                recordHudVariant();
            }
        });
        stockGuidance = new StockGuidance();
        session = new GuidanceSession(new GuidanceSession.TbtSink() {
            public boolean tbt(int icon, int secondIcon, long meters) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    // Stock scale: 0 = METER (<1000m), 1 = KILOMETER (>=1000m).
                    // combiSideStreet (6th arg) only accepts 0..4 in V039 NavigationCluster;
                    // secondIcon is carried in sideStreet (2nd arg) and TurnFrame slot 2.
                    cluster.updateTBTInfo(
                            icon,
                            secondIcon,
                            0f,
                            TurnFrame.tbtDistanceValue(meters),
                            TurnFrame.tbtDistanceError(meters),
                            0,
                            TurnFrame.tbtDistanceScale(meters),
                            0,
                            0);
                    DriveLog.core(24, icon, secondIcon, meters, 1, 0, 0);
                    writeDebugLog("TBT: 1st=0x" + Integer.toHexString(icon)
                            + " 2nd=0x" + Integer.toHexString(secondIcon)
                            + " dist=" + meters + "m");
                    return true;
                } catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
            public boolean lanes(byte[] frame) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    cluster.updateLaneInfo(frame);
                    logLaneBits(frame);
                    return true;
                } catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
            public boolean turns(byte[] frame) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    cluster.updateTPTurnListNew(frame);
                    DriveLog.core(26, frame.length > 1 ? frame[1] & 255 : -1,
                            frame.length > 2 ? frame[2] & 255 : -1,
                            frame.length > 3 ? frame[3] & 255 : -1, 1, frame.length,
                            frame.length > 4 ? frame[4] & 255 : -1);
                    return true;
                } catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
        });
        session.setOutputAllowed(false);
        io.postDelayed(outputRetry, 1000);
        IntentFilter filter = new IntentFilter();
        filter.addAction("kr.gen5w.action.AA_TBT");
        filter.addAction("kr.gen5w.action.AA_LANE");
        filter.addAction("com.google.android.apps.auto.navigation.TBT");
        registerReceiver(aaReceiver, filter, PERM_HUD_INPUT, null);

        IntentFilter mediaFilter = new IntentFilter();
        mediaFilter.addAction("com.android.music.metachanged");
        mediaFilter.addAction("com.android.music.playstatechanged");
        mediaFilter.addAction("com.spotify.music.metadatachanged");
        mediaFilter.addAction("com.google.android.music.metachanged");
        mediaFilter.addAction("kr.gen5w.action.MEDIA_TRACK");
        registerReceiver(mediaReceiver, mediaFilter);

        IntentFilter sysFilter = new IntentFilter();
        sysFilter.addAction(AaRouteCache.GPM_FINISH);
        registerReceiver(systemReceiver, sysFilter);

        startAaSocketServer();
        bind();
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                || "com.hkmc.intent.action.SYSTEM_POWERON".equals(intent.getAction()))) {
            disconnected();
            io.post(new Runnable() { public void run() { recordHudVariant(); } });
            main.removeCallbacks(registerRetry); register();
        }
        return START_STICKY;
    }
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        stopping = true;
        try { unregisterReceiver(aaReceiver); } catch (Exception ignored) {}
        try { unregisterReceiver(mediaReceiver); } catch (Exception ignored) {}
        try { unregisterReceiver(systemReceiver); } catch (Exception ignored) {}
        if (aaServer != null) { try { aaServer.close(); } catch (Exception ignored) {} }
        epoch.close();
        main.removeCallbacksAndMessages(null);
        if (iap2 != null) {
            try { iap2.Iap2SvcStopMain(listener); }
            catch (Exception e) { Log.w(TAG, "listener cleanup unavailable"); }
            catch (LinkageError e) { Log.w(TAG, "listener cleanup API unavailable"); }
        }
        if (bound) { unbindService(connection); bound = false; }
        io.removeCallbacksAndMessages(null);
        io.post(new Runnable() { public void run() { refreshOwnership(); session.disconnect(); } });
        worker.quitSafely();
        super.onDestroy();
    }
    /** Check again at each write, including clears and retries. No OEM stop calls. */
    private boolean refreshOwnership() {
        int next = stockGuidance.read();
        boolean allowed = (next == StockGuidance.IDLE);
        // AA updates are intentionally not accepted while stock ownership is
        // active or unknown. Do not let an older cached turn reappear through
        // media OSD restoration after a newer, suppressed update was dropped.
        aaRoute.setOutputAllowed(allowed);
        session.setOutputAllowed(aaRoute.allowCarPlay(allowed));
        String owner = next == StockGuidance.IDLE ? (aaRoute.isActive() ? "AA" : "CARPLAY")
                : next == StockGuidance.ACTIVE ? "STOCK" : "UNKNOWN";
        if (!owner.equals(ownerState)) {
            ownerState = owner;
            DriveLog.core(20, "STOCK".equals(owner) ? 1 : "CARPLAY".equals(owner) ? 2
                    : "AA".equals(owner) ? 3 : 4, 0, 0, 0, 0, 0);
            Log.i(TAG, "HUD owner=" + owner);
            try {
                java.io.FileOutputStream out = openFileOutput("hud-owner.status", MODE_PRIVATE);
                try { out.write((owner + "\n").getBytes("US-ASCII")); }
                finally { out.close(); }
            } catch (java.io.IOException e) { Log.w(TAG, "HUD owner status unavailable"); }
        }
        return allowed;
    }
    private void purgeLegacyDebugLogs() {
        try {
            java.io.File dir = getFilesDir();
            if (dir == null) return;
            new java.io.File(dir, "navi-debug.log").delete();
            new java.io.File(dir, "navi-debug.log.1").delete();
        } catch (Throwable ignored) {}
    }
    private boolean outputError(Throwable e) {
        cluster = null;
        session.invalidateOutput();
        DriveLog.core(27, e instanceof LinkageError ? 2 : 1, 0, 0, 0, 0, 0);
        Log.w(TAG, "cluster output failed: " + e.getClass().getSimpleName());
        return false;
    }
    private void recordWarningCapability() {
        String status;
        try { status = NativeWarningSupport.inspect(NavigationCluster.class); }
        catch (LinkageError e) { status = "APIS_UNAVAILABLE_SOURCE_UNOBSERVED"; }
        Log.i(TAG, "native warning capability=" + status);
        try {
            java.io.FileOutputStream out = openFileOutput("hud-native-warning.status", MODE_PRIVATE);
            try { out.write((status + "\n").getBytes("US-ASCII")); }
            finally { out.close(); }
        } catch (java.io.IOException e) { Log.w(TAG, "native warning status unavailable"); }
    }
    private void recordHudVariant() {
        String status = "UNKNOWN";
        try {
            status = HudVariant.inspect(Class.forName("com.hkmc.device.VariantCoding"),
                    Class.forName("com.hkmc.device.VariantCoding$HUD_CODES"));
        } catch (Exception e) { Log.w(TAG, "HUD configuration unavailable"); }
          catch (LinkageError e) { Log.w(TAG, "HUD configuration API unavailable"); }
        try {
            java.io.FileOutputStream out = openFileOutput("hud-variant.status", MODE_PRIVATE);
            try { out.write((status + "\n").getBytes("US-ASCII")); }
            finally { out.close(); }
        } catch (java.io.IOException e) { Log.w(TAG, "HUD configuration status unavailable"); }
    }
    private final Runnable outputRetry = new Runnable() { public void run() {
        if (stopping) return;
        refreshOwnership();
        flushAaClear();
        session.retryOutput();
        io.postDelayed(this, 1000);
    }};
    private void bind() {
        if (stopping || bound) return;
        Intent intent = new Intent("com.remote.service.IAP2SERVICE");
        intent.setPackage("com.tcc.iap2server");
        try { bound = bindService(intent, connection, Context.BIND_AUTO_CREATE); }
        catch (RuntimeException e) { bound = false; }
        Log.i(TAG, "iap2 binding=" + bound);
        if (!bound) main.postDelayed(bindRetry, RETRY_MS);
    }
    private final Runnable bindRetry = new Runnable() { public void run() { bind(); } };
    private final Runnable registerRetry = new Runnable() { public void run() { register(); } };
    private final Runnable routeRetry = new Runnable() { public void run() { requestGuidance(); } };
    private void queueGuidanceRequest() {
        main.removeCallbacks(routeRetry);
        if (!stopping) main.post(routeRetry);
    }
    private void requestGuidance() {
        if (stopping || !registered || iap2 == null) return;
        final long ticket = epoch.ticket();
        if (ticket < 0) return;
        final IIap2Service service = iap2;
        try {
            if (guidanceRequest.ensure(ticket,new GuidanceRequest.Backend() {
                public int count() throws Exception { return service.Iap2SvcGetRouteGuidanceRegisteredComponentCount(); }
                public int components(int[] ids,String[] names) throws Exception {
                    return service.Iap2SvcGetRouteGuidanceComponentNameIdList(ids,names);
                }
                public boolean start(String[] names) throws Exception {
                    return service.Iap2SvcStartRouteGuidanceUpdate(names,true,true);
                }
            })) return;
        } catch (Exception e) { Log.w(TAG,"route request not ready: " + e.getClass().getSimpleName()); }
          catch (LinkageError e) { Log.w(TAG,"route request API unavailable"); return; }
        if (!stopping && registered && iap2 == service && epoch.isCurrent(ticket)) {
            main.postDelayed(routeRetry,RETRY_MS);
        }
    }
    private void register() {
        if (stopping || iap2 == null) return;
        registered = false;
        try {
            Iap2ListenerInfo info = new Iap2ListenerInfo();
            info.onSetListenerName("gen5wkr.core"); info.onSetSupportType(0x1001);
            // Init can immediately replay cached guidance for an existing link.
            // Accept that replay before making the registration call.
            if (iap2.Iap2SvcIsIap2Connected()) epoch.open();
            if (iap2.Iap2SvcInit(listener, info)) {
                registered = true;
                queueGuidanceRequest();
                Log.i(TAG, "route listener registered"); return;
            }
        } catch (Exception e) { Log.w(TAG, "route registration failed: " + e.getClass().getSimpleName()); }
          catch (LinkageError e) { disconnected(); Log.w(TAG, "route API unavailable"); return; }
        disconnected();
        registered = false;
        main.postDelayed(registerRetry, RETRY_MS);
    }
    private final ServiceConnection connection = new ServiceConnection() {
        public void onServiceConnected(ComponentName name, IBinder binder) {
            if (stopping) return;
            iap2 = IIap2Service.Stub.asInterface(binder); register();
        }
        public void onServiceDisconnected(ComponentName name) {
            registered = false;
            iap2 = null; main.removeCallbacks(registerRetry);
            disconnected();
        }
    };
    private final IIap2Listener listener = new IIap2Listener.Stub() {
        public void connected(int type, String name) {
            if (!stopping) {
                epoch.open();
                io.post(new Runnable() { public void run() { routeSourceCode = 0; resetAaState(); } });
                queueGuidanceRequest();
            }
        }
        public void disconnected(int type) {
            if (!stopping) CoreService.this.disconnected();
        }
        public void notify(final int what, int a, int b, Iap2NotiMsg message) {
            // Stock NotiType: IdentificationAccepted=0, AuthenticationSuccess=5.
            if (!stopping && (what == 0 || what == 5)) { queueGuidanceRequest(); return; }
            if (stopping || (what != GuidanceParser.STATUS && what != GuidanceParser.MANEUVER
                    && what != GuidanceParser.LANES)) return;
            final long ticket = epoch.ticket();
            if (ticket < 0) return;
            final List<Item> fields;
            try { fields = Convert.of(message); }
            catch (RuntimeException e) { clear(ticket); return; }
            io.post(new Runnable() {
                public void run() {
                    if (!epoch.isCurrent(ticket)) return;
                    logNaviDebug(what, fields);
                    refreshOwnership();
                    if (outputEpoch != ticket) { session.disconnect(); outputEpoch = ticket; }
                    session.message(what, fields);
                    if (session.hasActiveGuidance()) {
                        resetAaState();
                    }
                }
            });
        }
        private void logNaviDebug(int what, List<Item> fields) {
            try {
                if (what == GuidanceParser.MANEUVER) {
                    int[] address = GuidanceParser.address(fields);
                    Maneuver m = GuidanceParser.maneuver(fields, null);
                    int icon = m == null ? -1 : ClusterIcon.of(m);
                    DriveLog.core(28, routeSourceCode, GuidanceDiagnostics.fieldMask(fields),
                            address == null ? -1 : address[0], address == null ? -1 : address[1],
                            m == null ? -1 : m.type, icon);
                    if (m != null) {
                        DriveLog.core(22, m.type, m.exitAngle, m.drivingSide,
                                m.junctionType, m.distanceMeters, icon);
                        String line = "MANEUVER: comp=" + m.component + " idx=" + m.index + " type=" + m.type
                                + " angle=" + m.exitAngle + " side=" + m.drivingSide + " junc=" + m.junctionType
                                + " -> icon=0x" + Integer.toHexString(icon);
                        writeDebugLog(line);
                    }
                } else if (what == GuidanceParser.STATUS) {
                    GuidanceParser.Status s = GuidanceParser.status(fields);
                    if (s != null) {
                        if (s.hasSource) routeSourceCode = GuidanceDiagnostics.sourceCode(s.source);
                        DriveLog.core(21, s.state, s.distanceToNext, s.laneIndex,
                                s.laneTotal, s.laneVisible ? 1 : 0, s.hasDistance ? 1 : 0);
                        DriveLog.core(23, routeSourceCode, GuidanceDiagnostics.fieldMask(fields),
                                s.component, s.state, s.current.length, 0);
                        String line = "STATUS: comp=" + s.component + " state=" + s.state
                                + " dist=" + s.distanceToNext
                                + " curr=" + java.util.Arrays.toString(s.current);
                        writeDebugLog(line);
                    }
                } else if (what == GuidanceParser.LANES) {
                    int[] address = GuidanceParser.address(fields);
                    DriveLog.core(29, routeSourceCode, GuidanceDiagnostics.fieldMask(fields),
                            address == null ? -1 : address[0], address == null ? -1 : address[1],
                            0, 0);
                }
            } catch (Throwable ignored) {}
        }
        private void clear(final long ticket) {
            if (!stopping) io.post(new Runnable() {
                public void run() { if (epoch.isCurrent(ticket)) { refreshOwnership(); session.disconnect(); } }
            });
        }
    };

    private void writeDebugLog(String line) {
        Log.i("Gen5wNavi", line);
    }
    private void logLaneBits(byte[] frame) {
        if (frame == null || frame.length != 81) return;
        for (int i = 1; i <= 10; i++) {
            int value = frame[i] & 255;
            if (value != 0) DriveLog.core(25, i, value, 0, 0, 0, 0);
        }
        for (int i = 0x13; i < 0x2b; i++) {
            int value = frame[i] & 255;
            if (value != 0) DriveLog.core(25, i, value, 0, 0, 0, 0);
        }
        for (int i = 0x43; i <= 0x46; i++) {
            int value = frame[i] & 255;
            if (value != 0) DriveLog.core(25, i, value, 0, 0, 0, 0);
        }
        DriveLog.core(25, 81, frame[1] & 255, frame[2] & 255, frame[3] & 255,
                frame[4] & 255, 0);
    }
    private void disconnected() {
        main.removeCallbacks(routeRetry);
        final long closed = epoch.close();
        io.post(new Runnable() {
            public void run() {
                if (outputEpoch <= closed) {
                    refreshOwnership();
                    session.disconnect(); cluster = null; outputEpoch = closed; routeSourceCode = 0;
                }
            }
        });
    }

    private volatile boolean mediaOsdActive = false;
    private boolean aaClearPending; // io thread: keep a clear until stock guidance yields

    private boolean isAaGuidanceActive() {
        return aaRoute.isActive();
    }

    private void resetAaState() {
        aaRoute.clear();
    }

    private static NavigationCluster.CrossroadName crossroadName(String name) {
        NavigationCluster.CrossroadName cr = new NavigationCluster.CrossroadName();
        cr.name = name != null ? name : "";
        return cr;
    }

    private static String sanitizeText(String raw, int maxLen) {
        if (raw == null) return "";
        StringBuilder sb = new StringBuilder();
        String trimmed = raw.trim();
        for (int i = 0; i < trimmed.length() && sb.length() < maxLen; i++) {
            char c = trimmed.charAt(i);
            sb.append(Character.isISOControl(c) ? ' ' : c);
        }
        return sb.toString().trim();
    }

    private void renderMediaOsd(final String track, final String artist) {
        final String safeTitle = sanitizeText(track, 32);
        if (safeTitle.isEmpty()) return;
        final String safeArtist = sanitizeText(artist, 32);
        io.post(new Runnable() {
            public void run() {
                if (!refreshOwnership()) return;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    String line = "[음악] " + safeTitle;
                    if (!safeArtist.isEmpty()) {
                        line += " - " + safeArtist;
                    }
                    mediaOsdActive = true;
                    boolean cpActive = session != null && session.hasActiveGuidance();
                    boolean aaActive = !cpActive && isAaGuidanceActive();
                    int icon = aaActive ? aaRoute.icon() : 0x41;
                    int second = aaActive ? aaRoute.secondIcon() : 0;
                    cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{icon, second}, line));
                    cluster.updateTPCrossroadName(crossroadName(line));
                    writeDebugLog("MEDIA_OSD: shown");
                    io.removeCallbacks(restoreNaviRunnable);
                    io.postDelayed(restoreNaviRunnable, 3000);
                } catch (Throwable e) { outputError(e); }
            }
        });
    }

    private final Runnable restoreNaviRunnable = new Runnable() {
        public void run() {
            mediaOsdActive = false;
            if (!refreshOwnership()) return;
            try {
                if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                if (session != null && session.hasActiveGuidance()) {
                    resetAaState();
                    cluster.updateTPCrossroadName(crossroadName(""));
                    session.invalidateOutput();
                    session.retryOutput();
                } else if (isAaGuidanceActive()) {
                    cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{aaRoute.icon(), aaRoute.secondIcon()}, aaRoute.road()));
                    cluster.updateTPCrossroadName(crossroadName(aaRoute.road()));
                } else {
                    cluster.updateTPTurnListNew(TurnFrame.clear());
                    cluster.updateTPCrossroadName(crossroadName(""));
                }
                writeDebugLog("MEDIA_OSD: restored navi");
            } catch (Throwable e) { outputError(e); }
        }
    };

    private final BroadcastReceiver systemReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (intent == null) return;
            String action = intent.getAction();
            if (AaRouteCache.endsGuidance(action)) {
                renderAaTbt(0, 0, -1, null);
            }
        }
    };

    private final BroadcastReceiver mediaReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (intent == null) return;
            String track = intent.getStringExtra("track");
            if (track == null) track = intent.getStringExtra("title");
            if (track == null) track = intent.getStringExtra("track_name");
            String artist = intent.getStringExtra("artist");
            if (artist == null) artist = intent.getStringExtra("artist_name");
            if (track != null && !track.trim().isEmpty()) {
                renderMediaOsd(track, artist);
            }
        }
    };

    private void renderAaLane(final byte[] frame) {
        io.post(new Runnable() {
            public void run() {
                if (!refreshOwnership()) return;
                if (session != null && session.hasActiveGuidance()) return;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    cluster.updateLaneInfo(frame != null ? frame : LaneFrame.clear());
                    writeDebugLog("AA_LANE: updated " + (frame != null ? frame.length : 0) + " bytes");
                } catch (Throwable e) { outputError(e); }
            }
        });
    }

    private void flushAaClear() {
        if (!aaClearPending || !refreshOwnership()) return;
        try {
            if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
            if (session != null && session.hasActiveGuidance()) {
                cluster.updateTPCrossroadName(crossroadName(""));
                session.invalidateOutput();
                session.retryOutput();
            } else {
                cluster.updateTBTInfo(0, 0, 0f, 0f, -3, 0, 0, 0, 0);
                if (!mediaOsdActive) {
                    cluster.updateTPTurnListNew(TurnFrame.clear());
                    cluster.updateTPCrossroadName(crossroadName(""));
                }
                cluster.updateLaneInfo(LaneFrame.clear());
            }
            aaClearPending = false;
        } catch (Throwable e) { outputError(e); }
    }

    private void renderAaTbt(final int icon, final int secondIcon, final long dist, final String road) {
        io.post(new Runnable() {
            public void run() {
                if (dist < 0 || icon <= 0) {
                    aaClearPending |= isAaGuidanceActive();
                    resetAaState();
                    flushAaClear();
                    return;
                }
                if (!refreshOwnership()) return;
                if (session != null && session.hasActiveGuidance()) return;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    aaClearPending = false;
                    aaRoute.update(icon, secondIcon, dist, road);
                    session.setOutputAllowed(false);
                    cluster.updateTBTInfo(
                            icon,
                            secondIcon,
                            0f,
                            TurnFrame.tbtDistanceValue(dist),
                            TurnFrame.tbtDistanceError(dist),
                            0,
                            TurnFrame.tbtDistanceScale(dist),
                            0,
                            0);
                    if (!mediaOsdActive) {
                        cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{icon, secondIcon}, road));
                        cluster.updateTPCrossroadName(crossroadName(road != null ? road : ""));
                    }
                    writeDebugLog("AA_TBT: 1st=0x" + Integer.toHexString(icon)
                            + " 2nd=0x" + Integer.toHexString(secondIcon)
                            + " dist=" + dist + "m");
                } catch (Throwable e) { outputError(e); }
            }
        });
    }

    private final BroadcastReceiver aaReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (intent == null) return;
            String action = intent.getAction();
            if ("kr.gen5w.action.AA_TBT".equals(action)
                    || "com.google.android.apps.auto.navigation.TBT".equals(action)) {
                boolean clear = intent.getBooleanExtra("clear", false);
                long dist = intent.getLongExtra("distance", intent.getIntExtra("dist", -1));
                int icon = intent.getIntExtra("icon", 0);
                int second = intent.getIntExtra("second_icon", 0);
                String road = intent.getStringExtra("road");
                String desc = intent.getStringExtra("desc");
                int type = intent.getIntExtra("type", 3);
                DriveLog.core(32, type, icon, second, dist,
                        road == null ? 0 : 1, desc == null ? 0 : 1);
                if (clear || dist < 0) {
                    renderAaTbt(0, 0, -1, null);
                    return;
                }
                if (icon <= 0 && (road != null || desc != null)) {
                    Maneuver m = new Maneuver();
                    m.type = type; m.afterRoad = road; m.desc = desc; m.appSource = "AndroidAuto";
                    icon = ClusterIcon.of(m);
                } else if (icon > 0 && (road != null || desc != null)) {
                    icon = ClusterIcon.refineManeuver(icon, road, desc);
                }
                // The next icon has no road metadata here; preserve it as received.
                renderAaTbt(icon, second, dist, road);

                int laneCount = intent.getIntExtra("lane_count", 0);
                if (laneCount > 0) {
                    int[] dirs = intent.getIntArrayExtra("lane_dirs");
                    boolean[] rec = intent.getBooleanArrayExtra("lane_rec");
                    byte[] laneFrame = LaneFrame.encodeSimple(laneCount, dirs, rec, icon);
                    renderAaLane(laneFrame);
                }
            } else if ("kr.gen5w.action.AA_LANE".equals(action)) {
                byte[] raw = intent.getByteArrayExtra("lane_raw");
                if (raw != null) {
                    renderAaLane(raw);
                } else {
                    int laneCount = intent.getIntExtra("lane_count", 0);
                    int[] dirs = intent.getIntArrayExtra("lane_dirs");
                    boolean[] rec = intent.getBooleanArrayExtra("lane_rec");
                    byte[] laneFrame = LaneFrame.encodeSimple(laneCount, dirs, rec, aaRoute.icon());
                    renderAaLane(laneFrame);
                }
            }
        }
    };

    private LocalServerSocket aaServer;
    private void startAaSocketServer() {
        new Thread(new Runnable() {
            public void run() {
                try {
                    aaServer = new LocalServerSocket("gen5wkr.aa.tbt");
                    while (!stopping) {
                        LocalSocket client = aaServer.accept();
                        handleAaClient(client);
                    }
                } catch (Throwable ignored) {}
            }
        }, "gen5w-aa-tbt").start();
    }

    private void handleAaClient(LocalSocket client) {
        if (client == null) return;
        try {
            client.setSoTimeout(AA_SOCKET_TIMEOUT_MS);
            Credentials creds = client.getPeerCredentials();
            int uid = creds != null ? creds.getUid() : -1;
            if (uid != 0 && uid != 1000 && uid != Process.myUid()) {
                return;
            }
            java.io.BufferedReader reader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(client.getInputStream(), "UTF-8"), 1024);
            String line;
            String road = null, desc = null;
            long dist = -1;
            int type = 3, icon = 0, second = 0;
            boolean clear = false;
            String mediaTrack = null, mediaArtist = null;
            int laneCount = 0;
            int[] laneDirs = null;
            boolean[] laneRec = null;
            int linesRead = 0;
            while (linesRead < AA_SOCKET_MAX_LINES && (line = reader.readLine()) != null) {
                linesRead++;
                line = line.trim();
                if (line.isEmpty()) break;
                if (line.startsWith("ROAD:")) road = line.substring(5).trim();
                else if (line.startsWith("DESC:")) desc = line.substring(5).trim();
                else if (line.startsWith("DIST:")) try { dist = Long.parseLong(line.substring(5).trim()); } catch (Exception ignored) {}
                else if (line.startsWith("TYPE:")) try { type = Integer.parseInt(line.substring(5).trim()); } catch (Exception ignored) {}
                else if (line.startsWith("ICON:")) try { icon = Integer.decode(line.substring(5).trim()); } catch (Exception ignored) {}
                else if (line.startsWith("2ND:")) try { second = Integer.decode(line.substring(4).trim()); } catch (Exception ignored) {}
                else if (line.startsWith("TRACK:")) mediaTrack = line.substring(6).trim();
                else if (line.startsWith("ARTIST:")) mediaArtist = line.substring(7).trim();
                else if (line.startsWith("LANE:")) {
                    try {
                        String[] parts = line.substring(5).trim().split(":");
                        laneCount = Integer.parseInt(parts[0]);
                        if (parts.length > 1) {
                            String[] lTokens = parts[1].split("\\|");
                            laneDirs = new int[lTokens.length];
                            laneRec = new boolean[lTokens.length];
                            for (int i = 0; i < lTokens.length; i++) {
                                String tok = lTokens[i];
                                if (tok.contains("#")) {
                                    String[] sub = tok.split("#");
                                    laneDirs[i] = Integer.parseInt(sub[0]);
                                    laneRec[i] = true;
                                } else {
                                    laneDirs[i] = Integer.parseInt(tok);
                                }
                            }
                        }
                    } catch (Exception ignored) {}
                }
                else if (line.equalsIgnoreCase("CLEAR")) clear = true;
            }
            if (mediaTrack != null) {
                renderMediaOsd(mediaTrack, mediaArtist);
            }
            DriveLog.core(32, type, icon, second, dist,
                    road == null ? 0 : 1, desc == null ? 0 : 1);
            if (laneCount > 0) {
                byte[] lf = LaneFrame.encodeSimple(laneCount, laneDirs, laneRec, icon > 0 ? icon : aaRoute.icon());
                renderAaLane(lf);
            }
            if (clear || dist < 0) {
                if (mediaTrack == null) renderAaTbt(0, 0, -1, null);
            } else {
                if (icon <= 0 && (road != null || desc != null)) {
                    Maneuver m = new Maneuver();
                    m.type = type; m.afterRoad = road; m.desc = desc; m.appSource = "AndroidAuto";
                    icon = ClusterIcon.of(m);
                } else if (icon > 0 && (road != null || desc != null)) {
                    icon = ClusterIcon.refineManeuver(icon, road, desc);
                }
                // The next icon has no road metadata here; preserve it as received.
                renderAaTbt(icon, second, dist, road);
            }
        } catch (Throwable ignored) {
        } finally {
            try { client.close(); } catch (Throwable ignored) {}
        }
    }
}
