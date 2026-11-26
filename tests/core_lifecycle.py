"""Run the production CoreService lifecycle methods with host boundary fakes."""
from pathlib import Path
import subprocess
import repo_tmp as tempfile

root = Path(__file__).resolve().parents[1]
source = (root/'app/src/kr/gen5w/core/CoreService.java').read_text(encoding='utf-8')
# Safety boundary: HUD output must not change the stock navigation mute state.
assert 'com.mnsoft.navi.action.SOUND_ON' not in source, 'HUD must not force stock navigation sound on'
assert 'com.mnsoft.navi.action.SOUND_OFF' not in source, 'HUD must not force stock navigation sound off'

# A successful cluster packet has no expiry in ClusterService. No blind resends.
for guess in ('PE00_REASSERT_MS', 'PE00_CLEAR_REPEATS', 'maintainSubInfo', 'Thread.sleep(250L)', 'session.refreshActive()', 'aaTrapReset'):
    assert guess not in source, 'unjustified output workaround: ' + guess
assert 'session.hasPhoneRoute()' in source
# Current-road metadata does not describe the next maneuver.
assert 'ClusterIcon.refineManeuver(second, road, null)' not in source, 'AA next icon must not use the current road'
# Stock/unknown ownership must drop the AA tunnel request together with the AA route cache.
assert 'if (!allowed) yieldToStock(next == StockGuidance.ACTIVE);' in source, 'refreshOwnership must yield AA PE_00 state to stock'
assert 'maintainTunnelPe00();\n        io.postDelayed(this, 1000);' in source, 'outputRetry must maintain PE_00'

def method(signature):
    start = source.index(signature)
    begin = source.index('{', start)
    level = 1
    end = begin+1
    while level:
        level += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

methods = '\n'.join(method(sig) for sig in [
    'private boolean sendSubInfo()', 'private boolean isAaGuidanceActive()', 'private void resetAaState()',
    'private static NavigationCluster.CrossroadName crossroadName(',
    'private boolean sendTunnelPe00(', 'private boolean syncAaTunnel(',
    'private boolean applyTunnelPe00()', 'private boolean syncCarPlayTunnel(',
    'private void maintainTunnelPe00()', 'private void yieldAaToCarPlay()',
    'private void finalTunnelClear()', 'private void shutdownOutputs()', 'private void yieldToStock(',
    'private void flushAaClear()', 'private void renderAaTbt(', 'private void renderAaTbtWithTunnel(final int icon, final int secondIcon, final long dist, final String road, final boolean tunnel) {',
    'private void renderAaTbtWithTunnel(final int icon, final int secondIcon, final long dist, final String road, final boolean tunnel, final Maneuver maneuver) {',
    'private void renderAaLaneNow(byte[] frame)', 'private void renderAaLane(', 'private void writeAaLanes(', 'private void writeAaRoute()',
    'private void retryAaOutput()', 'private void expireAaRoute()'])
# The production route cache and stock turn builder, nested so the harness stays self-contained.
cache = (root/'app/src/kr/gen5w/hud/AaRouteCache.java').read_text(encoding='utf-8')
cache = cache[cache.index('public final class AaRouteCache'):].replace('public final class', 'static final class', 1)
maneuver_src = (root/'app/src/kr/gen5w/hud/Maneuver.java').read_text(encoding='utf-8')
maneuver_src = maneuver_src[maneuver_src.index('public final class Maneuver'):].replace('public final class', 'static final class', 1)
stockturn_src = (root/'app/src/kr/gen5w/hud/StockTurn.java').read_text(encoding='utf-8')
stockturn_src = stockturn_src[stockturn_src.index('public final class StockTurn'):].replace('public final class', 'static final class', 1)
harness = r'''
import java.util.*;
public class CoreLifecycleTest {
    static class Handler { void post(Runnable r) { r.run(); } }
    static class ClusterIcon {
        static final int OVERPASS_ENTRY_LC=0x58, OVERPASS_ENTRY_R=0x57, OVERPASS_SIDE_L=0x52, OVERPASS_SIDE_R=0x51;
        static final int UNDERPASS_ENTRY_LC=0x5b, UNDERPASS_ENTRY_R=0x5a, UNDERPASS_SIDE_L=0x55, UNDERPASS_SIDE_R=0x54;
        static final int IC_ENTER_C=0xa0, IC_ENTER_R=0xa1, IC_ENTER_L=0xa2, IC_EXIT_C=0xa3, IC_EXIT_R=0xa4, IC_EXIT_L=0xa5;
        static final int TOLL=0xb2, REST_AREA=0xb7;
        static int of(Maneuver m) { return -1; }
        static boolean isTunnelText(String a, String b) {
            return (a != null && a.contains("터널")) || (b != null && b.contains("터널"));
        }
    }
    static class AaNavigationParser { static final int FORK_RIGHT=0xad, FORK_LEFT=0xae; }
    static class NavigationCluster {
        static class CrossroadName { String name; }
        static int subWrites, subError; static float subDistance;
        void updateTBTSubInfo(float d,int err,int unit,int h,int m,int type,int format,float compass,int compassErr) {
            subWrites++; subDistance=d; subError=err;
        }
        // Static: production code replaces a failed binding with a new instance.
        static int clears, turns, laneWrites, failTbt, failLanes, lastIcon, lastSideStreet, lastCombi, pe00Writes, pe00Exist, failPe00, pe00Background, laneClears, trapWrites; static long lastDist, pe00Dist; static float lastDirection;
        static void reset() { clears=turns=laneWrites=failTbt=failLanes=lastIcon=lastSideStreet=lastCombi=pe00Writes=pe00Exist=failPe00=pe00Background=laneClears=trapWrites=0; lastDist=0; pe00Dist=-1; lastDirection=0f; }
        NavigationCluster(Object ctx) {}
        void updateTPCrossroadName(CrossroadName name) {}
        void updateTBTInfo(int i,int side,float a,float b,int c,int d,int e,int f,int g) {
            if (failTbt > 0) { failTbt--; throw new IllegalStateException("cluster binder died"); }
            if (i == 0) throw new AssertionError("displayType 0 is invalid/spinner on V039");
            lastSideStreet = side; lastDirection = a; lastCombi = d;
            if (i == TurnFrame.TBT_DISPLAY_IDLE) clears++; else { turns++; lastIcon = i; lastDist = (long) b; }
        }
        void updateTPTurnListNew(byte[] frame) {}
        void updateLaneInfo(byte[] frame) {
            if (failLanes > 0) { failLanes--; throw new IllegalStateException("cluster binder died"); }
            if (frame != null && frame.length == 1 && frame[0] == 0) laneClears++; else if (frame != null) laneWrites++;
        }
        void updateTBTTrapInfo(int a,int b,int c,int d,int e,int f,int g,int h,int i,int j,int k,int l,int m,int n,int o,int p,int q) {
            if (a!=-1||b!=-1||c!=3||d!=-1||i!=15||j!=65535||k!=3||l!=100||m!=255||n!=15||o!=3||p!=3||q!=15) throw new AssertionError("trap reset must match stock GPM");
            trapWrites++;
        }
        void updateSTD_NAVI_PE_00_Info(int tunnelDistance, int tunnelRoadClass, int tunnelExist,
                int parkingLot, int airConditionWarning, int airConditionType) {
            if (failPe00 > 0) { failPe00--; throw new IllegalStateException("pe00 binder died"); }
            pe00Writes++; pe00Exist = tunnelExist; pe00Dist = tunnelDistance;
            // Phone writes must not fabricate the stock parking/air-condition fields.
            pe00Background |= parkingLot | airConditionWarning | airConditionType | tunnelRoadClass;
        }
    }
    static class DriveLog { static void core(int event,long a,long b,long c,long d,long e,long f) {} }
    static class Log { static void i(String tag, String line) {} }
    static final String TAG = "test";
    long clock;
    long now() { return clock; }
    static class TimeFrame { static int[] arrival(long at,long seconds,java.util.TimeZone zone) { return new int[]{12,30}; } }
    static class LaneFrame { static byte[] clear() { return new byte[]{0}; } }
    static class TurnFrame {
        static final int ICON_STRAIGHT = 0x41, TBT_DISPLAY_IDLE = 8, DIST_ERR_UNKNOWN = -3, SCALE_METER = 0, BAR_ERR_INVALID = -1;
        static final long FAR_STRAIGHT_THRESHOLD_M = Long.MAX_VALUE;
        static byte[] clear() { return null; }
        static byte[] encode(int[] icons, String road) { return null; }
        static int effectiveIcon(int icon, long d) { return icon > 0 && d > FAR_STRAIGHT_THRESHOLD_M ? ICON_STRAIGHT : icon; }
        static float tbtDistanceValue(long d) { return d; }
        static int tbtDistanceError(long d) { return 0; }
        static int tbtDistanceScale(long d) { return 0; }
        static int tbtDisplayType(int icon) { return icon; }
        static int tbtBarGraphLevel(int icon, long d) { return 0; }
        static int tbtBarGraphError(int icon, long d) { return icon <= 0 ? BAR_ERR_INVALID : (d > 300L ? -2 : 0); }
    }
    static class Session {
        boolean active; int retries;
        boolean hasPhoneRoute() { return active; }
        void invalidateOutput() {}
        void retryOutput() { retries++; }
        int disconnects; void disconnect() { disconnects++; }
        void setOutputAllowed(boolean value) {}
    }
    Handler io = new Handler(); Session session = new Session();
    AaRouteCache aaRoute = new AaRouteCache();
    { aaRoute.setOutputAllowed(true); }
    { NavigationCluster.reset(); }
    NavigationCluster cluster = new NavigationCluster(null);
    NavigationCluster shared = cluster;
    static class AaModern { void reset() {} }
    AaModern aaModern = new AaModern();
    String lastCrossroadSent;
    int guidingCalls;
    boolean lastGuiding;
    void notifyNaviPhoneGuiding(boolean a) { guidingCalls++; lastGuiding = a; }
    boolean failDist2c; int dist2cCalls; long lastDist2c = Long.MIN_VALUE;
    boolean sendHudDistance2C(long m) {
        if (failDist2c) { failDist2c = false; outputError(new IllegalStateException("subInfo2C binder died")); return false; }
        dist2cCalls++; lastDist2c = m;
        return true;
    }
    boolean aaClearPending, mediaOsdActive, allowed=true;
    boolean cpStockNear, aaStockNear; String cpNearManeuverKey, aaNearManeuverKey;
    boolean pe00Missing, phoneTunnelSent;
    long lastPe00Bucket = Long.MIN_VALUE, lastPe00Ms = Long.MIN_VALUE;
    boolean cpTunnelWant, aaTunnelWant;
    long cpTunnelDist = -1L, aaTunnelDist = -1L;
    int currentIcon1, currentIcon2;
    long currentDist=-1; String currentRoadName;
    boolean refreshOwnership() { return allowed; }
    long subMeters=-1, subSeconds=-1, subArrivalMs=-1L, lastSubMs=Long.MIN_VALUE; boolean subInfoMissing; int subSends;
    Object getApplicationContext() { return null; }
    void writeDebugLog(String s) {}
    int outputErrors; boolean expectErrors;
    boolean outputError(Throwable e) { if (!expectErrors) throw new AssertionError(e); outputErrors++; cluster = null; lastPe00Bucket = Long.MIN_VALUE; return false; }
    static void check(boolean condition, String message) { if(!condition) throw new AssertionError(message); }
    public static void main(String[] args) {
        CoreLifecycleTest c=new CoreLifecycleTest();
        c.allowed=true; c.renderAaTbt(65,0,1900,"road");
        c.allowed=false; c.renderAaTbt(0,0,-1,null);
        check(!c.isAaGuidanceActive() && c.aaClearPending && c.cluster.clears==0, "clear state while stock owns display");
        c.flushAaClear(); check(c.cluster.clears==0, "do not clear stock HUD");
        c.allowed=true; c.flushAaClear(); check(c.cluster.clears==1 && !c.aaClearPending && !c.lastGuiding, "flush deferred clear");
        c.renderAaTbt(65,0,1000,"road"); c.session.active=true;
        c.renderAaTbt(0,0,-1,null);
        check(c.cluster.clears==1 && c.session.retries==1, "preserve CarPlay on AA end");
        c.session.active=false; c.renderAaTbt(0,0,-1,null);
        check(c.cluster.clears==1, "unrelated finish must not clear native HUD");
        c.renderAaTbt(65,0,1000,"old"); c.allowed=false; c.renderAaTbt(0,0,-1,null);
        c.allowed=true; c.renderAaTbt(66,0,2000,"new"); c.flushAaClear();
        check(c.cluster.clears==1 && c.aaRoute.icon()==66 && !c.aaClearPending, "new route replaces pending clear");
        // A failed AA turn write is retried once a second until it succeeds.
        CoreLifecycleTest r=new CoreLifecycleTest(); r.expectErrors=true;
        r.shared.failTbt=1; r.renderAaTbt(66,65,700,"road");
        check(r.outputErrors==1 && r.shared.turns==0 && r.aaRoute.routePending(), "failed AA turn stays pending");
        r.retryAaOutput();
        check(r.shared.turns==1 && r.shared.lastIcon==66 && r.shared.lastDist==700 && r.dist2cCalls>=1 && r.lastDist2c==700 && !r.aaRoute.routePending(), "AA turn and SubInfo2C sent with sideStreet=0");
        r.retryAaOutput(); check(r.shared.turns==1, "sent AA turn is not resent");
        r.shared.failLanes=1; r.renderAaLane(new byte[]{1});
        check(r.shared.laneWrites==0 && r.aaRoute.lanePending(), "failed AA lane stays pending");
        r.retryAaOutput(); check(r.shared.laneWrites==1 && !r.aaRoute.lanePending(), "AA lane resent after failure");
        r.shared.failTbt=1; r.renderAaTbt(67,0,500,"road"); r.session.active=true; r.retryAaOutput();
        check(r.shared.turns==1, "AA retry yields to active CarPlay");
        r.session.active=false; r.allowed=false; r.renderAaTbt(68,0,400,"road");
        check(r.shared.turns==1, "no AA write while stock owns display");
        r.allowed=true; r.renderAaTbt(66,65,6000,"far");
        check(r.shared.lastIcon==66 && r.shared.lastSideStreet==0 && r.shared.lastDist==6000, "AA far maneuver keeps its real icon and sideStreet=0");
        r.renderAaTbt(66,65,400,"near-road");
        check(r.shared.lastIcon==StockTurn.DISPLAY_TURN && r.shared.lastSideStreet==0x0005 && r.shared.lastDirection==45f && r.shared.lastCombi==0, "AA near maneuver switches to StockTurn 0x0d");
        r.renderAaTbt(66,65,500,"near-road");
        check(r.shared.lastIcon==StockTurn.DISPLAY_TURN, "AA hysteresis holds near at 500m");
        r.renderAaTbt(66,65,600,"near-road");
        check(r.shared.lastIcon==66 && r.shared.lastSideStreet==0, "AA hysteresis exits to far icon at 600m");

        // A turn with no update for EXPIRE_MS is cleared as if it had ended.
        CoreLifecycleTest x=new CoreLifecycleTest(); x.clock=1000;
        x.renderAaTbt(65,0,900,"road");
        x.clock=1000+AaRouteCache.EXPIRE_MS-1; x.expireAaRoute();
        check(x.isAaGuidanceActive() && x.shared.clears==0, "fresh AA turn kept");
        x.clock=1000+AaRouteCache.EXPIRE_MS; x.expireAaRoute();
        check(!x.isAaGuidanceActive() && x.shared.clears==1 && !x.aaClearPending, "stale AA turn cleared from HUD");
        x.expireAaRoute(); check(x.shared.clears==1, "expiry clears once");
        x.renderAaTbt(65,0,900,"road"); x.session.active=true; x.clock+=AaRouteCache.EXPIRE_MS; x.expireAaRoute();
        check(x.shared.clears==1 && x.session.retries==1, "expiry under CarPlay keeps CarPlay");

        // Distance sub-info clear failure keeps AA clear pending until retry succeeds.
        CoreLifecycleTest d=new CoreLifecycleTest(); d.expectErrors=true;
        d.renderAaTbt(65,0,1000,"road"); d.failDist2c=true; d.renderAaTbt(0,0,-1,null);
        check(d.aaClearPending && d.outputErrors==1 && d.cluster==null, "failed distance clear keeps AA clear pending");
        d.flushAaClear();
        check(!d.aaClearPending && !d.lastGuiding, "deferred clear finishes once distance clear succeeds");
        check(NavigationCluster.pe00Writes == 0, "non-tunnel AA routes never touch PE_00");

        // AA tunnel triggers PE_00 within 1000m and clears once on exit/non-tunnel.
        CoreLifecycleTest p=new CoreLifecycleTest(); p.expectErrors=true;
        p.renderAaTbtWithTunnel(0x5b,0,430,"남산1호터널",true);
        check(NavigationCluster.pe00Writes==1 && NavigationCluster.pe00Exist==1 && NavigationCluster.pe00Dist==400 && !p.aaRoute.routePending(), "AA tunnel sends PE_00");
        p.renderAaTbtWithTunnel(0x41,0,300,"일반도로",false);
        check(NavigationCluster.pe00Writes==2 && NavigationCluster.pe00Exist==0 && NavigationCluster.pe00Dist==0, "leaving tunnel clears PE_00 once");
        p.renderAaTbt(0,0,-1,null);
        check(NavigationCluster.pe00Writes==2, "normal AA end after non-tunnel does not repeat PE_00 clear");
        NavigationCluster.failPe00=1;
        p.renderAaTbtWithTunnel(0x5b,0,200,"북악터널",true);
        check(p.outputErrors==1 && p.aaRoute.routePending(), "failed PE_00 keeps route pending");
        p.retryAaOutput();
        check(NavigationCluster.pe00Writes==3 && NavigationCluster.pe00Exist==1 && NavigationCluster.pe00Dist==200 && !p.aaRoute.routePending(), "retry sends pending PE_00");
        p.renderAaTbt(0,0,-1,null);
        check(NavigationCluster.pe00Writes==4 && NavigationCluster.pe00Exist==0, "AA end clears active PE_00");

        // A time-only packet may not erase the distance when this route has none yet.
        CoreLifecycleTest totals=new CoreLifecycleTest(); totals.session.active=true;
        int initialSub=NavigationCluster.subWrites;
        check(!totals.sendSubInfo() && NavigationCluster.subWrites==initialSub, "active route with unknown totals does not blank distance");
        totals.subSeconds=1800; totals.subArrivalMs=123456;
        int sw=NavigationCluster.subWrites;
        check(!totals.sendSubInfo() && NavigationCluster.subWrites==sw, "unknown distance defers time-only packet");
        totals.subMeters=5000;
        check(totals.sendSubInfo() && NavigationCluster.subDistance==5000, "known distance and clock sent together");
        totals.session.active=false; totals.subMeters=-1; totals.subSeconds=-1; totals.subArrivalMs=-1;
        check(totals.sendSubInfo() && NavigationCluster.subDistance==-1, "explicit route end still clears totals");
        // Successful PE_00 packets never repeat, including shutdown clears.
        CoreLifecycleTest q=new CoreLifecycleTest(); q.clock=10000;
        q.maintainTunnelPe00(); check(NavigationCluster.pe00Writes==0, "idle maintenance never touches PE_00");
        q.syncCarPlayTunnel(true,300); int w=NavigationCluster.pe00Writes;
        for(int i=0;i<10;i++){q.clock+=4000; q.maintainTunnelPe00();}
        check(NavigationCluster.pe00Writes==w, "successful tunnel never reasserted on timer");
        q.finalTunnelClear(); check(NavigationCluster.pe00Writes==w+1 && NavigationCluster.pe00Exist==0, "shutdown clears once");
        q.maintainTunnelPe00(); check(NavigationCluster.pe00Writes==w+1, "successful clear never repeats");
        // Only an observed local failure remains pending for recovery.
        q.syncAaTunnel(true,400); q.expectErrors=true; NavigationCluster.failPe00=1;
        q.syncAaTunnel(false,-1); check(q.phoneTunnelSent, "failed clear stays pending");
        q.maintainTunnelPe00(); check(!q.phoneTunnelSent, "observed failed clear retried");
        CoreLifecycleTest k=new CoreLifecycleTest(); k.syncAaTunnel(true,300); w=NavigationCluster.pe00Writes;
        k.aaRoute.setOutputAllowed(false); k.yieldToStock(true);
        k.maintainTunnelPe00(); check(NavigationCluster.pe00Writes==w, "no clear over stock guidance");
        // Stale lanes: a new maneuver without lanes clears them once; a clear with nothing shown writes nothing.
        CoreLifecycleTest l=new CoreLifecycleTest(); l.clock=1000;
        l.renderAaLane(LaneFrame.clear()); check(NavigationCluster.laneClears==0, "no lane frame shown: clear writes nothing");
        l.renderAaLane(new byte[]{1,2,3}); check(NavigationCluster.laneWrites>=1, "lane frame written");
        int lc=NavigationCluster.laneClears; l.renderAaLane(LaneFrame.clear());
        check(NavigationCluster.laneClears==lc+1, "stale lanes cleared for a lane-less maneuver");
        l.renderAaLane(LaneFrame.clear()); check(NavigationCluster.laneClears==lc+1, "repeated lane clear is not rewritten");
        // Lane clearing is decided in queue order on the io thread, per new maneuver.
        CoreLifecycleTest m=new CoreLifecycleTest(); m.clock=1000;
        m.renderAaTbtWithTunnel(66,0,900,"road",false); m.renderAaLane(new byte[]{1,2,3});
        int mc=NavigationCluster.laneClears;
        m.renderAaTbtWithTunnel(66,0,800,"road",false); check(NavigationCluster.laneClears==mc, "same maneuver keeps its lanes");
        m.renderAaTbtWithTunnel(67,0,700,"road",false); check(NavigationCluster.laneClears==mc, "new maneuver that supplies lanes does not clear first");
        m.renderAaTbtWithTunnel(68,0,600,"road",false); check(NavigationCluster.laneClears==mc, "GPM turn update without lane data preserves lanes");
        m.renderAaTbtWithTunnel(69,0,500,"road",false); check(NavigationCluster.laneClears==mc, "subsequent turn does not invent lane clear");
        // Shutdown during AA guidance clears the AA outputs (stock idle) and the CarPlay session.
        CoreLifecycleTest sd=new CoreLifecycleTest(); sd.clock=1000; sd.renderAaTbt(66,0,900,"road"); int sdc=NavigationCluster.clears;
        sd.shutdownOutputs();
        check(NavigationCluster.clears==sdc+1 && !sd.aaRoute.isActive(), "shutdown clears active AA guidance");
        // Stock GPM sends the trap reset with AA turn updates: once per guidance, and again after a clear.
        CoreLifecycleTest t=new CoreLifecycleTest(); t.clock=1000; int tw=NavigationCluster.trapWrites;
        t.renderAaTbt(66,0,900,"road"); check(NavigationCluster.trapWrites==tw+1, "AA guidance sends the stock trap reset");
        t.renderAaTbt(66,0,800,"road"); check(NavigationCluster.trapWrites==tw+2, "trap reset follows each turn update as in GPM");
        t.renderAaTbt(0,0,-1,null); t.renderAaTbt(66,0,700,"road"); check(NavigationCluster.trapWrites==tw+3, "trap reset sent again for a new guidance");
        check(NavigationCluster.pe00Background==0, "phone PE_00 never fabricates parking/air-condition/road-class fields");
        System.out.println("PASS Core lifecycle: stock ownership, deferred AA clear, CarPlay preservation, AA retry, expiry, and PE_00");
    }
'''
with tempfile.TemporaryDirectory(prefix='gen5w-core-lifecycle-') as tmp:
    path = Path(tmp)/'CoreLifecycleTest.java'
    path.write_bytes((harness+'\n'+maneuver_src+'\n'+stockturn_src+'\n'+cache+'\n'+methods+'\n}\n').encode('utf-8'))
    subprocess.run(['javac','--release','8','-d',tmp,str(path)], check=True)
    subprocess.run(['java','-cp',tmp,'CoreLifecycleTest'], check=True)
