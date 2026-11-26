import java.util.Arrays;
import java.util.List;
import kr.gen5w.hud.*;
import kr.gen5w.probe.Item;

public final class GuidanceSessionTest {
    static int passed;
    static final class Sink implements GuidanceSession.TunnelSink {
        boolean tunnelActive; long tunnelDist = Long.MIN_VALUE; int tunnelWrites; boolean rejectTunnel;
        public boolean tunnel(boolean active, long m) { if (rejectTunnel) return false; tunnelActive = active; tunnelDist = m; tunnelWrites++; return true; }
        long time = Long.MIN_VALUE; int timeWrites;
        public boolean timeRemaining(long s) { time = s; timeWrites++; return true; }
        String dest; int destWrites;
        public boolean destination(String n) { dest = n; destWrites++; return true; }
        long remain = Long.MIN_VALUE; int remainWrites;
        public boolean remaining(long m) { remain = m; remainWrites++; return true; }
        boolean rejectTbt, rejectTurns; int tbtWrites, tbtIcon;
        public boolean tbt(int icon, int secondIcon, long m) { if (rejectTbt) return false; tbtWrites++; tbtIcon = icon; return true; }
        byte[] turns, lanes;
        int laneWrites;
        boolean rejectLane;
        public boolean lanes(byte[] frame) { laneWrites++; if (rejectLane) return false; lanes = frame.clone(); return true; }
        int writes;
        public boolean turns(byte[] frame) { if (rejectTurns) return false; turns = frame.clone(); writes++; return true; }
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
        {
            Sink rs = new Sink(); GuidanceSession rsess = new GuidanceSession(rs);
            rsess.maneuver(m(7, 1));
            GuidanceParser.Status st = s(1, "지도 A", 7); st.hasRemaining = true; st.distanceRemaining = 12345;
            rsess.status(st);
            check("remaining distance reaches sink", rs.remain == 12345);
            int rw = rs.remainWrites;
            rsess.status(st);
            check("duplicate remaining not resent", rs.remainWrites == rw);
            rsess.status(s(5, "지도 A", 7));
            check("reroute holds remaining", rs.remain == 12345);
            rsess.status(s(1, "지도 A", 7));
            check("reroute retains remaining", rs.remain == 12345);
            st.distanceRemaining = 900; rsess.status(st);
            rsess.disconnect();
            check("disconnect clears remaining", rs.remain == -1);
            GuidanceParser.Status ds = s(1, "지도 A", 7); ds.hasDestination = true; ds.destination = "서울역";
            rsess.status(ds);
            check("destination reaches sink", "서울역".equals(rs.dest));
            int dw = rs.destWrites; rsess.status(ds);
            check("duplicate destination not resent", rs.destWrites == dw);
            rsess.status(s(0, "지도 A", 7));
            check("route end clears destination", "".equals(rs.dest));
            GuidanceParser.Status ts = s(1, "지도 A", 7); ts.hasTime = true; ts.timeRemaining = 1830;
            rsess.status(ts);
            check("remaining time reaches sink", rs.time == 1830);
            int tw = rs.timeWrites;
            ts.timeRemaining = 1805; rsess.status(ts);
            check("same-minute time not resent", rs.timeWrites == tw);
            ts.timeRemaining = 1700; rsess.status(ts);
            check("new minute resent", rs.time == 1700);
            rsess.status(s(5, "지도 A", 7));
            check("reroute holds time", rs.time >= 0);
        }
        {
            Sink out = new Sink(); GuidanceSession route = new GuidanceSession(out);
            GuidanceParser.Status start = s(1, "route"); start.hasRemaining = true; start.distanceRemaining = 5000;
            start.hasTime = true; start.timeRemaining = 1800; route.status(start);
            check("route lease without a turn", route.hasPhoneRoute());
            int writesBefore = out.remainWrites;
            route.status(s(5, "route"));
            check("rerouting keeps route totals and lease", route.hasPhoneRoute() && out.remain == 5000 && out.remainWrites == writesBefore);
            route.status(s(4, "route"));
            check("locating without a turn keeps route totals", out.remain == 5000 && out.time >= 0);
            GuidanceParser.Status invalid = s(5, "route"); invalid.hasRemaining=true; invalid.distanceRemaining=-1;
            invalid.hasTime=true; invalid.timeRemaining=-1; route.status(invalid);
            check("transient invalid estimates cannot blank known totals", out.remain == 5000 && out.time >= 0);
            int timeBefore = out.timeWrites;
            java.lang.reflect.Field timeAt = GuidanceSession.class.getDeclaredField("timeLeftAtMs");
            timeAt.setAccessible(true); timeAt.setLong(route, System.currentTimeMillis() - 120000L);
            route.retryOutput();
            check("elapsed time alone does not resend arrival clock", out.timeWrites == timeBefore);
            route.setOutputAllowed(false); route.setOutputAllowed(true); route.retryOutput();
            check("ownership recovery resends unchanged totals", out.remainWrites == writesBefore + 1 && out.remain == 5000);
            route.disconnect(); check("disconnect releases route lease", !route.hasPhoneRoute() && out.remain == -1);
        }
        {
            Sink es = new Sink(); GuidanceSession eta = new GuidanceSession(es);
            eta.maneuver(m(7, 1));
            GuidanceParser.Status st = s(1, "지도 E", 7);
            st.hasTime = true; st.timeRemaining = -1;
            st.etaRaw = System.currentTimeMillis() / 1000L + 1800L;
            eta.status(st);
            check("ETA epoch fills arrival time when TimeRemaining is absent", es.time >= 1700 && es.time <= 1800);
        }
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
        for (int state : new int[]{0,2,3,5,77}) {
            session.maneuver(m(8, 1)); session.status(s(1, "지도 B", 8)); session.status(s(state, "지도 B", 8));
            check("non-guidance state clears " + state, blank(sink));
        }
        {
            Sink us = new Sink(); GuidanceSession under = new GuidanceSession(us);
            Item ulane = new Item(); ulane.id = 2;
            ulane.groups.add(Arrays.asList(n(0,0),n(1,2),n(2,0,90),n(3,90)));
            under.maneuver(m(7, 1));
            GuidanceParser.Status active = s(1, "지도 U", 7);
            active.hasDistance = true; active.distanceToNext = 350;
            active.hasRemaining = true; active.distanceRemaining = 4200;
            active.hasDestination = true; active.destination = "도착지";
            active.hasLaneIndex = true; active.laneIndex = 3;
            active.hasLaneTotal = true; active.laneTotal = 1;
            active.hasLaneVisible = true; active.laneVisible = true;
            under.status(active);
            under.message(GuidanceParser.LANES, Arrays.asList(n(0,1),n(1,3),ulane));
            check("locating from active preserves turn/tbt/remain/dest/lanes",
                    !blank(us) && us.tbtIcon == 0x46 && us.remain == 4200 && "도착지".equals(us.dest) && us.lanes[1] == 1);
            // GPS loss in underpass: state=4 (Locating) with empty current list preserves display
            GuidanceParser.Status loc = s(GuidanceSession.STATE_LOCATING, "지도 U");
            under.status(loc);
            check("underpass state 4 keeps turn frame active",
                    !blank(us) && us.tbtIcon == 0x46 && us.remain == 4200 && "도착지".equals(us.dest) && us.lanes[1] == 1
                            && "도로".equals(under.currentRoad()) && under.hasActiveGuidance());
            // Recovering back to state=1 continues seamlessly
            under.status(s(1, "지도 U", 7));
            check("recovering from underpass state 4 keeps guidance",
                    !blank(us) && us.tbtIcon == 0x46 && us.remain == 4200 && us.lanes[1] == 1);
            // Grazing locating deadline clears after LOCATING_GRACE_MS
            under.status(s(GuidanceSession.STATE_LOCATING, "지도 U"));
            under.expireLocating(1000L);
            under.expireLocating(1000L + GuidanceSession.LOCATING_GRACE_MS - 1L);
            check("before locating grace deadline guidance stays held", !blank(us) && us.tbtIcon == 0x46);
            under.expireLocating(1000L + GuidanceSession.LOCATING_GRACE_MS);
            check("after locating grace deadline guidance clears",
                    blank(us) && us.tbtIcon == 0 && us.remain >= 0 && !"".equals(us.dest) && us.lanes[1] == 0);
            // Long tunnel: still locating after the grace (route kept, output hidden), then GPS
            // returns with the same current turn and no maneuver resend -> the turn comes back.
            under.status(s(GuidanceSession.STATE_LOCATING, "지도 U"));
            check("long tunnel stays hidden while locating after grace", blank(us));
            under.status(s(1, "지도 U", 7));
            check("long tunnel recovery restores the turn without a maneuver resend",
                    !blank(us) && us.tbtIcon == 0x46);
            // Idle session entering state=4 must stay blank
            GuidanceSession idle = new GuidanceSession(new Sink());
            idle.maneuver(m(7, 1));
            idle.status(s(GuidanceSession.STATE_LOCATING, "지도 U", 7));
            check("locating from idle stays blank", !idle.hasActiveGuidance());
            // Immediate non-navigating exit (0, 2, 5, disconnect) while in state=4 clears immediately
            for (int endState : new int[]{0, 2, 5}) {
                under.maneuver(m(8, 2)); under.status(s(1, "지도 U", 8));
                under.status(s(GuidanceSession.STATE_LOCATING, "지도 U"));
                under.status(s(endState, "지도 U", 8));
                check("exiting locating via state " + endState + " clears immediately", blank(us));
            }
            under.maneuver(m(8, 2)); under.status(s(1, "지도 U", 8));
            under.status(s(GuidanceSession.STATE_LOCATING, "지도 U"));
            under.disconnect();
            check("disconnect during locating clears immediately", blank(us));
            check("non-tunnel locating flow never emits PE_00", us.tunnelWrites == 0);
        }
        {
            Sink ts = new Sink(); GuidanceSession tses = new GuidanceSession(ts);
            Maneuver tm = m(5, 3); tm.afterRoad = "남산1호터널 진입";
            tses.maneuver(tm);
            GuidanceParser.Status far = s(1, "지도 T", 5); far.hasDistance = true; far.distanceToNext = 1500;
            tses.status(far);
            check("far tunnel (>1000m) does not emit PE_00", ts.tunnelWrites == 0 && !ts.tunnelActive);
            GuidanceParser.Status near = s(1, "지도 T", 5); near.hasDistance = true; near.distanceToNext = 800;
            tses.status(near);
            check("tunnel within 1000m activates PE_00", ts.tunnelWrites == 1 && ts.tunnelActive && ts.tunnelDist == 800);
            GuidanceParser.Status sameBucket = s(1, "지도 T", 5); sameBucket.hasDistance = true; sameBucket.distanceToNext = 770;
            tses.status(sameBucket);
            check("distinct 50m bucket updates PE_00", ts.tunnelWrites == 2 && ts.tunnelActive && ts.tunnelDist == 750);
            GuidanceParser.Status dedupBucket = s(1, "지도 T", 5); dedupBucket.hasDistance = true; dedupBucket.distanceToNext = 760;
            tses.status(dedupBucket);
            check("same 50m bucket does not spam PE_00", ts.tunnelWrites == 2);
            GuidanceParser.Status close = s(1, "지도 T", 5); close.hasDistance = true; close.distanceToNext = 30;
            tses.status(close);
            check("tunnel <50m buckets to 0m", ts.tunnelWrites == 3 && ts.tunnelActive && ts.tunnelDist == 0);
            tses.status(s(GuidanceSession.STATE_LOCATING, "지도 T"));
            check("locating in tunnel holds PE_00 at 0m", ts.tunnelActive && ts.tunnelDist == 0);
            ts.rejectTunnel = true;
            tses.disconnect();
            check("failed PE_00 clear stays pending", ts.tunnelActive);
            ts.rejectTunnel = false;
            tses.retryOutput();
            check("retryOutput completes deferred PE_00 clear", !ts.tunnelActive && ts.tunnelDist == -1);
            int writesAfterClear = ts.tunnelWrites;
            tses.maneuver(m(6, 3)); tses.status(s(1, "지도 T", 6)); tses.disconnect();
            check("non-tunnel route after tunnel never re-emits PE_00", ts.tunnelWrites == writesAfterClear);
        }
        {
            // Audit P2: GPS loss with an unknown distance must not activate a distant tunnel at 0m.
            Sink fs = new Sink(); GuidanceSession fses = new GuidanceSession(fs);
            Maneuver fm = m(5, 3); fm.afterRoad = "남산1호터널 진입";
            fses.maneuver(fm);
            GuidanceParser.Status far5 = s(1, "지도 T", 5); far5.hasDistance = true; far5.distanceToNext = 5000;
            fses.status(far5);
            GuidanceParser.Status lost = s(GuidanceSession.STATE_LOCATING, "지도 T"); lost.hasDistance = true; lost.distanceToNext = -1;
            fses.status(lost);
            check("GPS loss never turns a distant tunnel into an active 0m tunnel", fs.tunnelWrites == 0 && !fs.tunnelActive);
            GuidanceParser.Status back = s(1, "지도 T", 5); back.hasDistance = true; back.distanceToNext = 600;
            fses.status(back);
            check("tunnel activates once really within 1000m", fs.tunnelWrites == 1 && fs.tunnelActive && fs.tunnelDist == 600);
        }
        {
            // A rejected activation already reached the HUD service, so its clear must still be delivered.
            Sink rs = new Sink(); rs.rejectTunnel = true; GuidanceSession rses = new GuidanceSession(rs);
            Maneuver rm = m(5, 3); rm.afterRoad = "북악터널";
            rses.maneuver(rm);
            GuidanceParser.Status nearR = s(1, "지도 R", 5); nearR.hasDistance = true; nearR.distanceToNext = 300;
            rses.status(nearR);
            check("rejected activation is not recorded", rs.tunnelWrites == 0);
            rses.maneuver(m(6, 3)); // re-render retries the activation; still rejected
            rs.rejectTunnel = false;
            GuidanceParser.Status plain = s(1, "지도 R", 6); plain.hasDistance = true; plain.distanceToNext = 500;
            rses.status(plain);
            check("clear follows a rejected activation", rs.tunnelWrites == 1 && !rs.tunnelActive && rs.tunnelDist == -1);
            rses.disconnect();
            check("clear is sent only once", rs.tunnelWrites == 1);
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
        check("overpass text sets stock overpass icon and OFF_OVER", (sink.turns[2] & 255) == ClusterIcon.OVERPASS_ENTRY_LC && (sink.lanes[LaneBits.OFF_OVER] & 255) == 1 && (sink.lanes[LaneBits.OFF_UNDER] & 255) == 0);
        Maneuver underM = m(7, 3); underM.afterRoad = "지하차도 진입";
        session.maneuver(underM);
        check("underpass text sets stock underpass icon and OFF_UNDER", (sink.turns[2] & 255) == ClusterIcon.UNDERPASS_ENTRY_LC && (sink.lanes[LaneBits.OFF_UNDER] & 255) == 1 && (sink.lanes[LaneBits.OFF_OVER] & 255) == 0);
        session.maneuver(m(7, 3));
        check("normal straight clears OFF_OVER and OFF_UNDER", (sink.lanes[LaneBits.OFF_OVER] & 255) == 0 && (sink.lanes[LaneBits.OFF_UNDER] & 255) == 0);
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
        {
            // CoreService retries every second with no route input (outputRetry -> retryOutput).
            Sink cs = new Sink(); GuidanceSession cp = new GuidanceSession(cs);
            cs.rejectTbt = true; cs.rejectTurns = true;
            cp.maneuver(m(3, 1)); cp.status(s(1, "지도 A", 3));
            check("failed CarPlay turn not claimed", cs.tbtWrites == 0 && cs.writes == 0 && cp.hasActiveGuidance());
            cs.rejectTbt = false; cs.rejectTurns = false;
            cp.retryOutput();
            check("failed CarPlay turn resent by retry", cs.tbtWrites == 1 && cs.tbtIcon > 0 && cs.writes == 1);
            cp.retryOutput();
            check("sent CarPlay turn not repeated", cs.tbtWrites == 1 && cs.writes == 1);
            cp.invalidateOutput(); cp.retryOutput();
            check("lost cluster binding resends CarPlay turn", cs.tbtWrites == 2 && cs.writes == 2);
        }
        NotificationEpoch epoch = new NotificationEpoch();
        check("no notifications accepted before connection", epoch.ticket() == -1);
        long first = epoch.open();
        check("connected ticket valid", epoch.isCurrent(first));
        epoch.close();
        check("disconnect invalidates queued notification", !epoch.isCurrent(first) && epoch.ticket() == -1);
        long second = epoch.open();
        check("reconnect has a fresh generation", second != first && !epoch.isCurrent(first) && epoch.isCurrent(second));
        check("duplicate connected event keeps generation", epoch.open() == second);
        NotificationEpoch handover = new NotificationEpoch();
        long bluetooth = handover.open(4);
        long wifi = handover.open(5);
        check("transport handover invalidates old queued guidance", wifi != bluetooth && !handover.isCurrent(bluetooth));
        check("duplicate wifi connect retains its subscription", handover.open(5) == wifi);
        check("late bluetooth disconnect cannot close wifi guidance", handover.close(4) == -1 && handover.isCurrent(wifi));
        check("current wifi disconnect closes guidance", handover.close(5) > wifi && handover.ticket() == -1);
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
        backend.invalid = false;
        backend.listUnavailable = true;
        check("unreviewed missing list cannot invent a component", !request.ensure(4,backend));
        backend.lookupId = 1;
        check("OEM component lookup can confirm a name when list parsing fails", request.ensure(4,backend));
        check("confirmed OEM component requested", "RouteGuidanceComponent0".equals(backend.lastName));
        backend.lookupId=0; backend.reviewed=true;
        check("reviewed OEM profile may request its canonical single component",request.ensure(5,backend));
        check("canonical fallback permits all V039 models and build dates",
                GuidanceRequest.reviewedCanonicalProfile("OSHEV.KOR.0000.V039.001.260902")
                && GuidanceRequest.reviewedCanonicalProfile("OTHER.V039.001.260902")
                && GuidanceRequest.reviewedCanonicalProfile("MODEL.EUR.S5W_M.V039.999.270101")
                && GuidanceRequest.reviewedCanonicalProfile("MODEL.USA.V039.000.240101"));
        check("canonical fallback excludes other or malformed versions",
                !GuidanceRequest.reviewedCanonicalProfile("OSHEV.KOR.0000.V035.001.250507")
                && !GuidanceRequest.reviewedCanonicalProfile("MODEL.V040.001.260902")
                && !GuidanceRequest.reviewedCanonicalProfile("MODEL.V0390.001.260902")
                && !GuidanceRequest.reviewedCanonicalProfile("MODEL.XV039.001.260902")
                && !GuidanceRequest.reviewedCanonicalProfile("")
                && !GuidanceRequest.reviewedCanonicalProfile(null));
        MediaSubscription media = new MediaSubscription();
        final int[] mediaCalls = {0};
        final boolean[] mediaAccept = {false};
        MediaSubscription.Backend mediaBackend = new MediaSubscription.Backend() {
            public boolean start() { mediaCalls[0]++; return mediaAccept[0]; }
        };
        check("media subscription waits for a live session", !media.ensure(-1,mediaBackend) && mediaCalls[0]==0);
        check("not-ready media subscription remains retryable", !media.ensure(1,mediaBackend) && mediaCalls[0]==1);
        mediaAccept[0]=true;
        check("native media acceptance is required", media.ensure(1,mediaBackend) && mediaCalls[0]==2);
        check("media is requested once per live session", media.ensure(1,mediaBackend) && mediaCalls[0]==2);
        check("handover requests media on the new session", media.ensure(2,mediaBackend) && mediaCalls[0]==3);
        {
            // Synthetic iAP2 payload (ID 10 junction angles + ID 11 exit angle) -> GuidanceSession.StockSink -> StockTurn.
            final java.util.List<StockTurn.Frame> frames = new java.util.ArrayList<StockTurn.Frame>();
            GuidanceSession.StockSink stockSink = new GuidanceSession.StockSink() {
                private boolean near;
                public boolean tbt(int icon, int secondIcon, long meters) { return tbt(null, icon, secondIcon, meters); }
                public boolean tbt(Maneuver man, int icon, int secondIcon, long meters) {
                    if (icon <= 0) { near = false; frames.add(new StockTurn.Frame(0, 0, 0, 0, false)); return true; }
                    StockTurn.Frame f = StockTurn.build(man, icon, meters, near);
                    near = f.near;
                    frames.add(f);
                    return true;
                }
                public boolean tunnel(boolean active, long m) { return true; }
                public boolean timeRemaining(long s) { return true; }
                public boolean destination(String d) { return true; }
                public boolean remaining(long m) { return true; }
                public boolean lanes(byte[] f) { return true; }
                public boolean turns(byte[] f) { return true; }
            };
            GuidanceSession cp = new GuidanceSession(stockSink);
            Item ang = new Item(); ang.id = 10; ang.ints = new int[]{0, 22, 337};
            cp.message(GuidanceParser.MANEUVER, Arrays.asList(
                    n(0, 1), n(1, 5), n(3, 1), text(4, "역삼역"), n(5, 700), n(8, 0), n(9, 0), ang, n(11, -90)));
            cp.message(GuidanceParser.STATUS, Arrays.asList(n(0, 1), n(1, 1), n(13, 5), n(10, 700)));
            check("far CarPlay maneuver keeps Korean icon 0x46", frames.size() == 1 && frames.get(0).displayType == 0x46 && frames.get(0).sideStreet == 0);
            cp.message(GuidanceParser.STATUS, Arrays.asList(n(0, 1), n(1, 1), n(13, 5), n(10, 400)));
            check("near CarPlay maneuver switches to 0x0d with ID 10+11 mask", frames.size() == 2
                    && frames.get(1).displayType == StockTurn.DISPLAY_TURN
                    && frames.get(1).sideStreet == 0x4803
                    && frames.get(1).directionType == 36
                    && frames.get(1).combiSideStreet == 0);
            // Delta updating ID 10 junction angles at same distance must trigger a StockSink update.
            Item ang2 = new Item(); ang2.id = 10; ang2.ints = new int[]{0, 270};
            cp.message(GuidanceParser.MANEUVER, Arrays.asList(n(0, 1), n(1, 5), ang2));
            check("delta ID 10 re-emits updated StockTurn mask", frames.size() == 3 && frames.get(2).sideStreet == 0x0801);
        }
        System.out.println("guidance session: " + passed + " passed");
    }
    static Item text(int id,String value) { Item it = new Item(); it.id=id; it.strings=new String[]{value}; return it; }
    static final class RequestBackend implements GuidanceRequest.ReviewedOemBackend {
        int count, starts, lookupId; boolean accept, invalid, listUnavailable, reviewed; String lastName;
        public boolean canonicalFallbackAllowed() { return reviewed; }
        public int count() { return count; }
        public int components(int[] ids,String[] names) { if(listUnavailable)return 0; ids[0]=0; names[0]=invalid ? null : "RouteGuidanceComponent0"; return 1; }
        public int componentId(String name) { return lookupId; }
        public boolean start(String[] names) { starts++; lastName=names[0]; return accept; }
    }
}
