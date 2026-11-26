"""Run the production DiPO bridge; replace only Android/OEM boundary classes."""
from pathlib import Path
import subprocess
import repo_tmp as tempfile

ROOT = Path(__file__).resolve().parents[1]
STUBS = {
 'android/content/Intent.java': '''package android.content; public class Intent {public final String action; public Intent(String a){action=a;} public Intent setPackage(String p){return this;} public Intent putExtra(String k,long v){return this;}}''',
 'android/os/SystemClock.java': 'package android.os; public final class SystemClock { public static long elapsedRealtime(){return 1L;} }',
 'android/os/RemoteException.java': 'package android.os; public class RemoteException extends Exception {}',
 'android/util/Log.java': 'package android.util; public final class Log { public static java.util.List<String> lines=new java.util.ArrayList<String>(); public static int i(String t,String m){lines.add(t+":"+m);return 0;} }',
 'com/daudio/app/dipo/telechips/CarPlayService.java': '''package com.daudio.app.dipo.telechips;
 public class CarPlayService {public int requests,failures,inbound,connections,disconnects;public boolean failNotification;public void sendBroadcast(android.content.Intent i){if(failNotification)throw new IllegalStateException("delivery failed");if(i.action.endsWith("REQUESTED"))requests++;else if(i.action.endsWith("DISCONNECTED"))failures++;else if(i.action.endsWith("CONNECTED"))connections++;}public Object iAPSendMessage(byte[] b,int n){inbound++;return null;}public Object disconnectCarPlay(){disconnects++;return null;}}''',
 'com/tcc/iap2/IIap2Listener.java': '''package com.tcc.iap2; public interface IIap2Listener {void connected(int c,String s);void disconnected(int c);void notify(int w,int a,int b,Iap2NotiMsg m);abstract class Stub implements IIap2Listener {}}''',
 'com/tcc/iap2/IIap2Service.java': '''package com.tcc.iap2; public interface IIap2Service {boolean Iap2SvcInit(IIap2Listener l,Iap2ListenerInfo i)throws android.os.RemoteException;boolean Iap2SvcTransportReadDone(byte[] b,int n)throws android.os.RemoteException;}''',
 'com/tcc/iap2/Iap2ListenerInfo.java': '''package com.tcc.iap2;public class Iap2ListenerInfo{public void onSetSupportType(int i){}public void onSetListenerName(String s){}}''',
 'com/tcc/iap2/Iap2NotiMsg.java': '''package com.tcc.iap2;public class Iap2NotiMsg{public static final int OBJ_BLOB=11;public Iap2ObjGroup getItemGroup(){return new Iap2ObjGroup();}public static class Iap2ObjGroup{public int getItemCnt(){return 1;}public Iap2ObjItem getObjItem(int i){return new Iap2ObjItem();}}public static class Iap2ObjItem{public int getItemParamType(){return OBJ_BLOB;}public byte[] getItemByteArray(){return new byte[]{1};}}}''',
}
HARNESS = '''import kr.gen5w.dipo.RelayBridge;
import com.daudio.app.dipo.telechips.CarPlayService;
public class DipoRelayRuntimeTest {
 static void check(boolean ok,String m){if(!ok)throw new AssertionError(m);}
 static String address(String iap,String session){try{return (String)RelayBridge.class.getMethod("reconnectAddress",String.class,String.class).invoke(null,iap,session);}catch(Exception e){throw new AssertionError("missing safe reconnect address selection",e);}}
 static boolean keepBluetooth(){try{return ((Boolean)RelayBridge.class.getMethod("keepBluetoothForWireless").invoke(null)).booleanValue();}catch(Exception e){throw new AssertionError("missing wireless Bluetooth preservation gate",e);}}
 static class Port implements com.tcc.iap2.IIap2Service {
  int init,reads;boolean failOnce,rejectOnce,connectInInit,rejectRead;byte first;
  Runnable onRead;String order="";
  com.tcc.iap2.IIap2Listener listener;
  public boolean Iap2SvcInit(com.tcc.iap2.IIap2Listener l,com.tcc.iap2.Iap2ListenerInfo i)throws android.os.RemoteException {
   listener=l;init++;if(connectInInit)l.connected(5,null);if(init==1&&failOnce)throw new android.os.RemoteException();return !(init==1&&rejectOnce);
  }
  public boolean Iap2SvcTransportReadDone(byte[] b,int n)throws android.os.RemoteException{reads++;first=b[0];order+=b[0];if(rejectRead)throw new android.os.RemoteException();if(onRead!=null){Runnable r=onRead;onRead=null;r.run();}return false;}
 }
 public static void main(String[] args){
  Port p=new Port();CarPlayService owner=new CarPlayService();
  if(args[0].equals("consumed")){
   check(!RelayBridge.fromCarPlay(owner,new byte[]{1},1),"unowned callback must remain on OEM path");
   RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);
   check(RelayBridge.fromCarPlay(owner,new byte[]{1},1),"queued wireless callback has one consumer");
   check(!RelayBridge.fromCarPlay(owner,null,1),"invalid callback is not consumed");
   RelayBridge.sessionFinalized(owner);
   check(!RelayBridge.fromCarPlay(owner,new byte[]{1},1),"finalized callback remains unconsumed");
  }else if(args[0].equals("reconnect")){
   check("AA:BB".equals(address(null,"aa:bb")),"missing iAP identity must use session identity");
   check("CC:DD".equals(address("cc:dd","aa:bb")),"iAP identity takes precedence");
   check(address(null,null)==null,"missing both identities preserves stored address");
   check(address("","")==null,"empty identities preserve stored address");
  }else if(args[0].equals("register-exception")||args[0].equals("register-false")){
   p.failOnce=args[0].equals("register-exception");p.rejectOnce=!p.failOnce;
   RelayBridge.bind(p);RelayBridge.bind(p);
   check(p.init==2,"failed listener registration must retry the same service");
   RelayBridge.bind(p);check(p.init==2,"successful registration must stay idempotent");
  }else if(args[0].equals("early")){
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);
   byte[] frame={7,8};RelayBridge.fromCarPlay(owner,frame,2);frame[0]=99;
   check(owner.requests==1,"first iAP data must request handover before sessionStarted");
   check(p.reads==0,"unconnected component5 must buffer, not transmit");
   RelayBridge.connected(5,null);check(p.reads==1&&p.first==7,"early frame must be copied and flushed once");
  }else if(args[0].equals("late-bind")||args[0].equals("connect-in-init")){
   RelayBridge.sessionCreated(owner);RelayBridge.fromCarPlay(owner,new byte[]{7},1);
   p.connectInInit=args[0].equals("connect-in-init");
   if(!p.connectInInit)RelayBridge.connected(5,null);
   RelayBridge.bind(p);check(p.reads==1&&owner.connections==1,"registration completion must flush data and announce accepted connection");
  }else if(args[0].equals("overflow")||args[0].equals("byte-overflow")){
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);
   byte[] frame=new byte[args[0].equals("overflow")?1:1048577];
   for(int i=0;i<(frame.length==1?65:1);i++)RelayBridge.fromCarPlay(owner,frame,frame.length);
   RelayBridge.connected(5,null);
   check(p.reads==0,"overflow must abort rather than transmit a truncated protocol prefix");
   check(owner.failures==1,"overflow must notify host once");
  }else if(args[0].equals("read-false")){
   // V039 iAP2 server: Iap2SvcTransportReadDone returns false even when it delivered the data.
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);RelayBridge.connected(5,null);
   RelayBridge.fromCarPlay(owner,new byte[]{2},1);
   check(p.reads==2&&owner.failures==0&&owner.connections==1,"a false result from the V039 server is not a failure");
  }else if(args[0].equals("read-binder-failure")){
   p.rejectRead=true;RelayBridge.bind(p);RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);RelayBridge.connected(5,null);
   RelayBridge.fromCarPlay(owner,new byte[]{2},1);
   check(p.reads==1&&owner.failures==1&&owner.connections==0,"rejected transport must stop and notify without subsequent connected event");
  }else if(args[0].equals("replace-during-flush")){
   CarPlayService next=new CarPlayService();RelayBridge.bind(p);RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);p.onRead=()->RelayBridge.sessionCreated(next);
   RelayBridge.connected(5,null);
   check(next.connections==0&&owner.connections==0,"old completion cannot announce a replacement session connected");
  }else if(args[0].equals("reentrant-order")||args[0].equals("finalize-during-flush")){
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);RelayBridge.fromCarPlay(owner,new byte[]{2},1);
   boolean ending=args[0].equals("finalize-during-flush");
   p.onRead=()->{if(ending)RelayBridge.sessionFinalized(owner);else RelayBridge.fromCarPlay(owner,new byte[]{3},1);};
   RelayBridge.connected(5,null);
   check(ending?p.reads==1:p.order.equals("123"),"flush must preserve order and stop when its session ends");
  }else if(args[0].equals("rejected-listener")){
   p.rejectOnce=true;RelayBridge.sessionCreated(owner);RelayBridge.bind(p);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);p.listener.disconnected(5);
   RelayBridge.bind(p);p.listener.connected(5,null);
   check(p.reads==1,"rejected registration listener cannot discard buffered data");
  }else if(args[0].equals("old-listener")){
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);
   Port next=new Port();RelayBridge.bind(next);RelayBridge.fromCarPlay(owner,new byte[]{1},1);
   p.listener.disconnected(5);next.listener.connected(5,null);
   check(next.reads==1,"obsolete listener disconnect cannot discard current queue");
   p.listener.notify(81,0,0,new com.tcc.iap2.Iap2NotiMsg());
   check(owner.inbound==0,"obsolete listener cannot inject into current session");
   next.listener.notify(81,0,0,new com.tcc.iap2.Iap2NotiMsg());check(owner.inbound==1,"active wireless input must pass");
  }else if(args[0].equals("early-outbound")){
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);
   p.listener.notify(81,0,0,new com.tcc.iap2.Iap2NotiMsg());check(owner.inbound==1,"link-detect before connected(5) must reach the phone");
   Port other=new Port();RelayBridge.sessionCreated(owner);RelayBridge.bind(other);
   other.listener.notify(81,0,0,new com.tcc.iap2.Iap2NotiMsg());check(owner.inbound==1,"no handover request: component-5 output is not forwarded");
  }else if(args[0].equals("wired-inbound")){
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,0);
   p.listener.notify(81,0,0,new com.tcc.iap2.Iap2NotiMsg());check(owner.inbound==0,"wireless input cannot enter wired session");
  }else if(args[0].equals("wired")){
   RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,0);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==0,"wired session must never request relay");
  }else if(args[0].equals("usb-early")){
   RelayBridge.connected(1,"usb");RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==0,"USB ownership excludes early wireless handover");
  }else if(args[0].equals("stale-owner")){
   CarPlayService stale=new CarPlayService();RelayBridge.sessionCreated(stale);RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(stale,new byte[]{1},1);check(stale.requests==0&&owner.requests==0,"old owner cannot inject into replacement session");
   RelayBridge.sessionFinalized(stale);RelayBridge.fromCarPlay(owner,new byte[]{1},1);
   check(owner.requests==1,"late old finalization cannot erase the current session");
  }else if(args[0].equals("stale-start")){
   CarPlayService stale=new CarPlayService();RelayBridge.sessionCreated(stale);RelayBridge.sessionCreated(owner);
   try{RelayBridge.class.getMethod("sessionStarted",CarPlayService.class,int.class).invoke(null,stale,0);}catch(Exception e){throw new AssertionError("sessionStarted must carry its owner",e);}
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==1,"stale start cannot turn replacement into wired");
  }else if(args[0].equals("listener-bt")){
   // V039 DiPO's own listener accepts only component 1; the relay's Bluetooth session (4) must reach it as 1.
   Object binder = new Object();
   long[] tk = new long[1];
   check(RelayBridge.prepareListenerConnected(binder, 4, "02:00:00:00:57:95", tk)==1,"Bluetooth CarPlay session must reach DiPO as a phone session");
   Boolean prevSyn=RelayBridge.enterBinderConnected(true);Boolean prevDel=RelayBridge.beginLocalDeliveryTracking();
   try{RelayBridge.connected(1,"02:00:00:00:57:95");RelayBridge.markLocalConnectedDelivered(1);
    RelayBridge.finishListenerConnected(binder,1,tk[0],RelayBridge.consumeLocalDeliveryTracking(prevDel));
   }finally{RelayBridge.exitBinderConnected(prevSyn);}
   RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==1,"a mapped Bluetooth session is not USB ownership");
  }else if(args[0].equals("listener-usb")){
   Object binder = new Object();
   long[] tk = new long[1];
   check(RelayBridge.prepareListenerConnected(binder, 1, "usb", tk)==1,"USB stays component 1");
   Boolean prevSyn=RelayBridge.enterBinderConnected(false);Boolean prevDel=RelayBridge.beginLocalDeliveryTracking();
   try{RelayBridge.connected(1,"usb");RelayBridge.markLocalConnectedDelivered(1);
    RelayBridge.finishListenerConnected(binder,1,tk[0],RelayBridge.consumeLocalDeliveryTracking(prevDel));
   }finally{RelayBridge.exitBinderConnected(prevSyn);}
   RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==0,"real USB still excludes wireless handover");
  }else if(args[0].equals("listener-cp5")){
   Object binder1 = new Object(), binder2 = new Object();
   long[] tk = new long[1];
   check(RelayBridge.prepareListenerConnected(binder1, 5, null, tk)==5&&tk[0]==0,"null serial must not remap component 5");
   check(RelayBridge.prepareListenerConnected(binder1, 5, "02:00:00:00:57:95", tk)==1&&tk[0]!=0,"after dropped null serial, valid component 5 still remaps to 1");
   // Concurrent second 5 while first is still in flight must not double-connect.
   long[] tkDup = new long[1];
   check(RelayBridge.prepareListenerConnected(binder1, 5, "02:00:00:00:57:95", tkDup)<0,"concurrent 5 during in-flight connect must stay notify-only");
   // Simulate OEM dropping before localConnected: finish with delivered=false clears reservation.
   Boolean pS0=RelayBridge.enterBinderConnected(true);Boolean pD0=RelayBridge.beginLocalDeliveryTracking();
   RelayBridge.finishListenerConnected(binder1,1,tk[0],RelayBridge.consumeLocalDeliveryTracking(pD0));RelayBridge.exitBinderConnected(pS0);
   check(RelayBridge.prepareListenerConnected(binder1, 5, "02:00:00:00:57:95", tk)==1,"failed OEM connect must keep component 5 eligible for retry");
   // In-flight B connect must not be poisoned by stale binder1 disconnect.
   long[] tkB = new long[1];
   check(RelayBridge.prepareListenerConnected(binder2, 5, "02:00:00:00:57:95", tkB)==1,"binder2 reserves 5->1");
   RelayBridge.listenerDisconnected(binder1, 1);
   RelayBridge.finishListenerConnected(binder2, 1, tkB[0], true);
   check(RelayBridge.prepareListenerConnected(binder2, 5, "02:00:00:00:57:95", tk)<0,"stale binder1 disconnect cannot block binder2 commit");
   RelayBridge.listenerDisconnected(binder2, 1);
   // Real multi-thread callback race check using binderCallbackLock.
   java.util.concurrent.CountDownLatch entered = new java.util.concurrent.CountDownLatch(1), release = new java.util.concurrent.CountDownLatch(1);
   java.util.concurrent.atomic.AtomicInteger t2Mapped = new java.util.concurrent.atomic.AtomicInteger(99);
   Thread t1 = new Thread(() -> {
    synchronized (RelayBridge.binderCallbackLock()) {
     long[] tk1 = new long[1];
     RelayBridge.prepareListenerConnected(binder1, 5, "02:00:00:00:57:95", tk1);
     entered.countDown();
     try { release.await(); } catch (InterruptedException ignored) {}
     RelayBridge.finishListenerConnected(binder1, 1, tk1[0], true);
    }
   });
   t1.start();
   try { entered.await(); } catch (InterruptedException ignored) {}
   Thread t2 = new Thread(() -> {
    synchronized (RelayBridge.binderCallbackLock()) {
     t2Mapped.set(RelayBridge.prepareListenerConnected(binder1, 5, "02:00:00:00:57:95", new long[1]));
    }
   });
   t2.start();
   try { Thread.sleep(30); } catch (InterruptedException ignored) {}
   check(t2Mapped.get()==99,"second binder callback waits cleanly on binderCallbackLock");
   release.countDown();
   try { t1.join(); t2.join(); } catch (InterruptedException ignored) {}
   check(t2Mapped.get()<0,"after first thread commits under lock, waiting thread sees notify-only");
   RelayBridge.listenerDisconnected(binder1, 1);
   check(RelayBridge.prepareListenerConnected(binder2, 5, "02:00:00:00:57:95", tk)==1,"after disconnect, component 5 re-establishes phone connection once");
   RelayBridge.finishListenerConnected(binder2,1,tk[0],false);
   check(RelayBridge.prepareListenerConnected(binder2, 2, "p", tk)==2&&RelayBridge.prepareListenerConnected(binder2, 0, "p", tk)==0,"other components stay stock");
   RelayBridge.sessionCreated(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==1,"mapped 5->1 session must not set USB ownership");
  }else if(args[0].equals("cp5-early-ready")){
   RelayBridge.bind(p);p.listener.connected(5,null);
   RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);
   check(owner.connections==1,"sessionStarted after early cp5 connect promotes connection at once");
   RelayBridge.fromCarPlay(owner,new byte[]{9},1);
   check(p.reads==1&&p.first==9,"fromCarPlay flushes immediately when cp5 connected before session");
  }else if(args[0].equals("cp5-finalized-stale-ready")){
   RelayBridge.bind(p);
   RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);
   RelayBridge.connected(5,null);
   check(owner.connections==1,"first session connects");
   RelayBridge.finalizeWirelessSession(owner);
   // Delayed component-5 disconnect has not arrived yet when replacement session starts.
   CarPlayService nextOwner=new CarPlayService();
   RelayBridge.sessionCreated(nextOwner);RelayBridge.sessionStarted(nextOwner,1);
   check(nextOwner.connections==0&&nextOwner.requests==1,"stale readiness from finalized session must not auto-connect replacement");
   RelayBridge.fromCarPlay(nextOwner,new byte[]{7},1);
   check(p.reads==0&&nextOwner.failures==0,"replacement data waits instead of flushing onto stale transport");
   // Delayed disconnect of previous retired transport must not cancel replacement session.
   p.listener.disconnected(5);
   check(nextOwner.failures==0,"delayed disconnect from retired transport cannot cancel replacement");
   p.listener.connected(5,null);
   check(nextOwner.connections==1&&p.reads==1&&p.first==7,"fresh component-5 connect promotes replacement and flushes");
  }else if(args[0].equals("ignore-disconnect")){
   check(!RelayBridge.ignoreListenerDisconnect(4),"before any wireless session the Bluetooth end is DiPO's");
   RelayBridge.sessionCreated(owner);check(!RelayBridge.ignoreListenerDisconnect(4),"a created session is not yet wireless");
   RelayBridge.sessionStarted(owner,1);
   check(RelayBridge.ignoreListenerDisconnect(4)&&RelayBridge.ignoreListenerDisconnect(5),"wireless CarPlay up: Bluetooth and channel ends are not DiPO's");
   check(!RelayBridge.ignoreListenerDisconnect(1)&&!RelayBridge.ignoreListenerDisconnect(2),"USB and other ends stay stock");
   RelayBridge.sessionFinalized(owner);check(!RelayBridge.ignoreListenerDisconnect(4),"after the session ends DiPO cleans up");
  }else if(args[0].equals("ignore-during-handover")){
   RelayBridge.sessionCreated(owner);RelayBridge.fromCarPlay(owner,new byte[]{1},1);
   check(RelayBridge.ignoreListenerDisconnect(4),"handover requested: the server ending component 4 must not stop DiPO");
  }else if(args[0].equals("wired-disconnect")){
   RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,0);
   check(!RelayBridge.ignoreListenerDisconnect(4)&&!RelayBridge.ignoreListenerDisconnect(5),"wired session never hides ends");
  }else if(args[0].equals("drop-notify")){
   check(!RelayBridge.dropListenerNotify(0)&&!RelayBridge.dropListenerNotify(24),"Bluetooth identification must reach DiPO (it starts AirPlay)");
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);RelayBridge.fromCarPlay(owner,new byte[]{1},1);
   check(RelayBridge.dropListenerNotify(0)&&RelayBridge.dropListenerNotify(24),"channel identification must not restart DiPO");
   check(!RelayBridge.dropListenerNotify(81)&&!RelayBridge.dropListenerNotify(5),"other notifications pass");
   RelayBridge.connected(5,null);RelayBridge.disconnected(5);
   check(!RelayBridge.dropListenerNotify(0),"after the channel ends identification passes again");
  }else if(args[0].equals("wireless-start")){
   // Car 2026-11-12 19:01:59: DiPO started the Wi-Fi session, then its onDisableBluetooth
   // dropped the phone's Bluetooth 2.8 s later, before any CarPlay-channel iAP2 data.
   RelayBridge.bind(p);RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);
   check(owner.requests==1,"a wireless DiPO session must hand over at once");
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==1,"handover is requested once");
   check(p.reads==0,"data waits for component 5");
   RelayBridge.connected(5,null);check(p.reads==1&&owner.connections==1,"component 5 is accepted after a session-start handover");
  }else if(args[0].equals("bluetooth-disable")){
   check(!keepBluetooth(),"no session does not suppress stock Bluetooth cleanup");
   RelayBridge.sessionCreated(owner);check(!keepBluetooth(),"created session is not wireless yet");
   RelayBridge.sessionStarted(owner,1);check(keepBluetooth(),"wireless CarPlay keeps the phone Bluetooth link");
   RelayBridge.sessionFinalized(owner);check(!keepBluetooth(),"finalized session restores stock cleanup");
   RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,0);
   check(!keepBluetooth(),"wired CarPlay retains stock Bluetooth cleanup");
   RelayBridge.connected(1,"usb");RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);
   check(!keepBluetooth(),"an active USB projection never suppresses Bluetooth cleanup");
  }else if(args[0].equals("wireless-start-usb")){
   RelayBridge.connected(1,"usb");RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);
   check(owner.requests==0,"a USB phone never hands over");
  }else if(args[0].equals("finalized")){
   RelayBridge.sessionCreated(owner);RelayBridge.sessionStarted(owner,1);RelayBridge.sessionFinalized(owner);
   RelayBridge.fromCarPlay(owner,new byte[]{1},1);check(owner.requests==1,"finalized session must not revive");
  }else if(args[0].equals("finalize-wireless-owner")){
   Object binder = new Object(); long[] tk = new long[1];
   check(RelayBridge.prepareListenerConnected(binder, 4, "02:00:00:00:57:95", tk) == 1, "bt maps to 1");
   RelayBridge.finishListenerConnected(binder, 1, tk[0], true);
   check(RelayBridge.isConnectedOwner(binder), "connected owner tracked");
   RelayBridge.sessionCreated(owner); RelayBridge.sessionStarted(owner, 1);
   check(RelayBridge.finalizeWirelessSession(owner) == binder, "wireless finalize returns remapped DiPO owner for disconnect cleanup");
   check(!RelayBridge.isConnectedOwner(binder) && RelayBridge.finalizeWirelessSession(owner) == null, "cleanup owner returned once");
  }else if(args[0].equals("finalize-observation")){
   RelayBridge.sessionCreated(owner); RelayBridge.sessionStarted(owner,1);owner.failNotification=true;
   RelayBridge.sessionFinalized(owner);
   String lines=android.util.Log.lines.toString();
   check(lines.contains("event=session-finalized generation=1 time=1 disconnect-delivery=failed"),"finalize logs generation/time and failed enqueue");
   check(lines.contains("D1|1|1|40|1|0|0|0|0|0"),"numeric finalize failure event uses validated schema");
  }else if(args[0].startsWith("stock-restart-")){
   RelayBridge.sessionCreated(owner); RelayBridge.sessionStarted(owner,1);
   try {
    Class<?> stock=Class.forName("com.daudio.app.dipo.service.DipoService");
    stock.getField("owner").set(null,owner);
    stock.getField("mode").set(null,args[0].substring("stock-restart-".length()));
    int result=RelayBridge.requestCarPlayRestartAndWait(250L);
    int expected=args[0].endsWith("apply")?RelayBridge.RESTART_APPLIED:
        args[0].endsWith("reject")?RelayBridge.RESTART_REJECTED:
        args[0].endsWith("unavailable")?RelayBridge.RESTART_UNAVAILABLE:RelayBridge.RESTART_REQUESTED;
    check(result==expected,"stock result must distinguish observed application, pending, rejection and unavailable: "+result);
    boolean pending=args[0].endsWith("pending"); // "created": a replacement is already in progress, so no fallback
    check(owner.disconnects==(pending?1:0),"H(true) without a replacement session falls back to exactly one disconnect; apply/reject/unavailable never disconnect: "+owner.disconnects);
    check(((Integer)stock.getField("calls").get(null)).intValue()==(args[0].endsWith("unavailable")?0:1),"exactly one H(true) request");
   }catch(Exception e){throw new AssertionError(e);}
  }else if(args[0].equals("restart-carplay")){
   check(!RelayBridge.requestCarPlayRestart() && owner.disconnects == 0, "idle restart does nothing");
   RelayBridge.sessionCreated(owner); RelayBridge.sessionStarted(owner, 1);
   check(RelayBridge.requestCarPlayRestartAndWait(0)==RelayBridge.RESTART_REQUESTED && owner.disconnects == 1, "missing stock method invokes disconnect exactly once, never claims applied");
  }
  System.out.println("PASS actual DiPO relay "+args[0]);
 }
}'''

with tempfile.TemporaryDirectory(prefix='gen5w-dipo-runtime-') as folder:
    work = Path(folder)
    sources = []
    for name, text in {**STUBS, 'DipoRelayRuntimeTest.java': HARNESS}.items():
        path = work/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        sources.append(str(path))
    sources += [str(ROOT/'tools/v039-relay/dipo-src/kr/gen5w/dipo/RelayBridge.java'),
                str(ROOT/'shared/src/kr/gen5w/diag/SafeDiagnostic.java')]
    subprocess.run(['javac', '-encoding', 'UTF-8', '-Xlint:-options', '--release', '8', '-d', str(work), *sources], check=True)
    failed = []
    for case in ('consumed','reconnect','register-exception','register-false','early','late-bind','connect-in-init','overflow','byte-overflow','read-false','read-binder-failure','replace-during-flush','reentrant-order','finalize-during-flush','rejected-listener','old-listener','early-outbound','wired-inbound','wired','usb-early','stale-owner','stale-start','finalized','finalize-wireless-owner','finalize-observation','restart-carplay','listener-bt','listener-usb','listener-cp5','cp5-early-ready','cp5-finalized-stale-ready','ignore-disconnect','ignore-during-handover','wired-disconnect','drop-notify','wireless-start','bluetooth-disable','wireless-start-usb'):
        result = subprocess.run(['java','-cp',str(work),'DipoRelayRuntimeTest',case], timeout=10)
        if result.returncode:
            failed.append(case)
    if failed:
        raise SystemExit('FAIL production cases: '+', '.join(failed))

    # Add stock API only after testing the missing-class fallback above.
    stock = work/'com/daudio/app/dipo/service/DipoService.java'
    stock.parent.mkdir(parents=True, exist_ok=True)
    stock.write_bytes(b'''package com.daudio.app.dipo.service;
public class DipoService {
 public static com.daudio.app.dipo.telechips.CarPlayService owner;
 public static String mode;public static int calls;
 public static DipoService bC(){return "unavailable".equals(mode)?null:new DipoService();}
 public void H(boolean forced){if(!forced)throw new AssertionError("must force configuration");calls++;
  if("reject".equals(mode))throw new IllegalStateException("stock failed");
  if("apply".equals(mode)){
   kr.gen5w.dipo.RelayBridge.sessionFinalized(owner);
   kr.gen5w.dipo.RelayBridge.sessionCreated(owner);
   new Thread(new Runnable(){public void run(){kr.gen5w.dipo.RelayBridge.sessionStarted(owner,1);}}).start();
  }else if("created".equals(mode)){kr.gen5w.dipo.RelayBridge.sessionCreated(owner);}
 }
}''')
    subprocess.run(['javac','--release','8','-cp',str(work),'-d',str(work),str(stock)],check=True)
    for case in ('apply','pending','created','reject','unavailable'):
        subprocess.run(['java','-cp',str(work),'DipoRelayRuntimeTest','stock-restart-'+case],check=True,timeout=10)

    stock.write_bytes(b'package com.daudio.app.dipo.service; public class DipoService { public static DipoService bC(){return new DipoService();} }')
    subprocess.run(['javac','--release','8','-cp',str(work),'-d',str(work),str(stock)],check=True)
    subprocess.run(['java','-cp',str(work),'DipoRelayRuntimeTest','restart-carplay'],check=True,timeout=10)
    print('PASS missing H(boolean) falls back once')
