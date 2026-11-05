"""Run the complete production WirelessBridge with Android/OEM boundary fakes."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
stubs = {
'android/content/Context.java': 'package android.content; public abstract class Context { public static final String USB_SERVICE="usb"; public abstract Object getSystemService(String n); public Object registerReceiver(BroadcastReceiver r,IntentFilter f,String p,android.os.Handler h){return null;} public void unregisterReceiver(BroadcastReceiver r){} public void sendBroadcast(Intent i){} }',
'android/content/BroadcastReceiver.java': 'package android.content; public abstract class BroadcastReceiver { public abstract void onReceive(Context c,Intent i); }',
'android/content/IntentFilter.java': 'package android.content; public class IntentFilter { public IntentFilter(String a){} public void addAction(String a){} }',
'android/content/Intent.java': 'package android.content; public class Intent { public static final String ACTION_SHUTDOWN="shutdown"; public String action,pkg; public java.util.Map<String,String> extras=new java.util.HashMap<String,String>(); public Intent(String a){action=a;} public String getAction(){return action;} public Intent setPackage(String p){pkg=p;return this;} public Intent putExtra(String k,String v){extras.put(k,v);return this;} public int getIntExtra(String k,int d){return d;} public Object getParcelableExtra(String k){return null;} }',
'android/app/Service.java': 'package android.app; public abstract class Service extends android.content.Context { public void stopSelf(){} }',
'android/os/Handler.java': 'package android.os; public class Handler { public Handler(Looper l){} public void post(Runnable r){r.run();} public void postDelayed(Runnable r,long t){} public void removeCallbacks(Runnable r){} }',
'android/os/Looper.java': 'package android.os; public class Looper { public static Looper getMainLooper(){return new Looper();} }',
'android/os/SystemClock.java': 'package android.os; public class SystemClock { public static long elapsedRealtime(){return 10;} }',
'android/os/SystemProperties.java': 'package android.os; public class SystemProperties { public static String value=""; public static String get(String k){return "wifi.interface".equals(k)?value:"";} }',
'android/util/Log.java': 'package android.util; public class Log { public static java.util.List<String> lines=new java.util.concurrent.CopyOnWriteArrayList<String>(); public static int i(String t,String m){lines.add(m);return 0;} }',
'android/bluetooth/BluetoothAdapter.java': 'package android.bluetooth; public class BluetoothAdapter { public static final String ACTION_STATE_CHANGED="state",EXTRA_STATE="extra"; public static final int STATE_ON=12; public static BluetoothAdapter getDefaultAdapter(){return null;} public boolean isEnabled(){return true;} public java.util.Set<BluetoothDevice> getBondedDevices(){return new java.util.HashSet<BluetoothDevice>();} }',
'android/bluetooth/BluetoothDevice.java': 'package android.bluetooth; public class BluetoothDevice { public static final String ACTION_ACL_CONNECTED="connected",ACTION_ACL_DISCONNECTED="disconnected",ACTION_UUID="uuid",EXTRA_DEVICE="device"; public static final int BOND_BONDED=12; public int getBondState(){return 12;} public String getAddress(){return "phone";} public boolean fetchUuidsWithSdp(){return true;} public android.os.ParcelUuid[] getUuids(){return new android.os.ParcelUuid[0];} }',
'android/os/ParcelUuid.java': 'package android.os; public class ParcelUuid { public java.util.UUID getUuid(){return null;} }',
'android/hardware/usb/UsbDevice.java': 'package android.hardware.usb; public class UsbDevice { public int getVendorId(){return 0;} }',
'android/hardware/usb/UsbManager.java': 'package android.hardware.usb; public class UsbManager { public static final String ACTION_USB_DEVICE_ATTACHED="attach",ACTION_USB_DEVICE_DETACHED="detach",EXTRA_DEVICE="usb"; public java.util.Map<String,UsbDevice> getDeviceList(){return new java.util.HashMap<String,UsbDevice>();} }',
'com/hkmc/userprofile/UserProfileManager.java': 'package com.hkmc.userprofile; public class UserProfileManager { public UserProfileManager(android.content.Context c){} public int getUserType(){return 0;} }',
'kr/gen5w/wireless/DriveLog.java': 'package kr.gen5w.wireless; public class DriveLog { public static java.util.List<String> codes=new java.util.concurrent.CopyOnWriteArrayList<String>(); public static void bridge(int a,int b,int c,int d,int e,int f,int g){codes.add(b+":"+c);} }',
'kr/gen5w/wireless/V039RelayCoordinator.java': '''package kr.gen5w.wireless;
import android.content.Context; import android.os.Handler;
final class V039RelayCoordinator {
 interface Events { void relayEvent(String name,String result); }
 int starts;
 V039RelayCoordinator(Context c,Handler h,Events e){} void open(){} void tick(){}
 void start(String a){starts++;} void candidateLost(){} void handoverRequested(){}
 void handoverConnected(){} void handoverDisconnected(){} void apObservedReady(){}
 void credentialsReady(){} void projectionActive(){} void close(){}
 void cancel(BtRelaySession.CancelReason r){} boolean active(){return false;}
}''',
}
harness = r"""
package kr.gen5w.wireless;
import java.util.concurrent.*;
public class WirelessBridgeIntegrationTest {
    static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
    public static class Info {
        public String getWLDevBtAddr(){return "phone";} public int getWLDType(){return 1;}
        public boolean getWLDOnOff(){return true;} public boolean getWLDAutoConnection(){return true;}
    }
    public static class Manager {
        TestContext context; int reads,calls; boolean saved,foreignAfterInspection,unavailableAfterInspection;
        public Object getWLDeviceInfo(String a,String b,int c){return saved?new Info():null;}
        public String getCPConnectedBTAddress(){outside(); return reads==0?"":"other";}
        public String getAAConnectedBTAddress(){outside(); return "";}
        public int getWirelessConnectState(){outside(); reads++; if(reads>1&&unavailableAfterInspection)throw new SecurityException(); return reads>1&&foreignAfterInspection?3:0;}
        public void requestConnectSPP(String a){outside(); calls++;}
        void outside(){check(!Thread.holdsLock(context.bridge.session),"OEM read/call must be outside session monitor");}
    }
    public static class TestContext extends android.content.Context implements PhoneProjectionAccess.ProfileProvider {
        Manager manager=new Manager(); WirelessBridge bridge; int broadcasts; boolean foreignAfterBroadcast,unavailableAfterBroadcast;
        TestContext(){manager.context=this; bridge=new WirelessBridge(this);}
        public Object getSystemService(String n){if(bridge!=null)check(!Thread.holdsLock(bridge.session),"service lookup outside monitor");return "phoneprojection".equals(n)?manager:null;}
        public PhoneProjectionAccess.Profile find(String a){return manager.saved?new PhoneProjectionAccess.Profile(a,1,true,true):null;}
        public void sendBroadcast(android.content.Intent i){check(!Thread.holdsLock(bridge.session),"broadcast outside monitor"); broadcasts++; check("com.daudio.app.phoneprojection".equals(i.pkg)&&i.extras.size()==1,"scoped single extra action"); if(foreignAfterBroadcast)manager.foreignAfterInspection=true; if(unavailableAfterBroadcast)manager.unavailableAfterInspection=true;}
    }
    static void settle(TestContext c) throws Exception {for(int i=0;i<5;i++){c.bridge.oemCalls.submit(new Runnable(){public void run(){}}).get(2,TimeUnit.SECONDS); Thread.sleep(20);}}
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
    static void missingProfileFallsBackOnlyForFreshAppleSdp() throws Exception {
        TestContext apple=new TestContext(); try {
            apple.bridge.enableRelay(); apple.bridge.appleCarPlay.put("phone",Boolean.TRUE);
            apple.bridge.session.candidate("phone",0); apple.bridge.session.tick(0);
            long generation=apple.bridge.session.generation();
            apple.bridge.session.inspected(generation,new StockProjectionSession.Observation(
                StockProjectionSession.Result.INVOKED,true,0,StockProjectionSession.ProfileState.DISABLED,
                false,false,false,StockProjectionSession.WifiCredentialState.UNKNOWN,11),1);
            java.lang.reflect.Method maintain=WirelessBridge.class.getDeclaredMethod("maintainRelay"); maintain.setAccessible(true); maintain.invoke(apple.bridge);
            check(apple.bridge.relay.starts==1,"fresh Apple SDP admits missing-profile CarPlay fallback");
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
    public static void main(String[] args)throws Exception{ownershipChangesCancelAtEveryBoundary();idleOwnershipAllowsOneBootstrap();interfaceDiagnosticsNeverBlockBootstrap();missingProfileFallsBackOnlyForFreshAppleSdp();System.out.println("PASS production WirelessBridge ownership integration");}
}
"""
with tempfile.TemporaryDirectory(prefix='gen5w-wireless-bridge-') as tmp:
    base=Path(tmp)
    for name, text in stubs.items():
        p=base/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8')
    test=base/'kr/gen5w/wireless/WirelessBridgeIntegrationTest.java';test.write_text(harness,encoding='utf-8')
    prod=root/'packages/wireless-bridge/src/kr/gen5w/wireless'
    sources=[str(p) for p in base.rglob('*.java')]+[str(prod/name) for name in ['WirelessBridge.java','StockProjectionSession.java','PhoneProjectionAccess.java','ProjectionWifiAccess.java','BluetoothCandidateScan.java','BtRelaySession.java','SdpRefresh.java']]
    subprocess.run(['javac','--release','8','-d',tmp]+sources,check=True)
    subprocess.run(['java','-cp',tmp,'kr.gen5w.wireless.WirelessBridgeIntegrationTest'],check=True)
