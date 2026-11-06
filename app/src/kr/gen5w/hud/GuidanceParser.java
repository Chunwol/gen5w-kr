package kr.gen5w.hud;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import kr.gen5w.probe.Item;

/** Parses copied iAP2 fields. IDs come from the stock com.tcc.iap2 constants;
 * notification IDs (0x78/79/7a) are distinct from wire message IDs (0x5201/02).
 * No Android calls or cluster writes. Bad/ambiguous input returns null.
 */
public final class GuidanceParser {
    public static final int STATUS = 0x78, MANEUVER = 0x79, LANES = 0x7a;
    private GuidanceParser() {}

    public static final class Status {
        public int component, state = -1;
        public String source;
        public long distanceToNext = -1;
        public boolean hasState, hasSource, hasCurrent, hasDistance;
        /** RouteGuidanceUpdate DistanceRemaing (id 7), meters to the destination. */
        public long distanceRemaining = -1;
        public boolean hasRemaining;
        /** RouteGuidanceUpdate TimeRemaingToDestination (id 6), read as seconds; -1 when absent or malformed. */
        public long timeRemaining = -1;
        public boolean hasTime;
        /** Raw EstimatedTimeOfArrival (id 5), kept only for the diagnostic log; -1 when absent or malformed. */
        public long etaRaw = -1;
        /** DistanceRemaingDisplayUnits (id 9), DistanceRemaingDisplayStr length (id 8), ManeuverCount (id 14); -1 when absent. */
        public int remainUnits = -1, remainStrLength = -1, maneuverCount = -1;
        /** RouteGuidanceUpdate DestinationName (id 4). */
        public String destination;
        public boolean hasDestination;
        public int laneIndex = -1, laneTotal = -1;
        public boolean hasLaneIndex, hasLaneVisible, laneVisible, hasLaneTotal;
        public int[] current = new int[0];
        // Stock RouteGuidanceState: 1 RouteSet, 6 ProceedToRoute.
        public boolean canDisplay() { return state == 1 || state == 6; }
    }
    public static final class Lane {
        public int index, status;
        public int[] angles, highlights;
    }
    public static final class Lanes {
        public int component, index;
        public final List<Lane> lanes = new ArrayList<Lane>();
    }

    public static Maneuver maneuver(List<Item> fields) {
        return maneuver(fields, null);
    }
    public static Maneuver maneuver(List<Item> fields, Maneuver previous) {
        try {
            Map<Integer, Item> f = index(fields);
            Maneuver m = new Maneuver();
            m.component = unsigned(f, 0, -1, 65535);
            m.index = unsigned(f, 1, -1, 65535);
            if (previous != null && (previous.component != m.component || previous.index != m.index)) return null;
            m.type = unsigned(f, 3, previous == null ? -1 : previous.type, 65535);
            if (m.component < 0 || m.index < 0 || m.type < 0) return null;
            m.desc = f.containsKey(2) || previous == null ? string(f, 2) : previous.desc;
            m.afterRoad = f.containsKey(4) || previous == null ? string(f, 4) : previous.afterRoad;
            m.distanceMeters = number(f, 5, previous == null ? -1 : previous.distanceMeters);
            if (m.distanceMeters < -1 || m.distanceMeters > 0xffffffffL) return null;
            m.drivingSide = unsigned(f, 8, previous == null ? Maneuver.UNKNOWN_DRIVING_SIDE : previous.drivingSide, 1);
            m.junctionType = unsigned(f, 9, previous == null ? -1 : previous.junctionType, 65535);
            m.exitAngle = integer(f, 11, previous == null ? Maneuver.UNKNOWN_ANGLE : previous.exitAngle);
            return m;
        } catch (IllegalArgumentException e) { return null; }
    }

    /** Stock notifications can address several display components, and deltas
     * can omit the component list. Select one component without changing input.
     */
    public static List<Item> forComponent(List<Item> fields, int preferred) {
        try {
            Map<Integer, Item> f = index(fields);
            Item old = f.get(0);
            int selected = preferred;
            if (old != null) {
                if (old.ints == null || old.ints.length == 0 || old.ints.length > 16) return null;
                selected = old.ints[0];
                for (int id : old.ints) {
                    if (id < 0 || id > 65535) return null;
                    if (id == preferred) selected = preferred;
                }
            }
            if (selected < 0 || selected > 65535) return null;
            Item component = new Item(); component.id = 0; component.type = 5;
            component.ints = new int[]{selected};
            List<Item> out = new ArrayList<Item>();
            out.add(component);
            for (Item item : fields) if (item.id != 0) out.add(item);
            return out;
        } catch (IllegalArgumentException e) { return null; }
    }
    public static int[] address(List<Item> fields) {
        try {
            Map<Integer, Item> f = index(fields);
            int component = unsigned(f, 0, -1, 65535), index = unsigned(f, 1, -1, 65535);
            return component < 0 || index < 0 ? null : new int[]{component, index};
        } catch (IllegalArgumentException e) { return null; }
    }

    public static Status status(List<Item> fields) {
        try {
            Map<Integer, Item> f = index(fields);
            Status s = new Status();
            s.component = unsigned(f, 0, -1, 65535);
            if (s.component < 0) return null;
            s.state = unsigned(f, 1, -1, 65535);
            s.hasState = f.containsKey(1);
            s.hasSource = f.containsKey(19);
            s.hasCurrent = f.containsKey(13);
            s.current = array(f.get(13));
            for (int index : s.current) if (index < 0 || index > 65535) return null;
            s.distanceToNext = number(f, 10, -1);
            s.hasDistance = f.containsKey(10);
            if (s.distanceToNext < -1 || s.distanceToNext > 0xffffffffL) return null;
            s.hasRemaining = f.containsKey(7);
            s.distanceRemaining = number(f, 7, -1);
            if (s.distanceRemaining < -1 || s.distanceRemaining > 0xffffffffL) return null;
            s.hasTime = f.containsKey(6);
            s.timeRemaining = optional(f, 6);
            s.etaRaw = optional(f, 5);
            s.remainUnits = (int)optional(f, 9);
            s.maneuverCount = (int)optional(f, 14);
            Item str = f.get(8);
            s.remainStrLength = str != null && str.strings != null && str.strings.length == 1 && str.strings[0] != null
                    ? str.strings[0].length() : -1;
            s.hasDestination = f.containsKey(4);
            s.destination = string(f, 4);
            s.source = string(f, 19);
            s.hasLaneIndex = f.containsKey(16);
            s.laneIndex = unsigned(f, 16, -1, 65535);
            s.hasLaneTotal = f.containsKey(17);
            s.laneTotal = unsigned(f, 17, -1, 65535);
            s.hasLaneVisible = f.containsKey(18);
            s.laneVisible = unsigned(f, 18, 0, 1) == 1;
            return s;
        } catch (IllegalArgumentException e) { return null; }
    }

    public static Lanes lanes(List<Item> fields) { return lanes(fields, null); }
    public static Lanes lanes(List<Item> fields, Lanes previous) {
        try {
            Map<Integer, Item> f = index(fields);
            Lanes out = new Lanes();
            out.component = unsigned(f, 0, -1, 65535);
            out.index = unsigned(f, 1, -1, 65535);
            if (out.component < 0 || out.index < 0) return null;
            if (previous != null && (previous.component != out.component || previous.index != out.index)) return null;
            Item group = f.get(2);
            if (group == null) return previous == null ? null : copy(previous);
            if (group.groups.size() > 8) return null;
            // Empty LaneInformation explicitly removes the lane set. Nonempty
            // groups update the addressed lanes, preserving omitted fields.
            if (previous != null && !group.groups.isEmpty()) out = copy(previous);
            List<Integer> seen = new ArrayList<Integer>();
            for (List<Item> fieldsInLane : group.groups) {
                Map<Integer, Item> g = index(fieldsInLane);
                Lane lane = new Lane();
                lane.index = unsigned(g, 0, -1, 255);
                if (lane.index < 0 || seen.contains(lane.index)) return null;
                seen.add(lane.index);
                Lane old = null;
                for (Lane candidate : out.lanes) if (candidate.index == lane.index) old = candidate;
                lane.status = unsigned(g, 1, old == null ? -1 : old.status, 255);
                if (lane.status < 0) return null;
                lane.angles = g.containsKey(2) || old == null ? array(g.get(2)) : old.angles.clone();
                lane.highlights = g.containsKey(3) || old == null ? array(g.get(3)) : old.highlights.clone();
                if (old != null) out.lanes.remove(old);
                out.lanes.add(lane);
            }
            if (out.lanes.size() > 8) return null;
            Collections.sort(out.lanes, new Comparator<Lane>() {
                public int compare(Lane a, Lane b) { return a.index - b.index; }
            });
            if (!out.lanes.isEmpty()) {
                int base = out.lanes.get(0).index;
                if (base != 0 && base != 1) return null;
                for (int i = 0; i < out.lanes.size(); i++) if (out.lanes.get(i).index != base+i) return null;
            }
            return out;
        } catch (IllegalArgumentException e) { return null; }
    }
    static Lanes copy(Lanes in) {
        Lanes out = new Lanes(); out.component = in.component; out.index = in.index;
        for (Lane lane : in.lanes) {
            Lane c = new Lane(); c.index = lane.index; c.status = lane.status;
            c.angles = lane.angles.clone(); c.highlights = lane.highlights.clone(); out.lanes.add(c);
        }
        return out;
    }

    private static Map<Integer, Item> index(List<Item> fields) {
        if (fields == null || fields.size() > 256) throw new IllegalArgumentException();
        Map<Integer, Item> out = new HashMap<Integer, Item>();
        for (Item item : fields) {
            if (item == null || out.put(item.id, item) != null) throw new IllegalArgumentException();
        }
        return out;
    }
    private static long number(Map<Integer, Item> fields, int id, long fallback) {
        Item item = fields.get(id);
        if (item == null) return fallback;
        if (item.ints != null && item.ints.length == 1 && item.longs == null) {
            // OBJ_NUMU32 uses an int[] in the stock library as well.
            return item.type == 6 ? item.ints[0] & 0xffffffffL : item.ints[0];
        }
        if (item.longs != null && item.longs.length == 1 && item.ints == null) return item.longs[0];
        throw new IllegalArgumentException();
    }
    /** Diagnostic field: a malformed value never rejects the whole status, it reads as -1. */
    private static long optional(Map<Integer, Item> f, int id) {
        try {
            long value = number(f, id, -1);
            return value < -1 ? -1 : value;
        } catch (IllegalArgumentException e) { return -1; }
    }
    private static int integer(Map<Integer, Item> f, int id, int fallback) {
        long n = number(f, id, fallback);
        if (n < Integer.MIN_VALUE || n > Integer.MAX_VALUE) throw new IllegalArgumentException();
        return (int)n;
    }
    private static int unsigned(Map<Integer, Item> f, int id, int fallback, int max) {
        if (!f.containsKey(id)) return fallback;
        int value = integer(f, id, fallback);
        if (value < 0 || value > max) throw new IllegalArgumentException();
        return value;
    }
    private static String string(Map<Integer, Item> f, int id) {
        Item item = f.get(id);
        if (item == null) return null;
        if (item.strings == null || item.strings.length != 1 || item.strings[0] == null
                || item.strings[0].length() > 4096) throw new IllegalArgumentException();
        return item.strings[0];
    }
    private static int[] array(Item item) {
        if (item == null) return new int[0];
        if (item.ints == null || item.ints.length > 32) throw new IllegalArgumentException();
        return item.ints.clone();
    }
}
