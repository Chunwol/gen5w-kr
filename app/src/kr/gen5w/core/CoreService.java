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
import kr.gen5w.hud.TimeFrame;
import kr.gen5w.hud.TollText;
import kr.gen5w.hud.NativeWarningSupport;
import kr.gen5w.hud.TurnFrame;
import kr.gen5w.hud.StockTurn;
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
    private static final String ACTION_PHONE_GUIDING = "kr.gen5w.action.PHONE_GUIDING";
    private static final long PHONE_GUIDING_RENEW_MS = 2000L;
    private static final long RETRY_MS = 5000;
    private static final int AA_SOCKET_TIMEOUT_MS = 1000;
    private static final int AA_SOCKET_MAX_LINES = 16;
    private HandlerThread worker;
    private Handler io, main;
    private volatile boolean stopping;
    private boolean switchedOff; // set once in onCreate; nothing else is initialised then
    private boolean bound;
    private boolean registered;
    private IIap2Service iap2;
    private GuidanceSession session;
    private NavigationCluster cluster;
    private StockGuidance stockGuidance;
    private final AaRouteCache aaRoute = new AaRouteCache();
    private final kr.gen5w.hud.AaNavigationState aaModern = new kr.gen5w.hud.AaNavigationState();
    private String ownerState; // worker thread only
    private String lastCrossroadSent; // io thread only
    private boolean lastPhoneGuidingSent; // io thread only
    private long lastPhoneGuidingSentMs = -PHONE_GUIDING_RENEW_MS; // io thread only
    private final NotificationEpoch epoch = new NotificationEpoch();
    private long outputEpoch = -1; // accessed only on io
    private int routeSourceCode; // worker thread; numeric diagnostics only
    private final GuidanceRequest guidanceRequest = new GuidanceRequest(); // synchronized internally
    private volatile boolean stockOwnsHud;
    private boolean cpStockNear;
    private String cpNearManeuverKey;
    private long cpNearGuideDist;
    private boolean aaStockNear;
    private String aaNearManeuverKey;
    private long aaNearGuideDist;

    @Override public void onCreate() {
        super.onCreate();
        // Switched off from the in-car screen: start nothing and end at once.
        if (HudSwitch.isOff(new java.io.File(getApplicationInfo().dataDir))) {
            switchedOff = true;
            stopSelf();
            return;
        }
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
        session = new GuidanceSession(new GuidanceSession.StockSink() {
            public boolean tbt(int icon, int secondIcon, long meters) {
                return tbt(null, icon, secondIcon, meters);
            }
            public boolean tbt(Maneuver maneuver, int icon, int secondIcon, long meters) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    boolean clearing = icon <= 0;
                    StockTurn.Frame frame;
                    if (clearing) {
                        cpStockNear = false;
                        cpNearManeuverKey = null;
                        cpNearGuideDist = 0L;
                        frame = new StockTurn.Frame(TurnFrame.TBT_DISPLAY_IDLE, 0, 0, 0, false);
                    } else {
                        String key = StockTurn.maneuverKey(maneuver, icon, maneuver != null ? maneuver.afterRoad : null);
                        if (cpNearManeuverKey == null || !cpNearManeuverKey.equals(key)) {
                            cpStockNear = false;
                            cpNearManeuverKey = key;
                            cpNearGuideDist = 0L;
                        }
                        boolean wasNear = cpStockNear;
                        frame = StockTurn.build(maneuver, icon, meters, cpStockNear);
                        if (!wasNear && frame.near) cpNearGuideDist = StockTurn.guideDistance(meters);
                        else if (!frame.near) cpNearGuideDist = 0L;
                        cpStockNear = frame.near;
                        notifyNaviPhoneGuiding(true);
                    }
                    float distVal = clearing ? 0f : TurnFrame.tbtDistanceValue(meters);
                    int distErr = clearing ? TurnFrame.DIST_ERR_UNKNOWN : TurnFrame.tbtDistanceError(meters);
                    int distScale = clearing ? TurnFrame.SCALE_METER : TurnFrame.tbtDistanceScale(meters);
                    int barLevel = TurnFrame.tbtBarGraphLevel(clearing ? 0 : icon, clearing ? -1L : meters, frame.near, cpNearGuideDist);
                    int barErr = TurnFrame.tbtBarGraphError(clearing ? 0 : icon, clearing ? -1L : meters, frame.near);
                    cluster.updateTBTInfo(
                            frame.displayType,
                            frame.sideStreet,
                            frame.directionDegrees,
                            distVal,
                            distErr,
                            frame.combiSideStreet,
                            distScale,
                            barLevel,
                            barErr);
                    if (!sendHudDistance2C(clearing ? -1L : meters)) return false;
                    if (clearing && !session.hasPhoneRoute() && !isAaGuidanceActive()) notifyNaviPhoneGuiding(false);
                    DriveLog.core(24, icon, secondIcon, meters, 1, 0, 0);
                    kr.gen5w.diag.DebugTrace.event("hud.output.tbt", icon, secondIcon, meters);
                    writeDebugLog("OURS updateTBTInfo " + frame.displayType + " " + frame.sideStreet + " " + frame.directionDegrees + " " + distVal
                            + " " + distErr + " " + frame.combiSideStreet + " " + distScale + " " + barLevel + " " + barErr);
                    writeDebugLog("TBT: 1st=0x" + Integer.toHexString(frame.displayType)
                            + " 2nd=0x" + Integer.toHexString(clearing ? 0 : secondIcon)
                            + " dist=" + (clearing ? -1L : meters) + "m"
                            + (frame.near ? " near mask=0x" + Integer.toHexString(frame.sideStreet) + " dir=" + frame.directionType : " far"));
                    return true;
                } catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
            public boolean remaining(long meters) {
                subMeters = meters;
                return sendSubInfo();
            }
            public boolean timeRemaining(long seconds) {
                subSeconds = seconds;
                subArrivalMs = (seconds < 0 || seconds > TimeFrame.MAX_SECONDS) ? -1L : System.currentTimeMillis() + seconds * 1000L;
                return sendSubInfo();
            }
            /** Stock DiPO sends type 0 plus the name to updateTPFlexibleDestinationName. */
            public boolean destination(String name) {
                if (destMissing) return true;
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    NavigationCluster.DestinationName d = new NavigationCluster.DestinationName();
                    d.type = 0;
                    d.name = name;
                    cluster.updateTPFlexibleDestinationName(d);
                    writeDebugLog("DEST: \"" + name + "\"");
                    return true;
                } catch (NoSuchMethodError e) { destMissing = true; return true; }
                  catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
            public boolean lanes(byte[] frame) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    cluster.updateLaneInfo(frame);
                    writeDebugLog("OURS updateLaneInfo " + hex(frame));
                    logLaneBits(frame);
                    return true;
                } catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
            public boolean turns(byte[] frame) {
                if (!refreshOwnership()) return false;
                try {
                    if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
                    if (session != null && session.hasPhoneRoute()) notifyNaviPhoneGuiding(true);
                    cluster.updateTPTurnListNew(frame);
                    writeDebugLog("OURS updateTPTurnListNew " + hex(frame));
                    if (session != null) {
                        String road = session.currentRoad();
                        if (road == null) road = "";
                        if (!road.equals(lastCrossroadSent)) {
                            try {
                                cluster.updateTPCrossroadName(crossroadName(road));
                                writeDebugLog("OURS updateTPCrossroadName \"" + road + "\"");
                                lastCrossroadSent = road;
                            } catch (NoSuchMethodError ignored) { }
                        }
                    }
                    DriveLog.core(26, frame.length > 1 ? frame[1] & 255 : -1,
                            frame.length > 2 ? frame[2] & 255 : -1,
                            frame.length > 3 ? frame[3] & 255 : -1, 1, frame.length,
                            frame.length > 4 ? frame[4] & 255 : -1);
                    return true;
                } catch (RuntimeException e) { return outputError(e); }
                  catch (LinkageError e) { return outputError(e); }
            }
            public boolean tunnel(boolean active, long distanceMeters) {
                return syncCarPlayTunnel(active, distanceMeters);
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
        if (switchedOff) return START_NOT_STICKY;
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
        if (switchedOff) { super.onDestroy(); return; }
        stopping = true;
        try { unregisterReceiver(aaReceiver); } catch (Exception ignored) {}
        try { unregisterReceiver(mediaReceiver); } catch (Exception ignored) {}
        try { unregisterReceiver(systemReceiver); } catch (Exception ignored) {}
        stopAaSocketServer();
        epoch.close();
        main.removeCallbacksAndMessages(null);
        if (iap2 != null) {
            try { iap2.Iap2SvcStopMain(listener); }
            catch (Exception e) { Log.w(TAG, "listener cleanup unavailable"); }
            catch (LinkageError e) { Log.w(TAG, "listener cleanup API unavailable"); }
        }
        if (bound) { unbindService(connection); bound = false; }
        io.removeCallbacksAndMessages(null);
        io.post(new Runnable() { public void run() { shutdownOutputs(); } });
        worker.quitSafely();
        super.onDestroy();
    }
    /** Check again at each write, including clears and retries. No OEM stop calls. */
    private boolean refreshOwnership() {
        int next = stockGuidance.read();
        kr.gen5w.diag.DebugTrace.event("hud.owner", next, epoch.ticket());
        stockOwnsHud = (next == StockGuidance.ACTIVE);
        boolean allowed = (next == StockGuidance.IDLE);
        // AA updates are intentionally not accepted while stock ownership is
        // active or unknown. Do not let an older cached turn reappear through
        // media OSD restoration after a newer, suppressed update was dropped.
        aaRoute.setOutputAllowed(allowed);
        if (!allowed) yieldToStock(next == StockGuidance.ACTIVE);
        session.setOutputAllowed(aaRoute.allowCarPlay(allowed));
        String owner = next == StockGuidance.IDLE ? (aaRoute.isActive() ? "AA" : "CARPLAY")
                : next == StockGuidance.ACTIVE ? "STOCK" : "UNKNOWN";
        if (!stopping) {
            boolean guiding = ("CARPLAY".equals(owner) && session != null && session.hasPhoneRoute())
                    || ("AA".equals(owner) && isAaGuidanceActive());
            notifyNaviPhoneGuiding(guiding);
        }
        if (!owner.equals(ownerState)) {
            ownerState = owner;
            DriveLog.core(20, "STOCK".equals(owner) ? 1 : "CARPLAY".equals(owner) ? 2
                    : "AA".equals(owner) ? 3 : 4, 0, 0, 0, 0, 0);
            Log.i(TAG, "HUD owner=" + owner);
            try {
                java.io.FileOutputStream out = openFileOutput("hud-owner.status", MODE_PRIVATE);
                try { out.write((owner + "\n").getBytes("US-ASCII")); }
                finally { out.close(); }
            } catch (java.io.IOException e) { kr.gen5w.diag.SafeDiagnostic.failure("core.hud.owner.write",e);Log.w(TAG, "HUD owner status unavailable"); }
        }
        return allowed;
    }
    /** Stock guidance is active or unknown: AA state was dropped with aaRoute, including its tunnel request. */
    private void yieldToStock(boolean stockActive) {
        aaModern.reset();
        cpStockNear = false;
        cpNearManeuverKey = null;
        cpNearGuideDist = 0L;
        aaStockNear = false;
        aaNearManeuverKey = null;
        aaNearGuideDist = 0L;
        // Anything the phone sessions showed is stale once stock owns the cluster; the session re-sends its desired values.
        subMeters = -1; subSeconds = -1; subArrivalMs = -1L;
        lastCrossroadSent = null;
        aaTunnelWant = false;
        aaTunnelDist = -1L;
        if (stockActive) {
            // Stock guidance owns PE_00 now; never clear over it later.
            phoneTunnelSent = false;
            lastPe00Bucket = Long.MIN_VALUE;
        }
    }
    private void purgeLegacyDebugLogs() {
        try {
            java.io.File dir = getFilesDir();
            if (dir == null) return;
            new java.io.File(dir, "navi-debug.log").delete();
            new java.io.File(dir, "navi-debug.log.1").delete();
        } catch (Throwable ignored) {}
    }
    private long subMeters = -1, subSeconds = -1;
    private long subArrivalMs = -1L; // io thread only
    /** Stock mnsoft 0x4D sub-info layout: distance + unit (0 m, 1 km); hours/minutes are the arrival clock with
     * time type 1 and 24-hour format (2); hours and minutes 0xff with type 0 mean "none". */
    private boolean sendSubInfo() {
        if (subInfoMissing) return true;
        if (!refreshOwnership()) return false;
        // SubInfo is an atomic distance+clock packet. A time-only update before the
        // first route distance must not send an invalid distance over the current one.
        // Return false so the session retains the pending time until distance arrives.
        if (session.hasPhoneRoute() && subMeters < 0) return false;
        try {
            if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
            // The arrival clock is fixed when the duration arrived, so a re-send does not move it later.
            int[] clock = subArrivalMs < 0 ? null : TimeFrame.arrival(subArrivalMs, 0L, java.util.TimeZone.getDefault());
            cluster.updateTBTSubInfo(
                    TurnFrame.tbtDistanceValue(subMeters),
                    TurnFrame.tbtDistanceError(subMeters),
                    TurnFrame.tbtDistanceScale(subMeters),
                    clock == null ? 0xff : clock[0], clock == null ? 0xff : clock[1],
                    clock == null ? 0 : 1, clock == null ? 0 : 2, 0f, -1);
            writeDebugLog("SUB: remaining=" + subMeters + "m time=" + subSeconds + "s");
            writeDebugLog("OURS updateTBTSubInfo9 " + TurnFrame.tbtDistanceValue(subMeters) + " " + TurnFrame.tbtDistanceError(subMeters) + " " + TurnFrame.tbtDistanceScale(subMeters) + " " + (clock == null ? 255 : clock[0]) + " " + (clock == null ? 255 : clock[1]) + " " + (clock == null ? 0 : 1) + " " + (clock == null ? 0 : 2) + " 0.0 -1");
            // 36: requested distance/arrival packet (-1 = clear); void API does not acknowledge delivery.
            DriveLog.core(36, subMeters, subSeconds, clock == null ? -1 : clock[0], clock == null ? -1 : clock[1], 0, 0);
            return true;
        } catch (NoSuchMethodError e) { subInfoMissing = true; return true; }
          catch (RuntimeException e) { return outputError(e); }
          catch (LinkageError e) { return outputError(e); }
    }
    /** Set when this head unit's cluster API lacks an optional method; the output is then skipped. */
    private boolean subInfoMissing, destMissing, subInfo2cMissing, pe00Missing;
    private boolean phoneTunnelSent; // io thread only
    private long lastPe00Bucket = Long.MIN_VALUE; // io thread only
    /** One PE_00 owner for both phone sources: CarPlay (session) wins over AA; io thread only. */
    private boolean cpTunnelWant, aaTunnelWant;
    private long cpTunnelDist = -1L, aaTunnelDist = -1L;
    /**
     * Low-level PE_00 writer. ClusterService replaces the complete packet, so only the tunnel
     * fields are set: parking/air-condition fields stay 0 exactly as the stock 4-argument
     * NavigationCluster.updateSTD_NAVI_PE_00_Info(dist, roadClass, exist, parkingLot) sends them.
     * A clear is sent only after this app asserted a tunnel, never as a blind background write.
     */
    private boolean sendTunnelPe00(boolean active, long meters) {
        if (pe00Missing) return true;
        if (!active && !phoneTunnelSent) return true;
        if (!refreshOwnership()) return false;
        long bucket = !active ? -1L : (meters < 50L ? 0L : Math.min(1000L, (meters / 50L) * 50L));
        if (active == phoneTunnelSent && bucket == lastPe00Bucket) return true;
        try {
            if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
            if (active) {
                int dist = (int) Math.min(1023L, Math.max(0L, bucket));
                cluster.updateSTD_NAVI_PE_00_Info(dist, 0, 1, 0, 0, 0);
                phoneTunnelSent = true;
                lastPe00Bucket = bucket;
            } else {
                cluster.updateSTD_NAVI_PE_00_Info(0, 0, 0, 0, 0, 0);
                phoneTunnelSent = false;
                lastPe00Bucket = -1L;
            }
            // 39: requested PE_00 packet (b = distance bucket, -1 = clear; repeat field is zero).
            DriveLog.core(39, active ? 1 : 0, active ? bucket : -1L, 0, 0, 0, 0);
            writeDebugLog("PE00: active=" + active + " dist=" + (active ? bucket : -1L) + "m");
            return true;
        } catch (NoSuchMethodError e) {
            pe00Missing = true;
            phoneTunnelSent = false;
            lastPe00Bucket = -1L;
            return true;
        } catch (RuntimeException e) { return outputError(e); }
          catch (LinkageError e) { return outputError(e); }
    }
    /** Writes the merged phone tunnel state: active CarPlay guidance owns PE_00, otherwise AA, otherwise clear. */
    private boolean applyTunnelPe00() {
        boolean carPlayGuiding = session != null && session.hasPhoneRoute();
        if (cpTunnelWant) return sendTunnelPe00(true, cpTunnelDist);
        if (aaTunnelWant && !carPlayGuiding) return sendTunnelPe00(true, aaTunnelDist);
        return sendTunnelPe00(false, -1L);
    }
    private boolean syncCarPlayTunnel(boolean active, long meters) {
        cpTunnelWant = active;
        cpTunnelDist = active ? meters : -1L;
        return applyTunnelPe00();
    }
    private boolean syncAaTunnel(boolean tunnel, long dist) {
        boolean active = tunnel && dist >= 0 && dist <= 1000L;
        aaTunnelWant = active;
        aaTunnelDist = active ? dist : -1L;
        return applyTunnelPe00();
    }
    /** Retry only an observed local failure; successful packets are deduplicated. */
    private void maintainTunnelPe00() { applyTunnelPe00(); }
    /** io thread, service shutdown: clear what AA and CarPlay still show (while stock is idle), then the tunnel flag. */
    private void shutdownOutputs() {
        aaClearPending |= isAaGuidanceActive();
        resetAaState();
        refreshOwnership();      // re-enables CarPlay output now that the AA route is gone
        flushAaClear();
        session.disconnect();
        session.retryOutput();
        finalTunnelClear();
        refreshOwnership();
        notifyNaviPhoneGuiding(false);
    }
    /** io thread. Final clears at shutdown: the delayed maintenance tick will not run again once the worker quits. */
    private void finalTunnelClear() {
        cpTunnelWant = false;
        aaTunnelWant = false;
        sendTunnelPe00(false, -1L);
    }
    private boolean sendHudDistance2C(long meters) {
        if (subInfo2cMissing || cluster == null) return true;
        try {
            if (meters < 0) {
                cluster.updateTBTSubInfo2C(
                        TurnFrame.SUB2C_UNIT_INVALID, TurnFrame.SUB2C_FRAC_INVALID, TurnFrame.SUB2C_INT_INVALID,
                        TurnFrame.SUB2C_UNIT_INVALID, TurnFrame.SUB2C_FRAC_INVALID, TurnFrame.SUB2C_INT_INVALID,
                        TurnFrame.SUB2C_UNIT_INVALID, TurnFrame.SUB2C_FRAC_INVALID, TurnFrame.SUB2C_INT_INVALID);
                return true;
            }
            cluster.updateTBTSubInfo2C(
                    TurnFrame.subInfo2CUnit(meters), TurnFrame.subInfo2CTenths(meters), TurnFrame.subInfo2CWhole(meters),
                    TurnFrame.SUB2C_UNIT_INVALID, TurnFrame.SUB2C_FRAC_INVALID, TurnFrame.SUB2C_INT_INVALID,
                    TurnFrame.SUB2C_UNIT_INVALID, TurnFrame.SUB2C_FRAC_INVALID, TurnFrame.SUB2C_INT_INVALID);
            return true;
        } catch (NoSuchMethodError e) { subInfo2cMissing = true; return true; }
          catch (RuntimeException e) { return outputError(e); }
          catch (LinkageError e) { return outputError(e); }
    }
    private boolean outputError(Throwable e) {
        boolean report=kr.gen5w.diag.SafeDiagnostic.failure("core.hud.output",e);
        cluster = null;
        lastCrossroadSent = null;
        lastPe00Bucket = Long.MIN_VALUE;
        session.invalidateOutput();
        DriveLog.core(27, e instanceof LinkageError ? 2 : 1, 0, 0, 0, 0, 0);
        if(report)Log.w(TAG, "cluster output failed: " + e.getClass().getSimpleName());
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
        } catch (java.io.IOException e) { kr.gen5w.diag.SafeDiagnostic.failure("core.warning.status.write",e);Log.w(TAG, "native warning status unavailable"); }
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
        } catch (java.io.IOException e) { kr.gen5w.diag.SafeDiagnostic.failure("core.hud.config.write",e);Log.w(TAG, "HUD configuration status unavailable"); }
    }
    private final Runnable outputRetry = new Runnable() { public void run() {
        if (stopping) return;
        refreshOwnership();
        recordHudHealth();
        expireAaRoute();
        flushAaClear();
        retryAaOutput();
        session.expireLocating(now());
        session.retryOutput();
        maintainTunnelPe00();
        io.postDelayed(this, 1000);
    }};
    /** Fresh ownership observation only; this does not assert HUD delivery. */
    private void recordHudHealth() {
        android.util.AtomicFile target = new android.util.AtomicFile(
                new java.io.File(getFilesDir(), "hud-health.status"));
        java.io.FileOutputStream out = null;
        try {
            String status = (android.os.SystemClock.elapsedRealtime() / 1000) + " "
                    + (ownerState == null ? "UNKNOWN" : ownerState) + "\n";
            out = target.startWrite();
            out.write(status.getBytes("US-ASCII"));
            target.finishWrite(out);
        } catch (java.io.IOException e) {
            boolean report=kr.gen5w.diag.SafeDiagnostic.failure("core.hud.heartbeat.write",e);
            if (out != null) target.failWrite(out);
            if(report)Log.w(TAG, "HUD health status unavailable");
        }
    }
    private void bind() {
        if (stopping || bound) return;
        Intent intent = new Intent("com.remote.service.IAP2SERVICE");
        intent.setPackage("com.tcc.iap2server");
        try { bound = bindService(intent, connection, Context.BIND_AUTO_CREATE); }
        catch (RuntimeException e) { kr.gen5w.diag.SafeDiagnostic.failure("core.iap.bind",e);bound = false; }
        Log.i(TAG, "iap2 binding=" + bound);
        if (!bound) main.postDelayed(bindRetry, RETRY_MS);
    }
    private final Runnable bindRetry = new Runnable() { public void run() { bind(); } };
    private final Runnable registerRetry = new Runnable() { public void run() { register(); } };
    private final Runnable routeRetry = new Runnable() { public void run() { requestGuidance(); } };
    private final kr.gen5w.hud.MediaSubscription mediaSubscription = new kr.gen5w.hud.MediaSubscription();
    private boolean requestMedia(final IIap2Service service, final long ticket) {
        try {
            return mediaSubscription.ensure(ticket, new kr.gen5w.hud.MediaSubscription.Backend() {
                public boolean start() throws Exception {
                    boolean accepted = service.Iap2SvcNowPlayingStart();
                    kr.gen5w.diag.DebugTrace.event("media.subscribe", ticket, accepted ? 1 : 0);
                    return accepted;
                }
            });
        } catch (Exception e) {
            kr.gen5w.diag.SafeDiagnostic.failure("core.media.subscribe",e);
            return false;
        } catch (LinkageError unavailable) {
            // The optional media API must never disable guidance on another OEM ABI.
            kr.gen5w.diag.SafeDiagnostic.failure("core.media.api",unavailable);
            return true;
        }
    }
    private void queueGuidanceRequest(long delayMs) {
        main.removeCallbacks(routeRetry);
        if (stopping) return;
        long ticket = epoch.ticket();
        if (ticket >= 0 && guidanceRequest.isConfirmed(ticket)) return;
        if (delayMs <= 0L) main.post(routeRetry);
        else main.postDelayed(routeRetry, delayMs);
    }
    private void requestGuidance() {
        if (stopping || !registered || iap2 == null) return;
        final long ticket = epoch.ticket();
        kr.gen5w.diag.DebugTrace.event("route.request", ticket, registered ? 1 : 0);
        if (ticket < 0) return;
        final IIap2Service service = iap2;
        // OEM DiPO skips its Now Playing start on Wireless transport. The
        // relayed component-5 iAP2 link still needs this shared native feed
        // for stock INFO. Accept/retry independently of route-list discovery.
        final boolean mediaReady = requestMedia(service, ticket);
        if (guidanceRequest.isConfirmed(ticket)) {
            if (!mediaReady && !stopping && registered && iap2 == service && epoch.isCurrent(ticket)) {
                main.postDelayed(routeRetry, RETRY_MS);
            }
            return;
        }
        if (stockOwnsHud) {
            if (!stopping && registered && iap2 == service && epoch.isCurrent(ticket)) {
                main.postDelayed(routeRetry, RETRY_MS);
            }
            return;
        }
        long nextDelay = RETRY_MS;
        boolean needRetry = !mediaReady;
        try {
            GuidanceRequest.Step step = guidanceRequest.step(ticket, new GuidanceRequest.StopBackend() {
                public boolean canonicalFallbackAllowed() throws Exception {
                    Object product = Class.forName("android.os.SystemProperties")
                            .getMethod("get", String.class).invoke(null, "ro.build.product");
                    return GuidanceRequest.reviewedCanonicalProfile((String)product);
                }
                public int count() throws Exception {
                    int count = service.Iap2SvcGetRouteGuidanceRegisteredComponentCount();
                    kr.gen5w.diag.DebugTrace.event("route.components", ticket, count);
                    return count;
                }
                public int components(int[] ids,String[] names) throws Exception {
                    int received = service.Iap2SvcGetRouteGuidanceComponentNameIdList(ids,names);
                    kr.gen5w.diag.DebugTrace.event("route.list", ticket, received,
                        ids.length > 0 ? ids[0] : -1,
                        names.length > 0 && names[0] != null ? names[0].length() : -1);
                    return received;
                }
                public int componentId(String name) throws Exception {
                    int id = service.Iap2SvcGetRouteGuidanceComponentIdByName(name);
                    kr.gen5w.diag.DebugTrace.event("route.lookup", ticket, id);
                    return id;
                }
                public boolean start(String[] names) throws Exception {
                    boolean accepted = service.Iap2SvcStartRouteGuidanceUpdate(names,true,true);
                    Log.i(TAG, "route.start ticket=" + ticket + " accepted=" + accepted);
                    kr.gen5w.diag.DebugTrace.event("route.start", ticket, names.length, accepted ? 1 : 0);
                    return accepted;
                }
                public boolean stop(String[] names) throws Exception {
                    boolean accepted = service.Iap2SvcStopRouteGuidanceUpdate(names);
                    Log.i(TAG, "route.stop ticket=" + ticket + " accepted=" + accepted);
                    kr.gen5w.diag.DebugTrace.event("route.stop", ticket, names.length, accepted ? 1 : 0);
                    return accepted;
                }
            });
            if (!step.done) {
                needRetry = true;
                nextDelay = !mediaReady && step.nextDelayMs > RETRY_MS ? RETRY_MS : step.nextDelayMs;
            }
        } catch (Exception e) {
            needRetry = true;
            Log.w(TAG,"route request not ready: " + e.getClass().getSimpleName());
        } catch (LinkageError e) {
            Log.w(TAG,"route request API unavailable");
            return;
        }
        if (needRetry && !stopping && registered && iap2 == service && epoch.isCurrent(ticket)) {
            main.postDelayed(routeRetry, nextDelay > 0L ? nextDelay : RETRY_MS);
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
                queueGuidanceRequest(GuidanceRequest.INITIAL_SETTLE_MS);
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
            if (!stopping && type > 0 && type <= 5) {
                long ticket = epoch.open(type);
                kr.gen5w.diag.DebugTrace.event("route.connected", type, ticket);
                io.post(new Runnable() { public void run() { routeSourceCode = 0; resetAaState(); } });
                queueGuidanceRequest(GuidanceRequest.INITIAL_SETTLE_MS);
            }
        }
        public void disconnected(int type) {
            if (!stopping) {
                long closed = epoch.close(type);
                kr.gen5w.diag.DebugTrace.event("route.disconnected", type, closed);
                if (closed >= 0) finishDisconnect(closed);
            }
        }
        public void notify(final int what, int a, int b, Iap2NotiMsg message) {
            kr.gen5w.diag.DebugTrace.event("route.notify", what, epoch.ticket());
            // Stock NotiType: IdentificationAccepted=0, AuthenticationSuccess=5.
            if (!stopping && (what == 0 || what == 5)) { queueGuidanceRequest(GuidanceRequest.INITIAL_SETTLE_MS); return; }
            if (stopping || (what != GuidanceParser.STATUS && what != GuidanceParser.MANEUVER
                    && what != GuidanceParser.LANES)) return;
            final long ticket = epoch.ticket();
            if (ticket < 0) return;
            guidanceRequest.confirmData(ticket);
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
                    kr.gen5w.diag.DebugTrace.event("route.parsed", what, ticket, fields.size(), session.hasPhoneRoute() ? 1 : 0);
                    if (session.hasPhoneRoute()) yieldAaToCarPlay();
                }
            });
        }
        /** Raw remaining-time, ETA and distance values for the USB drive log (events 33 and 35). */
    private void logRouteEstimates(GuidanceParser.Status s, List<Item> fields) {
        if (!s.hasTime && s.etaRaw < 0 && !s.hasRemaining && !s.hasDestination) return;
        long cap = 9999999999L;
        int[] clock = TimeFrame.arrival(System.currentTimeMillis(), s.timeRemaining, java.util.TimeZone.getDefault());
        long etaHigh = s.etaRaw < 0 ? -1 : s.etaRaw >>> 32;
        long etaLow = s.etaRaw < 0 ? -1 : s.etaRaw & 0xffffffffL;
        DriveLog.core(33, Math.min(s.timeRemaining, cap), etaHigh, etaLow, s.distanceRemaining,
                clock == null ? -1 : clock[0] * 100 + clock[1], (s.hasTime ? 1 : 0) | (s.etaRaw >= 0 ? 2 : 0));
        DriveLog.core(35, s.remainUnits, s.remainStrLength, s.maneuverCount,
                s.hasDestination && s.destination != null ? s.destination.length() : -1, s.state, 0);
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
                                + (m.hasJunctionElementAngles ? " angles=" + java.util.Arrays.toString(m.junctionElementAngles) : "")
                                + " -> icon=0x" + Integer.toHexString(icon)
                                + " road=\"" + m.afterRoad + "\" desc=\"" + m.desc + "\"";
                        writeDebugLog(line);
                        String tollText = (m.desc == null ? "" : m.desc) + " " + (m.afterRoad == null ? "" : m.afterRoad);
                        if (TollText.mentionsToll(tollText)) {
                            DriveLog.core(34, TollText.amount(tollText), tollText.length(),
                                    m.type, m.exitAngle, icon, 0);
                        }
                    }
                } else if (what == GuidanceParser.STATUS) {
                    GuidanceParser.Status s = GuidanceParser.status(fields);
                    if (s != null) {
                        if (s.hasSource) routeSourceCode = GuidanceDiagnostics.sourceCode(s.source);
                        DriveLog.core(21, s.state, s.distanceToNext, s.laneIndex,
                                s.laneTotal, s.laneVisible ? 1 : 0, s.hasDistance ? 1 : 0);
                        DriveLog.core(23, routeSourceCode, GuidanceDiagnostics.fieldMask(fields),
                                s.component, s.state, s.current.length, 0);
                        logRouteEstimates(s, fields);
                        String line = "STATUS: comp=" + s.component + " state=" + s.state
                                + " dist=" + s.distanceToNext
                                + " curr=" + java.util.Arrays.toString(s.current)
                                + (s.hasLaneIndex || s.hasLaneTotal || s.hasLaneVisible
                                    ? " lane=" + s.laneIndex + "/" + s.laneTotal + " vis=" + s.laneVisible : "");
                        writeDebugLog(line);
                    }
                } else if (what == GuidanceParser.LANES) {
                    int[] address = GuidanceParser.address(fields);
                    DriveLog.core(29, routeSourceCode, GuidanceDiagnostics.fieldMask(fields),
                            address == null ? -1 : address[0], address == null ? -1 : address[1],
                            0, 0);
                    GuidanceParser.Lanes ls = GuidanceParser.lanes(fields, null);
                    if (ls != null) {
                        StringBuilder sb = new StringBuilder("LANES: comp=").append(ls.component)
                                .append(" idx=").append(ls.index).append(" n=").append(ls.lanes.size());
                        for (int li = 0; li < ls.lanes.size(); li++) {
                            GuidanceParser.Lane gl = ls.lanes.get(li);
                            sb.append(' ').append(gl.index).append(':').append(gl.status)
                              .append('/').append(java.util.Arrays.toString(gl.angles))
                              .append('*').append(java.util.Arrays.toString(gl.highlights));
                        }
                        writeDebugLog(sb.toString());
                    } else {
                        writeDebugLog("LANES: comp=" + (address == null ? -1 : address[0])
                                + " idx=" + (address == null ? -1 : address[1])
                                + " fields=" + fields.size());
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
        finishDisconnect(epoch.close());
    }
    private void finishDisconnect(final long closed) {
        main.removeCallbacks(routeRetry);
        guidanceRequest.reset();
        io.post(new Runnable() {
            public void run() {
                if (outputEpoch <= closed) {
                    refreshOwnership();
                    session.disconnect(); cluster = null; lastCrossroadSent = null; outputEpoch = closed; routeSourceCode = 0;
                    notifyNaviPhoneGuiding(false);
                }
            }
        });
    }

    private volatile boolean mediaOsdActive = false;
    private boolean aaClearPending; // io thread: keep a clear until stock guidance yields

    private boolean isAaGuidanceActive() {
        return aaRoute.isActive();
    }

    /** io thread. CarPlay guidance took over: drop AA state, and an AA tunnel must not outlive AA guidance. */
    private void yieldAaToCarPlay() {
        boolean aaTunnel = aaTunnelWant;
        resetAaState();
        if (aaTunnel) applyTunnelPe00();
    }

    private void resetAaState() {
        aaModern.reset();
        aaStockNear = false;
        aaNearManeuverKey = null;
        aaNearGuideDist = 0L;
        aaRoute.clear();
        aaTunnelWant = false;
        aaTunnelDist = -1L;
    }

    private static String hex(byte[] a) {
        if (a == null) return "null";
        StringBuilder b = new StringBuilder("bytes[").append(a.length).append("]=");
        for (byte x : a) { b.append(Character.forDigit((x >> 4) & 15, 16)).append(Character.forDigit(x & 15, 16)); }
        return b.toString();
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
                    boolean cpActive = session != null && session.hasPhoneRoute();
                    boolean aaActive = !cpActive && isAaGuidanceActive();
                    int icon = aaActive ? TurnFrame.effectiveIcon(aaRoute.icon(), aaRoute.distance()) : 0x41;
                    int second = (aaActive && aaRoute.distance() <= TurnFrame.FAR_STRAIGHT_THRESHOLD_M) ? aaRoute.secondIcon() : 0;
                    cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{icon, second}, line));
                    cluster.updateTPCrossroadName(crossroadName(line));
                    lastCrossroadSent = line;
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
                if (session != null && session.hasPhoneRoute()) {
                    resetAaState();
                    cluster.updateTPCrossroadName(crossroadName(""));
                    lastCrossroadSent = "";
                    session.invalidateOutput();
                    session.retryOutput();
                } else if (isAaGuidanceActive()) {
                    String cross = aaRoute.road() != null ? aaRoute.road() : "";
                    int aaIcon = TurnFrame.effectiveIcon(aaRoute.icon(), aaRoute.distance());
                    int aaSecond = aaRoute.distance() > TurnFrame.FAR_STRAIGHT_THRESHOLD_M ? 0 : aaRoute.secondIcon();
                    cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{aaIcon, aaSecond}, aaRoute.road()));
                    cluster.updateTPCrossroadName(crossroadName(cross));
                    lastCrossroadSent = cross;
                } else {
                    cluster.updateTPTurnListNew(TurnFrame.clear());
                    cluster.updateTPCrossroadName(crossroadName(""));
                    lastCrossroadSent = "";
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

    /** Encodes on the io thread so the masks use the maneuver icon of the queued turn updates, not a stale cached one. */
    private void renderAaLaneSimple(final int laneCount, final int[] dirs, final boolean[] rec) {
        io.post(new Runnable() {
            public void run() {
                renderAaLaneNow(LaneFrame.encodeSimple(laneCount, dirs, rec, aaRoute.icon()));
            }
        });
    }

    private void renderAaLane(final byte[] frame) {
        io.post(new Runnable() { public void run() { renderAaLaneNow(frame); } });
    }

    /** io thread. */
    private void renderAaLaneNow(byte[] frame) {
        if (!refreshOwnership()) return;
        if (session != null && session.hasPhoneRoute()) return;
        byte[] next = frame != null ? frame : LaneFrame.clear();
        byte[] held = aaRoute.lanes();
        // Nothing to clear: no lane frame was ever shown for this route, or the clear is already current.
        if (java.util.Arrays.equals(next, LaneFrame.clear())
                && (held == null || java.util.Arrays.equals(held, next))) return;
        aaRoute.updateLanes(next, now());
        writeAaLanes(next);
    }

    /** io thread. A failed lane write stays pending in aaRoute and is retried with the turn. */
    private void writeAaLanes(byte[] frame) {
        if (frame == null) return;
        try {
            if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
            cluster.updateLaneInfo(frame);
            aaRoute.laneSent();
            writeDebugLog("OURS updateLaneInfo " + hex(frame));
            logLaneBits(frame);
            writeDebugLog("AA_LANE: updated " + frame.length + " bytes");
        } catch (Throwable e) { outputError(e); }
    }

    /** io thread. Writes the cached AA turn; it stays pending until a write succeeds. */
    private void writeAaRoute() {
        if (!aaRoute.routePending()) return;
        int icon = aaRoute.icon(), secondIcon = aaRoute.secondIcon();
        long dist = aaRoute.distance();
        String road = aaRoute.road();
        boolean tunnel = aaRoute.tunnel();
        Maneuver maneuver = aaRoute.maneuver();
        int displayIcon = TurnFrame.effectiveIcon(icon, dist);
        int displaySecond = dist > TurnFrame.FAR_STRAIGHT_THRESHOLD_M ? 0 : secondIcon;
        String key = StockTurn.maneuverKey(maneuver, displayIcon, road);
        if (aaNearManeuverKey == null || !aaNearManeuverKey.equals(key)) {
            aaStockNear = false;
            aaNearManeuverKey = key;
            aaNearGuideDist = 0L;
        }
        boolean wasNear = aaStockNear;
        StockTurn.Frame frame = StockTurn.build(maneuver, displayIcon, dist, aaStockNear);
        if (!wasNear && frame.near) aaNearGuideDist = StockTurn.guideDistance(dist);
        else if (!frame.near) aaNearGuideDist = 0L;
        aaStockNear = frame.near;
        try {
            if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
            notifyNaviPhoneGuiding(true);
            float distVal = TurnFrame.tbtDistanceValue(dist);
            int distErr = TurnFrame.tbtDistanceError(dist);
            int distScale = TurnFrame.tbtDistanceScale(dist);
            int barLevel = TurnFrame.tbtBarGraphLevel(displayIcon, dist, frame.near, aaNearGuideDist);
            int barErr = TurnFrame.tbtBarGraphError(displayIcon, dist, frame.near);
            cluster.updateTBTInfo(
                    frame.displayType,
                    frame.sideStreet,
                    frame.directionDegrees,
                    distVal,
                    distErr,
                    frame.combiSideStreet,
                    distScale,
                    barLevel,
                    barErr);
            if (!sendHudDistance2C(dist)) return;
            if (!mediaOsdActive) {
                String cross = road != null ? road : "";
                cluster.updateTPTurnListNew(TurnFrame.encode(new int[]{displayIcon, displaySecond}, road));
                cluster.updateTPCrossroadName(crossroadName(cross));
                lastCrossroadSent = cross;
            }
            // GPM navigation/a.java:62-63,70-71,81-82,94-95: reset after each turn update.
            cluster.updateTBTTrapInfo(-1, -1, 3, -1, 0, 0, 0, 0, 15, 65535, 3, 100, 255, 15, 3, 3, 15);
            if (!syncAaTunnel(tunnel, dist)) return;
            aaRoute.routeSent();
            writeDebugLog("OURS updateTBTInfo " + frame.displayType + " " + frame.sideStreet + " " + frame.directionDegrees + " " + distVal
                    + " " + distErr + " " + frame.combiSideStreet + " " + distScale + " " + barLevel + " " + barErr);
            writeDebugLog("AA_TBT: 1st=0x" + Integer.toHexString(frame.displayType)
                    + " (icon=0x" + Integer.toHexString(displayIcon) + ")"
                    + " 2nd=0x" + Integer.toHexString(displaySecond)
                    + " dist=" + dist + "m"
                    + (frame.near ? " near mask=0x" + Integer.toHexString(frame.sideStreet) + " dir=" + frame.directionType : " far"));
        } catch (Throwable e) { outputError(e); }
    }

    /** io thread, once a second. CarPlay has its own retry; it also owns the display when active. */
    private void retryAaOutput() {
        if (session != null && session.hasPhoneRoute()) return;
        if (aaRoute.routePending()) writeAaRoute();
        if (aaRoute.lanePending()) writeAaLanes(aaRoute.lanes());
    }

    /** io thread. A turn with no update for AaRouteCache.EXPIRE_MS is cleared as if it had ended. */
    private void expireAaRoute() {
        if (!aaRoute.expired(now())) return;
        Log.i(TAG, "AA guidance expired without an end signal");
        aaClearPending |= isAaGuidanceActive();
        resetAaState();
        flushAaClear();
    }

    private long now() { return android.os.SystemClock.elapsedRealtime(); }

    /** Broadcast active phone guidance lease to wrapped com.mnsoft.navi on io thread. */
    private void notifyNaviPhoneGuiding(boolean active) {
        if (active && stopping) return;
        long t = now();
        if (active == lastPhoneGuidingSent && (!active || t - lastPhoneGuidingSentMs < PHONE_GUIDING_RENEW_MS)) {
            return;
        }
        // An unleased interval allows stock to replace every packet. Restore all
        // unchanged desired outputs once ownership is reacquired, rather than on a timer.
        if (active && (!lastPhoneGuidingSent || t - lastPhoneGuidingSentMs >= 15000L)) {
            session.invalidateOutput();
            lastPe00Bucket = Long.MIN_VALUE;
        }
        // 37: stock-navigation suppression lease changed (renewals are not logged).
        if (active != lastPhoneGuidingSent) DriveLog.core(37, active ? 1 : 0, 0, 0, 0, 0, 0);
        lastPhoneGuidingSent = active;
        lastPhoneGuidingSentMs = t;
        try {
            Intent intent = new Intent(ACTION_PHONE_GUIDING);
            intent.setPackage("com.mnsoft.navi");
            intent.putExtra("active", active);
            intent.putExtra("ts", t);
            sendBroadcast(intent);
        } catch (RuntimeException ignored) { }
    }

    private void flushAaClear() {
        if (!aaClearPending || !refreshOwnership()) return;
        try {
            if (cluster == null) cluster = new NavigationCluster(getApplicationContext());
            if (session != null && session.hasPhoneRoute()) {
                cluster.updateTPCrossroadName(crossroadName(""));
                lastCrossroadSent = null;
                aaTunnelWant = false;
                aaTunnelDist = -1L;
                if (!applyTunnelPe00()) return;
                session.invalidateOutput();
                session.retryOutput();
            } else {
                cluster.updateTBTInfo(
                        TurnFrame.TBT_DISPLAY_IDLE, 0, 0f, 0f,
                        TurnFrame.DIST_ERR_UNKNOWN, 0, TurnFrame.SCALE_METER, 0, TurnFrame.BAR_ERR_INVALID);
                writeDebugLog("OURS updateTBTInfo " + TurnFrame.TBT_DISPLAY_IDLE + " 0 0.0 0.0 "
                        + TurnFrame.DIST_ERR_UNKNOWN + " 0 " + TurnFrame.SCALE_METER + " 0 " + TurnFrame.BAR_ERR_INVALID);
                if (!sendHudDistance2C(-1L)) return;
                if (!mediaOsdActive) {
                    cluster.updateTPTurnListNew(TurnFrame.clear());
                    cluster.updateTPCrossroadName(crossroadName(""));
                    lastCrossroadSent = "";
                }
                cluster.updateLaneInfo(LaneFrame.clear());
                aaTunnelWant = false;
                aaTunnelDist = -1L;
                if (!applyTunnelPe00()) return;
                notifyNaviPhoneGuiding(false);
            }
            aaClearPending = false;
        } catch (Throwable e) { outputError(e); }
    }

    private void renderAaTbt(final int icon, final int secondIcon, final long dist, final String road) {
        renderAaTbtWithTunnel(icon, secondIcon, dist, road, false);
    }

    /** Legacy GPM turn updates carry no lane-clear instruction. */
    private void renderAaTbtWithTunnel(final int icon, final int secondIcon, final long dist, final String road, final boolean tunnel) {
        renderAaTbtWithTunnel(icon, secondIcon, dist, road, tunnel, null);
    }

    private void renderAaTbtWithTunnel(final int icon, final int secondIcon, final long dist, final String road, final boolean tunnel, final Maneuver maneuver) {
        io.post(new Runnable() {
            public void run() {
                if (dist < 0 || icon <= 0) {
                    aaClearPending |= isAaGuidanceActive();
                    resetAaState();
                    flushAaClear();
                    return;
                }
                if (!refreshOwnership()) return;
                if (session != null && session.hasPhoneRoute()) return;
                if (!aaRoute.update(icon, secondIcon, dist, road, tunnel, maneuver, now())) return;
                aaClearPending = false;
                session.setOutputAllowed(false);
                writeAaRoute();
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
                int drivingSide = intent.getIntExtra("driving_side", Maneuver.UNKNOWN_DRIVING_SIDE);
                int junctionType = intent.getIntExtra("junction_type", -1);
                int exitAngle = intent.getIntExtra("exit_angle", Maneuver.UNKNOWN_ANGLE);
                DriveLog.core(32, type, icon, second, dist,
                        road == null ? 0 : 1, desc == null ? 0 : 1);
                writeDebugLog("AA_IN: type=" + type + " icon=0x" + Integer.toHexString(icon) + " dist=" + dist
                        + " road=\"" + road + "\" desc=\"" + desc + "\"");
                if (clear || dist < 0) {
                    renderAaTbt(0, 0, -1, null);
                    return;
                }
                Maneuver m = new Maneuver();
                m.type = type; m.drivingSide = drivingSide; m.junctionType = junctionType;
                m.exitAngle = exitAngle; m.afterRoad = road; m.desc = desc; m.appSource = "AndroidAuto";
                if (icon <= 0) {
                    icon = ClusterIcon.of(m);
                } else {
                    icon = ClusterIcon.refineManeuver(icon, road, desc);
                }
                // The next icon has no road metadata here; preserve it as received.
                int laneCount = intent.getIntExtra("lane_count", 0);
                renderAaTbtWithTunnel(icon, second, dist, road, ClusterIcon.isTunnelText(road, desc), m);

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
                    renderAaLaneSimple(laneCount, dirs, rec);
                }
            }
        }
    };

    private final Object aaSocketLock = new Object();
    private volatile LocalServerSocket aaServer;
    private volatile LocalSocket aaClient;
    private Thread aaThread;

    private void stopAaSocketServer() {
        synchronized (aaSocketLock) {
            if (aaClient != null) try { aaClient.close(); } catch (java.io.IOException ignored) { }
            if (aaServer != null) try { aaServer.close(); } catch (java.io.IOException ignored) { }
            aaClient = null;
            aaServer = null;
        }
        if (aaThread != null) aaThread.interrupt();
    }

    private void startAaSocketServer() {
        aaThread = new Thread(new Runnable() {
            public void run() {
                while (!stopping) {
                    LocalServerSocket server = null;
                    try {
                        server = new LocalServerSocket("gen5wkr.aa.tbt");
                        synchronized (aaSocketLock) {
                            if (stopping) return;
                            aaServer = server;
                        }
                        Log.i(TAG, "AA input listener ready");
                        while (!stopping) {
                            LocalSocket client = server.accept();
                            synchronized (aaSocketLock) {
                                if (stopping) {
                                    client.close();
                                    break;
                                }
                                aaClient = client;
                            }
                            try { handleAaClient(client); }
                            finally {
                                synchronized (aaSocketLock) {
                                    if (aaClient == client) aaClient = null;
                                }
                            }
                        }
                    } catch (java.io.IOException e) {
                        if (!stopping) Log.w(TAG, "AA input listener unavailable; retry scheduled");
                    } catch (RuntimeException e) {
                        if (!stopping) Log.w(TAG, "AA input listener failed; retry scheduled");
                    } finally {
                        if (server != null) try { server.close(); } catch (java.io.IOException ignored) { }
                        synchronized (aaSocketLock) {
                            if (aaServer == server) aaServer = null;
                        }
                    }
                    if (stopping) return;
                    try { Thread.sleep(RETRY_MS); }
                    catch (InterruptedException e) { return; }
                }
            }
        }, "gen5w-aa-tbt");
        aaThread.start();
    }

    /** io thread: never render distance from an older maneuver or retain reroute arrows. */
    private void acceptModernAa(kr.gen5w.hud.AaNavigationParser.Event event) {
        if (!refreshOwnership() || (session != null && session.hasPhoneRoute())) {
            aaModern.reset();
            aaStockNear = false;
            aaNearManeuverKey = null;
            return;
        }
        kr.gen5w.hud.AaNavigationState.Snapshot next = aaModern.accept(event);
        kr.gen5w.diag.DebugTrace.event("aa.wire", event.messageId, event.steps.size(), event.distanceMeters);
        for (int si = 0; si < event.steps.size(); si++) {
            kr.gen5w.hud.AaNavigationParser.Step st = event.steps.get(si);
            writeDebugLog("AA_STEP: " + si + " aaType=" + st.aaType + " -> icon=0x" + Integer.toHexString(st.icon())
                    + " road=\"" + st.maneuver.afterRoad + "\" desc=\"" + st.maneuver.desc + "\"");
        }
        if (next == null) return;
        if (next.clear) {
            aaClearPending |= isAaGuidanceActive();
            aaRoute.clear(); // keep pending modern step/distance state; reset only the displayed cache
            flushAaClear();
            return;
        }
        if (!aaRoute.update(next.icon, next.secondIcon, next.distanceMeters, next.road, next.tunnel, next.maneuver, now())) return;
        aaClearPending = false;
        session.setOutputAllowed(false);
        writeAaRoute();
        aaRoute.updateLanes(next.lanes(), now());
        writeAaLanes(aaRoute.lanes());
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
            java.io.PushbackInputStream input = new java.io.PushbackInputStream(client.getInputStream(), 4);
            byte[] prefix = new byte[4];
            int received = 0;
            while (received < 4) {
                int count = input.read(prefix, received, 4-received);
                if (count < 0) break;
                received += count;
            }
            input.unread(prefix, 0, received);
            if (received == 4 && prefix[0]=='G' && prefix[1]=='A' && prefix[2]=='N' && prefix[3]=='1') {
                kr.gen5w.hud.AaWireFrame frame = kr.gen5w.hud.AaWireFrame.read(input);
                final kr.gen5w.hud.AaNavigationParser.Event event;
                try { event = kr.gen5w.hud.AaNavigationParser.parse(frame.type, frame.payload); }
                catch (IllegalArgumentException malformed) {
                    kr.gen5w.diag.DebugTrace.event("aa.wire.invalid", frame.type, frame.payload.length);
                    return;
                }
                io.post(new Runnable() { public void run() { acceptModernAa(event); } });
                return;
            }
            java.io.BufferedReader reader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(input, "UTF-8"), 1024);
            String line;
            String road = null, desc = null;
            long dist = -1;
            int type = 3, icon = 0, second = 0;
            int drivingSide = Maneuver.UNKNOWN_DRIVING_SIDE, junctionType = -1;
            int exitAngle = Maneuver.UNKNOWN_ANGLE;
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
                else if (line.startsWith("DRIVING_SIDE:")) try { drivingSide = Integer.parseInt(line.substring(13).trim()); } catch (Exception ignored) {}
                else if (line.startsWith("JUNCTION_TYPE:")) try { junctionType = Integer.parseInt(line.substring(14).trim()); } catch (Exception ignored) {}
                else if (line.startsWith("EXIT_ANGLE:")) try { exitAngle = Integer.parseInt(line.substring(11).trim()); } catch (Exception ignored) {}
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
            writeDebugLog("AA_IN: type=" + type + " icon=0x" + Integer.toHexString(icon) + " dist=" + dist
                    + " road=\"" + road + "\" desc=\"" + desc + "\"");
            if (!clear && dist >= 0) {
                if (icon <= 0) {
                    Maneuver m = new Maneuver();
                    m.type = type; m.drivingSide = drivingSide; m.junctionType = junctionType;
                    m.exitAngle = exitAngle; m.afterRoad = road; m.desc = desc; m.appSource = "AndroidAuto";
                    icon = ClusterIcon.of(m);
                } else {
                    icon = ClusterIcon.refineManeuver(icon, road, desc);
                }
            }
            if (laneCount > 0) {
                byte[] lf = LaneFrame.encodeSimple(laneCount, laneDirs, laneRec, icon > 0 ? icon : aaRoute.icon());
                renderAaLane(lf);
            }
            if (clear || dist < 0) {
                if (mediaTrack == null) renderAaTbt(0, 0, -1, null);
            } else {
                // The next icon has no road metadata here; preserve it as received.
                renderAaTbtWithTunnel(icon, second, dist, road, ClusterIcon.isTunnelText(road, desc));
            }
        } catch (Throwable e) {
            kr.gen5w.diag.SafeDiagnostic.failure("core.aa.receive",e);
        } finally {
            try { client.close(); } catch (Throwable ignored) {}
        }
    }
}
