package kr.gen5w.wireless;

import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.ParcelUuid;
import android.os.SystemClock;
import android.util.Log;
import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2ListenerInfo;
import com.tcc.iap2.Iap2NotiMsg;
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Method;
import java.util.ArrayDeque;
import java.util.HashSet;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import kr.gen5w.hotspot.ApProfiles;
import kr.gen5w.hotspot.ApBrokerClient;

/** Runs in an Android-managed app process. Own RFCOMM transport, OEM iAP2
 * authentication and OEM CarPlay projection. Logs contain no phone addresses,
 * keys, message bodies, UUIDs received from phones, or route names.
 */
public final class WirelessBridge implements WirelessSession.Port {
    static final String TAG="Gen5wWireless";
    static final UUID WIRELESS=UUID.fromString("00000000-deca-fade-deca-deafdecacaff");
    static final UUID WIRELESS_FALLBACK=UUID.fromString("00000000-deca-fade-deca-deafdecacafe");
    static final String PROJECTION_ACTION="com.daudio.app.dipo.carplaymagiccode.wireless";
    static final String PROJECTION_PACKAGE="com.daudio.app.dipo";
    static final String COMPONENT="com.telechips.android.iap2.component";
    final Context context;
    final Handler main;
    final BluetoothAdapter adapter=BluetoothAdapter.getDefaultAdapter();
    final WirelessSession session=new WirelessSession(this);
    final SdpRefresh sdpRefresh=new SdpRefresh();
    final Set<String> linked=new HashSet<String>();
    final Map<String,UUID> advertised=new HashMap<String,UUID>();
    final Map<String,Integer> selectedService=new HashMap<String,Integer>();
    final Map<String,Integer> failedService=new HashMap<String,Integer>();
    final ArrayDeque<byte[]> pending=new ArrayDeque<byte[]>();
    final ThreadPoolExecutor writes=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(32));
    final WirelessSession.Resource<BluetoothSocket> transport=new WirelessSession.Resource<BluetoothSocket>();
    final AtomicInteger queuedBytes=new AtomicInteger();
    IIap2Service iap;
    ComponentName server;
    boolean bound, registered;
    volatile boolean cable, shuttingDown;
    final WirelessSession.WiredSignal carplayCable=new WirelessSession.WiredSignal();
    boolean nativeRequested;
    int pendingBytes;
    IIap2Listener listener;
    long projectionGeneration=-1, projectionDeadline, projectionNext;
    long provisionGeneration=-1, provisionDeadline, provisionNext;

    WirelessBridge(Context context) { this.context=context; main=new Handler(Looper.getMainLooper()); }
    final BroadcastReceiver stopReceiver=new BroadcastReceiver(){ public void onReceive(Context c,Intent i){shutdown();}};
    void run() {
        IntentFilter f=new IntentFilter();
        f.addAction(BluetoothDevice.ACTION_ACL_CONNECTED);f.addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED);
        f.addAction(BluetoothDevice.ACTION_UUID);f.addAction(BluetoothAdapter.ACTION_STATE_CHANGED);
        f.addAction("android.bluetooth.headsetclient.profile.action.CONNECTION_STATE_CHANGED");
        f.addAction("android.bluetooth.headset.profile.action.CONNECTION_STATE_CHANGED");
        f.addAction("android.hardware.usb.action.CARPLAY_DEVICE_ATTACHED");
        f.addAction("android.hardware.usb.action.CARPLAY_DEVICE_DETACHED");
        f.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        f.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        f.addAction("android.hardware.usb.action.USB_STATE");
        f.addAction("com.hkmc.intent.action.SYSTEM_POWERON");
        context.registerReceiver(events,f,null,main);
        IntentFilter stop=new IntentFilter("kr.gen5w.wireless.STOP_BRIDGE");
        stop.addAction(Intent.ACTION_SHUTDOWN);
        context.registerReceiver(stopReceiver,stop,"android.permission.SHUTDOWN",main);
        refreshWired();bind();main.post(tick);
    }
    void bind() {
        if(bound || shuttingDown)return;
        try { bound=context.bindService(new Intent("com.remote.service.IAP2SERVICE").setPackage("com.tcc.iap2server"),connection,Context.BIND_AUTO_CREATE); }
        catch(RuntimeException e){log("bind unavailable: "+e.getClass().getName());}
    }
    final ServiceConnection connection=new ServiceConnection(){
        public void onServiceConnected(ComponentName name,IBinder binder){
            if(shuttingDown)return;
            server=name;iap=IIap2Service.Stub.asInterface(binder);registered=false;register();
        }
        public void onServiceDisconnected(ComponentName name){
            iap=null;registered=false;server=null;listener=null;
            session.environment(false,cable,false,now());
        }
    };
    void register(){
        if(iap==null || registered)return;
        try {
            if(listener!=null){iap.Iap2SvcStopMain(listener);listener=null;}
            Iap2ListenerInfo info=new Iap2ListenerInfo();
            info.onSetListenerName("gen5wkr.wireless");info.onSetSupportType(0x4401);
            IIap2Listener created=createListener(-1);
            registered=iap.Iap2SvcInit(created,info);
            if(registered)listener=created;
        } catch(Exception e){log("listener registration unavailable");}
    }
    final Runnable tick=new Runnable(){public void run(){
        if(shuttingDown)return;
        try {
            refreshWired();bind();register();
            boolean foreign=iap!=null && iap.Iap2SvcIsIap2Connected() && !nativeRequested;
            session.environment(registered,cable,foreign,now());
            scan();session.tick(now());flush();retryProvision(false);retryProjection();
        }catch(Exception e){log("service polling unavailable");}
        main.postDelayed(this,1000);
    }};
    void scan(){
        if(adapter==null || !adapter.isEnabled())return;
        // This OEM API exists on KitKat; BluetoothDevice.isConnected does not.
        // Recover a connection established before our boot receiver/daemon ran.
        String hfp=null;
        try{hfp=(String)adapter.getClass().getMethod("getConnectedHfpAddr").invoke(adapter);}
        catch(Exception ignored){}
        for(BluetoothDevice d:adapter.getBondedDevices()){
            boolean connected=linked.contains(d.getAddress()) || d.getAddress().equalsIgnoreCase(hfp);
            if(!connected)try{connected=(Boolean)d.getClass().getMethod("isConnected").invoke(d);}catch(Exception ignored){}
            if(connected)connected(d);
        }
    }
    void connected(BluetoothDevice d){
        if(d==null)return;
        String address=d.getAddress();
        if(linked.add(address)){
            sdpRefresh.reset(address);advertised.remove(address);selectedService.remove(address);failedService.remove(address);
            session.lost(address,now());
        }
        consider(d);
    }
    void consider(BluetoothDevice d){
        consider(d,false);
    }
    void consider(BluetoothDevice d,boolean freshSdpResult){
        if(d==null || d.getBondState()!=BluetoothDevice.BOND_BONDED)return;
        String address=d.getAddress();
        if(!sdpRefresh.ready(address)){
            long time=now();
            if(sdpRefresh.begin(address,time)){
                boolean requested=false;
                try{requested=d.fetchUuidsWithSdp();}catch(RuntimeException ignored){}
                if(!requested){
                    sdpRefresh.complete(address,time,false);
                    log("iAP SDP refresh request unavailable");
                }else log("iAP SDP refresh requested");
            }
            return;
        }
        ParcelUuid[] uuids=d.getUuids();
        if(uuids==null){
            sdpRefresh.complete(address,now(),false);
            log("iAP SDP result unavailable");
            return;
        }
        boolean caff=false,cafe=false;
        for(ParcelUuid uuid:uuids){
            if(uuid==null)continue;
            if(WIRELESS.equals(uuid.getUuid()))caff=true;
            if(WIRELESS_FALLBACK.equals(uuid.getUuid()))cafe=true;
        }
        Integer previous=failedService.get(address);
        int selected=WirelessSession.selectIapService(caff,cafe,previous==null?0:previous.intValue());
        Integer oldSelection=selectedService.put(address,Integer.valueOf(selected));
        boolean selectionChanged=oldSelection==null || oldSelection.intValue()!=selected;
        UUID chosen=selected==1?WIRELESS:selected==2?WIRELESS_FALLBACK:null;
        if(chosen!=null){
            advertised.put(address,chosen);
            if(freshSdpResult || selectionChanged)
                log("iAP SDP result caff="+caff+" cafe="+cafe+" selected="+(selected==1?"caff":"cafe"));
            session.candidate(address,now());
        }else{
            advertised.remove(address);
            failedService.remove(address);
            if(freshSdpResult || selectionChanged)log("iAP SDP result has no supported service");
            if(selectionChanged)session.lost(address,now());
        }
    }
    final BroadcastReceiver events=new BroadcastReceiver(){public void onReceive(Context c,Intent i){
        String action=i.getAction();BluetoothDevice d=(BluetoothDevice)i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
        if(BluetoothDevice.ACTION_ACL_CONNECTED.equals(action)){
            if(d!=null)connected(d);
        }else if(BluetoothDevice.ACTION_ACL_DISCONNECTED.equals(action)){
            if(d!=null){linked.remove(d.getAddress());sdpRefresh.reset(d.getAddress());advertised.remove(d.getAddress());selectedService.remove(d.getAddress());failedService.remove(d.getAddress());session.lost(d.getAddress(),now());}
        }else if(BluetoothDevice.ACTION_UUID.equals(action)){
            if(d!=null && linked.contains(d.getAddress())){sdpRefresh.complete(d.getAddress(),now(),true);consider(d,true);}
        }else if(action!=null && action.endsWith("profile.action.CONNECTION_STATE_CHANGED")){
            int state=i.getIntExtra("android.bluetooth.profile.extra.STATE",-1);
            if(d!=null && state==2)connected(d);
            // A profile disconnect is not an ACL disconnect. RFCOMM may remain active.
        }else if("android.hardware.usb.action.CARPLAY_DEVICE_ATTACHED".equals(action)){
            carplayCable.event(action,false);refreshWired();
        }else if("android.hardware.usb.action.CARPLAY_DEVICE_DETACHED".equals(action)){
            carplayCable.event(action,false);refreshWired();
        }else if("android.hardware.usb.action.USB_STATE".equals(action)){
            // USB_STATE describes this unit's device-mode link, not a phone
            // detached from its USB host port.
            refreshWired();
        }else if(UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action) || UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)){
            UsbDevice usb=(UsbDevice)i.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            carplayCable.event(action,usb!=null && usb.getVendorId()==0x05ac);
            refreshWired();
            // Pause even if the host inventory has not caught up with this event.
            if(UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action) && usb!=null && (usb.getVendorId()==0x05ac || usb.getVendorId()==0x18d1)) {
                cable=true;session.environment(registered,true,false,now());
            }
        }
        else if(BluetoothAdapter.ACTION_STATE_CHANGED.equals(action) && i.getIntExtra(BluetoothAdapter.EXTRA_STATE,0)!=BluetoothAdapter.STATE_ON){
            session.shutdown();linked.clear();sdpRefresh.clear();advertised.clear();selectedService.clear();failedService.clear();
        }else if("com.hkmc.intent.action.SYSTEM_POWERON".equals(action)){
            session.shutdown();linked.clear();sdpRefresh.clear();advertised.clear();selectedService.clear();failedService.clear();registered=false;
        }
    }};
    public void open(final long g,final String address){
        final UUID service=advertised.get(address);
        BluetoothSocket previous; synchronized(this){previous=transport.reserve(g);}
        closeSocket(previous);
        new Thread(new Runnable(){public void run(){
            BluetoothSocket opened=null;
            String stage="socket-setup";
            try{
                if(adapter==null || service==null)throw new IllegalStateException();
                requireCurrent(g);
                opened=adapter.getRemoteDevice(address).createRfcommSocketToServiceRecord(service);
                synchronized(WirelessBridge.this){requireCurrent(g);if(!transport.attach(g,opened))throw new IllegalStateException();}
                adapter.cancelDiscovery();stage="socket-connect";opened.connect();
                stage="ap-setup";requireCurrent(g);ensureHotspot(g);requireCurrent(g);
                final BluetoothSocket ready=opened;
                main.post(new Runnable(){public void run(){
                    if(session.current(g) && transport.owns(g,ready)){
                        session.socket(g,now());
                        if(session.current(g) && transport.owns(g,ready))read(g,ready);else closeSocket(ready);
                    }
                    else closeSocket(ready);
                }});
            }catch(Exception e){
                closeSocket(opened);
                log("transport failure stage="+stage+" type="+e.getClass().getName());
                if("socket-connect".equals(stage) && e instanceof java.io.IOException){
                    final int failed=WIRELESS.equals(service)?1:2;
                    log("socket error kind="+WirelessSession.socketErrorKind(e.getMessage()));
                    main.post(new Runnable(){public void run(){
                        if(session.current(g)){
                            failedService.put(address,Integer.valueOf(failed));
                            log("socket service="+(failed==1?"caff":"cafe")+" failed; retrying advertised alternative if available");
                            session.failed(g,now());
                        }
                    }});
                } else fail(g,"transport open failed");
            }
        }},"gen5w-bt-open").start();
    }
    public void start(long g){
        try{
            refreshWired();
            if(iap==null || server==null)throw new IllegalStateException();
            // Reserve callback provenance before asynchronous native creation.
            if(!session.current(g) || cable || iap.Iap2SvcIsIap2Connected())throw new IllegalStateException();
            if(listener!=null)iap.Iap2SvcStopMain(listener);
            registered=false;listener=null;
            Iap2ListenerInfo info=new Iap2ListenerInfo();
            info.onSetListenerName("gen5wkr.wireless");info.onSetSupportType(0x4401);
            IIap2Listener created=createListener(g);
            if(!iap.Iap2SvcInit(created,info))throw new IllegalStateException();
            listener=created;registered=true;
            if(cable || iap.Iap2SvcIsIap2Connected())throw new IllegalStateException();
            nativeRequested=true;
            if(context.startService(new Intent().setComponent(server).putExtra(COMPONENT,3))==null)throw new IllegalStateException();
        }catch(Exception e){fail(g,"native start unavailable");}
    }
    void read(final long g,final BluetoothSocket ready){
        new Thread(new Runnable(){public void run(){
            try{
                InputStream in=ready.getInputStream();byte[] buffer=new byte[8192];int count;
                while((count=in.read(buffer))!=-1){
                    if(queuedBytes.addAndGet(count)>262144){queuedBytes.addAndGet(-count);fail(g,"transport input overflow");return;}
                    final byte[] data=new byte[count];System.arraycopy(buffer,0,data,0,count);
                    if(!main.post(new Runnable(){public void run(){
                        if(!session.current(g)){queuedBytes.addAndGet(-data.length);return;}
                        pending.add(data);pendingBytes+=data.length;flush();
                    }})){queuedBytes.addAndGet(-count);return;}
                }
                fail(g,"transport closed");
            }catch(Exception e){fail(g,"transport read failed");}
        }},"gen5w-bt-read").start();
    }
    void flush(){
        if(iap==null || !nativeRequested)return;
        try{
            if(!iap.Iap2SvcIsIap2Connected())return;
            while(!pending.isEmpty()){
                byte[] data=pending.remove();pendingBytes-=data.length;queuedBytes.addAndGet(-data.length);
                // Stock Java returns false after successfully feeding native.
                iap.Iap2SvcTransportReadDone(data,data.length);
            }
        }catch(Exception e){fail(session.generation(),"native input failed");}
    }
    IIap2Listener createListener(final long g){
        final AtomicInteger outgoing=new AtomicInteger();
        return new IIap2Listener.Stub(){
        public void connected(int type,String ignored){}
        public void disconnected(int type){fail(g,"native disconnected");}
        public void notify(final int what,int a,int b,Iap2NotiMsg message){
            if(!transport.current(g))return;
            final byte[] data=what==0x50?blob(message):null;
            if(data!=null && outgoing.addAndGet(data.length)>262144){
                outgoing.addAndGet(-data.length);fail(g,"transport output overflow");return;
            }
            if(!main.post(new Runnable(){public void run(){
                if(!session.current(g)){if(data!=null)outgoing.addAndGet(-data.length);return;}
                if(what==0x50){if(data==null)fail(g,"invalid transport output");else write(g,data,outgoing);}
                else if(what==5)session.authenticated(g,now());
                else if(what==0)retryProvision(true);
                else if(what==4 || what==7 || what==0x32 || what==0x33)fail(g,"native session failed");
            }})){if(data!=null)outgoing.addAndGet(-data.length);}
        }
    };}
    static byte[] blob(Iap2NotiMsg message){
        if(message==null)return null;
        try{
            Iap2NotiMsg.Iap2ObjGroup group=message.getItemGroup();
            if(group==null || group.getItemCnt()>16)return null;
            for(int i=0;i<group.getItemCnt();i++){
                Iap2NotiMsg.Iap2ObjItem item=group.getObjItem(i);
                if(item!=null && item.getItemId()==1 && item.getItemParamType()==11){
                    byte[] b=item.getItemByteArray();return b!=null && b.length<=65536?b.clone():null;
                }
            }
        }catch(RuntimeException ignored){}
        return null;
    }
    void write(final long g,final byte[] data,final AtomicInteger budget){
        final BluetoothSocket target=transport.get(g);
        try{writes.execute(new Runnable(){public void run(){
            try{
                if(target==null || !transport.owns(g,target))return;
                OutputStream out=target.getOutputStream();out.write(data);out.flush();
            }catch(Exception e){fail(g,"transport write failed");}
            finally{budget.addAndGet(-data.length);}
        }});}catch(RuntimeException e){budget.addAndGet(-data.length);fail(g,"transport output overflow");}
    }
    public void authenticated(long g){
        try{
            if(!session.current(g) || cable)return;
            long started=now();
            provisionGeneration=g;provisionDeadline=started+15000;provisionNext=started;
            projectionGeneration=g;projectionDeadline=started+15000;projectionNext=started+1000;
            // Its control receiver is registered dynamically by DipoService.
            // Wake the exported stock service before the retrying dispatch.
            if(context.startService(new Intent().setComponent(new ComponentName(PROJECTION_PACKAGE,
                    PROJECTION_PACKAGE+".service.DipoService")))==null)throw new IllegalStateException();
            context.sendBroadcast(new Intent(PROJECTION_ACTION).setPackage(PROJECTION_PACKAGE));
            retryProvision(true);log("authenticated; wireless provisioning and projection pending");
        }
        catch(Exception e){fail(g,"wireless provisioning unavailable");}
    }
    public void close(long g,boolean stopNative){
        boolean requested=nativeRequested;
        nativeRequested=false;projectionGeneration=-1;provisionGeneration=-1;pending.clear();queuedBytes.addAndGet(-pendingBytes);pendingBytes=0;writes.getQueue().clear();
        BluetoothSocket prior=null;
        synchronized(this){prior=transport.detach(g);}
        closeSocket(prior);
        if(iap!=null && listener!=null)try{iap.Iap2SvcStopMain(listener);}catch(Exception ignored){}
        listener=null;registered=false;
        if(stopNative && requested && !cable && server!=null)try{context.startService(new Intent().setComponent(server).putExtra(COMPONENT,-3));}
        catch(RuntimeException e){log("native stop unavailable");}
    }
    void requireCurrent(long g) {
        if(shuttingDown || cable || !transport.current(g))throw new IllegalStateException();
    }
    /** USB host discovery and stock USB mode can precede the CarPlay broadcast. */
    void refreshWired() {
        boolean present=carplayCable.attached();
        try {
            UsbManager usb=(UsbManager)context.getSystemService(Context.USB_SERVICE);
            if(usb!=null)for(UsbDevice device:usb.getDeviceList().values()) {
                if(device!=null && (device.getVendorId()==0x05ac || device.getVendorId()==0x18d1)){present=true;break;}
            }
        }catch(RuntimeException ignored){}
        try {
            Method get=Class.forName("android.os.SystemProperties").getMethod("get",String.class);
            present |= WirelessSession.wiredConfiguration((String)get.invoke(null,"sys.usb.config"))
                    || WirelessSession.wiredConfiguration((String)get.invoke(null,"sys.usb.state"));
        }catch(Exception ignored){}
        if(cable!=present){
            cable=present;
            session.environment(registered,cable,false,now());
            if(!cable){scan();session.tick(now());}
        }
    }
    void ensureHotspot(final long g) throws Exception{
        requireCurrent(g);
        ApProfiles.Guard guard=new ApProfiles.Guard(){
            public void check(){requireCurrent(g);}
        };
        ApBrokerClient.ensure(guard);
        requireCurrent(g);
    }
    void retryProvision(boolean force){
        long g=provisionGeneration;
        if(g<0 || !session.current(g) || cable || shuttingDown){provisionGeneration=-1;return;}
        long time=now();
        if(time>=provisionDeadline){provisionGeneration=-1;fail(g,"wireless provisioning request unavailable");return;}
        if(!force && time<provisionNext)return;
        provisionNext=time+1000;
        try{
            if(iap!=null && iap.Iap2SvcWiFiRequestInformation()){
                provisionGeneration=-1;log("wireless provisioning request accepted; phone connection unverified");
            }
        }catch(Exception e){fail(g,"wireless provisioning unavailable");}
    }
    void retryProjection(){
        long g=projectionGeneration;
        if(g<0 || !session.current(g) || cable || shuttingDown){projectionGeneration=-1;return;}
        if(listening("/proc/net/tcp") || listening("/proc/net/tcp6")){projectionGeneration=-1;return;}
        if(now()>=projectionDeadline){projectionGeneration=-1;fail(g,"projection listener unavailable");return;}
        if(now()<projectionNext)return;
        projectionNext=now()+1000;
        context.sendBroadcast(new Intent(PROJECTION_ACTION).setPackage(PROJECTION_PACKAGE));
    }
    static boolean listening(String path){
        BufferedReader reader=null;
        try{
            reader=new BufferedReader(new FileReader(path));String line;
            while((line=reader.readLine())!=null){
                if(WirelessSession.projectionListening(line))return true;
            }
        }catch(Exception ignored){}finally{if(reader!=null)try{reader.close();}catch(Exception ignored){}}
        return false;
    }
    void fail(final long g,final String reason){main.post(new Runnable(){public void run(){
        if(session.current(g)){log(reason);session.failed(g,now());}
    }});}
    void shutdown(){
        if(shuttingDown)return;
        shuttingDown=true;session.shutdown();writes.shutdownNow();
        main.removeCallbacks(tick);
        if(iap!=null && listener!=null)try{iap.Iap2SvcStopMain(listener);}catch(Exception ignored){}
        if(bound)try{context.unbindService(connection);}catch(RuntimeException ignored){}
        try{context.unregisterReceiver(events);}catch(RuntimeException ignored){}
        try{context.unregisterReceiver(stopReceiver);}catch(RuntimeException ignored){}
        if(context instanceof Service)((Service)context).stopSelf();
    }
    static void closeSocket(BluetoothSocket s){if(s!=null)try{s.close();}catch(Exception ignored){}}
    static long now(){return SystemClock.elapsedRealtime();}
    static void log(String text){Log.i(TAG,text);}
}
