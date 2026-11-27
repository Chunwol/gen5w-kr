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
        session.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,1),n(3,2),n(8,0),n(9,0),n(11,90)));
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(1,1),list(1),n(10,350)));
        check(out.icon==0x43 && out.meters==350);
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(10,300)));
        check(out.meters==300);int sent=out.calls;
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0)));
        check(out.meters==300 && out.calls==sent);
        session.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),list(2)));
        check(out.icon==0 && out.meters==-1);
        session.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,2),n(3,1),n(5,999),n(8,0),n(9,0),n(11,-90)));
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
        retry.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,1),n(3,2),n(8,0),n(9,0),n(11,90)));
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
        check(TurnFrame.tbtDistanceValue(-1L)==0f && TurnFrame.tbtDistanceScale(-1L)==TurnFrame.SCALE_METER && TurnFrame.tbtDistanceError(-1L)==TurnFrame.DIST_ERR_UNKNOWN);
        check(TurnFrame.tbtDistanceValue(350L)==350f && TurnFrame.tbtDistanceScale(350L)==TurnFrame.SCALE_METER && TurnFrame.tbtDistanceError(350L)==TurnFrame.DIST_ERR_OK);
        check(TurnFrame.tbtDistanceValue(999L)==999f && TurnFrame.tbtDistanceScale(999L)==TurnFrame.SCALE_METER && TurnFrame.tbtDistanceError(999L)==TurnFrame.DIST_ERR_OK);
        check(TurnFrame.tbtDistanceValue(1000L)==1.0f && TurnFrame.tbtDistanceScale(1000L)==TurnFrame.SCALE_KILOMETER);
        check(TurnFrame.tbtDistanceValue(1900L)==1.9f && TurnFrame.tbtDistanceScale(1900L)==TurnFrame.SCALE_KILOMETER);
        check(TurnFrame.tbtDistanceValue(80000L)==80.0f && TurnFrame.tbtDistanceScale(80000L)==TurnFrame.SCALE_KILOMETER && TurnFrame.tbtDistanceError(80000L)==TurnFrame.DIST_ERR_OK);
        check(TurnFrame.tbtDistanceValue(4294967295L)==32767.9f && TurnFrame.tbtDistanceScale(4294967295L)==TurnFrame.SCALE_KILOMETER);
        check(TurnFrame.TBT_DISPLAY_IDLE==8 && TurnFrame.tbtDisplayType(0)==8 && TurnFrame.tbtDisplayType(-1)==8 && TurnFrame.tbtDisplayType(0x46)==0x46);
        check(TurnFrame.effectiveIcon(0x43, 6000L)==0x43 && TurnFrame.effectiveIcon(0x43, 3000L)==0x43 && TurnFrame.effectiveIcon(0x43, -1L)==0x43 && TurnFrame.effectiveIcon(0, 6000L)==0);
        check(TurnFrame.tbtBarGraphError(0, -1L)==TurnFrame.BAR_ERR_INVALID && TurnFrame.tbtBarGraphLevel(0, -1L)==0);
        check(TurnFrame.tbtBarGraphError(0x43, 500L)==TurnFrame.BAR_ERR_INVALID && TurnFrame.tbtBarGraphLevel(0x43, 500L)==0);
        check(TurnFrame.tbtBarGraphError(0x43, 400L)==TurnFrame.BAR_ERR_OK && TurnFrame.tbtBarGraphLevel(0x43, 400L)==100);
        check(TurnFrame.tbtBarGraphError(0x43, 200L)==TurnFrame.BAR_ERR_OK && TurnFrame.tbtBarGraphLevel(0x43, 200L)==50);
        check(TurnFrame.tbtBarGraphError(0x43, 30L)==TurnFrame.BAR_ERR_OK && TurnFrame.tbtBarGraphLevel(0x43, 30L)==10);
        check(TurnFrame.tbtBarGraphError(0x43, 0L)==TurnFrame.BAR_ERR_OK && TurnFrame.tbtBarGraphLevel(0x43, 0L)==10);
        // Stock V039 drive curve (guideDist=340m): 290->80, 250->70, 240->70, 90->20, 60->10, 5->10.
        check(TurnFrame.tbtBarGraphLevel(0x43, 290L, true, 340L)==80 && TurnFrame.tbtBarGraphLevel(0x43, 250L, true, 340L)==70);
        check(TurnFrame.tbtBarGraphLevel(0x43, 240L, true, 340L)==70 && TurnFrame.tbtBarGraphLevel(0x43, 90L, true, 340L)==20);
        check(TurnFrame.tbtBarGraphLevel(0x43, 60L, true, 340L)==10 && TurnFrame.tbtBarGraphLevel(0x43, 5L, true, 340L)==10);
        check(TurnFrame.tbtBarGraphError(0x43, 450L, false)==TurnFrame.BAR_ERR_INVALID && TurnFrame.tbtBarGraphLevel(0x43, 450L, false, 340L)==0);
        // Audit P3: saturate before rounding so huge AA distances cannot wrap.
        check(TurnFrame.subInfo2CWhole(Long.MAX_VALUE)==65534 && TurnFrame.subInfo2CTenths(Long.MAX_VALUE)==9);
        check(TurnFrame.subInfo2CWhole(65534900L)==65534 && TurnFrame.subInfo2CTenths(65534900L)==9);
        check(TurnFrame.subInfo2CWhole(99999999999L)==65534 && TurnFrame.subInfo2CTenths(99999999999L)==9);
        // 0x40 draws the cluster spinner: never sent, straight-ahead instead.
        check(TurnFrame.effectiveIcon(0x40, 100L)==0x41 && TurnFrame.encode(new int[]{0x40, 0x40}, "")[2]==0x41
                && TurnFrame.encode(new int[]{0x43, 0x40}, "")[3]==0x41);
        check(TurnFrame.subInfo2CUnit(-1L)==15 && TurnFrame.subInfo2CTenths(-1L)==15 && TurnFrame.subInfo2CWhole(-1L)==65535);
        check(TurnFrame.subInfo2CUnit(350L)==0 && TurnFrame.subInfo2CTenths(350L)==0 && TurnFrame.subInfo2CWhole(350L)==350);
        check(TurnFrame.subInfo2CUnit(1900L)==1 && TurnFrame.subInfo2CTenths(1900L)==9 && TurnFrame.subInfo2CWhole(1900L)==1);
        check(TurnFrame.subInfo2CUnit(1999L)==1 && TurnFrame.subInfo2CTenths(1999L)==0 && TurnFrame.subInfo2CWhole(1999L)==2);
        // Stock >3km straight-ahead threshold in GuidanceSession
        Output farOut=new Output();GuidanceSession farSession=new GuidanceSession(farOut);
        farSession.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,1),n(3,2),n(8,0),n(9,0),n(11,90)));
        farSession.message(GuidanceParser.MANEUVER,Arrays.asList(n(0,0),n(1,2),n(3,1),n(8,0),n(9,0),n(11,-90)));
        farSession.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(1,1),list(1,2),n(10,6000)));
        check(farOut.icon==0x43 && farOut.secondIcon==0x46 && (farOut.turnFrame[2]&255)==0x43 && (farOut.turnFrame[3]&255)==0x46);
        farSession.message(GuidanceParser.STATUS,Arrays.asList(n(0,0),n(1,1),list(1,2),n(10,3000)));
        check(farOut.icon==0x43 && farOut.secondIcon==0x46 && (farOut.turnFrame[2]&255)==0x43 && (farOut.turnFrame[3]&255)==0x46);
        System.out.println("TbtDistanceTest "+checks+" assertions passed");
    }
}
