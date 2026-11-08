"""Exercise production relay lifecycle; fake only Android, adapter and AP boundaries."""
import ast
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
tree = ast.parse((root / 'tests/wireless_bridge_integration.py').read_text(encoding='utf-8'))
stubs = ast.literal_eval(next(n.value for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'stubs' for t in n.targets)))
stubs.pop('kr/gen5w/wireless/V039RelayCoordinator.java')
stubs['android/os/SystemClock.java'] = 'package android.os; public class SystemClock { public static long time; public static long elapsedRealtime(){return time;} }'
stubs['kr/gen5w/wireless/BtRelayPipe.java'] = 'package kr.gen5w.wireless; class BtRelayPipe { enum Event { CLOSED } interface Diagnostics { void event(Event e,int c); } }'
stubs['kr/gen5w/wireless/V039BtRelayAdapter.java'] = '''package kr.gen5w.wireless;
class V039BtRelayAdapter {
 interface Listener {void ready();void sppConnected(long g);void iap2Connected(long g,int c);void disconnected(long g,int c);void failed(long g,Failure f);}
 enum Failure { SPP_CONNECT,IAP2_START,IAP2_UNAVAILABLE,OTHER }
 static int connects; static long generation; static boolean reject=true;
 V039BtRelayAdapter(android.content.Context c,Listener l,BtRelayPipe.Diagnostics d){}
 boolean open(){return true;} boolean connect(long g,String a){connects++;generation=g;return !reject;}
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
 static V039RelayCoordinator fresh(){V039BtRelayAdapter.connects=0;V039BtRelayAdapter.reject=true;android.os.SystemClock.time=0;V039RelayCoordinator c=new V039RelayCoordinator(null,new android.os.Handler(null),new V039RelayCoordinator.Events(){public void relayEvent(String n,String r){}});c.ready();return c;}
 static void retriesBounded(){V039RelayCoordinator c=fresh();try{
 c.start("phone");check(V039BtRelayAdapter.connects==1,"initial attempt");
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
 android.os.SystemClock.time=99999;c.start("phone");check(V039BtRelayAdapter.connects==1,"no retry during cleanup");
 c.candidateLost();c.start("other");check(V039BtRelayAdapter.connects==1,"no second owner during cleanup");
 kr.gen5w.hotspot.ApBrokerClient.release.countDown();
 }finally{if(kr.gen5w.hotspot.ApBrokerClient.release!=null)kr.gen5w.hotspot.ApBrokerClient.release.countDown();c.close();}}
 static void shutdownCleansAp()throws Exception{V039RelayCoordinator c=fresh();V039BtRelayAdapter.reject=false;c.start("phone");c.credentialsReady();c.sppConnected(V039BtRelayAdapter.generation);
 java.lang.reflect.Field f=c.getClass().getDeclaredField("apCalls");f.setAccessible(true);java.util.concurrent.ExecutorService executor=(java.util.concurrent.ExecutorService)f.get(c);
 int before=kr.gen5w.hotspot.ApBrokerClient.stopped;c.close();check(executor.awaitTermination(2,java.util.concurrent.TimeUnit.SECONDS),"AP worker terminates");check(kr.gen5w.hotspot.ApBrokerClient.stopped==before+1,"shutdown drains owned AP stop with valid guard");}
 public static void main(String[]args)throws Exception{retriesBounded();cleanupOwnsGate();shutdownCleansAp();System.out.println("PASS production relay coordinator retry integration");}
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
