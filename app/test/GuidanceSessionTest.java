import java.util.Arrays;
import java.util.List;
import kr.gen5w.hud.*;
import kr.gen5w.probe.Item;

public final class GuidanceSessionTest {
    static int passed;
    static final class Sink implements GuidanceSession.LaneSink {
        byte[] turns, lanes;
        int laneWrites;
        boolean rejectLane;
        public boolean lanes(byte[] frame) { laneWrites++; if (rejectLane) return false; lanes = frame.clone(); return true; }
        int writes;
        public boolean turns(byte[] frame) { turns = frame.clone(); writes++; return true; }
    }
    static void check(String name, boolean ok) {
        if (!ok) throw new AssertionError(name);
        passed++; System.out.println("PASS " + name);
    }
    static Maneuver m(int index, int type) {
        Maneuver m = new Maneuver(); m.component = 1; m.index = index;
        m.type = type; m.drivingSide = 0; m.junctionType = 0; m.exitAngle = 0;
        if (type == 1) m.exitAngle = -90;
        else if (type == 2) m.exitAngle = 90;
        m.afterRoad = "도로"; return m;
    }
    static GuidanceParser.Status s(int state, String source, int... indices) {
        GuidanceParser.Status s = new GuidanceParser.Status();
        s.component = 1; s.state = state; s.hasState = true;
        s.source = source; s.hasSource = source != null;
        s.current = indices; s.hasCurrent = true; return s;
    }
    static boolean blank(Sink sink) { return sink.turns != null && sink.turns.length == 2 && sink.turns[0] == (byte)0xf2 && sink.turns[1] == 0; }
    static Item n(int id, int... values) { Item it = new Item(); it.id = id; it.ints = values; return it; }
    public static void main(String[] args) throws Exception {
        Sink sink = new Sink(); GuidanceSession session = new GuidanceSession(sink);
        session.maneuver(m(7, 1));
        check("no output before route status", sink.writes == 0);
        session.status(s(1, "지도 A", 7));
        check("selected maneuver reaches turn frame", sink.turns.length == 87 && (sink.turns[2] & 255) == 0x46);
        int writes = sink.writes;
        session.status(s(1, "지도 A", 7));
        check("duplicate frame not resent", sink.writes == writes);
        session.status(s(5, "지도 A", 7));
        check("reroute clears previous arrow", blank(sink));
        session.status(s(1, "지도 A", 7));
        check("reroute cannot resurrect cached maneuver", blank(sink));
        session.maneuver(m(7, 2));
        check("fresh maneuver after reroute displays", (sink.turns[2] & 255) == 0x43);
        session.status(s(1, "지도 B", 7));
        check("map app change invalidates old cache", blank(sink));
        session.maneuver(m(7, 3));
        check("new app maneuver displays", (sink.turns[2] & 255) == 0x41);
        session.status(s(1, "지도 B", 8));
        check("missing selected index clears old arrow", blank(sink));
        session.maneuver(m(8, 999));
        check("unsupported maneuver remains blank", blank(sink));
        session.maneuver(m(8, 2));
        GuidanceParser.Status delta = new GuidanceParser.Status(); delta.component = 1;
        session.status(delta);
        check("omitted state and selection preserve current guidance", (sink.turns[2] & 255) == 0x43);
        session.disconnect();
        check("disconnect clears", blank(sink));
        session.status(s(1, "지도 B", 8));
        check("reconnect cannot revive old maneuver", blank(sink));
        for (int state : new int[]{0,2,3,4,5,77}) {
            session.maneuver(m(8, 1)); session.status(s(1, "지도 B", 8)); session.status(s(state, "지도 B", 8));
            check("non-guidance state clears " + state, blank(sink));
        }
        Maneuver missing = m(0,1); missing.exitAngle = Maneuver.UNKNOWN_ANGLE;
        check("missing angle uses the type's default icon", ClusterIcon.of(missing) == 0x46);
        missing.drivingSide = Maneuver.UNKNOWN_DRIVING_SIDE;
        check("missing angle and side is not guessed", ClusterIcon.of(missing) == ClusterIcon.NONE);
        Maneuver curve = m(0,1); curve.exitAngle = -77;
        check("non-stock curve angle is not guessed", ClusterIcon.of(curve) == ClusterIcon.NONE);
        curve.exitAngle = -25;
        check("shallow text-free angle is not guessed", ClusterIcon.of(curve) == ClusterIcon.NONE);
        check("known unsupported type returns none", ClusterIcon.of(m(0,999)) == ClusterIcon.NONE);
        byte[] frame = TurnFrame.encode(new int[]{0x46,0x43,0x41}, "한글");
        check("turn frame header and icon slots", frame.length == 87 && frame[0] == (byte)0xf2 && frame[1] == 3 && frame[4] == 0x41);
        check("turn frame text is UTF-16LE", frame[5] == (byte)0x5c && frame[6] == (byte)0xd5);
        check("invalid first icon clears frame", Arrays.equals(TurnFrame.encode(new int[]{-1}, "x"), TurnFrame.clear()));
        session.disconnect();
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1,2), n(1,1), n(13,4)));
        session.message(GuidanceParser.MANEUVER, Arrays.asList(n(0,1,2), n(1,4), n(3,2), n(8,0), n(9,0), n(11,90)));
        check("component-id list selects a consistent component", (sink.turns[2] & 255) == 0x43);
        session.message(GuidanceParser.MANEUVER, Arrays.asList(n(1,4), n(5,200)));
        check("partial maneuver update preserves type", (sink.turns[2] & 255) == 0x43);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(1,3)));
        check("component omitted in status uses active component", blank(sink));
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1), n(1,1), n(13,7)));
        session.message(GuidanceParser.MANEUVER, Arrays.asList(n(0,1), n(1,7), n(3,1), n(8,0), n(9,0), n(11,-90)));
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1), n(13)));
        check("empty current list explicitly clears", blank(sink));
        Maneuver exit = m(0, 23); exit.afterRoad = "동탄IC";
        check("explicit interchange exit beats text heuristic", ClusterIcon.of(exit) == ClusterIcon.IC_EXIT_R);
        Maneuver road = m(0, 1); road.afterRoad = "Olympic-daero";
        check("ordinary road containing ic is not an interchange", ClusterIcon.of(road) == 0x46);
        session.disconnect();
        for (int i = 0; i < 128; i++) session.maneuver(m(i,1));
        session.status(s(1, "지도", 0));
        session.maneuver(m(127,2));
        check("updating existing cache entry does not evict selected turn", (sink.turns[2] & 255) == 0x46);
        Maneuver round = m(0, 28); round.junctionType = 1; round.exitAngle = 135;
        check("roundabout uses angle rather than exit ordinal", ClusterIcon.of(round) == 0x64);
        round.type = 46; round.exitAngle = 90;
        check("unsupported nineteenth exit is not interpolated", ClusterIcon.of(round) == ClusterIcon.NONE);
        round.type = 31; round.exitAngle = 0; round.drivingSide = 1;
        check("left-driving stock roundabout code", ClusterIcon.of(round) == 0xc0);
        round.drivingSide = 0; round.exitAngle = Maneuver.UNKNOWN_ANGLE;
        check("unknown roundabout direction clears", ClusterIcon.of(round) == ClusterIcon.NONE);
        round.type = 19; round.exitAngle = -180;
        check("roundabout uturn", ClusterIcon.of(round) == 0x66);
        round = m(0, 15);
        check("ferry icon from stock", ClusterIcon.of(round) == 0xb0);
        round = m(0, 52);
        check("highway change left icon from stock", ClusterIcon.of(round) == 0xae);
        session.disconnect();
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(1,1),n(13,7),n(16,3),n(18,1)));
        session.maneuver(m(7,3));
        Item laneGroup = new Item(); laneGroup.id = 2;
        laneGroup.groups.add(Arrays.asList(n(0,0),n(1,2),n(2,0,90),n(3,90)));
        session.message(GuidanceParser.LANES, Arrays.asList(n(0,1),n(1,3),laneGroup));
        check("selected lane set reaches lane sink", sink.lanes != null && sink.lanes.length == 81 && sink.lanes[0] == (byte)0xf1 && sink.lanes[1] == 1);
        Maneuver overM = m(7, 3); overM.afterRoad = "성산고가차도 진입";
        session.maneuver(overM);
        check("overpass maneuver sets OFF_OVER lane mask in LaneFrame", (sink.turns[2] & 255) == ClusterIcon.OVERPASS_ENTRY_LC && (sink.lanes[LaneBits.OFF_OVER] & 255) == 1);
        session.maneuver(m(7, 3));
        check("returning to normal straight clears OFF_OVER lane mask", (sink.lanes[LaneBits.OFF_OVER] & 255) == 0);
        int laneWrites = sink.laneWrites;
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1)));
        check("unchanged lane frame suppressed", sink.laneWrites == laneWrites);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(16,4)));
        check("missing lane selection clears stale lanes", sink.lanes[1] == 0);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(16,3),n(18,0)));
        check("explicit hidden lane guidance clears", sink.lanes[1] == 0);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(18,1)));
        check("visible lane delta restores selected set", sink.lanes[1] == 1);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(13,8)));
        check("turn transition without fresh lane selection clears", sink.lanes[1] == 0);
        session.disconnect();
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(1,1),n(16,3),n(18,1)));
        check("disconnect discards lane cache", sink.lanes[1] == 0);
        session.message(GuidanceParser.LANES, Arrays.asList(n(0,1),n(1,3),laneGroup));
        check("lane set can display without maneuver list", sink.lanes[1] == 1);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(1,5)));
        check("reroute clears lanes", sink.lanes[1] == 0);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(1,1),n(16,3),n(18,1)));
        check("reroute discards old lane cache", sink.lanes[1] == 0);
        sink.rejectLane = true;
        session.message(GuidanceParser.LANES, Arrays.asList(n(0,1),n(1,3),laneGroup));
        check("failed lane write does not claim display", sink.lanes[1] == 0);
        int beforeRetry = sink.laneWrites; sink.rejectLane = false;
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1)));
        check("failed lane write retried on next update", sink.lanes[1] == 1 && sink.laneWrites == beforeRetry+1);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),text(19,"other app")));
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),text(19,"new app")));
        check("source change clears lanes", sink.lanes[1] == 0);
        session.message(GuidanceParser.STATUS, Arrays.asList(n(0,1),n(16,3),n(18,1)));
        check("source change discarded lane cache", sink.lanes[1] == 0);
        session.message(GuidanceParser.LANES, Arrays.asList(n(0,1),n(1,3),laneGroup));
        session.message(GuidanceParser.LANES, Arrays.asList(n(0,1),n(1,3),n(1,4)));
        check("malformed lane message clears stale frame", sink.lanes[1] == 0);
        NotificationEpoch epoch = new NotificationEpoch();
        check("no notifications accepted before connection", epoch.ticket() == -1);
        long first = epoch.open();
        check("connected ticket valid", epoch.isCurrent(first));
        epoch.close();
        check("disconnect invalidates queued notification", !epoch.isCurrent(first) && epoch.ticket() == -1);
        long second = epoch.open();
        check("reconnect has a fresh generation", second != first && !epoch.isCurrent(first) && epoch.isCurrent(second));
        check("duplicate connected event keeps generation", epoch.open() == second);
        GuidanceRequest request = new GuidanceRequest();
        RequestBackend backend = new RequestBackend();
        check("guidance request waits for link", !request.ensure(-1,backend) && backend.starts == 0);
        check("guidance request waits for advertised components", !request.ensure(1,backend) && backend.starts == 0);
        backend.count = 1;
        check("failed native start stays retryable", !request.ensure(1,backend) && backend.starts == 1);
        backend.accept = true;
        check("guidance request uses discovered component name", request.ensure(1,backend) && "RouteGuidanceComponent0".equals(backend.lastName));
        int starts = backend.starts;
        check("successful request sent once per link", request.ensure(1,backend) && backend.starts == starts);
        check("reconnect requests guidance again", request.ensure(2,backend) && backend.starts == starts+1);
        backend.invalid = true;
        check("malformed native component list not requested", !request.ensure(3,backend) && backend.starts == starts+1);
        System.out.println("guidance session: " + passed + " passed");
    }
    static Item text(int id,String value) { Item it = new Item(); it.id=id; it.strings=new String[]{value}; return it; }
    static final class RequestBackend implements GuidanceRequest.Backend {
        int count, starts; boolean accept, invalid; String lastName;
        public int count() { return count; }
        public int components(int[] ids,String[] names) { ids[0]=0; names[0]=invalid ? null : "RouteGuidanceComponent0"; return 1; }
        public boolean start(String[] names) { starts++; lastName=names[0]; return accept; }
    }
}
