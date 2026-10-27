import java.util.Arrays;
import kr.gen5w.hud.*;
import kr.gen5w.probe.Item;
public final class TbtDistanceTest {
    static int checks;
    static void check(boolean value) { checks++; if(!value)throw new AssertionError("TBT "+checks); }
    static final class Output implements GuidanceSession.TbtSink {
        int icon, secondIcon, calls, turnCalls, laneCalls; long meters; boolean accept=true;
        byte[] turnFrame, laneFrame;
        public boolean turns(byte[] frame){turnCalls++;if(accept)turnFrame=frame;return accept;}
        public boolean lanes(byte[] frame){laneCalls++;if(accept)laneFrame=frame;return accept;}
        public boolean tbt(int i, int s, long m){icon=i;secondIcon=s;meters=m;calls++;return accept;}
    }
    static Item n(int id,int value){Item i=new Item();i.id=id;i.ints=new int[]{value};return i;}
    static Item list(int...values){Item i=new Item();i.id=13;i.ints=values;return i;}
    public static void main(String[]args){
        Output out=new Output();GuidanceSession session=new GuidanceSession(out);
        session.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,1),n(3,2)));
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(1,1),list(1),n(10,350)));
        check(out.icon==0x43 && out.meters==350);
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(10,300)));
        check(out.meters==300);int sent=out.calls;
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0)));
        check(out.meters==300 && out.calls==sent);
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),list(2)));
        check(out.icon==0 && out.meters==-1);
        session.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,2),n(3,1),n(5,999)));
        check(out.icon==0x46 && out.meters==-1); // leg length is not distance remaining
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),list(1, 2)));
        check(out.icon==0x43 && out.secondIcon==0x46);
        Item wide=n(10,-1);wide.type=6;
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),wide));
        check(out.meters==4294967295L);
        out.accept=false;
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(10,200)));
        sent=out.calls;out.accept=true;
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0)));
        check(out.calls==sent+1 && out.meters==200);
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(1,5)));
        check(out.icon==0 && out.meters==-1);
        session.disconnect();check(out.icon==0 && out.meters==-1);
        Output flaky=new Output();GuidanceSession retry=new GuidanceSession(flaky);
        retry.retryOutput();check(flaky.calls==0 && flaky.turnCalls==0 && flaky.laneCalls==0);
        flaky.accept=false;
        retry.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,1),n(3,2)));
        retry.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(1,1),list(1),n(10,150)));
        check(flaky.turnFrame==null);
        flaky.accept=true;retry.retryOutput();
        check(flaky.turnFrame.length==87 && flaky.icon==0x43 && flaky.meters==150);
        int turns=flaky.turnCalls, lanes=flaky.laneCalls, distances=flaky.calls;
        retry.retryOutput();check(flaky.turnCalls==turns && flaky.laneCalls==lanes && flaky.calls==distances);
        retry.invalidateOutput();retry.retryOutput();
        check(flaky.turnCalls==turns+1 && flaky.laneCalls==lanes+1 && flaky.calls==distances+1);
        flaky.accept=false;retry.disconnect();flaky.accept=true;retry.retryOutput();
        check(flaky.turnFrame.length==2 && flaky.laneFrame[1]==0 && flaky.icon==0 && flaky.meters==-1);
        System.out.println("TbtDistanceTest "+checks+" assertions passed");
    }
}
