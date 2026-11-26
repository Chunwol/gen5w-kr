"""Run production adapters with host Android/OEM boundaries and a recording hook backend."""
from pathlib import Path
import ast, subprocess
import repo_tmp as tempfile
ROOT=Path(__file__).resolve().parents[1]
# Read stub data without executing that standalone regression script.
module=ast.parse((ROOT/'tests/dipo_relay_runtime.py').read_text())
STUBS=ast.literal_eval(next(n.value for n in module.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='STUBS' for t in n.targets)))
STUBS.update({
'android/content/ContentResolver.java':'''package android.content;public class ContentResolver{}''',
'android/provider/Settings.java':'''package android.provider;public final class Settings{public static final class System{public static final java.util.Map<String,Integer> VALUES=new java.util.HashMap<String,Integer>();public static int getInt(android.content.ContentResolver r,String name,int def){Integer v=VALUES.get(name);return v!=null?v.intValue():def;}}}''',
'com/hkmc/userprofile/UserProfileManager.java':'''package com.hkmc.userprofile;public class UserProfileManager{public int userType;public int getUserType(){return userType;}}''',
'android/bluetooth/BluetoothProfile.java':'''package android.bluetooth;public interface BluetoothProfile{interface ServiceListener{void onServiceConnected(int p,BluetoothProfile b);void onServiceDisconnected(int p);}}''',
'com/daudio/app/dipo/renamed/BluetoothManager.java':'''package com.daudio.app.dipo.renamed;public class BluetoothManager implements android.bluetooth.BluetoothProfile.ServiceListener{public String saved="KEEP";public int writes;public synchronized void save(String value){saved=value;writes++;}public void onServiceConnected(int p,android.bluetooth.BluetoothProfile b){}public void onServiceDisconnected(int p){}}''',
'com/daudio/app/dipo/service/DipoService.java':'''package com.daudio.app.dipo.service;import com.daudio.app.dipo.renamed.*;public class DipoService extends android.content.Context{public com.hkmc.userprofile.UserProfileManager ir=new com.hkmc.userprofile.UserProfileManager();public boolean stockSplit;public final boolean fy(){return stockSplit;}public Owner owner=new Owner();public BluetoothManager manager=new BluetoothManager();public class Details{public int calls;public boolean fail;public void changed(String address,String name,String transport,String extra)throws Throwable{calls++;String selected=((String)kr.gen5w.portable.Hook.call("reconnectIdentity",owner)).toUpperCase();kr.gen5w.portable.Hook.call("saveAddress",manager,selected.equalsIgnoreCase(address)?address:selected);if(fail)throw new IllegalStateException("callback failure");}}}''',
'android/content/ComponentName.java':'''package android.content;public class ComponentName{String p,c;public ComponentName(String p,String c){this.p=p;this.c=c;}public String getPackageName(){return p;}public String getClassName(){return c;}}''',
'android/content/Intent.java':'''package android.content;public class Intent{public String action;public ComponentName component;public int mode=-1;public Object device;public boolean activeExtra;public long tsExtra=-1L;public Intent(String a){action=a;}public String getAction(){return action;}public Intent setPackage(String p){return this;}public Intent putExtra(String k,long v){return this;}public ComponentName getComponent(){return component;}public int getIntExtra(String key,int fallback){return mode;}public boolean getBooleanExtra(String key,boolean fallback){return "active".equals(key)?activeExtra:fallback;}public long getLongExtra(String key,long fallback){return "ts".equals(key)?tsExtra:fallback;}public Object getParcelableExtra(String key){return device;}}''',
'android/content/BroadcastReceiver.java':'''package android.content;public abstract class BroadcastReceiver{public static class PendingResult{public volatile int code=-1;public volatile boolean finished;public void setResultCode(int c){code=c;}public void finish(){finished=true;}}public static PendingResult last;public PendingResult goAsync(){last=new PendingResult();return last;}public abstract void onReceive(Context c,Intent i);}''',
'android/content/IntentFilter.java':'''package android.content;public class IntentFilter{public String action;public IntentFilter(String a){action=a;}}''',
'android/util/Log.java':'''package android.util;public class Log{public static java.util.List<String> lines=new java.util.ArrayList<String>();public static int i(String t,String m){lines.add(t+": "+m);return 0;}public static int w(String t,String m){return 0;}public static int e(String t,String m){return 0;}public static int d(String t,String m){return 0;}}''',
'android/os/Looper.java':'''package android.os;public class Looper{public static final Looper MAIN=new Looper();}''',
'android/os/Handler.java':'''package android.os;public class Handler{public static final java.util.List<Runnable> pending=new java.util.ArrayList<Runnable>();public Handler(Looper l){}public boolean post(Runnable r){pending.add(r);return true;}public boolean postDelayed(Runnable r,long delayMs){pending.add(r);return true;}public static void flush(){while(!pending.isEmpty()){pending.remove(0).run();}}}''',
'android/os/SystemClock.java':'''package android.os;public class SystemClock{public static long nowMs=1000L;public static long elapsedRealtime(){return nowMs;}}''',
'com/hkmc/cluster/NavigationCluster.java':'''package com.hkmc.cluster;public class NavigationCluster{public static class CrossroadName{}public static class DestinationName{}public static class TurnList{}public static class LaneInformation{}public int pe00Calls,pe00Parking,pe00Warning,pe00Type;public void updateSTD_NAVI_PE_00_Info(int d,int r,int e,int p,int w,int t){pe00Calls++;pe00Parking=p;pe00Warning=w;pe00Type=t;}public int tbtCalls,lastDisplayType,subCalls,sub2Calls,sub2cCalls,remainCalls,crossCalls,destCalls,listCalls,listNewCalls,tpLaneCalls,laneCalls,slifCalls;public void updateTBTInfo(int dt,int ss,float dir,float dist,int err,int css,int sc,int bg,int bge){tbtCalls++;lastDisplayType=dt;}public void updateTBTSubInfo(float d,int e,int u,int h,int m,int tt,int tf,float c,int ce){subCalls++;}public void updateTBTSubInfo(float d,int e,int u,int h,int m,int tt,int tf,float c,int ce,int ep){subCalls++;}public void updateTBTSubInfo2(float p1,int e1,float p2,int e2,float p3,int e3,int u){sub2Calls++;}public void updateTBTSubInfo2(float p1,int e1,int u1,float p2,int e2,int u2,float p3,int e3,int u3){sub2Calls++;}public void updateTBTSubInfo2C(int a,int b,int c,int d,int e,int f,int g,int h,int i){sub2cCalls++;}public void updateRemainDis(int r,int u,int d,int t){remainCalls++;}public void updateTPCrossroadName(CrossroadName n){crossCalls++;}public void updateTPFlexibleDestinationName(DestinationName n){destCalls++;}public void updateTPTurnList(TurnList[] l){listCalls++;}public void updateTPTurnListNew(byte[] b){listNewCalls++;}public void updateTPLaneInfo(LaneInformation l){tpLaneCalls++;}public void updateLaneInfo(byte[] b){laneCalls++;}public void updateSLIFNaviInformation(int a,int b,int c,int d,int e){slifCalls++;}}''',
'android/content/Context.java':'''package android.content;public class Context{public String pkg="com.daudio.app.dipo";public ContentResolver resolver=new ContentResolver();public BroadcastReceiver registeredReceiver;public String registeredPermission;public String sentAction;public String getPackageName(){return pkg;}public String getPackageCodePath(){return "fake.dex";}public ClassLoader getClassLoader(){return getClass().getClassLoader();}public ContentResolver getContentResolver(){return resolver;}public android.os.Looper getMainLooper(){return android.os.Looper.MAIN;}public Intent registerReceiver(BroadcastReceiver r,IntentFilter f,String p,android.os.Handler h){registeredReceiver=r;registeredPermission=p;return null;}public void sendBroadcast(Intent i){sentAction=i!=null?i.getAction():null;}public ComponentName startService(Intent i){return null;}}''',
'android/content/ContextWrapper.java':'''package android.content;public class ContextWrapper extends Context{public int calls;public RuntimeException failure;public ComponentName result=new ComponentName("result","service");public ComponentName startService(Intent i){calls++;if(failure!=null)throw failure;return result;}}''',
'android/content/ServiceConnection.java':'''package android.content;public interface ServiceConnection{void onServiceConnected(ComponentName n,android.os.IBinder b);void onServiceDisconnected(ComponentName n);}''',
'android/os/IBinder.java':'''package android.os;public interface IBinder{default String getInterfaceDescriptor()throws android.os.RemoteException{return "com.tcc.iap2.IIap2Service";}}''',
'android/hardware/usb/UsbDevice.java':'''package android.hardware.usb;public class UsbDevice{public UsbInterface[] items;public UsbDevice(int... classes){items=new UsbInterface[classes.length];for(int i=0;i<classes.length;i++)items[i]=new UsbInterface(classes[i]);}public int getInterfaceCount(){return items.length;}public UsbInterface getInterface(int i){return items[i];}}''',
'android/hardware/usb/UsbInterface.java':'''package android.hardware.usb;public class UsbInterface{int type;public UsbInterface(int t){type=t;}public int getInterfaceClass(){return type;}}''',
'dalvik/system/DexFile.java':'''package dalvik.system;import java.util.*;public class DexFile{public static String[] names;public DexFile(String s){}public Enumeration<String> entries(){return Collections.enumeration(Arrays.asList(names));}public void close(){}}''',
'kr/gen5w/diag/SafeDiagnostic.java':'''package kr.gen5w.diag;public class SafeDiagnostic{public static void failure(String s,Throwable t){}}''',
'kr/gen5w/portable/Hook.java':'''package kr.gen5w.portable;import java.lang.reflect.*;import java.util.*;public class Hook{public static ArrayList<Method> targets=new ArrayList<Method>(),replacements=new ArrayList<Method>();public static ArrayList<Integer> removed=new ArrayList<Integer>();public static int fail=-1;public static int install(Method t,Method r){if(targets.size()==fail)throw new IllegalStateException("install failure");targets.add(t);replacements.add(r);return targets.size()-1;}public static void uninstall(int i){removed.add(i);}public static Object original(int i,Object receiver,Object[]args)throws Throwable{try{Method m=targets.get(i);m.setAccessible(true);return m.invoke(receiver,args);}catch(InvocationTargetException e){throw e.getCause();}}public static Object call(String name,Object receiver,Object...args)throws Throwable{for(int i=0;i<replacements.size();i++){Method m=replacements.get(i);if(m.getName().equals(name)&&targets.get(i).getDeclaringClass().isInstance(receiver)){Object[] values=new Object[args.length+2];values[0]=receiver;System.arraycopy(args,0,values,1,args.length);values[values.length-1]=i;try{return m.invoke(null,values);}catch(InvocationTargetException e){throw e.getCause();}}}throw new AssertionError("missing hook "+name);}}''',
'com/daudio/app/dipo/renamed/Sentinel.java':'''package com.daudio.app.dipo.renamed;public class Sentinel{public static int initialized;}''',
'com/daudio/app/dipo/renamed/Wireless.java':'''package com.daudio.app.dipo.renamed;public class Wireless{static{Sentinel.initialized++;}public boolean isSupportWirelessCarPlay(){return true;}public boolean F(android.content.Context c)throws Throwable{return c!=null&&(Boolean)kr.gen5w.portable.Hook.call("wirelessSupport",this);}}''',
'com/daudio/app/dipo/telechips/CarPlayScreen.java':'''package com.daudio.app.dipo.telechips;public enum CarPlayScreen{VideoStream_1280x720_60fps,VideoStream_1920x720_60fps}''',
'com/daudio/app/dipo/renamed/DisplayConfig.java':'''package com.daudio.app.dipo.renamed;public class DisplayConfig{public int width=1920,calls;public boolean split=true;public RuntimeException failure;public Runnable during;public int mU()throws Throwable{calls++;boolean wireless=(Boolean)kr.gen5w.portable.Hook.call("wirelessSupport",new Wireless());if(during!=null)during.run();if(failure!=null)throw failure;return !wireless&&split&&width==1920?1280:width;}public int mV(){return 720;}public com.daudio.app.dipo.telechips.CarPlayScreen mW()throws Throwable{return ((Integer)kr.gen5w.portable.Hook.call("screenWidth",this))==1280?com.daudio.app.dipo.telechips.CarPlayScreen.VideoStream_1280x720_60fps:com.daudio.app.dipo.telechips.CarPlayScreen.VideoStream_1920x720_60fps;}}''',
'com/daudio/app/dipo/renamed/ExtraDisplay.java':'''package com.daudio.app.dipo.renamed;public class ExtraDisplay{public int mU(){return 1920;}public int mV(){return 720;}public com.daudio.app.dipo.telechips.CarPlayScreen mW(){return null;}}''',
'com/daudio/app/dipo/renamed/ExtraWireless.java':'''package com.daudio.app.dipo.renamed;public class ExtraWireless{public boolean isSupportWirelessCarPlay(){return true;}}''',
'com/daudio/app/dipo/renamed/Owner.java':'''package com.daudio.app.dipo.renamed;import com.tcc.iap2.*;import android.content.*;import android.os.*;public class Owner{public String address;public synchronized String identity(){return address;}private boolean notifications;public boolean enabled(){return notifications;}public void clearNotifications(){notifications=false;}public boolean dropBeforeLocal,throwInLocal;public java.util.concurrent.CountDownLatch enteredLatch,releaseLatch;public class Local implements IIap2Listener{public int calls,component;public void connected(int c,String s){if(Owner.this.enteredLatch!=null){Owner.this.enteredLatch.countDown();try{Owner.this.releaseLatch.await(2000,java.util.concurrent.TimeUnit.MILLISECONDS);}catch(InterruptedException ignored){}}if(Owner.this.throwInLocal)throw new RuntimeException("boom");calls++;component=c;}public void disconnected(int c){calls++;component=c;}public void notify(int w,int a,int b,Iap2NotiMsg m){}public class BinderListener extends IIap2Listener.Stub{public int calls,component;public void connected(int c,String s){if(s==null)return;calls++;component=c;if(c==1&&!Owner.this.dropBeforeLocal){Owner.this.notifications=true;try{kr.gen5w.portable.Hook.call("localConnected",Local.this,c,s);}catch(RuntimeException|Error e){throw e;}catch(Throwable e){throw new RuntimeException(e);}}}public void disconnected(int c){calls++;component=c;if(c==1){Owner.this.notifications=false;try{kr.gen5w.portable.Hook.call("localDisconnected",Local.this,c);}catch(RuntimeException|Error e){throw e;}catch(Throwable e){throw new RuntimeException(e);}}}public void notify(int w,int a,int b,Iap2NotiMsg m){calls++;component=w;}}}public class OtherConnection implements ServiceConnection{public int calls;public void onServiceConnected(ComponentName n,IBinder b){calls++;}public void onServiceDisconnected(ComponentName n){}}public class Connection implements ServiceConnection{public int calls;public void onServiceConnected(ComponentName n,IBinder b){calls++;}public void onServiceDisconnected(ComponentName n){}}}''',
})
STUBS['com/daudio/app/dipo/telechips/CarPlayService.java']=STUBS['com/daudio/app/dipo/telechips/CarPlayService.java'].replace('public int requests','public int originals;public Runnable onFinalizeOriginal;public void onDisableBluetooth(String why){originals++;}public void onSessionCreated(){originals++;}public void onSessionStarted(int t){originals++;}public void onSessionFinalized(int r){originals++;if(onFinalizeOriginal!=null){Runnable r0=onFinalizeOriginal;onFinalizeOriginal=null;r0.run();}}public void oniAPSendMessage(byte[] b,int n){originals++;}public int requests')
STUBS['com/tcc/iap2/IIap2Service.java']=STUBS['com/tcc/iap2/IIap2Service.java'].replace('public interface IIap2Service {','public interface IIap2Service {class Stub {public static IIap2Service value;public static IIap2Service asInterface(android.os.IBinder b){return value;}}')
STUBS['com/daudio/app/dipo/telechips/CarPlayService.java']=STUBS['com/daudio/app/dipo/telechips/CarPlayService.java'].replace('public int originals;', 'public int originals;public int rate,stoppedStream,audioType;public void onAudioStreamStart(int s,int t,int r){originals++;rate=r;}public void onAudioStreamStop(int s){originals++;stoppedStream=s;}public void onSetPropertyAudioType(int r){originals++;audioType=r;}public void onModeChanged(int a,int b,int c,int d,int e,int f){originals++;}')
STUBS['com/daudio/app/dipo/telechips/CarPlayService$1iAPSendMessage.java']='''package com.daudio.app.dipo.telechips;public class CarPlayService$1iAPSendMessage extends Thread{private byte[] msg=new byte[6];private int len;private synchronized void setMsgDataLen(int n){if(len>Integer.MAX_VALUE||len<Integer.MIN_VALUE)len=n;}public int length(){return len;}}'''
HARNESS='''import kr.gen5w.portable.*;import kr.gen5w.dipo.RelayBridge;import android.content.*;import android.hardware.usb.*;import com.daudio.app.dipo.renamed.*;import com.daudio.app.dipo.telechips.*;import com.tcc.iap2.*;
public class AdapterTest {
 static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
 static class Port implements IIap2Service {int registered,reads;public boolean Iap2SvcInit(IIap2Listener l,Iap2ListenerInfo i){registered++;return true;}public boolean Iap2SvcTransportReadDone(byte[] b,int n){reads++;return false;}}
 public static void main(String[] args)throws Throwable{
 String mode=args[0];Context c=new Context();dalvik.system.DexFile.names=new String[]{"com.daudio.app.dipo.renamed.Owner","com.daudio.app.dipo.renamed.Owner$Local","com.daudio.app.dipo.renamed.Owner$Local$BinderListener","com.daudio.app.dipo.renamed.Owner$Connection","com.daudio.app.dipo.renamed.Owner$OtherConnection","com.daudio.app.dipo.renamed.Wireless","com.daudio.app.dipo.renamed.DisplayConfig","com.daudio.app.dipo.renamed.BluetoothManager","com.daudio.app.dipo.service.DipoService$Details"};
 if(mode.equals("ambiguous")){String[] old=dalvik.system.DexFile.names;dalvik.system.DexFile.names=java.util.Arrays.copyOf(old,old.length+1);dalvik.system.DexFile.names[old.length]="com.daudio.app.dipo.renamed.ExtraWireless";try{ProjectionAdapters.install(c);throw new AssertionError("accepted ambiguity");}catch(IllegalArgumentException expected){}check(Hook.targets.size()==0,"ambiguity must install nothing");return;}
 if(mode.startsWith("display-")){
  java.util.List<String> names=new java.util.ArrayList<String>(java.util.Arrays.asList(dalvik.system.DexFile.names));
  if(mode.equals("display-missing"))names.remove("com.daudio.app.dipo.renamed.DisplayConfig");
  else names.add("com.daudio.app.dipo.renamed.ExtraDisplay");
  dalvik.system.DexFile.names=names.toArray(new String[0]);
  try{ProjectionAdapters.install(c);throw new AssertionError("accepted missing/ambiguous display role");}catch(IllegalArgumentException expected){}
  check(Hook.targets.size()==0,"invalid display role installs nothing");return;
 }
 if(mode.equals("rollback")){Hook.fail=5;try{ProjectionAdapters.install(c);throw new AssertionError("accepted failed install");}catch(IllegalStateException expected){}check(Hook.removed.equals(java.util.Arrays.asList(4,3,2,1,0)),"rollback reverse order");return;}
 if(mode.startsWith("gpm")){c.pkg="com.google.android.projection.sink";ProjectionAdapters.install(c);ContextWrapper receiver=new ContextWrapper();Intent intent=new Intent("start");intent.component=new ComponentName("com.google.android.projection.sink","com.google.android.projection.service.GalReceiverService");intent.mode=1;intent.device=new UsbDevice(8,9);
 check(Hook.call("startService",receiver,intent)==null&&receiver.calls==0,"storage-only service start suppressed");
 intent.device=new UsbDevice(8,255);check(Hook.call("startService",receiver,intent)==receiver.result&&receiver.calls==1,"mixed USB original exactly once");
 intent.device=new UsbDevice(8);intent.mode=2;check(Hook.call("startService",receiver,intent)==receiver.result&&receiver.calls==2,"other start mode unchanged");
 RuntimeException sentinel=new RuntimeException("identity");receiver.failure=sentinel;try{Hook.call("startService",receiver,intent);throw new AssertionError("swallowed");}catch(RuntimeException e){check(e==sentinel,"preserve exception identity");}check(receiver.calls==3,"failure cannot retry original");return;}
 if(mode.equals("navi")) {
  c.pkg="com.mnsoft.navi";
  android.os.Handler.pending.clear();
  check(ProjectionAdapters.install(c),"navi install accepted");
  android.os.Handler.flush();
  check(Hook.targets.size()==14,"exact 14 cluster TBT/HUD hooks installed without SLIF");
  check("kr.gen5w.permission.HUD_INPUT".equals(c.registeredPermission),"PHONE_GUIDING receiver requires HUD_INPUT signature permission");
  check(c.sentAction==null,"no unauthenticated NAVI_READY broadcast emitted");
  com.hkmc.cluster.NavigationCluster nc=new com.hkmc.cluster.NavigationCluster();
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  check(nc.tbtCalls==1&&nc.lastDisplayType==8,"stock DisplayType(8) passes when phone not guiding");
  Intent on=new Intent("kr.gen5w.action.PHONE_GUIDING"); on.activeExtra=true; on.tsExtra=1000L;
  c.registeredReceiver.onReceive(c,on);
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  Hook.call("updateTBTInfo",nc,0,0,0f,0f,-3,0,15,0,0);
  Hook.call("dropTbtSubInfo9",nc,0f,0,15,-1,-1,0,0,0f,-1);
  Hook.call("dropTbtSubInfo2C",nc,0,0,0,0,0,0,0,0,0);
  Hook.call("dropRemainDis",nc,0,0,0,0);
  Hook.call("dropOneArg",nc,new com.hkmc.cluster.NavigationCluster.CrossroadName());
  Hook.call("dropOneArg",nc,new byte[]{1});
  check(nc.tbtCalls==1&&nc.subCalls==0&&nc.sub2cCalls==0&&nc.remainCalls==0&&nc.crossCalls==0&&nc.laneCalls==0,"idle stock TBT calls suppressed while phone guiding");
  Hook.call("dropPe00",nc,0,0,0,0,0,0);
  check(nc.pe00Calls==0,"unrelated stock tunnel packet suppressed during phone route");
  Hook.call("dropPe00",nc,0,0,0,1,0,0);
  check(nc.pe00Calls==1&&nc.pe00Parking==1,"parking packet is preserved");
  Hook.call("dropPe00",nc,0,0,0,0,1,2);
  check(nc.pe00Calls==2&&nc.pe00Warning==1&&nc.pe00Type==2,"HVAC warning fields preserved");
  nc.updateSLIFNaviInformation(60,0,0,0,0);
  check(nc.slifCalls==1,"SLIF speed limit warnings never hooked or suppressed");
  Hook.call("updateTBTInfo",nc,0x42,0,0f,500f,0,0,0,0,0);
  check(nc.tbtCalls==2&&nc.lastDisplayType==0x42,"real stock turn immediately yields phone guidance and executes");
  Intent duringStock=new Intent("kr.gen5w.action.PHONE_GUIDING"); duringStock.activeExtra=true; duringStock.tsExtra=2000L;
  c.registeredReceiver.onReceive(c,duringStock);
  Hook.call("dropTbtSubInfo9",nc,0f,0,15,-1,-1,0,0,0f,-1);
  check(nc.subCalls==1,"PHONE_GUIDING ignored while stock active turn owns cluster");
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  check(nc.tbtCalls==3,"cleared guiding flag allows subsequent DisplayType(8)");
  Intent staleOld=new Intent("kr.gen5w.action.PHONE_GUIDING"); staleOld.activeExtra=true; staleOld.tsExtra=900L;
  Intent staleSame=new Intent("kr.gen5w.action.PHONE_GUIDING"); staleSame.activeExtra=true; staleSame.tsExtra=1000L;
  Intent staleNoTs=new Intent("kr.gen5w.action.PHONE_GUIDING"); staleNoTs.activeExtra=true; staleNoTs.tsExtra=-1L;
  c.registeredReceiver.onReceive(c,staleOld);
  c.registeredReceiver.onReceive(c,staleSame);
  c.registeredReceiver.onReceive(c,staleNoTs);
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  check(nc.tbtCalls==4,"stale or missing-ts pre-yield broadcasts cannot reclaim cluster lease");
  android.os.SystemClock.nowMs=1500L;
  Intent fresh=new Intent("kr.gen5w.action.PHONE_GUIDING"); fresh.activeExtra=true; fresh.tsExtra=1500L;
  c.registeredReceiver.onReceive(c,fresh);
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  check(nc.tbtCalls==4,"post-yield fresh PHONE_GUIDING suppresses idle stock DisplayType(8)");
  Intent off=new Intent("kr.gen5w.action.PHONE_GUIDING"); off.activeExtra=false; off.tsExtra=1600L;
  c.registeredReceiver.onReceive(c,off);
  android.os.SystemClock.nowMs=20000L;
  Intent expired=new Intent("kr.gen5w.action.PHONE_GUIDING"); expired.activeExtra=true; expired.tsExtra=2000L;
  Intent future=new Intent("kr.gen5w.action.PHONE_GUIDING"); future.activeExtra=true; future.tsExtra=25000L;
  c.registeredReceiver.onReceive(c,expired);
  c.registeredReceiver.onReceive(c,future);
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  check(nc.tbtCalls==5,"expired-in-transit and future timestamps must not arm lease");
  Intent delayedFresh=new Intent("kr.gen5w.action.PHONE_GUIDING"); delayedFresh.activeExtra=true; delayedFresh.tsExtra=19000L;
  c.registeredReceiver.onReceive(c,delayedFresh);
  Intent outOfOrderOff=new Intent("kr.gen5w.action.PHONE_GUIDING"); outOfOrderOff.activeExtra=false; outOfOrderOff.tsExtra=18000L;
  c.registeredReceiver.onReceive(c,outOfOrderOff);
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  check(nc.tbtCalls==5,"out-of-order older inactive broadcast cannot clear newer lease");
  android.os.SystemClock.nowMs=34000L;
  Hook.call("updateTBTInfo",nc,8,0,0f,0f,-3,0,15,0,0);
  check(nc.tbtCalls==6,"lease expires from sentAtMs+LEASE_MS rather than receipt time");
  android.os.Handler.pending.clear();
  try {
   java.lang.reflect.Field reg=NaviAdapters.class.getDeclaredField("receiverRegistered");
   java.lang.reflect.Field sch=NaviAdapters.class.getDeclaredField("receiverScheduled");
   reg.setAccessible(true); sch.setAccessible(true);
   reg.setBoolean(null,false); sch.setBoolean(null,false);
   c.registeredReceiver=null; c.sentAction=null;
   Hook.call("dropOneArg",nc,new com.hkmc.cluster.NavigationCluster.CrossroadName());
   android.os.Handler.flush();
   check(nc.crossCalls==1&&c.registeredReceiver!=null&&c.sentAction==null,"non-TBT hook self-heals receiver registration without unauthenticated broadcast");
  } catch (NoSuchFieldException ignored) { throw new AssertionError("missing receiver flags"); }
  return;
 }
 if(mode.equals("reconnect")) {
  ProjectionAdapters.install(c);com.daudio.app.dipo.service.DipoService service=new com.daudio.app.dipo.service.DipoService();com.daudio.app.dipo.service.DipoService.Details details=service.new Details();
  check(Hook.call("reconnectIdentity",service.owner)==null,"getter outside callback stays null");
  Hook.call("sessionDetails",details,"aa:bb","name","wireless","extra");check("aa:bb".equals(service.manager.saved),"missing identity falls back to session");
  service.manager.saved="KEEP";int writes=service.manager.writes;Hook.call("sessionDetails",details,null,"name",null,null);check("KEEP".equals(service.manager.saved)&&writes==service.manager.writes,"both missing preserves saved address");
  service.owner.address="cc:dd";Hook.call("sessionDetails",details,"aa:bb",null,null,null);check("CC:DD".equals(service.manager.saved),"iAP identity wins");
  service.owner.address=null;details.fail=true;try{Hook.call("sessionDetails",details,"aa:bb",null,null,null);throw new AssertionError("missing failure");}catch(IllegalStateException expected){}
  check(Hook.call("reconnectIdentity",service.owner)==null,"throwing callback cleans scope");Hook.call("saveAddress",service.manager,"");check("".equals(service.manager.saved),"outside callback setter unchanged");return;
 }
 ProjectionAdapters.Transaction bootstrapTx=ProjectionAdapters.beginInstall(c);
 check(bootstrapTx!=null&&c.registeredReceiver==null,"restart receiver stays unregistered until commit");
 bootstrapTx.commit();
 check(c.registeredReceiver!=null&&"kr.gen5w.permission.HUD_INPUT".equals(c.registeredPermission),"beginInstall+commit (Bootstrap path) registers RESTART_CARPLAY receiver with HUD_INPUT permission");
 c.registeredReceiver.onReceive(c,new Intent("kr.gen5w.dipo.RESTART_CARPLAY"));
 for(int n=0;n<200&&!android.content.BroadcastReceiver.last.finished;n++)Thread.sleep(5);
 check(android.content.BroadcastReceiver.last.finished&&android.content.BroadcastReceiver.last.code==kr.gen5w.dipo.RelayBridge.RESTART_NONE,"ordered receiver distinguishes NO_SESSION");
 check(Hook.targets.size()==24,"complete hook set");check(Sentinel.initialized==0,"discovery must not initialize classes");check(ProjectionAdapters.install(c)&&Hook.targets.size()==24,"installation idempotent");
 Owner owner=new Owner();Owner.Local local=owner.new Local();Owner.Local.BinderListener binder=local.new BinderListener();Owner.Connection connection=owner.new Connection();CarPlayService car=new CarPlayService();
 owner.dropBeforeLocal=true;
 Hook.call("binderConnected",binder,5,"peer");check(binder.calls==1&&local.calls==0,"OEM early drop must not lock cp5 remap");
 owner.dropBeforeLocal=false;
 owner.throwInLocal=true;
 try{Hook.call("binderConnected",binder,5,"peer");throw new AssertionError("exception must propagate");}catch(RuntimeException expected){}
 owner.throwInLocal=false;
 check(local.calls==0,"throwing connect callback leaves cp5 retryable");
 Hook.call("binderConnected",binder,5,"peer");
 check(local.calls==1&&binder.component==1&&local.component==1&&owner.enabled(),"cp5 retries cleanly after exception");
 Hook.call("binderDisconnected",binder,1);
 local.calls=0;binder.calls=0;owner.clearNotifications();
 owner.enteredLatch=new java.util.concurrent.CountDownLatch(1);
 owner.releaseLatch=new java.util.concurrent.CountDownLatch(1);
 final java.util.concurrent.atomic.AtomicBoolean discDone=new java.util.concurrent.atomic.AtomicBoolean(false);
 final java.util.concurrent.atomic.AtomicReference<Throwable> threadErr=new java.util.concurrent.atomic.AtomicReference<Throwable>();
 final Owner.Local.BinderListener concBinder=binder;
 Thread tConn=new Thread(()->{try{Hook.call("binderConnected",concBinder,5,"peer");}catch(Throwable t){threadErr.compareAndSet(null,t);}});
 tConn.setDaemon(true);
 Thread tDisc=new Thread(()->{try{Hook.call("binderDisconnected",concBinder,1);discDone.set(true);}catch(Throwable t){threadErr.compareAndSet(null,t);}});
 tDisc.setDaemon(true);
 try{
  tConn.start();
  check(owner.enteredLatch.await(2000,java.util.concurrent.TimeUnit.MILLISECONDS),"binderConnected entered OEM local");
  tDisc.start();
  long blockDeadline=System.currentTimeMillis()+2000L;
  while(tDisc.getState()!=Thread.State.BLOCKED&&System.currentTimeMillis()<blockDeadline)Thread.sleep(5);
  check(tDisc.getState()==Thread.State.BLOCKED&&!discDone.get(),"binderDisconnected must block on DipoAdapters BINDER_CALLBACK_LOCK while OEM connect runs");
 }finally{
  owner.releaseLatch.countDown();
  tConn.join(2000);tDisc.join(2000);
  owner.enteredLatch=null;owner.releaseLatch=null;
 }
 check(!tConn.isAlive()&&!tDisc.isAlive(),"concurrent binder callbacks completed");
 if(threadErr.get()!=null)throw threadErr.get();
 check(discDone.get(),"binderDisconnected completed after connect released lock");
 local.calls=0;binder.calls=0;owner.clearNotifications();
 Hook.call("binderConnected",binder,5,(Object)null);check(binder.calls==0,"null serial 5 cannot trigger connect or burn cp5 state");
 Hook.call("binderConnected",binder,5,"peer");check(binder.calls==1&&binder.component==1&&owner.enabled()&&local.calls==1,"late-bind 5 without prior 4 reaches DiPO as phone");
 Hook.call("binderConnected",binder,5,"peer");check(owner.enabled()&&binder.calls==1&&local.calls==1,"subsequent 5 enables notifications without restarting session");
 Hook.call("binderDisconnected",binder,1);check(binder.calls==2&&binder.component==1&&local.calls==2&&!owner.enabled(),"disconnect reaches DiPO, forwards local disconnect, and clears session state");
 Owner.Local.BinderListener binder2=local.new BinderListener();
 Hook.call("binderConnected",binder,4,"peer");check(binder.calls==3&&binder.component==1&&local.calls==3,"4 maps to stock phone");Hook.call("binderConnected",binder,5,"peer");check(binder.calls==3,"5 cannot restart stock session on same listener");
 Hook.call("binderConnected",binder2,5,"peer");check(binder2.calls==1&&binder2.component==1&&local.calls==4,"recreated listener remaps component 5");
 Hook.call("binderConnected",binder2,4,"peer");check(binder2.calls==1,"delayed 4 after connected 5 stays notify-only");
 Hook.call("binderConnected",binder2,2,"peer");check(binder2.calls==2&&binder2.component==2,"other component preserved");
 Hook.call("localConnected",local,5,"peer");check(local.calls==4,"local channel consumed");Hook.call("localConnected",local,4,"peer");check(local.calls==5&&local.component==4,"local nonchannel unchanged");
 Hook.call("localDisconnected",local,5);check(local.calls==6&&local.component==5,"local disconnect runs cleanup and delegates to OEM");
 Port port=new Port();IIap2Service.Stub.value=port;Hook.call("serviceConnected",connection,new ComponentName("p","c"),new android.os.IBinder(){});check(connection.calls==1&&port.registered==1,"bind after original");
 Hook.call("serviceConnected",connection,new ComponentName("p","c"),new android.os.IBinder(){public String getInterfaceDescriptor(){return "other.Binder";}});check(connection.calls==2&&port.registered==1,"unrelated binder delegates only");
 Hook.call("serviceConnected",connection,new ComponentName("p","c"),new android.os.IBinder(){public String getInterfaceDescriptor()throws android.os.RemoteException{throw new android.os.RemoteException();}});check(connection.calls==3&&port.registered==1,"descriptor failure preserves original");
 Owner.OtherConnection other=owner.new OtherConnection();Hook.call("serviceConnected",other,new ComponentName("p","c"),new android.os.IBinder(){public String getInterfaceDescriptor(){return "carplay.Binder";}});check(other.calls==1&&port.registered==1,"second owner connection delegates unrelated binder");
 Hook.call("sessionCreated",car);Hook.call("sessionStarted",car,1);check(car.originals==2&&car.requests==1,"sessions bridge and original exactly once");
 Hook.call("disableBluetooth",car,"wireless");check(car.originals==3,"wireless CarPlay delivers the OEM Bluetooth handover");
 int old=binder.calls;Hook.call("binderDisconnected",binder,4);Hook.call("binderNotify",binder,0,1,2,new Iap2NotiMsg());check(binder.calls==old,"wireless disconnect and identification suppressed");Hook.call("binderNotify",binder,81,1,2,new Iap2NotiMsg());check(binder.calls==old+1,"other notify preserved");
 Hook.call("fromCarPlay",car,new byte[]{1},1);check(car.originals==3,"relayed outbound callback must not also enter the null OEM path");Hook.call("sessionFinalized",car,7);check(car.originals==4 && !owner.enabled() && binder2.component==1 && local.component==1,"finalized original runs once and delivers component-1 disconnect to DiPO listener");Hook.call("disableBluetooth",car,"finalized");check(car.originals==5,"finalized session delegates OEM Bluetooth cleanup");Hook.call("sessionCreated",car);Hook.call("sessionStarted",car,0);Hook.call("disableBluetooth",car,"wired");check(car.originals==8,"wired callbacks preserve OEM Bluetooth cleanup");Hook.call("fromCarPlay",car,new byte[]{1},1);check(car.originals==9,"wired outbound retains the OEM callback");
 Hook.call("binderConnected",binder2,4,"peer");check(RelayBridge.isConnectedOwner(binder2),"4 mapped to 1 while idle");Hook.call("binderDisconnected",binder2,4);check(!owner.enabled() && binder2.component==1 && !RelayBridge.isConnectedOwner(binder2),"pre-wireless BT disconnect maps 4->1 so DiPO clears CarPlay connected state");
 check(!(Boolean)Hook.call("wirelessSupport",new Wireless()),"stock wireless path disabled");
 DisplayConfig display=new DisplayConfig();
 check(display.mU()==1280,"fixture reproduces forced-false regression");
 check((Integer)Hook.call("screenWidth",display)==1920,"split ON advertises full 1920 video");
 check(display.calls==2,"width scope delegates original exactly once");
 check(display.mW()==CarPlayScreen.VideoStream_1920x720_60fps,"mW selects full video via scoped mU");
 display.split=false;check((Integer)Hook.call("screenWidth",display)==1920,"split OFF remains full width");
 display.width=800;check((Integer)Hook.call("screenWidth",display)==800,"800 display remains stock");
 display.width=1280;check((Integer)Hook.call("screenWidth",display)==1280,"1280 display remains stock");
 display.width=1920;display.split=true;
 display.during=()->{try{
  check((Boolean)Hook.call("splitScreen",new Wireless(),c),"nested preference scope");
  check((Boolean)Hook.call("wirelessSupport",new Wireless()),"nested scope restores outer capability");
  final boolean[] leaked={true};Thread otherThread=new Thread(()->{try{leaked[0]=(Boolean)Hook.call("wirelessSupport",new Wireless());}catch(Throwable t){throw new AssertionError(t);}});
  otherThread.start();otherThread.join();check(!leaked[0],"width scope cannot leak across threads");
 }catch(Throwable t){throw new AssertionError(t);}};
 Hook.call("screenWidth",display);display.during=null;
 RuntimeException widthFailure=new RuntimeException("width failure");display.failure=widthFailure;
 try{Hook.call("screenWidth",display);throw new AssertionError("width exception swallowed");}catch(RuntimeException expected){check(expected==widthFailure,"original exception identity");}
 check(!(Boolean)Hook.call("wirelessSupport",new Wireless()),"width scope removed after exception");
 display.failure=null;

 check((Boolean)Hook.call("splitScreen",new Wireless(),c),"INFO capability must be available inside OEM split preference query");
 check(!(Boolean)Hook.call("splitScreen",new Wireless(),(Object)null),"OEM null context rejection retained");
 check(!(Boolean)Hook.call("wirelessSupport",new Wireless()),"INFO scope cannot enable stock wireless connection");
 com.daudio.app.dipo.service.DipoService splitService=new com.daudio.app.dipo.service.DipoService();
 android.provider.Settings.System.VALUES.clear();
 check(!(Boolean)Hook.call("splitScreenEnabled",splitService),"splitScreenEnabled stays false when stock is false");
 android.provider.Settings.System.VALUES.put("phoneprojection_setting_use_split_screen",1);
 android.provider.Settings.System.VALUES.put("carplay_ss_osd",0);
 check(!(Boolean)Hook.call("splitScreenEnabled",splitService),"splitScreenEnabled never OR-overrides stock false");
 splitService.stockSplit=true;
 check((Boolean)Hook.call("splitScreenEnabled",splitService),"splitScreenEnabled preserves stock true");
 Hook.call("audioStreamStart",car,100,1,48000);Hook.call("audioStreamStop",car,102);Hook.call("setPropertyAudioType",car,2);Hook.call("modeChanged",car,2,2,0,0,0,0);check(car.originals==13&&car.rate==48000&&car.stoppedStream==102&&car.audioType==2,"trace callbacks preserve original delivery, stop, audio type, and sample rate");
 CarPlayService$1iAPSendMessage packet=new CarPlayService$1iAPSendMessage();Hook.call("iapSendLength",packet,6);check(packet.length()==6,"native iAP2 send must retain its actual packet length");
 try{Hook.call("iapSendLength",packet,7);throw new AssertionError("accepted oversized iAP2 length");}catch(IllegalArgumentException expected){}check(packet.length()==6,"rejected length must preserve the packet");
 Hook.call("sessionCreated",car);Hook.call("sessionStarted",car,1);
 check(c.registeredReceiver!=null,"RESTART_CARPLAY receiver must be registered via Bootstrap transaction");
 c.registeredReceiver.onReceive(c,new Intent("kr.gen5w.dipo.RESTART_CARPLAY"));long dl=System.currentTimeMillis()+2000L;while(car.disconnects==0&&System.currentTimeMillis()<dl)Thread.sleep(5);check(car.disconnects==1,"RESTART_CARPLAY receiver disconnects active session");
 // Concurrent binderConnected establishing a new session during onSessionFinalized must not be disconnected by stale finalize cleanup.
 Hook.call("binderConnected",binder2,4,"peer");
 check(owner.enabled()&&RelayBridge.isConnectedOwner(binder2),"new session owner connected");
 car.onFinalizeOriginal=()->{
  Thread racer=new Thread(()->{try{Hook.call("binderConnected",binder2,4,"peer2");}catch(Throwable t){throw new RuntimeException(t);}});
  racer.start();try{racer.join(2000);}catch(InterruptedException ignored){}
 };
 Hook.call("sessionFinalized",car,0);
 check(owner.enabled()&&RelayBridge.isConnectedOwner(binder2),"stale sessionFinalized cleanup must not disconnect newly established session");
 }
}'''
GPM_HARNESS='import kr.gen5w.portable.*;import android.content.*;import android.hardware.usb.*;public class GpmOnlyTest{static void check(boolean b,String m){if(!b)throw new AssertionError(m);}public static void main(String[] args)throws Throwable{Context c=new Context();'+HARNESS.split('if(mode.startsWith("gpm")){',1)[1].split('return;}\n',1)[0]+'}}'
def main():
 source=ROOT/'tools/portable/adapters/src/kr/gen5w/portable/ProjectionAdapters.java'
 assert source.exists(),'app-local structural adapter is missing'
 with tempfile.TemporaryDirectory(dir=ROOT/'tests') as temporary:
  tmp=Path(temporary);sources=[]
  for name,content in dict(STUBS,**{'AdapterTest.java':HARNESS,'GpmOnlyTest.java':GPM_HARNESS}).items():
   path=tmp/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(content);sources.append(path)
  sources+=list((ROOT/'tools/portable/adapters/src').rglob('*.java'))
  sources += [ROOT/'shared/src/kr/gen5w/diag/DebugTrace.java']
  sources += [ROOT/'tools/v039-relay/dipo-src/kr/gen5w/dipo/RelayBridge.java',ROOT/'tools/v039-relay/gpm-src/kr/gen5w/gpm/GpmUsbGuard.java']
  subprocess.run(['javac','--release','8','-Xlint:-options','-d',str(tmp/'classes'),*map(str,sources)],check=True)
  for case in ['dipo','ambiguous','display-missing','display-ambiguous','rollback','reconnect','navi','gpm']:
   if case=='gpm':
    (tmp/'classes/com/daudio').rename(tmp/'hidden-dipo');(tmp/'classes/com/tcc').rename(tmp/'hidden-tcc')
   subprocess.run(['java','-cp',str(tmp/'classes'),'GpmOnlyTest' if case=='gpm' else 'AdapterTest',case],check=True,timeout=30)
   print('PASS portable adapters',case)
if __name__=='__main__':main()
