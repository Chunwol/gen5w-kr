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
import android.os.SystemClock;
import android.util.Log;
import com.hkmc.cluster.NavigationCluster;
import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2ListenerInfo;
import com.tcc.iap2.Iap2NotiMsg;
import java.util.List;
import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.GuidanceParser;
import kr.gen5w.hud.GuidanceSession;
import kr.gen5w.hud.GuidanceRequest;
import kr.gen5w.hud.HighwayFrame;
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
    private static final String ACTION_SOUND_ON = "com.mnsoft.navi.action.SOUND_ON";
    private static final String PERM_HUD_INPUT = "kr.gen5w.permission.HUD_INPUT";
    private static final long RETRY_MS = 5000;
    private static final long AA_TBT_STALE_MS = 30000L;
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
    private int stockState = -2; // worker thread only
    private boolean highwayModeActive = false; // io thread only
    private final NotificationEpoch epoch = new NotificationEpoch();
    private long outputEpoch = -1; // accessed only on io
    private final GuidanceRequest guidanceRequest = new GuidanceRequest(); // main only

    @Override public void onCreate() {
        super.onCreate();
        main = new Handler(getMainLooper());
        worker = new HandlerThread("gen5w-route"); worker.start();
        io = new Handler(worker.getLooper());
        io.post(new Runnable() { public void run() { recordWarningCapability(); } });
        stockGuidance = new StockGuidance();
        session = new GuidanceSession(new GuidanceSession.TbtSink() {
            public boolean tbt(int icon, int secondIcon, long meters) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    // OEM scale 0 = metres. Unknown distance uses its error flag.
                    // secondIcon populates sideStreet (2) and combiSideStreet (6)
                    cluster.updateTBTInfo(icon, secondIcon, 0f, meters < 0 ? 0f : (float)meters,
                            meters < 0 ? -3 : 0, secondIcon, 0, 0, 0);
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
                    return true;
                } catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
            public boolean turns(byte[] frame) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    cluster.updateTPTurnListNew(frame);
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
        registerReceiver(mediaReceiver, mediaFilter, PERM_HUD_INPUT, null);

        startAaSocketServer();
        bind();
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                || "com.hkmc.intent.action.SYSTEM_POWERON".equals(intent.getAction()))) {
            disconnected();
            main.removeCallbacks(registerRetry); register();
        }
        keepStockSafetyGuidanceAlive();
        return START_STICKY;
    }
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        stopping = true;
        try { unregisterReceiver(aaReceiver); } catch (Exception ignored) {}
        try { unregisterReceiver(mediaReceiver); } catch (Exception ignored) {}
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
        session.setOutputAllowed(allowed);
        if (next != stockState) {
            stockState = next;
            String owner = next == StockGuidance.IDLE ? "CARPLAY"
                    : next == StockGuidance.ACTIVE ? "STOCK" : "UNKNOWN";
            Log.i(TAG, "HUD owner=" + owner);
            try {
                java.io.FileOutputStream out = openFileOutput("hud-owner.status", MODE_PRIVATE);
                try { out.write((owner + "\n").getBytes("US-ASCII")); }
                finally { out.close(); }
            } catch (java.io.IOException e) { Log.w(TAG, "HUD owner status unavailable"); }
            if (allowed) keepStockSafetyGuidanceAlive();
        }
        return allowed;
    }
    private void keepStockSafetyGuidanceAlive() {
        try {
            sendBroadcast(new Intent(ACTION_SOUND_ON));
        } catch (RuntimeException e) {
            Log.w(TAG, "stock safety broadcast unavailable: " + e.getMessage());
        }
    }
    private boolean outputError(Throwable e) {
        cluster = null;
        session.invalidateOutput();
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
    private final Runnable outputRetry = new Runnable() { public void run() {
        if (stopping) return;
        refreshOwnership();
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
            if (!stopping) { epoch.open(); queueGuidanceRequest(); }
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
                    Maneuver m = GuidanceParser.maneuver(fields, null);
                    if (m != null) {
                        int icon = ClusterIcon.of(m);
                        String line = "MANEUVER: comp=" + m.component + " idx=" + m.index + " type=" + m.type
                                + " angle=" + m.exitAngle + " side=" + m.drivingSide + " junc=" + m.junctionType
                                + " -> icon=0x" + Integer.toHexString(icon);
                        writeDebugLog(line);
                    }
                } else if (what == GuidanceParser.STATUS) {
                    GuidanceParser.Status s = GuidanceParser.status(fields);
                    if (s != null) {
                        String line = "STATUS: comp=" + s.component + " state=" + s.state
                                + " dist=" + s.distanceToNext
                                + " curr=" + java.util.Arrays.toString(s.current);
                        writeDebugLog(line);
                    }
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
        try {
            java.io.File dir = getFilesDir();
            if (dir == null) return;
            java.io.File f = new java.io.File(dir, "navi-debug.log");
            if (f.length() > 512 * 1024) {
                java.io.File bak = new java.io.File(dir, "navi-debug.log.1");
                bak.delete();
                f.renameTo(bak);
            }
            java.io.FileWriter fw = new java.io.FileWriter(f, true);
            fw.write(System.currentTimeMillis() + " " + line + "\n");
            fw.close();
        } catch (Throwable ignored) {}
    }
    private void disconnected() {
        main.removeCallbacks(routeRetry);
        final long closed = epoch.close();
        io.post(new Runnable() {
            public void run() {
                if (outputEpoch <= closed) {
                    refreshOwnership();
                    session.disconnect(); cluster = null; outputEpoch = closed;
                    keepStockSafetyGuidanceAlive();
                }
            }
        });
    }

    private String currentRoadName = null;
    private int currentIcon1 = 0, currentIcon2 = 0;
    private long currentDist = -1;
    private long lastAaTbtTime = 0L;
    private volatile boolean mediaOsdActive = false;

    private boolean isAaGuidanceActive() {
        if (currentDist < 0 || currentIcon1 <= 0 || lastAaTbtTime <= 0L) return false;
        if (SystemClock.elapsedRealtime() - lastAaTbtTime > AA_TBT_STALE_MS) {
            resetAaState();
            return false;
        }
        return true;
    }

    private void resetAaState() {
        io.removeCallbacks(aaExpireRunnable);
        currentIcon1 = 0;
        currentIcon2 = 0;
        currentDist = -1;
        currentRoadName = null;
        lastAaTbtTime = 0L;
    }

    private final Runnable aaExpireRunnable = new Runnable() {
        public void run() {
            if (currentDist < 0 && currentIcon1 <= 0) return;
            resetAaState();
            if (!refreshOwnership()) return;
            try {
                if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                if (session != null && session.hasActiveGuidance()) {
                    clearHighwayMode(cluster);
                    cluster.updateTPCrossroadName(crossroadName(""));
                    session.invalidateOutput();
                    session.retryOutput();
                } else {
                    cluster.updateTBTInfo(0, 0, 0f, 0f, -3, 0, 0, 0, 0);
                    if (!mediaOsdActive) {
                        cluster.updateTPTurnListNew(TurnFrame.clear());
                        cluster.updateTPCrossroadName(crossroadName(""));
                    }
                    clearHighwayMode(cluster);
                    cluster.updateLaneInfo(LaneFrame.clear());
                }
                writeDebugLog("AA_TBT: expired stale state");
            } catch (Throwable e) { outputError(e); }
        }
    };

    private static NavigationCluster.CrossroadName crossroadName(String name) {
        NavigationCluster.CrossroadName cr = new NavigationCluster.CrossroadName();
        cr.name = name != null ? name : "";
        return cr;
    }

    private void renderMediaOsd(final String track, final String artist) {
        if (track == null || track.trim().isEmpty()) return;
        io.post(new Runnable() {
            public void run() {
                if (!refreshOwnership()) return;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    String title = track.trim();
                    String line = "[음악] " + title;
                    if (artist != null && !artist.trim().isEmpty()) {
                        line += " - " + artist.trim();
                    }
                    mediaOsdActive = true;
                    boolean aaActive = isAaGuidanceActive();
                    int icon = aaActive ? currentIcon1 : 0x41;
                    int second = aaActive ? currentIcon2 : 0;
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
                    cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{currentIcon1, currentIcon2}, currentRoadName));
                    cluster.updateTPCrossroadName(crossroadName(currentRoadName));
                } else {
                    cluster.updateTPTurnListNew(TurnFrame.clear());
                    cluster.updateTPCrossroadName(crossroadName(""));
                }
                writeDebugLog("MEDIA_OSD: restored navi");
            } catch (Throwable e) { outputError(e); }
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
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    cluster.updateLaneInfo(frame != null ? frame : LaneFrame.clear());
                    writeDebugLog("AA_LANE: updated " + (frame != null ? frame.length : 0) + " bytes");
                } catch (Throwable e) { outputError(e); }
            }
        });
    }

    private void clearHighwayMode(NavigationCluster clu) {
        if (clu == null) return;
        try {
            HighwayFrame.Item item = HighwayFrame.clear();
            NavigationCluster.HighwayMode hwMode = new NavigationCluster.HighwayMode();
            hwMode.type = item.type;
            hwMode.direction = item.direction;
            hwMode.traffic = item.traffic;
            hwMode.unit = item.unit;
            hwMode.distance = item.distance;
            hwMode.name = item.name;
            clu.updateTPHighwayMode(new NavigationCluster.HighwayMode[]{hwMode});
        } catch (Throwable e) {
            writeDebugLog("clearHighwayMode: " + e.getMessage());
        } finally {
            highwayModeActive = false;
        }
    }

    private void renderAaTbt(final int icon, final int secondIcon, final long dist, final String road) {
        io.post(new Runnable() {
            public void run() {
                if (!refreshOwnership()) return;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    if (dist < 0 || icon <= 0) {
                        resetAaState();
                        if (session != null && session.hasActiveGuidance()) {
                            clearHighwayMode(cluster);
                            cluster.updateTPCrossroadName(crossroadName(""));
                            session.invalidateOutput();
                            session.retryOutput();
                        } else {
                            cluster.updateTBTInfo(0, 0, 0f, 0f, -3, 0, 0, 0, 0);
                            if (!mediaOsdActive) {
                                cluster.updateTPTurnListNew(TurnFrame.clear());
                                cluster.updateTPCrossroadName(crossroadName(""));
                            }
                            clearHighwayMode(cluster);
                            cluster.updateLaneInfo(LaneFrame.clear());
                        }
                        writeDebugLog("AA_TBT: cleared");
                    } else {
                        currentIcon1 = icon;
                        currentIcon2 = secondIcon;
                        currentDist = dist;
                        currentRoadName = road;
                        lastAaTbtTime = SystemClock.elapsedRealtime();
                        io.removeCallbacks(aaExpireRunnable);
                        io.postDelayed(aaExpireRunnable, AA_TBT_STALE_MS);
                        cluster.updateTBTInfo(icon, secondIcon, 0f, (float)dist, 0, secondIcon, 0, 0, 0);
                        if (!mediaOsdActive) {
                            cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{icon, secondIcon}, road));
                            cluster.updateTPCrossroadName(crossroadName(road != null ? road : ""));
                        }
                        HighwayFrame.Item hwItem = HighwayFrame.build(icon, road, (float)dist);
                        if (hwItem != null) {
                            NavigationCluster.HighwayMode hwMode = new NavigationCluster.HighwayMode();
                            hwMode.type = hwItem.type;
                            hwMode.direction = hwItem.direction;
                            hwMode.traffic = hwItem.traffic;
                            hwMode.unit = hwItem.unit;
                            hwMode.distance = hwItem.distance;
                            hwMode.name = hwItem.name;
                            cluster.updateTPHighwayMode(new NavigationCluster.HighwayMode[]{hwMode});
                            highwayModeActive = true;
                        } else if (highwayModeActive) {
                            clearHighwayMode(cluster);
                        }
                        writeDebugLog("AA_TBT: 1st=0x" + Integer.toHexString(icon)
                                + " 2nd=0x" + Integer.toHexString(secondIcon)
                                + " dist=" + dist + "m");
                    }
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
                if (clear || dist < 0) {
                    renderAaTbt(0, 0, -1, null);
                    return;
                }
                int icon = intent.getIntExtra("icon", 0);
                int second = intent.getIntExtra("second_icon", 0);
                String road = intent.getStringExtra("road");
                String desc = intent.getStringExtra("desc");
                int type = intent.getIntExtra("type", 3);
                if (icon <= 0 && (road != null || desc != null)) {
                    Maneuver m = new Maneuver();
                    m.type = type; m.afterRoad = road; m.desc = desc; m.appSource = "AndroidAuto";
                    icon = ClusterIcon.of(m);
                } else if (icon > 0 && (road != null || desc != null)) {
                    icon = ClusterIcon.refineManeuver(icon, road, desc);
                }
                if (second > 0 && road != null) {
                    second = ClusterIcon.refineManeuver(second, road, null);
                }
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
                    byte[] laneFrame = LaneFrame.encodeSimple(laneCount, dirs, rec, currentIcon1);
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
            if (laneCount > 0) {
                byte[] lf = LaneFrame.encodeSimple(laneCount, laneDirs, laneRec, icon > 0 ? icon : currentIcon1);
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
                if (second > 0 && road != null) {
                    second = ClusterIcon.refineManeuver(second, road, null);
                }
                renderAaTbt(icon, second, dist, road);
            }
        } catch (Throwable ignored) {
        } finally {
            try { client.close(); } catch (Throwable ignored) {}
        }
    }
}
