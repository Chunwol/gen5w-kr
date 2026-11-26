"""Exercise production relay lifecycle; fake only Android, adapter and AP boundaries."""
import ast
from pathlib import Path
import subprocess
import repo_tmp as tempfile

root = Path(__file__).resolve().parents[1]
tree = ast.parse((root / 'tests/wireless_bridge_integration.py').read_text(encoding='utf-8'))
stubs = ast.literal_eval(next(n.value for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'stubs' for t in n.targets)))
stubs.pop('kr/gen5w/wireless/V039RelayCoordinator.java')
stubs['android/os/Handler.java'] = '''package android.os; public class Handler {
 public static final java.util.List<Runnable> delayed = new java.util.ArrayList<Runnable>();
 public static long lastDelay = -1L;
 public Handler(Looper l){}
 public void post(Runnable r){r.run();}
 public void postDelayed(Runnable r,long t){lastDelay=t;delayed.add(r);}
 public void removeCallbacks(Runnable r){}
}'''
stubs['android/os/SystemClock.java'] = 'package android.os; public class SystemClock { public static long time; public static long elapsedRealtime(){return time;} }'
stubs['kr/gen5w/wireless/BtRelayPipe.java'] = 'package kr.gen5w.wireless; class BtRelayPipe { enum Event { CLOSED } interface Diagnostics { void event(Event e,int c); } }'
stubs['kr/gen5w/wireless/V039BtRelayAdapter.java'] = '''package kr.gen5w.wireless;
class V039BtRelayAdapter {
 interface Listener {void ready();void sppConnected(long g);void iap2Connected(long g,int c);void disconnected(long g,int c);void failed(long g,Failure f);}
 enum Failure { SPP_CONNECT,IAP2_START,IAP2_UNAVAILABLE,BTCM_UNAVAILABLE,TRANSPORT,OTHER }
 static int connects, fallbacks; static long generation; static boolean reject=true;
 V039BtRelayAdapter(android.content.Context c,Listener l,BtRelayPipe.Diagnostics d){}
 boolean open(){return true;} boolean connect(long g,String a){connects++;generation=g;return !reject;}
 boolean requestSppConnect(long g){if(g==generation){fallbacks++;return true;}return false;}
 boolean startIap2(long g,int c){return true;} void stop(int c){} void disconnect(){} void close(){}
}'''
stubs['kr/gen5w/hotspot/ApProfiles.java'] = 'package kr.gen5w.hotspot; public class ApProfiles { public interface Guard {void check() throws Exception;} }'
stubs['kr/gen5w/hotspot/ApBrokerClient.java'] = '''package kr.gen5w.hotspot; public class ApBrokerClient {
 public static volatile java.util.concurrent.CountDownLatch stopping,release; public static volatile int stopped;
 public static void ensure(ApProfiles.Guard g)throws Exception{g.check();}
 public static void stop(ApProfiles.Guard g)throws Exception{if(stopping!=null){stopping.countDown();release.await();}g.check();stopped++;}
}'''
harness = '''package kr.gen5w.wireless;
public class RelayCoordinatorIntegrationTest {
 static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
 static int failures;
 static V039RelayCoordinator fresh(){failures=0;V039BtRelayAdapter.connects=0;V039BtRelayAdapter.fallbacks=0;V039BtRelayAdapter.reject=true;android.os.Handler.delayed.clear();android.os.Handler.lastDelay=-1L;android.os.SystemClock.time=0;V039RelayCoordinator c=new V039RelayCoordinator(null,new android.os.Handler(null),new V039RelayCoordinator.Events(){public void relayEvent(String n,String r){if(r.startsWith("failed-"))failures++;}});c.ready();return c;}
 static void retriesBounded(){V039RelayCoordinator c=fresh();try{
 c.start("phone");check(V039BtRelayAdapter.connects==1,"initial attempt");
 c.tick();c.tick();check(failures==1,"one failure is reported once, not on every later update");
 android.os.SystemClock.time=4999;c.start("phone");check(V039BtRelayAdapter.connects==1,"five second backoff");
 android.os.SystemClock.time=5000;c.start("phone");check(V039BtRelayAdapter.connects==2,"same-phone transient failure retries after cleanup");
 android.os.SystemClock.time=14999;c.start("phone");check(V039BtRelayAdapter.connects==2,"ten second backoff");
 android.os.SystemClock.time=15000;c.start("phone");check(V039BtRelayAdapter.connects==3,"third attempt");
 android.os.SystemClock.time=99999;c.start("phone");check(V039BtRelayAdapter.connects==3,"bounded at three attempts");
 c.candidateLost();c.start("phone");check(V039BtRelayAdapter.connects==4,"loss resets retry budget");
 }finally{c.close();}}
 static void cleanupOwnsGate()throws Exception{V039RelayCoordinator c=fresh();try{
 V039BtRelayAdapter.reject=false;c.start("phone");long g=V039BtRelayAdapter.generation;
 c.credentialsReady();c.sppConnected(g);
 kr.gen5w.hotspot.ApBrokerClient.stopping=new java.util.concurrent.CountDownLatch(1);kr.gen5w.hotspot.ApBrokerClient.release=new java.util.concurrent.CountDownLatch(1);
 c.failed(g,V039BtRelayAdapter.Failure.OTHER);check(kr.gen5w.hotspot.ApBrokerClient.stopping.await(2,java.util.concurrent.TimeUnit.SECONDS),"AP cleanup started");
 c.tick();c.tick();c.tick();check(failures==1,"failure reported once while cleanup is still running");
 android.os.SystemClock.time=99999;c.start("phone");check(V039BtRelayAdapter.connects==1,"no retry during cleanup");
 c.candidateLost();c.start("other");check(V039BtRelayAdapter.connects==1,"no second owner during cleanup");
 kr.gen5w.hotspot.ApBrokerClient.release.countDown();
 }finally{if(kr.gen5w.hotspot.ApBrokerClient.release!=null)kr.gen5w.hotspot.ApBrokerClient.release.countDown();c.close();}}
 static void shutdownCleansAp()throws Exception{V039RelayCoordinator c=fresh();V039BtRelayAdapter.reject=false;c.start("phone");c.credentialsReady();c.sppConnected(V039BtRelayAdapter.generation);
 java.lang.reflect.Field f=c.getClass().getDeclaredField("apCalls");f.setAccessible(true);java.util.concurrent.ExecutorService executor=(java.util.concurrent.ExecutorService)f.get(c);
 int before=kr.gen5w.hotspot.ApBrokerClient.stopped;c.close();check(executor.awaitTermination(2,java.util.concurrent.TimeUnit.SECONDS),"AP worker terminates");check(kr.gen5w.hotspot.ApBrokerClient.stopped==before+1,"shutdown drains owned AP stop with valid guard");}
 static BtRelaySession.Phase phase(V039RelayCoordinator c)throws Exception{java.lang.reflect.Field f=c.getClass().getDeclaredField("session");f.setAccessible(true);return ((BtRelaySession)f.get(c)).phase();}
 static void waitPhase(V039RelayCoordinator c,BtRelaySession.Phase p)throws Exception{for(int i=0;i<200&&phase(c)!=p;i++)Thread.sleep(10);check(phase(c)==p,"phase "+p+" got "+phase(c));}
 static void wifiSessionOutlivesBluetooth()throws Exception{V039RelayCoordinator c=fresh();try{
 kr.gen5w.hotspot.ApBrokerClient.stopping=null;
 V039BtRelayAdapter.reject=false;c.start("phone");long g=V039BtRelayAdapter.generation;
 c.credentialsReady();c.sppConnected(g);c.iap2Connected(g,4);c.handoverRequested();c.handoverConnected();
 waitPhase(c,BtRelaySession.Phase.ACTIVE);
 int before=kr.gen5w.hotspot.ApBrokerClient.stopped;
 c.disconnected(g,4);c.bluetoothLost();c.failed(0,V039BtRelayAdapter.Failure.BTCM_UNAVAILABLE);c.failed(g,V039BtRelayAdapter.Failure.TRANSPORT);c.tick();
 check(phase(c)==BtRelaySession.Phase.ACTIVE&&kr.gen5w.hotspot.ApBrokerClient.stopped==before,"Bluetooth loss keeps the running Wi-Fi session and its AP");
 c.failed(g,V039BtRelayAdapter.Failure.IAP2_UNAVAILABLE);waitPhase(c,BtRelaySession.Phase.FAILED);
 check(kr.gen5w.hotspot.ApBrokerClient.stopped==before+1,"losing the iAP2 service (component 5) still stops the AP");
 android.os.SystemClock.time=50000;c.start("phone");g=V039BtRelayAdapter.generation;
 c.credentialsReady();c.sppConnected(g);c.iap2Connected(g,4);c.handoverRequested();c.handoverConnected();
 waitPhase(c,BtRelaySession.Phase.ACTIVE);before=kr.gen5w.hotspot.ApBrokerClient.stopped;
 c.handoverDisconnected();waitPhase(c,BtRelaySession.Phase.CANCELLED);
 check(kr.gen5w.hotspot.ApBrokerClient.stopped==before+1,"DiPO's session end stops the AP");
 // Before DiPO runs a session, Bluetooth loss still ends the attempt.
 android.os.SystemClock.time=100000;c.start("phone");long g2=V039BtRelayAdapter.generation;check(g2!=g,"new attempt");
 c.credentialsReady();c.sppConnected(g2);c.iap2Connected(g2,4);
 c.disconnected(g2,4);waitPhase(c,BtRelaySession.Phase.CANCELLED);
 }finally{c.close();}}
 static void sppActiveFallbackWithinFirstAttempt(){V039RelayCoordinator c=fresh();try{
 V039BtRelayAdapter.reject=false;c.start("phone");
 check(android.os.Handler.lastDelay==V039RelayCoordinator.SPP_ACTIVE_FALLBACK_MS&&android.os.Handler.delayed.size()==1,"schedules 2s active SPP fallback");
 android.os.Handler.delayed.get(0).run();
 check(V039BtRelayAdapter.fallbacks==1,"first attempt triggers requestSppConnect after 2s wait");
 c.sppConnected(V039BtRelayAdapter.generation);
 c.start("phone");
 int before=V039BtRelayAdapter.fallbacks;
 for(Runnable r:android.os.Handler.delayed)r.run();
 check(V039BtRelayAdapter.fallbacks==before,"fallback does not fire after SPP connected");
 }finally{c.close();}
 V039RelayCoordinator c2=fresh();V039BtRelayAdapter.reject=false;c2.start("phone");c2.close();
 int beforeClose=V039BtRelayAdapter.fallbacks;
 for(Runnable r:android.os.Handler.delayed)r.run();
 check(V039BtRelayAdapter.fallbacks==beforeClose,"fallback ignored after coordinator closes");}
 static void staleHandoverDisconnectIgnored()throws Exception{V039RelayCoordinator c=fresh();try{
 V039BtRelayAdapter.reject=false;android.os.SystemClock.time=500000;c.start("phone");
 check(c.active(),"attempt active");
 c.handoverDisconnected(499000L);
 check(c.active(),"disconnect sent before this attempt began is ignored");
 c.handoverDisconnected(500001L);waitPhase(c,BtRelaySession.Phase.CANCELLED);
 }finally{c.close();}}
 static void retryNowClearsBackoff(){V039RelayCoordinator c=fresh();try{
 for(int i=0;i<3;i++){c.start("phone");android.os.SystemClock.time+=100000;}
 check(V039BtRelayAdapter.connects==3,"exhausted 3 attempts");
 c.start("phone");check(V039BtRelayAdapter.connects==3,"blocked before retryNow");
 c.retryNow();c.start("phone");check(V039BtRelayAdapter.connects==4,"retryNow clears attempts/backoff immediately");
 }finally{c.close();}}
 static void component5EndReconcilesActive()throws Exception{V039RelayCoordinator c=fresh();try{
 V039BtRelayAdapter.reject=false;android.os.SystemClock.time=900000;c.start("phone");long g=c.generation();
 c.credentialsReady();c.sppConnected(g);c.iap2Connected(g,4);c.handoverRequested();c.handoverConnected();
 waitPhase(c,BtRelaySession.Phase.ACTIVE);
 c.disconnected(g-1,5);check(c.carPlayOwned(),"stale component5 end cannot cancel current generation");
 c.retryNow();check(c.carPlayOwned(),"retry alone cannot invent evidence of session end");
 c.disconnected(g,5);waitPhase(c,BtRelaySession.Phase.CANCELLED);
 c.start("phone");check(c.generation()>g,"real component5 end releases phantom ACTIVE for a new generation");
 }finally{c.close();}}
 public static void main(String[]args)throws Exception{component5EndReconcilesActive();retriesBounded();cleanupOwnsGate();shutdownCleansAp();wifiSessionOutlivesBluetooth();sppActiveFallbackWithinFirstAttempt();staleHandoverDisconnectIgnored();retryNowClearsBackoff();System.out.println("PASS production relay coordinator retry integration");}
}'''
with tempfile.TemporaryDirectory(prefix='gen5w-relay-coordinator-') as tmp:
    base = Path(tmp)
    for name, source in stubs.items():
        p = base / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(source, encoding='utf-8')
    test = base / 'kr/gen5w/wireless/RelayCoordinatorIntegrationTest.java'
    test.write_text(harness, encoding='utf-8')
    prod = root / 'packages/wireless-bridge/src/kr/gen5w/wireless'
    subprocess.run(['javac', '--release', '8', '-d', tmp,str(root/'shared/src/kr/gen5w/diag/SafeDiagnostic.java')] + [str(p) for p in base.rglob('*.java')] + [str(prod/n) for n in ['V039RelayCoordinator.java', 'BtRelaySession.java']], check=True)
    subprocess.run(['java', '-cp', tmp, 'kr.gen5w.wireless.RelayCoordinatorIntegrationTest'], check=True)
