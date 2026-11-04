import java.util.Arrays;
import kr.gen5w.hud.*;

public final class OwnershipTest {
    static final class Output implements GuidanceSession.TbtSink {
        int turns, lanes, distances, icon;
        byte[] frame;
        public boolean turns(byte[] value) { turns++; frame=value.clone(); return true; }
        public boolean lanes(byte[] value) { lanes++; return true; }
        public boolean tbt(int value,int secondValue,long meters) { distances++; icon=value; return true; }
        int writes() { return turns+lanes+distances; }
    }
    static void check(boolean value,String message) {
        if (!value) throw new AssertionError(message);
    }
    static void route(GuidanceSession session,int turn) {
        Maneuver m=new Maneuver(); m.component=1; m.index=1; m.type=turn; m.afterRoad="road";
        m.drivingSide=0; m.junctionType=0; m.exitAngle=turn==1 ? -90 : turn==2 ? 90 : 0;
        session.maneuver(m);
        GuidanceParser.Status s=new GuidanceParser.Status();
        s.component=1; s.state=1; s.hasState=true; s.hasCurrent=true; s.current=new int[]{1};
        session.status(s);
    }
    public static void main(String[] args) {
        warningCapabilities();
        Output out=new Output(); GuidanceSession session=new GuidanceSession(out);
        session.setOutputAllowed(false);
        route(session,1); session.retryOutput();
        check(out.writes()==0,"unknown ownership must block all output channels");
        session.setOutputAllowed(true); session.retryOutput();
        check(out.turns>0 && out.lanes>0 && out.distances>0,"idle stock navigation resumes all channels");
        byte[] old=out.frame; int count=out.writes();
        session.setOutputAllowed(false); route(session,2); session.retryOutput();
        check(out.writes()==count,"stock guidance blocks incoming changes and retry");
        session.setOutputAllowed(true); session.retryOutput();
        check(!Arrays.equals(old,out.frame),"resume uses newest CarPlay route");
        count=out.writes(); session.setOutputAllowed(false); session.disconnect(); session.retryOutput();
        check(out.writes()==count,"disconnect clears must never erase stock guidance");
        session.setOutputAllowed(true); session.retryOutput();
        check(out.frame.length==2 && out.icon==0,"resume after CarPlay ended clears old CarPlay data");
        AaRouteCache aa = new AaRouteCache();
        aa.setOutputAllowed(true);
        aa.update(0x41, 0, 300, "AA");
        session.setOutputAllowed(aa.allowCarPlay(true));
        count=out.writes();
        session.disconnect(); session.retryOutput();
        check(out.writes()==count,"CarPlay disconnect must not clear active auxiliary AA");
        aa.clear();
        session.setOutputAllowed(aa.allowCarPlay(true));
        session.retryOutput();
        check(out.writes()>count,"CarPlay cleanup can resume after auxiliary AA ends");
        check(!aa.allowCarPlay(false),"unknown or active stock guidance must still block CarPlay");
        System.out.println("ownership transitions passed");
    }
    static void warningCapabilities() {
        check(NativeWarningSupport.inspect(WarningApis.class).equals("APIS_PRESENT_SOURCE_UNOBSERVED"),
                "all native writers identify API presence, never live warning support");
        check(NativeWarningSupport.inspect(PartialWarnings.class).equals("APIS_INCOMPLETE_SOURCE_UNOBSERVED"),
                "partial firmware exposes incomplete warning capability");
        check(NativeWarningSupport.inspect(WrongWarnings.class).equals("APIS_UNAVAILABLE_SOURCE_UNOBSERVED"),
                "static or wrongly typed writers must not identify warning support");
        check(NativeWarningSupport.inspect(null).equals("APIS_UNAVAILABLE_SOURCE_UNOBSERVED"),
                "missing cluster API fails closed");
        check(WarningApis.calls == 0, "capability discovery must never submit warning values");
    }
    public static class WarningApis {
        static int calls;
        public void updateTBTTrapInfo(int a,int b,int c,int d,int e,int f,int g,int h,int i,
                int j,int k,int l,int m,int n,int o,int p,int q) { calls++; }
        public void updateNaviWarnDist(int a,int b,int c) { calls++; }
        public void updateSLIFNaviInformation(int a,int b,int c,int d,int e,int f) { calls++; }
    }
    public static class PartialWarnings {
        public void updateNaviWarnDist2(int a,int b,int c,int d,int e,int f,int g,int h,int i,int j) { }
    }
    public static class WrongWarnings {
        public static void updateNaviWarnDist(int a,int b,int c) { }
        public int updateSLIFNaviInformation(int a,int b,int c,int d,int e) { return 0; }
        public void updateTBTTrapInfo(int a) { }
    }
}
