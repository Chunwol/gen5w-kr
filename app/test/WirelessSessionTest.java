import kr.gen5w.wireless.WirelessSession;
public final class WirelessSessionTest {
    static int n;
    static void check(boolean b) { n++; if(!b) throw new AssertionError("wireless assertion "+n); }
    static final class Fake implements WirelessSession.Port {
        int open,start,close,auth,stop; long ticket; String address;
        public void open(long g,String a){open++;ticket=g;address=a;}
        public void start(long g){start++;}
        public void close(long g,boolean nativeOwned){close++;if(nativeOwned)stop++;}
        public void authenticated(long g){auth++;}
    }
    public static void main(String[] args) throws Exception {
        WirelessSession.WiredSignal cableSignal = new WirelessSession.WiredSignal();
        cableSignal.event("android.hardware.usb.action.CARPLAY_DEVICE_ATTACHED", false);
        cableSignal.event("android.hardware.usb.action.USB_STATE", false);
        check(cableSignal.attached());
        cableSignal.event("android.hardware.usb.action.USB_DEVICE_DETACHED", false);
        check(cableSignal.attached());
        cableSignal.event("android.hardware.usb.action.CARPLAY_DEVICE_DETACHED", false);
        check(!cableSignal.attached());
        cableSignal.event("android.hardware.usb.action.CARPLAY_DEVICE_ATTACHED", false);
        cableSignal.event("android.hardware.usb.action.USB_DEVICE_DETACHED", true);
        check(!cableSignal.attached());
        Fake p=new Fake();WirelessSession s=new WirelessSession(p);
        s.candidate("a",0);s.tick(0);check(p.open==0);
        s.environment(true,false,false,0);s.tick(0);check(p.open==1);long g=p.ticket;
        s.candidate("a",1);s.tick(1);check(p.open==1);
        s.socket(g,2);s.socket(g,3);check(p.start==1);
        s.authenticated(g);s.authenticated(g);check(p.auth==1);
        s.candidate("b",5);s.lost("b",6);check(s.current(g));
        s.environment(true,true,false,10);check(p.stop==0);check(!s.current(g));
        s.authenticated(g);check(p.auth==1);s.tick(100000);check(p.open==1);
        s.environment(true,false,false,100001);s.tick(100001);check(p.open==2);
        long second=p.ticket;s.failed(second,100002);check(p.close==2);check(p.stop==0);
        s.tick(102001);check(p.open==2);s.tick(102002);check(p.open==3);
        s.socket(p.ticket,102003);s.environment(false,false,false,102004);check(p.stop==1);
        s.environment(true,false,true,104005);s.tick(200000);check(p.open==3);
        s.environment(true,false,false,200001);s.tick(200001);check(p.open==4);
        long timeout=p.ticket;s.tick(260001);check(!s.current(timeout));check(p.close==4);
        s.lost("a",215002);s.tick(300000);check(p.open==4);
        s.candidate("b",300001);s.tick(300001);check(p.open==5);
        s.socket(p.ticket,300002);s.tick(345002);check(p.stop==2);
        s.shutdown();s.tick(900000);check(p.open==5);
        // Late completion before the timer tick must still respect the deadline.
        Fake q=new Fake();WirelessSession late=new WirelessSession(q);
        late.environment(true,false,false,0);late.candidate("a",0);late.tick(0);
        long expired=q.ticket;late.socket(expired,60000);
        check(q.start==0);check(q.close==1);check(!late.current(expired));
        late.tick(62000);check(q.open==2);long auth=q.ticket;
        late.socket(auth,62001);late.authenticated(auth,107001);
        check(q.auth==0);check(q.stop==1);check(!late.current(auth));
        late.tick(111001);long active=q.ticket;late.socket(active,111002);
        late.environment(true,false,true,111003);
        check(q.stop==1);check(!late.current(active)); // never stop a foreign native session
        late.authenticated(active,111004);late.failed(active,111005);check(q.close==3);
        // The exact Resource implementation used by Android workers is exercised here.
        final WirelessSession.Resource<Object> lease=new WirelessSession.Resource<Object>();
        final Object oldSocket=new Object(),newSocket=new Object();
        lease.reserve(7);
        final java.util.concurrent.CountDownLatch release=new java.util.concurrent.CountDownLatch(1);
        final boolean[] attached={true};
        Thread delayed=new Thread(new Runnable(){public void run(){
            try{release.await();attached[0]=lease.attach(7,oldSocket);}
            catch(InterruptedException e){throw new AssertionError(e);}
        }});
        delayed.start();check(lease.detach(7)==null);lease.reserve(8);
        check(lease.attach(8,newSocket));release.countDown();delayed.join(5000);
        check(!delayed.isAlive());check(!attached[0]);check(lease.get(8)==newSocket);
        check(lease.detach(7)==null);check(lease.owns(8,newSocket));
        check(!lease.attach(8,oldSocket));check(lease.detach(8)==newSocket);
        check(!lease.current(8));check(!lease.attach(8,oldSocket));
        lease.reserve(9);lease.detach(9);check(!lease.attach(9,oldSocket));
        check(!lease.current(-1));
        check(WirelessSession.projectionListening(" 0: 00000000:1B58 00000000:0000 0A 00000000:00000000"));
        check(WirelessSession.projectionListening(" 1: 00000000000000000000000000000000:1B58 00000000000000000000000000000000:0000 0A"));
        check(!WirelessSession.projectionListening(" 0: 00000000:1234 00000000:1B58 0A"));
        check(!WirelessSession.projectionListening(" 0: 00000000:1B58 00000000:0000 01"));
        check(!WirelessSession.projectionListening("sl local_address rem_address st"));
        check(!WirelessSession.projectionListening(null));
        // Periodic discovery of a second linked phone must not reset retry delay.
        Fake multi=new Fake(); WirelessSession phones=new WirelessSession(multi);
        phones.environment(true,false,false,0);phones.candidate("a",0);phones.tick(0);
        phones.failed(multi.ticket,1);
        phones.candidate("b",1000);phones.candidate("a",1000);phones.tick(1000);
        check(multi.open==1);
        phones.tick(2001);check(multi.open==2);check("a".equals(multi.address));
        phones.failed(multi.ticket,2002);
        phones.candidate("b",3000);phones.candidate("a",3000);phones.tick(4002);
        check(multi.open==2); // second failure still requires four seconds
        phones.tick(6002);check(multi.open==3);
        phones.lost("a",6003);phones.candidate("b",6003);phones.tick(6003);
        check(multi.open==4);check("b".equals(multi.address));check(phones.current(multi.ticket));
        check(WirelessSession.wiredConfiguration("carplay_connect"));
        check(WirelessSession.wiredConfiguration("adb,carplay_connect"));
        check(!WirelessSession.wiredConfiguration("carplay_disconnect"));
        check(!WirelessSession.wiredConfiguration("wireless_carplay_connect"));
        check(!WirelessSession.wiredConfiguration(null));
        System.out.println("WirelessSessionTest "+n+" assertions passed");
    }
}
