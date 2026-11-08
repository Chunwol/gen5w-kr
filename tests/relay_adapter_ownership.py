"""Actual adapter/pipe ownership can be reclaimed after an SPP wait times out."""
import ast
from pathlib import Path
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
tree=ast.parse((root/'tests/wireless_bridge_integration.py').read_text(encoding='utf-8'))
stubs=ast.literal_eval(next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='stubs' for t in n.targets)))
stubs.pop('kr/gen5w/wireless/V039RelayCoordinator.java')
stubs.update({
'android/content/Context.java': 'package android.content; public abstract class Context { public static final int BIND_AUTO_CREATE=1; public static final String USB_SERVICE="usb"; public abstract Object getSystemService(String s); public boolean bindService(Intent i,ServiceConnection s,int f){return true;} public void unbindService(ServiceConnection s){} public ComponentName startService(Intent i){return new ComponentName();} }',
'android/content/ComponentName.java':'package android.content; public class ComponentName {}',
'android/content/ServiceConnection.java':'package android.content; public interface ServiceConnection {void onServiceConnected(ComponentName n,android.os.IBinder b);void onServiceDisconnected(ComponentName n);}',
'android/content/Intent.java':'package android.content; public class Intent {public Intent(String s){} public Intent setPackage(String s){return this;} public Intent putExtra(String k,int v){return this;} public Intent putExtra(String k,String v){return this;}}',
'android/os/IBinder.java':'package android.os; public interface IBinder {}',
'android/os/RemoteException.java':'package android.os; public class RemoteException extends Exception {}',
'com/tcc/iap2/IIap2Listener.java':'package com.tcc.iap2; public interface IIap2Listener {public abstract class Stub implements IIap2Listener {public abstract void connected(int c,String s);public abstract void disconnected(int c);public abstract void notify(int w,int a,int b,Iap2NotiMsg m);}}',
'com/tcc/iap2/IIap2Service.java':'package com.tcc.iap2; public class IIap2Service {public static class Stub {public static IIap2Service asInterface(android.os.IBinder b){return new IIap2Service();}} public boolean Iap2SvcInit(IIap2Listener l,Iap2ListenerInfo i)throws android.os.RemoteException{return true;} public boolean Iap2SvcTransportReadDone(byte[] b,int n)throws android.os.RemoteException{return true;}}',
'com/tcc/iap2/Iap2ListenerInfo.java':'package com.tcc.iap2; public class Iap2ListenerInfo {public void onSetSupportType(int i){}public void onSetListenerName(String s){}}',
'com/tcc/iap2/Iap2NotiMsg.java':'package com.tcc.iap2; public class Iap2NotiMsg {public static final int OBJ_BLOB=1;public Iap2ObjGroup getItemGroup(){return null;}public static class Iap2ObjGroup {public int getItemCnt(){return 0;}public Iap2ObjItem getObjItem(int i){return null;}}public static class Iap2ObjItem{public int getItemParamType(){return 0;}public byte[] getItemByteArray(){return null;}}}',
})
harness='''package kr.gen5w.wireless;
public class RelayAdapterOwnershipTest {
 static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
 static void set(Object o,String n,Object v)throws Exception{java.lang.reflect.Field f=o.getClass().getDeclaredField(n);f.setAccessible(true);f.set(o,v);}
 static int connectedCallbacks;
 static class Manager extends com.broadcom.bt.hfdevice.hfbtcm.HfDeviceBTCMManager {int connects;boolean connected;public boolean IbtcmSppConnect(String a){connects++;return true;}public boolean IbtcmIsSppConnectedDevice(String a){return connected;}}
 public static void main(String[]args)throws Exception{
 V039BtRelayAdapter a=new V039BtRelayAdapter(new android.content.Context(){public Object getSystemService(String n){return null;}},new V039BtRelayAdapter.Listener(){public void ready(){}public void sppConnected(long g){connectedCallbacks++;}public void iap2Connected(long g,int c){}public void disconnected(long g,int c){}public void failed(long g,V039BtRelayAdapter.Failure f){}},new BtRelayPipe.Diagnostics(){public void event(BtRelayPipe.Event e,int c){}});
 Manager m=new Manager();set(a,"btcm",m);set(a,"iap2",new com.tcc.iap2.IIap2Service());
 check(a.connect(1,"phone"),"initial SPP request");check(!a.connect(2,"other"),"single local owner before cleanup");
 a.disconnect();check(a.connect(3,"phone"),"SPP timeout cleanup releases adapter owner for retry");
 check(m.connects==2,"retry reaches reviewed OEM SPP boundary");
 check(android.util.Log.lines.contains("path=relay event=cleanup result=local-owner-released-oem-spp-retained"),"explicit physical SPP limitation diagnostic");
 a.disconnect();m.connected=true;check(a.connect(5,"phone"),"reviewed OEM query permits retained SPP reuse");check(m.connects==2&&connectedCallbacks==1,"retained link attaches fresh pipe without duplicate OEM connect");
 a.stop(4);a.disconnect();check(a.connect(6,"phone"),"reuse after component stop");check(connectedCallbacks==2,"component stop releases pipe before clearing adapter owner");
 set(a,"iap2",new com.tcc.iap2.IIap2Service(){public boolean Iap2SvcTransportReadDone(byte[] b,int n)throws android.os.RemoteException{throw new android.os.RemoteException();}});
 java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();java.io.PrintStream original=System.err;
 boolean sent;try{System.setErr(new java.io.PrintStream(bytes));sent=a.readDone(4,new byte[]{1},1);}finally{System.setErr(original);}
 check(!sent&&bytes.toString("UTF-8").contains("bt.iap.read"),"iAP transport failure must retain false and diagnostic");
 a.close();System.out.println("PASS production relay adapter ownership cleanup");
 }}'''
with tempfile.TemporaryDirectory(prefix='gen5w-adapter-owner-') as tmp:
    base=Path(tmp)
    for name,source in stubs.items():
        p=base/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(source,encoding='utf-8')
    (base/'kr/gen5w/wireless/RelayAdapterOwnershipTest.java').write_text(harness,encoding='utf-8')
    prod=root/'packages/wireless-bridge/src/kr/gen5w/wireless'
    oem=root/'packages/wireless-bridge/stubs/com/broadcom/bt/hfdevice/hfbtcm'
    subprocess.run(['javac','--release','8','-d',tmp,str(root/'shared/src/kr/gen5w/diag/SafeDiagnostic.java')]+[str(p) for p in base.rglob('*.java')]+[str(prod/n) for n in ['V039BtRelayAdapter.java','BtRelayPipe.java']]+[str(p) for p in oem.glob('*.java')],check=True)
    subprocess.run(['java','-cp',tmp,'kr.gen5w.wireless.RelayAdapterOwnershipTest'],check=True)
