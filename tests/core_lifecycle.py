"""Run the production CoreService lifecycle methods with host boundary fakes."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root/'app/src/kr/gen5w/core/CoreService.java').read_text(encoding='utf-8')
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
    'private boolean isAaGuidanceActive()', 'private void resetAaState()',
    'private static NavigationCluster.CrossroadName crossroadName(',
    'private void flushAaClear()', 'private void renderAaTbt(',
    'private void reassertStockSafetyPeriod()'])
harness = r'''
import java.util.*;
public class CoreLifecycleTest {
    static long now = 10000;
    static class SystemClock { static long elapsedRealtime() { return now; } }
    static class Handler {
        Map<Runnable,Long> pending = new HashMap<Runnable,Long>();
        void post(Runnable r) { r.run(); }
        void removeCallbacks(Runnable r) { pending.remove(r); }
        void postDelayed(Runnable r, long delay) { pending.put(r, now+delay); }
        void advance(long value) {
            now=value;
            for (Runnable r : new ArrayList<Runnable>(pending.keySet())) {
                if (pending.get(r)<=now) { pending.remove(r); r.run(); }
            }
        }
    }
    static class NavigationCluster {
        static class CrossroadName { String name; }
        int clears;
        NavigationCluster(Object ctx) {}
        void updateTPCrossroadName(CrossroadName name) {}
        void updateTBTInfo(int i,int j,float a,float b,int c,int d,int e,int f,int g) { if(i==0) clears++; }
        void updateTPTurnListNew(byte[] frame) {}
        void updateLaneInfo(byte[] frame) {}
    }
    static class LaneFrame { static byte[] clear() { return null; } }
    static class TurnFrame {
        static byte[] clear() { return null; }
        static byte[] encode(int[] icons, String road) { return null; }
        static float tbtDistanceValue(long d) { return d; }
        static int tbtDistanceError(long d) { return 0; }
        static int tbtDistanceScale(long d) { return 0; }
    }
    static class Session {
        boolean active; int retries;
        boolean hasActiveGuidance() { return active; }
        void invalidateOutput() {}
        void retryOutput() { retries++; }
    }
    Handler io = new Handler(); Session session = new Session();
    NavigationCluster cluster = new NavigationCluster(null);
    boolean allowed=true, aaClearPending, mediaOsdActive, stopping;
    int currentIcon1, currentIcon2, soundCount;
    long currentDist=-1, lastSoundOnMs; String currentRoadName;
    static final long SOUND_ON_REASSERT_MS=5000;
    Runnable soundOnRetry = new Runnable() { public void run() { if(!stopping) reassertStockSafetyPeriod(); } };
    boolean refreshOwnership() { return allowed; }
    Object getApplicationContext() { return null; }
    void keepStockSafetyGuidanceAlive() { soundCount++; }
    void writeDebugLog(String s) {}
    void outputError(Throwable e) { throw new AssertionError(e); }
    static void check(boolean condition, String message) { if(!condition) throw new AssertionError(message); }
    public static void main(String[] args) {
        CoreLifecycleTest c=new CoreLifecycleTest();
        c.reassertStockSafetyPeriod();
        for(int i=0;i<20;i++) c.reassertStockSafetyPeriod();
        check(c.soundCount==1 && c.io.pending.size()==1, "coalesce SOUND_OFF burst");
        c.io.advance(14999); check(c.soundCount==1, "no early SOUND_ON");
        c.io.advance(15000); check(c.soundCount==2 && c.io.pending.isEmpty(), "one delayed SOUND_ON");
        c.reassertStockSafetyPeriod(); c.allowed=false; c.io.advance(20000);
        check(c.soundCount==2, "stock owner blocks delayed SOUND_ON");
        c.allowed=true; c.renderAaTbt(65,0,1900,"road");
        c.allowed=false; c.renderAaTbt(0,0,-1,null);
        check(!c.isAaGuidanceActive() && c.aaClearPending && c.cluster.clears==0, "clear state while stock owns display");
        c.flushAaClear(); check(c.cluster.clears==0, "do not clear stock HUD");
        c.allowed=true; c.flushAaClear(); check(c.cluster.clears==1 && !c.aaClearPending, "flush deferred clear");
        c.renderAaTbt(65,0,1000,"road"); c.session.active=true;
        c.renderAaTbt(0,0,-1,null);
        check(c.cluster.clears==1 && c.session.retries==1, "preserve CarPlay on AA end");
        c.session.active=false; c.renderAaTbt(0,0,-1,null);
        check(c.cluster.clears==1, "unrelated finish must not clear native HUD");
        c.renderAaTbt(65,0,1000,"old"); c.allowed=false; c.renderAaTbt(0,0,-1,null);
        c.allowed=true; c.renderAaTbt(66,0,2000,"new"); c.flushAaClear();
        check(c.cluster.clears==1 && c.currentIcon1==66 && !c.aaClearPending, "new route replaces pending clear");
        System.out.println("PASS Core lifecycle: sound throttle, stock ownership, deferred AA clear, CarPlay preservation");
    }
'''
with tempfile.TemporaryDirectory(prefix='gen5w-core-lifecycle-') as tmp:
    path = Path(tmp)/'CoreLifecycleTest.java'
    path.write_text(harness+'\n'+methods+'\n}\n', encoding='utf-8')
    subprocess.run(['javac','--release','8','-d',tmp,str(path)], check=True)
    subprocess.run(['java','-cp',tmp,'CoreLifecycleTest'], check=True)
