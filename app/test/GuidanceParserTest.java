import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import kr.gen5w.hud.GuidanceParser;
import kr.gen5w.hud.Maneuver;
import kr.gen5w.probe.Item;

public final class GuidanceParserTest {
    static int passed;
    static Item number(int id, int value) { Item x = new Item(); x.id = id; x.ints = new int[]{value}; return x; }
    static Item text(int id, String value) { Item x = new Item(); x.id = id; x.strings = new String[]{value}; return x; }
    static List<Item> fields(Item... items) { return Arrays.asList(items); }
    static void check(String name, boolean ok) {
        if (!ok) throw new AssertionError(name);
        passed++; System.out.println("PASS " + name);
    }
    public static void main(String[] args) {
        Maneuver m = GuidanceParser.maneuver(fields(number(0, 1), number(1, 7), text(2, "우측 진출"),
            number(3, 23), text(4, "동탄IC"), number(5, 150), number(8, 0), number(9, 0), number(11, 90)));
        check("stock maneuver field ids", m != null && m.component == 1 && m.index == 7 && m.type == 23
            && m.drivingSide == 0 && m.exitAngle == 90 && m.distanceMeters == 150 && "동탄IC".equals(m.afterRoad));
        check("maneuver requires type", GuidanceParser.maneuver(fields(number(0, 1), number(1, 0))) == null);
        check("maneuver requires component", GuidanceParser.maneuver(fields(number(1, 0), number(3, 1))) == null);
        check("maneuver rejects duplicate ids", GuidanceParser.maneuver(fields(number(0, 1), number(1, 0), number(3, 1), number(3, 2))) == null);
        check("null message rejected", GuidanceParser.maneuver(null) == null);
        m = GuidanceParser.maneuver(fields(number(0, 1), number(1, 0), number(3, 1)));
        check("missing angle stays unknown", m != null && m.exitAngle == Maneuver.UNKNOWN_ANGLE && m.drivingSide == Maneuver.UNKNOWN_DRIVING_SIDE);
        Item distance = new Item(); distance.id = 5; distance.longs = new long[]{3000000000L};
        m = GuidanceParser.maneuver(fields(number(0, 1), number(1, 0), number(3, 1), distance));
        check("distance preserves unsigned 32-bit range", m != null && m.distanceMeters == 3000000000L);
        distance.ints = new int[]{(int)3000000000L}; distance.longs = null; distance.type = 6;
        m = GuidanceParser.maneuver(fields(number(0, 1), number(1, 0), number(3, 1), distance));
        check("unsigned 32-bit int storage decoded", m != null && m.distanceMeters == 3000000000L);
        GuidanceParser.Status s = GuidanceParser.status(fields(number(0, 2), number(1, 5), text(19, "지도")));
        check("rerouting clears guidance", s != null && !s.canDisplay() && "지도".equals(s.source));
        check("route set allows display", GuidanceParser.status(fields(number(0, 2), number(1, 1))).canDisplay());
        check("loading locating arrived and no route clear", allClear(0, 2, 3, 4, 5));
        check("unknown state cannot display", !GuidanceParser.status(fields(number(0, 2), number(1, 77))).canDisplay());
        check("missing state cannot display", !GuidanceParser.status(fields(number(0, 2))).canDisplay());
        Item list = new Item(); list.id = 2;
        list.groups.add(fields(number(0, 1), number(1, 2), number(2, 90), number(3, 90)));
        list.groups.add(fields(number(0, 0), number(1, 1), number(2, 0)));
        GuidanceParser.Lanes lanes = GuidanceParser.lanes(fields(number(0, 2), number(1, 9), list));
        check("lane ids and raw status preserved", lanes != null && lanes.component == 2 && lanes.index == 9
            && lanes.lanes.size() == 2 && lanes.lanes.get(0).index == 0 && lanes.lanes.get(1).status == 2);
        list.groups.add(fields(number(0, 0), number(1, 1)));
        check("duplicate lane indices rejected", GuidanceParser.lanes(fields(number(0, 2), number(1, 9), list)) == null);
        check("unknown fields tolerated", GuidanceParser.maneuver(fields(number(0, 1), number(1, 0), number(3, 1), text(99, "future"))) != null);
        s = GuidanceParser.status(fields(number(0, 1), number(16, 7), number(17, 4), number(18, 1)));
        check("lane selection separate from maneuver selection", s != null && s.hasLaneIndex && s.laneIndex == 7 && s.hasLaneVisible && s.laneVisible);
        Item partial = new Item(); partial.id = 2;
        partial.groups.add(fields(number(0, 0), number(3, 90)));
        GuidanceParser.Lanes prior = new GuidanceParser.Lanes(); prior.component = 1; prior.index = 7;
        GuidanceParser.Lane priorLane = new GuidanceParser.Lane(); priorLane.index = 0; priorLane.status = 2;
        priorLane.angles = new int[]{0,90}; priorLane.highlights = new int[]{0}; prior.lanes.add(priorLane);
        GuidanceParser.Lanes changed = GuidanceParser.lanes(fields(number(0,1), number(1,7), partial), prior);
        check("lane delta retains angles and updates highlight", changed != null && changed.lanes.get(0).angles.length == 2 && changed.lanes.get(0).highlights[0] == 90);
        check("lane delta requires matching address", GuidanceParser.lanes(fields(number(0,1),number(1,8),partial),prior) == null);
        Item gap = new Item(); gap.id = 2;
        gap.groups.add(fields(number(0,0),number(1,1),number(2,0)));
        gap.groups.add(fields(number(0,2),number(1,1),number(2,90)));
        check("lane index gaps rejected", GuidanceParser.lanes(fields(number(0,1),number(1,7),gap)) == null);
        System.out.println("guidance parser: " + passed + " passed");
    }
    static boolean allClear(int... states) {
        for (int state : states) if (GuidanceParser.status(fields(number(0, 1), number(1, state))).canDisplay()) return false;
        return true;
    }
}
