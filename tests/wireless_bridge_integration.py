"""Run the complete production WirelessBridge with Android/OEM boundary fakes."""
from pathlib import Path
import subprocess
import repo_tmp as tempfile

root = Path(__file__).resolve().parents[1]
stubs = {
'android/content/Context.java': 'package android.content; public abstract class Context { public static final String USB_SERVICE="usb"; public abstract Object getSystemService(String n); public java.util.Map<String,String> receiverPermissions=new java.util.HashMap<String,String>(); public Object registerReceiver(BroadcastReceiver r,IntentFilter f,String p,android.os.Handler h){if(f!=null&&f.action!=null)receiverPermissions.put(f.action,p==null?"":p);return null;} public void unregisterReceiver(BroadcastReceiver r){} public void sendBroadcast(Intent i){} public java.io.File getFilesDir(){return null;} }',
'android/content/BroadcastReceiver.java': 'package android.content; public abstract class BroadcastReceiver { public abstract void onReceive(Context c,Intent i); }',
'android/content/IntentFilter.java': 'package android.content; public class IntentFilter { public String action; public IntentFilter(String a){action=a;} public void addAction(String a){} }',
'android/content/Intent.java': 'package android.content; public class Intent { public static final String ACTION_SHUTDOWN="shutdown"; public String action,pkg; public java.util.Map<String,String> extras=new java.util.HashMap<String,String>(); public Intent(String a){action=a;} public String getAction(){return action;} public Intent setPackage(String p){pkg=p;return this;} public Intent putExtra(String k,String v){extras.put(k,v);return this;} public java.util.Map<String,Object> objects=new java.util.HashMap<String,Object>(); public Intent putExtra(String k,Object v){objects.put(k,v);return this;} public int getIntExtra(String k,int d){Object v=objects.get(k);return v instanceof Integer?((Integer)v).intValue():d;} public long getLongExtra(String k,long d){return d;} public Object getParcelableExtra(String k){return objects.get(k);} }',
'android/app/Service.java': 'package android.app; public abstract class Service extends android.content.Context { public void stopSelf(){} }',
'android/os/Handler.java': 'package android.os; public class Handler { public Handler(Looper l){} public void post(Runnable r){r.run();} public void postDelayed(Runnable r,long t){} public void removeCallbacks(Runnable r){} }',
'android/os/Looper.java': 'package android.os; public class Looper { public static Looper getMainLooper(){return new Looper();} }',
'android/os/SystemClock.java': 'package android.os; public class SystemClock { public static long nowMs = 10L; public static long elapsedRealtime(){return nowMs;} }',
'android/os/SystemProperties.java': 'package android.os; public class SystemProperties { public static String value=""; public static String get(String k){return "wifi.interface".equals(k)?value:"";} }',
'android/util/Log.java': 'package android.util; public class Log { public static java.util.List<String> lines=new java.util.concurrent.CopyOnWriteArrayList<String>(); public static int i(String t,String m){lines.add(m);return 0;} }',
'android/bluetooth/BluetoothAdapter.java': 'package android.bluetooth; public class BluetoothAdapter { public static final String ACTION_STATE_CHANGED="state",EXTRA_STATE="extra"; public static final int STATE_ON=12; public static BluetoothAdapter instance; public static BluetoothAdapter getDefaultAdapter(){return instance;} public boolean isEnabled(){return true;} public java.util.Set<BluetoothDevice> bonded=new java.util.HashSet<BluetoothDevice>(); public java.util.Set<BluetoothDevice> getBondedDevices(){return bonded;} }',
'android/bluetooth/BluetoothDevice.java': 'package android.bluetooth; public class BluetoothDevice { public static final String ACTION_ACL_CONNECTED="connected",ACTION_ACL_DISCONNECTED="disconnected",ACTION_UUID="uuid",EXTRA_DEVICE="device"; public static final int BOND_BONDED=12; public String addr="phone"; public boolean connected=true,sdpResult=true; public int sdpCalls,vendor,bond=12; public BluetoothDevice(){} public BluetoothDevice(String a){addr=a;} public int getBondState(){return bond;} public String getAddress(){return addr;} public boolean isConnected(){return connected;} public int getVendor(){return vendor;} public boolean fetchUuidsWithSdp(){sdpCalls++;return sdpResult;} public android.os.ParcelUuid[] getUuids(){return new android.os.ParcelUuid[0];} }',
'android/os/ParcelUuid.java': 'package android.os; public class ParcelUuid { public java.util.UUID getUuid(){return null;} }',
'android/hardware/usb/UsbDevice.java': 'package android.hardware.usb; public class UsbDevice { public int getVendorId(){return 0;} }',
'android/hardware/usb/UsbManager.java': 'package android.hardware.usb; public class UsbManager { public static final String ACTION_USB_DEVICE_ATTACHED="attach",ACTION_USB_DEVICE_DETACHED="detach",EXTRA_DEVICE="usb"; public java.util.Map<String,UsbDevice> getDeviceList(){return new java.util.HashMap<String,UsbDevice>();} }',
'com/hkmc/userprofile/UserProfileManager.java': 'package com.hkmc.userprofile; public class UserProfileManager { public UserProfileManager(android.content.Context c){} public int getUserType(){return 0;} }',
'kr/gen5w/wireless/DriveLog.java': 'package kr.gen5w.wireless; public class DriveLog { public static java.util.List<String> codes=new java.util.concurrent.CopyOnWriteArrayList<String>(); public static void bridge(int a,long b,long c,long d,long e,long f,long g){codes.add(b+":"+c);} }',
'kr/gen5w/wireless/V039RelayCoordinator.java': '''package kr.gen5w.wireless;
import android.content.Context; import android.os.Handler;
final class V039RelayCoordinator {
 interface Events { void relayEvent(String name,String result); }
 int starts,cancels,losses; long owner; boolean running;
 V039RelayCoordinator(Context c,Handler h,Events e){} void open(){} void tick(){}
 void start(String a){starts++;owner++;} long generation(){return owner;} void candidateLost(){owner++;losses++;running=false;} void handoverRequested(){}
 boolean owned; int kept,retries; boolean hasCandidate(String a){return owned;} boolean carPlayOwned(){return owned;} void bluetoothLost(){if(owned){kept++;return;}candidateLost();} void retryNow(){retries++;}
 void handoverConnected(){} void handoverDisconnected(){} void handoverDisconnected(long t){} void apObservedReady(){}
 void credentialsReady(){} void projectionActive(){} void close(){}
 void cancel(BtRelaySession.CancelReason r){cancels++;} boolean active(){return running;} static boolean adapterOk=true; boolean adapterReady(){return adapterOk;}
}''',
}
harness = r"""
package kr.gen5w.wireless;
import java.util.concurrent.*;
public class WirelessBridgeIntegrationTest {
    static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
    static class TrackedPool extends ThreadPoolExecutor {
        final java.util.concurrent.atomic.AtomicInteger pending=new java.util.concurrent.atomic.AtomicInteger();
        TrackedPool(){super(2,2,0L,TimeUnit.MILLISECONDS,new LinkedBlockingQueue<Runnable>());}
        public void execute(final Runnable task){
            pending.incrementAndGet();
            try {super.execute(new Runnable(){public void run(){try{task.run();}finally{pending.decrementAndGet();}}});}
            catch(RuntimeException e){pending.decrementAndGet();throw e;}
        }
    }
    public static class Info {
        public String getWLDevBtAddr(){return "phone";} public int getWLDType(){return 1;}
        public boolean getWLDOnOff(){return true;} public boolean getWLDAutoConnection(){return true;}
    }
    public static class Manager {
        TestContext context; int reads,calls; boolean saved,foreignAfterInspection,unavailableAfterInspection,idle,off,noAuto; volatile boolean crash;
        volatile CountDownLatch inspectionEntered,inspectionRelease;
        public Object getWLDeviceInfo(String a,String b,int c){return saved?new Info():null;}
        public String getCPConnectedBTAddress(){outside(); return idle||reads==0?"":"other";}
        public String getAAConnectedBTAddress(){outside(); return "";}
        public int getWirelessConnectState(){outside(); if(inspectionEntered!=null){inspectionEntered.countDown();try{inspectionRelease.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}} reads++; if(reads>1&&unavailableAfterInspection)throw new SecurityException(); return reads>1&&foreignAfterInspection?3:0;}
        public void requestConnectSPP(String a){outside(); calls++;}
        void outside(){check(!Thread.holdsLock(context.bridge.session),"OEM read/call must be outside session monitor");}
    }
    public static class AudioManagerStub {
        public boolean musicActive;
        public boolean isMusicActive(){return musicActive;}
    }
    public static class TestContext extends android.content.Context implements PhoneProjectionAccess.ProfileProvider {
        Manager manager=new Manager(); WirelessBridge bridge; AudioManagerStub audio=new AudioManagerStub(); int broadcasts; boolean foreignAfterBroadcast,unavailableAfterBroadcast;
        static final StockApGuard.Flush NO_FLUSH=new StockApGuard.Flush(){public void run(){}};
        static StockApGuard tempGuard(StockApGuard.Flush flush){try{return new StockApGuard(java.nio.file.Files.createTempDirectory("gen5w-apguard").toFile(),"0123abcd-0000-1111-2222-333344445555",flush);}catch(java.io.IOException e){throw new AssertionError(e);}}
        TestContext(){this(tempGuard(NO_FLUSH));}
        TestContext(StockApGuard guard){manager.context=this; bridge=new WirelessBridge(this,guard);
            try { java.lang.reflect.Field f=WirelessBridge.class.getDeclaredField("oemCalls");f.setAccessible(true);
                bridge.oemCalls.shutdownNow();f.set(bridge,new TrackedPool());
            }catch(Exception e){throw new AssertionError(e);}
        }
        volatile Thread mainThread; final java.util.concurrent.atomic.AtomicInteger wifiOnMain=new java.util.concurrent.atomic.AtomicInteger(),wifiReads=new java.util.concurrent.atomic.AtomicInteger();
        public Object getSystemService(String n){if("wifi".equals(n)){wifiReads.incrementAndGet();if(Thread.currentThread()==mainThread)wifiOnMain.incrementAndGet();}if("audio".equals(n))return audio;if(bridge!=null)check(!Thread.holdsLock(bridge.session),"service lookup outside monitor");if(manager.crash&&"phoneprojection".equals(n))throw new ExceptionInInitializerError();return "phoneprojection".equals(n)?manager:null;}
        public PhoneProjectionAccess.Profile find(String a){return manager.saved?new PhoneProjectionAccess.Profile(a,1,!manager.off,!manager.noAuto):null;}
        public void sendBroadcast(android.content.Intent i){check(!Thread.holdsLock(bridge.session),"broadcast outside monitor"); broadcasts++; check("com.daudio.app.phoneprojection".equals(i.pkg)&&i.extras.size()==1,"scoped single extra action"); if(foreignAfterBroadcast)manager.foreignAfterInspection=true; if(unavailableAfterBroadcast)manager.unavailableAfterInspection=true;}
    }
    static void settle(TestContext c) throws Exception {
        // Active-count/queue snapshots can both be zero before a newly started
        // worker locks its first task. Count submissions before execute returns,
        // including nested continuations, and wait for their completion instead.
        TrackedPool pool=(TrackedPool)c.bridge.oemCalls;
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
        while(pool.pending.get()!=0) {
            if(System.nanoTime()>deadline)throw new AssertionError("OEM tasks did not settle");
            Thread.sleep(10);
        }
    }
    static void ownershipChangesCancelAtEveryBoundary() throws Exception {
        for(int boundary=0;boundary<3;boundary++)for(boolean unavailable:new boolean[]{false,true}){
            TestContext c=new TestContext();
            try {
                c.manager.saved=boundary==2;
                if(boundary==1){c.foreignAfterBroadcast=!unavailable;c.unavailableAfterBroadcast=unavailable;}
                else {c.manager.foreignAfterInspection=!unavailable;c.manager.unavailableAfterInspection=unavailable;}
                c.bridge.session.candidate("phone",10);c.bridge.session.tick(10);settle(c);
                check(c.broadcasts==(boundary==1?1:0),"fresh OEM ownership prevents broadcast at boundary "+boundary+" unavailable="+unavailable);
                check(c.manager.calls==0,"fresh OEM owner prevents Binder continuation");
                check(c.bridge.session.phase()==StockProjectionSession.Phase.CANCELLED,"foreign/unavailable ownership cancels generation");
            } finally {c.bridge.shutdown();}
        }
    }
    static void idleOwnershipAllowsOneBootstrap() throws Exception {
        TestContext c=new TestContext();try{c.bridge.session.candidate("phone",10);c.bridge.session.tick(10);settle(c);
            check(c.broadcasts==1&&c.manager.calls==1&&c.bridge.session.phase()==StockProjectionSession.Phase.WAITING_PROFILE,"idle OEM permits one complete bootstrap");
        }finally{c.bridge.shutdown();}
    }
    /** M6: a failed durable AP-attempt record must stop the OEM action itself. */
    static void apGuardFailureSendsNoOemAction() throws Exception {
        TestContext c=new TestContext(TestContext.tempGuard(new StockApGuard.Flush(){public void run() throws java.io.IOException{throw new java.io.IOException("injected sync failure");}}));
        try{c.bridge.session.candidate("phone",10);c.bridge.session.tick(10);settle(c);
            check(c.broadcasts==0,"guard record failure sends no OEM broadcast");
            check(c.manager.calls==0,"guard record failure performs no Binder continuation");
            check(c.bridge.session.phase()==StockProjectionSession.Phase.CANCELLED,"guard record failure cancels the request");
        }finally{c.bridge.shutdown();}
        TestContext none=new TestContext(new StockApGuard(null,null,TestContext.NO_FLUSH));
        try{none.bridge.session.candidate("phone",10);none.bridge.session.tick(10);settle(none);
            check(none.broadcasts==0&&none.bridge.session.phase()==StockProjectionSession.Phase.CANCELLED,"unavailable guard directory/boot id sends nothing");
        }finally{none.bridge.shutdown();}
    }
    static void interfaceDiagnosticsNeverBlockBootstrap() throws Exception {
        String present=java.net.NetworkInterface.getNetworkInterfaces().nextElement().getName();
        String[] names={"", "absent-gen5w-test", present};
        String[] tokens={"wifi-interface-unknown","wifi-interface-missing","wifi-interface-present"};
        for(int i=0;i<names.length;i++){
            android.os.SystemProperties.value=names[i]; android.util.Log.lines.clear();DriveLog.codes.clear();
            idleOwnershipAllowsOneBootstrap();
            check(android.util.Log.lines.contains("path=stock event=wifi result="+tokens[i]),"stable interface diagnostic "+i);
            check(DriveLog.codes.contains("10:"+(43+i)),"stable numeric interface diagnostic "+i);
            for(String line:android.util.Log.lines)if(names[i].length()>0)check(!line.contains(names[i]),"interface name never logged");
        }
    }
    static void relayReadySkipsStockBootstrap() throws Exception {
        boolean[][] cases={{true,true},{false,true},{true,false}}; // adapter ready, Apple CarPlay
        for(boolean[] k:cases){
            V039RelayCoordinator.adapterOk=k[0]; android.util.Log.lines.clear();
            TestContext c=new TestContext();try{c.bridge.enableRelay();c.bridge.appleCarPlay.put("phone",Boolean.valueOf(k[1]));
                c.bridge.session.candidate("phone",10);c.bridge.session.tick(10);settle(c);
                boolean skip=k[0]&&k[1];
                check(skip==android.util.Log.lines.contains("path=stock event=bootstrap result=skipped-relay-ready"),"skip only with ready adapter and Apple phone");
                check(skip?c.manager.calls==0&&c.broadcasts==0&&c.bridge.session.phase()==StockProjectionSession.Phase.FAILED
                          :c.manager.calls==1,"skipped bootstrap sends nothing; otherwise stock path runs");
            }finally{c.bridge.shutdown();V039RelayCoordinator.adapterOk=true;}
        }
    }
    // Car 2026-11-12 09:14:18: the stock bootstrap went out 0.17 s before the SDP answer
    // named the phone a CarPlay iPhone, so the relay waited the full 60 s stock timeout.
    static void lateAppleSdpEndsStockProfileWait() throws Exception {
        for(int k=0;k<3;k++){ // 0: Apple CarPlay, 1: SDP says not CarPlay, 2: adapter not ready
            V039RelayCoordinator.adapterOk=k!=2; android.util.Log.lines.clear();
            TestContext c=new TestContext();try{
                c.manager.idle=true; c.bridge.enableRelay();
                c.bridge.session.candidate("phone",10);c.bridge.session.tick(10);settle(c);
                check(c.manager.calls==1&&c.bridge.session.phase()==StockProjectionSession.Phase.WAITING_PROFILE,"stock bootstrap went out first");
                c.bridge.appleCarPlay.put("phone",Boolean.valueOf(k!=1));
                java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay");maintain.setAccessible(true);
                maintain.invoke(c.bridge);settle(c);
                boolean take=k==0;
                check(take==(c.bridge.session.phase()==StockProjectionSession.Phase.FAILED),"profile wait ends at once only for a ready relay and a CarPlay iPhone");
                check(take==android.util.Log.lines.contains("path=stock event=result result=profile-relay-takeover"),"takeover is logged");
                check(!take||c.bridge.relay.starts==1,"relay starts without the 60 s timeout");
                check(take||c.bridge.relay.starts==0,"otherwise the stock wait continues");
            }finally{c.bridge.shutdown();V039RelayCoordinator.adapterOk=true;}
        }
    }
    static void missingProfileFallsBackOnlyForFreshAppleSdp() throws Exception {
        TestContext apple=new TestContext(); try {
            apple.manager.idle=true; apple.bridge.enableRelay(); apple.bridge.appleCarPlay.put("phone",Boolean.TRUE);
            apple.bridge.session.candidate("phone",0); apple.bridge.session.tick(0);
            long generation=apple.bridge.session.generation();
            apple.bridge.session.inspected(generation,new StockProjectionSession.Observation(
                StockProjectionSession.Result.INVOKED,true,0,StockProjectionSession.ProfileState.DISABLED,
                false,false,false,StockProjectionSession.WifiCredentialState.UNKNOWN,11),1);
            java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay"); maintain.setAccessible(true); maintain.invoke(apple.bridge);
            settle(apple); check(apple.bridge.relay.starts==1,"fresh Apple SDP admits missing-profile CarPlay fallback");
        } finally { apple.bridge.shutdown(); }
        TestContext android=new TestContext(); try {
            android.bridge.enableRelay(); android.bridge.appleCarPlay.put("phone",Boolean.FALSE);
            android.bridge.session.candidate("phone",0); android.bridge.session.tick(0);
            long generation=android.bridge.session.generation();
            android.bridge.session.inspected(generation,new StockProjectionSession.Observation(
                StockProjectionSession.Result.INVOKED,true,0,StockProjectionSession.ProfileState.DISABLED,
                false,false,false,StockProjectionSession.WifiCredentialState.UNKNOWN,11),1);
            java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay"); maintain.setAccessible(true); maintain.invoke(android.bridge);
            check(android.bridge.relay.starts==0,"non-Apple device remains on stock Android Auto path");
        } finally { android.bridge.shutdown(); }
    }
    static void relayAdmissionRechecksOwnershipAndGeneration()throws Exception {
      for(int boundary=0;boundary<6;boundary++){
       TestContext c=new TestContext();try{
        c.manager.idle=boundary!=0;c.manager.foreignAfterInspection=boundary==0;c.manager.reads=2;c.bridge.enableRelay();c.bridge.appleCarPlay.put("phone",Boolean.TRUE);
        c.bridge.session.candidate("phone",0);
        c.manager.inspectionEntered=new CountDownLatch(1);c.manager.inspectionRelease=new CountDownLatch(1);
        c.bridge.session.tick(0);
        check(c.manager.inspectionEntered.await(2,TimeUnit.SECONDS),"stock inspection started");
        c.bridge.session.inspected(c.bridge.session.generation(),new StockProjectionSession.Observation(StockProjectionSession.Result.INVOKED,true,0,StockProjectionSession.ProfileState.DISABLED,false,false,false,StockProjectionSession.WifiCredentialState.UNKNOWN,11),1);
        java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay");maintain.setAccessible(true);maintain.invoke(c.bridge);
        check(c.bridge.relay.starts==0,"no relay before fresh ownership inspection");
        check(c.manager.inspectionEntered.await(2,TimeUnit.SECONDS),"fresh admission inspection started");
        if(boundary==1)c.bridge.cable=true;
        if(boundary==2){c.bridge.session.lost("phone",2);c.bridge.session.candidate("phone",3);}
        if(boundary==3)c.bridge.shuttingDown=true;
        if(boundary==4){c.bridge.relay.owner++;c.manager.idle=false;c.manager.foreignAfterInspection=true;}
        if(boundary==5)c.manager.unavailableAfterInspection=true;
        c.manager.inspectionRelease.countDown();settle(c);
        check(c.bridge.relay.starts==0,"foreign/wired/stale/shutdown result cannot start relay "+boundary);
        if(boundary==4)check(c.bridge.relay.cancels==0,"stale inspection cannot cancel newer relay generation");
       }finally{if(c.manager.inspectionRelease!=null)c.manager.inspectionRelease.countDown();c.bridge.shuttingDown=false;c.bridge.shutdown();}
      }
    }
    static void scanCandidateGenerationResetsRelay()throws Exception{
      TestContext c=new TestContext();try{
       c.bridge.enableRelay();c.bridge.session.candidate("phone",0);
       java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay");maintain.setAccessible(true);maintain.invoke(c.bridge);
       int losses=c.bridge.relay.losses;c.bridge.relay.running=true;
       c.bridge.session.lost("phone",1);c.bridge.session.candidate("other",2);maintain.invoke(c.bridge);
       check(c.bridge.relay.losses==losses+1&&!c.bridge.relay.running,"scan replacement cancels old relay even without ACL disconnect broadcast");
      }finally{c.bridge.shutdown();}
    }

    static void runningWifiSessionSurvivesBluetoothSideLoss()throws Exception{
      TestContext c=new TestContext();try{
       c.bridge.enableRelay();c.bridge.session.candidate("phone",0);
       java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay");maintain.setAccessible(true);maintain.invoke(c.bridge);
       c.bridge.relay.running=true;c.bridge.relay.owned=true;int losses=c.bridge.relay.losses;
       c.bridge.session.lost("phone",1);c.bridge.session.candidate("other",2);maintain.invoke(c.bridge);
       check(c.bridge.relay.losses==losses&&c.bridge.relay.running&&c.bridge.relay.kept==1,"stock candidate change keeps a Wi-Fi session DiPO runs");
       c.bridge.relay.owned=false;c.bridge.session.lost("other",3);c.bridge.session.candidate("phone",4);maintain.invoke(c.bridge);
       check(c.bridge.relay.losses==losses+1&&!c.bridge.relay.running,"without a Wi-Fi session the old rule applies");
      }finally{c.bridge.shutdown();}
    }

    // Car 2026-11-12: getWifiApConfiguration blocked the main thread 1.5-2 s while the Wi-Fi
    // driver loaded, which held back the relay's iAP2 step and the phone's data.
    static void wifiSettingsAreNeverReadOnTheMainThread()throws Exception{
      TestContext c=new TestContext();try{
       c.mainThread=Thread.currentThread();
       c.bridge.enableRelay();c.bridge.session.candidate("phone",0);
       java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay");maintain.setAccessible(true);
       maintain.invoke(c.bridge);settle(c);c.bridge.relay.running=true;c.wifiReads.set(0);c.wifiOnMain.set(0);
       for(int i=0;i<3;i++){maintain.invoke(c.bridge);settle(c);}
       check(c.wifiReads.get()>0,"credentials are still read while the relay runs");
       check(c.wifiOnMain.get()==0,"getWifiApConfiguration never runs on the main thread");
      }finally{c.bridge.shutdown();}
    }

    static void stockOffSettingBlocksAndStopsRelay()throws Exception{
      java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay");maintain.setAccessible(true);
      for(int mode=0;mode<2;mode++){
       TestContext c=new TestContext();try{
        c.manager.saved=true;c.manager.idle=true;if(mode==0)c.manager.off=true;else c.manager.noAuto=true;
        c.bridge.enableRelay();c.bridge.appleCarPlay.put("phone",Boolean.TRUE);
        c.bridge.session.candidate("phone",0);c.bridge.session.tick(0);settle(c);
        check(c.bridge.session.phase()==StockProjectionSession.Phase.BLOCKED,"stock path stops for the user setting "+mode);
        maintain.invoke(c.bridge);settle(c);maintain.invoke(c.bridge);settle(c);
        check(c.bridge.relay.starts==0,"stock off setting blocks relay start "+mode);
        c.bridge.relay.running=true;int cancels=c.bridge.relay.cancels;
        maintain.invoke(c.bridge);settle(c);
        check(c.bridge.relay.cancels==cancels+1,"stock off setting stops a running relay "+mode);
       }finally{c.bridge.shutdown();}
      }
      TestContext on=new TestContext();try{
        on.manager.saved=true;on.manager.idle=true;on.bridge.enableRelay();on.bridge.appleCarPlay.put("phone",Boolean.TRUE);
        on.bridge.session.candidate("phone",0);on.bridge.session.tick(0);
        on.bridge.session.inspected(on.bridge.session.generation(),new StockProjectionSession.Observation(StockProjectionSession.Result.INVOKED,true,1,StockProjectionSession.ProfileState.UNKNOWN,false,false,true,StockProjectionSession.WifiCredentialState.UNKNOWN,11),1);
        settle(on);maintain.invoke(on.bridge);settle(on);
        check(on.bridge.relay.starts==1,"enabled profile still admits the relay");
      }finally{on.bridge.shutdown();}
    }
    static void failedRelayReadNeverSticks()throws Exception{
      java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay");maintain.setAccessible(true);
      TestContext c=new TestContext();try{
        c.manager.saved=true;c.manager.idle=true;c.bridge.enableRelay();c.bridge.appleCarPlay.put("phone",Boolean.TRUE);
        c.bridge.session.candidate("phone",0);c.bridge.session.tick(0);
        c.bridge.session.inspected(c.bridge.session.generation(),new StockProjectionSession.Observation(StockProjectionSession.Result.INVOKED,true,1,StockProjectionSession.ProfileState.UNKNOWN,false,false,true,StockProjectionSession.WifiCredentialState.UNKNOWN,11),1);
        settle(c);c.manager.crash=true;maintain.invoke(c.bridge);settle(c);
        check(!c.bridge.relayInspectPending&&c.bridge.relay.starts==0,"an Error in the relay read clears the pending flag");
        c.manager.crash=false;maintain.invoke(c.bridge);settle(c);
        check(c.bridge.relay.starts==1,"the next read can start the relay");
      }finally{c.bridge.shutdown();}
    }
    static void relayNoticesRequireSystemSender()throws Exception{
      TestContext c=new TestContext();try{
        c.bridge.run();
        for(String a:new String[]{"REQUESTED","CONNECTED","DISCONNECTED"})
          check("android.permission.SHUTDOWN".equals(c.receiverPermissions.get("kr.gen5w.wireless.RELAY_HANDOVER_"+a)),"relay notice "+a+" requires a system sender");
        check("".equals(c.receiverPermissions.get("connected")),"system Bluetooth broadcasts stay open");
      }finally{c.bridge.shutdown();}
    }
    static void scanDisconnectResetsSdpAndMusicDefersSdp()throws Exception{
      android.bluetooth.BluetoothAdapter btAdapter = new android.bluetooth.BluetoothAdapter();
      android.bluetooth.BluetoothAdapter.instance = btAdapter;
      TestContext c=new TestContext();try{
        android.bluetooth.BluetoothDevice dev = new android.bluetooth.BluetoothDevice("AA:BB:CC:DD:EE:FF");
        btAdapter.bonded.add(dev);
        c.audio.musicActive = true;
        c.bridge.scan();
        check(dev.sdpCalls==0, "active music playback must suppress fetchUuidsWithSdp");
        check(c.bridge.sdpDeferredMusic.contains("AA:BB:CC:DD:EE:FF"), "deferred music device tracked");
        c.audio.musicActive = false;
        c.bridge.scan();
        check(dev.sdpCalls==1, "SDP resumes once music playback stops");
        c.bridge.sdpRefresh.complete("AA:BB:CC:DD:EE:FF", 200L, false);
        c.bridge.sdpRefresh.begin("AA:BB:CC:DD:EE:FF", 20000L);
        c.bridge.sdpRefresh.complete("AA:BB:CC:DD:EE:FF", 20100L, false);
        check(!c.bridge.sdpRefresh.canBegin("AA:BB:CC:DD:EE:FF", 40000L), "quota exhausted before scan disconnect");
        dev.connected = false;
        // Simulate 1s false-confirmation window: two scans >1s apart clear linked device via scan().
        android.os.SystemClock.nowMs = 45000L;
        c.bridge.scan();
        android.os.SystemClock.nowMs = 46100L;
        c.bridge.scan();
        check(c.bridge.sdpRefresh.canBegin("AA:BB:CC:DD:EE:FF", 50000L), "scan-detected disconnect with live adapter resets SDP retry quota");
      }finally{android.os.SystemClock.nowMs=10L;android.bluetooth.BluetoothAdapter.instance=null;c.bridge.shutdown();}
    }
    static void acceptFreshSdpPreservesAppleVendorAndRetriesEmptyUnknown()throws Exception{
      TestContext c=new TestContext();try{
        android.bluetooth.BluetoothDevice apple=new android.bluetooth.BluetoothDevice("11:22:33:44:55:66");
        apple.vendor=76;
        c.bridge.linked.add("11:22:33:44:55:66");
        c.bridge.acceptFreshSdp(apple);
        check(Boolean.TRUE.equals(c.bridge.appleCarPlay.get("11:22:33:44:55:66")),"empty ACTION_UUID preserves Apple vendor 76");
        check(c.bridge.sdpRefresh.ready("11:22:33:44:55:66"),"Apple vendor SDP marked ready");
        android.bluetooth.BluetoothDevice unknown=new android.bluetooth.BluetoothDevice("77:88:99:AA:BB:CC");
        unknown.vendor=0;
        c.bridge.linked.add("77:88:99:AA:BB:CC");
        c.bridge.sdpRefresh.begin("77:88:99:AA:BB:CC", 10L);
        c.bridge.acceptFreshSdp(unknown);
        check(!c.bridge.sdpRefresh.ready("77:88:99:AA:BB:CC"),"empty ACTION_UUID on non-Apple vendor stays retryable");
        check(!c.bridge.appleCarPlay.containsKey("77:88:99:AA:BB:CC"),"empty ACTION_UUID never caches negative CarPlay capability");
      }finally{c.bridge.shutdown();}
    }
    static void adapterReadyTriggersMaintainRelayImmediately()throws Exception{
      TestContext c=new TestContext();try{
        c.manager.saved=true;c.manager.idle=true;c.bridge.enableRelay();
        c.bridge.appleCarPlay.put("phone",Boolean.TRUE);
        c.bridge.session.candidate("phone",0);
        c.bridge.session.tick(0);
        c.bridge.session.inspected(c.bridge.session.generation(),new StockProjectionSession.Observation(
            StockProjectionSession.Result.INVOKED,true,1,StockProjectionSession.ProfileState.DISABLED,
            false,false,false,StockProjectionSession.WifiCredentialState.UNKNOWN,11),1);
        settle(c);
        check(c.bridge.relay.starts==0,"unrelated setup has not started relay before maintainRelay or adapter-ready");
        c.bridge.relayEvent("step","spp-connected");settle(c);
        check(c.bridge.relay.starts==0,"unrelated relay events do not trigger maintainRelay");
        c.bridge.relayEvent("relay","adapter-ready");settle(c);
        check(c.bridge.relay.starts==1,"adapter-ready immediately runs maintainRelay without waiting for 1s tick");
      }finally{c.bridge.shutdown();}
    }
    static void retryCarPlayBroadcastClearsBackoffAndStarts()throws Exception{
      TestContext c=new TestContext();try{
        c.bridge.run();
        check("android.permission.SHUTDOWN".equals(c.receiverPermissions.get("kr.gen5w.wireless.RETRY_CARPLAY")),"RETRY_CARPLAY requires SHUTDOWN permission");
        int before=c.bridge.relay.retries;
        c.bridge.events.onReceive(c,new android.content.Intent("kr.gen5w.wireless.RETRY_CARPLAY"));
        settle(c);
        check(c.bridge.relay.retries==before+1,"RETRY_CARPLAY triggers immediate retryNow");
      }finally{c.bridge.shutdown();}
    }
    static void unpairClearsCachesAndEndsOwnedWifi()throws Exception{
      TestContext c=new TestContext();try{
        android.bluetooth.BluetoothDevice d=new android.bluetooth.BluetoothDevice("phone");
        c.bridge.connected(d);c.bridge.appleCarPlay.put("phone",Boolean.TRUE);
        c.bridge.sdpRefresh.complete("phone",0,true);c.bridge.sdpDeferredMusic.add("phone");
        c.bridge.falseConnectionSince.put("PHONE",1L);
        c.bridge.relay.owned=true;c.bridge.relay.running=true;
        int losses=c.bridge.relay.losses;long generation=c.bridge.session.generation();
        d.bond=10;
        c.bridge.events.onReceive(c,new android.content.Intent("android.bluetooth.device.action.BOND_STATE_CHANGED")
            .putExtra("device",d).putExtra("android.bluetooth.device.extra.BOND_STATE",10));
        check(c.bridge.relay.losses==losses+1&&!c.bridge.relay.running,"unpair bypasses ACL Wi-Fi keep exception");
        check(c.bridge.session.candidate()==null&&!c.bridge.linked.contains("phone"),"candidate and link removed");
        check(!c.bridge.sdpRefresh.ready("phone")&&!c.bridge.appleCarPlay.containsKey("phone")
            &&!c.bridge.sdpDeferredMusic.contains("phone")&&!c.bridge.falseConnectionSince.containsKey("PHONE"),"all address caches discarded");
        c.bridge.acceptFreshSdp(d);check(!c.bridge.sdpRefresh.ready("phone"),"late SDP cannot revive deleted peer");
        d.bond=12;c.bridge.connected(d);
        check(c.bridge.session.candidate()==null,"late ACL with stale bond cache cannot undo unpair");
        c.bridge.events.onReceive(c,new android.content.Intent("android.bluetooth.device.action.BOND_STATE_CHANGED")
            .putExtra("device",d).putExtra("android.bluetooth.device.extra.BOND_STATE",12));
        check(c.bridge.session.generation()>generation,"re-pair creates a fresh candidate generation");
      }finally{c.bridge.shutdown();}
    }
    public static void main(String[] args)throws Exception{unpairClearsCachesAndEndsOwnedWifi();stockOffSettingBlocksAndStopsRelay();failedRelayReadNeverSticks();relayNoticesRequireSystemSender();ownershipChangesCancelAtEveryBoundary();idleOwnershipAllowsOneBootstrap();apGuardFailureSendsNoOemAction();interfaceDiagnosticsNeverBlockBootstrap();missingProfileFallsBackOnlyForFreshAppleSdp();relayReadySkipsStockBootstrap();relayAdmissionRechecksOwnershipAndGeneration();scanCandidateGenerationResetsRelay();runningWifiSessionSurvivesBluetoothSideLoss();wifiSettingsAreNeverReadOnTheMainThread();lateAppleSdpEndsStockProfileWait();scanDisconnectResetsSdpAndMusicDefersSdp();acceptFreshSdpPreservesAppleVendorAndRetriesEmptyUnknown();adapterReadyTriggersMaintainRelayImmediately();retryCarPlayBroadcastClearsBackoffAndStarts();System.out.println("PASS production WirelessBridge ownership integration");}
}
"""
with tempfile.TemporaryDirectory(prefix='gen5w-wireless-bridge-') as tmp:
    base=Path(tmp)
    for name, text in stubs.items():
        p=base/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8')
    test=base/'kr/gen5w/wireless/WirelessBridgeIntegrationTest.java';test.write_text(harness,encoding='utf-8')
    prod=root/'packages/wireless-bridge/src/kr/gen5w/wireless'
    sources=[str(p) for p in base.rglob('*.java')]+[str(prod/name) for name in ['WirelessBridge.java','StockProjectionSession.java','PhoneProjectionAccess.java','ProjectionWifiAccess.java','BluetoothCandidateScan.java','BtRelaySession.java','SdpRefresh.java','StockApGuard.java']]
    subprocess.run(['javac','--release','8','-d',tmp]+sources,check=True)
    subprocess.run(['java','-cp',tmp,'kr.gen5w.wireless.WirelessBridgeIntegrationTest'],check=True)
