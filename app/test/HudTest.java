import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.GuidanceParser;
import kr.gen5w.hud.LaneBits;
import kr.gen5w.hud.LaneFrame;

public final class HudTest {
    static int fails;
    static void eq(String name, int got, int want) {
        if (got != want) { System.out.printf("FAIL %s got 0x%x want 0x%x%n", name, got, want); fails++; }
        else System.out.println("PASS " + name);
    }
    static void eqs(String name, String got, String want) {
        if (!got.equals(want)) { System.out.println("FAIL " + name + " got " + got + " want " + want); fails++; }
        else System.out.println("PASS " + name);
    }
    static String hex(byte[] f, int off) { return String.format("%02x%02x", f[off] & 0xff, f[off+1] & 0xff); }

    public static void main(String[] args) {
        // Lane frame layout is independent of free-text maneuver inference.
        boolean[] rec = {false, false, true, true, false};
        byte[] f = new byte[81];
        LaneBits.entry(f, rec, ClusterIcon.OVERPASS_ENTRY_LC);
        eqs("overpass entry bits", hex(f, LaneBits.OFF_OVER), "0c00");
        byte[] f2 = new byte[81];
        LaneBits.entry(f2, rec, ClusterIcon.UNDERPASS_ENTRY_LC);
        eqs("underpass entry bits", hex(f2, LaneBits.OFF_UNDER), "0c00");
        eqs("unrelated overpass bits untouched", hex(f2, LaneBits.OFF_OVER), "0000");
        byte[] f3 = new byte[81];
        LaneBits.side(f3, rec, ClusterIcon.OVERPASS_SIDE_R, true);
        eqs("right side road marks left lanes", hex(f3, LaneBits.OFF_OVER), "0300");
        byte[] f4 = new byte[81];
        LaneBits.side(f4, rec, ClusterIcon.OVERPASS_SIDE_L, false);
        eqs("left side road marks right lanes", hex(f4, LaneBits.OFF_OVER), "1000");

        GuidanceParser.Lanes lanes = new GuidanceParser.Lanes();
        GuidanceParser.Lane lane = new GuidanceParser.Lane();
        lane.index = 1; lane.status = 255;
        lane.angles = new int[]{0,90,-90}; lane.highlights = new int[]{90};
        lanes.lanes.add(lane);
        byte[] encoded = LaneFrame.encode(lanes, ClusterIcon.OVERPASS_ENTRY_LC);
        eq("lane frame size", encoded.length, 81);
        eq("lane frame header", encoded[0] & 255, 0xf1);
        eq("lane count", encoded[1], 1);
        eq("possibility bits", encoded[3], 1 | (2<<2) | (1<<4));
        eq("straight direction", encoded[0x13], 1);
        eq("right direction", encoded[0x14], 5);
        eq("left direction", encoded[0x15], 3);
        eq("highlight overpass mask", encoded[0x43], 1);
        lane.highlights = new int[]{45};
        eq("highlight absent from angles clears", LaneFrame.encode(lanes,0)[1], 0);
        lane.highlights = new int[0]; lane.angles = new int[]{17};
        eq("unknown angle clears", LaneFrame.encode(lanes,0)[1], 0);
        lane.angles = new int[]{0,45,90,135};
        eq("four directions clear", LaneFrame.encode(lanes,0)[1], 0);

        // Non-directional straight icons upgrade on TG / Rest Area text, while directional icons stay preserved.
        eq("AA straight upgraded on TG text", ClusterIcon.refineManeuver(0x41, "서울TG", ""), ClusterIcon.TOLL);
        eq("AA straight upgraded on rest area text", ClusterIcon.refineManeuver(0x41, "망향휴게소", ""), ClusterIcon.REST_AREA);
        eq("AA icon preserved against conflicting side", ClusterIcon.refineManeuver(0x43, "좌측 진출", ""), 0x43);

        byte[] simple = LaneFrame.encodeSimple(3, new int[]{0,90,-90},
                new boolean[]{false,true,false}, 0);
        eq("simple lane count", simple[1], 3);
        eq("simple recommended lane", (simple[4] & 0x02) != 0 ? 1 : 0, 1);

        System.out.println(fails == 0 ? "hud all match" : fails + " failed");
        System.exit(fails == 0 ? 0 : 1);
    }
}
