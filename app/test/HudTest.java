import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.LaneBits;
import kr.gen5w.hud.Maneuver;
import kr.gen5w.hud.GuidanceParser;
import kr.gen5w.hud.LaneFrame;

public final class HudTest {
    static int fails;
    static Maneuver m(String road) { Maneuver x = new Maneuver(); x.type = 3; x.afterRoad = road; x.drivingSide = 0; return x; }
    static void eq(String name, int got, int want) {
        if (got != want) { System.out.printf("FAIL %s got 0x%x want 0x%x%n", name, got, want); fails++; }
        else System.out.println("PASS " + name);
    }
    static void eqs(String name, String got, String want) {
        if (!got.equals(want)) { System.out.println("FAIL " + name + " got " + got + " want " + want); fails++; }
        else System.out.println("PASS " + name);
    }
    static String hex(byte[] f, int off) { return String.format("%02x%02x", f[off] & 0xff, f[off+1] & 0xff); }

    public static void main(String[] a) {
        eq("tunnel entry centre", ClusterIcon.of(m("남산1호터널")), ClusterIcon.UNDERPASS_ENTRY_LC);
        eq("tunnel entry right", ClusterIcon.of(m("우측 터널")), ClusterIcon.UNDERPASS_ENTRY_R);
        eq("naver turn left in type 3", ClusterIcon.of(m("좌회전")), 0x46);
        eq("naver turn right in type 3", ClusterIcon.of(m("우회전")), 0x43);
        eq("underpass entry centre", ClusterIcon.of(m("밤밭지하차도")), ClusterIcon.UNDERPASS_ENTRY_LC);
        eq("underpass entry right", ClusterIcon.of(m("우측 밤밭지하차도")), ClusterIcon.UNDERPASS_ENTRY_R);
        eq("underpass side road", ClusterIcon.of(m("지하차도 옆길")), ClusterIcon.UNDERPASS_SIDE_L);
        eq("overpass entry", ClusterIcon.of(m("동부고가도로")), ClusterIcon.OVERPASS_ENTRY_LC);
        eq("overpass side right", ClusterIcon.of(m("우측 고가 옆길")), ClusterIcon.OVERPASS_SIDE_R);
        eq("toll", ClusterIcon.of(m("서울요금소")), ClusterIcon.TOLL);
        eq("rest area", ClusterIcon.of(m("안성휴게소")), ClusterIcon.REST_AREA);
        eq("ic enter right", ClusterIcon.of(m("우측 동탄나들목")), ClusterIcon.IC_ENTER_R);
        eq("ic exit", ClusterIcon.of(m("동탄나들목 진출")), ClusterIcon.IC_EXIT_C);
        // Naver / Kakao / TMap official guidance phrases
        eq("naver underpass centre spaced", ClusterIcon.of(m("전방에 지하 차도 진입")), ClusterIcon.UNDERPASS_ENTRY_LC);
        eq("naver underpass left spaced", ClusterIcon.of(m("왼쪽에 지하 차도 진입")), ClusterIcon.UNDERPASS_ENTRY_LC);
        eq("naver underpass right spaced", ClusterIcon.of(m("오른쪽에 지하 차도 진입")), ClusterIcon.UNDERPASS_ENTRY_R);
        eq("naver underpass side left", ClusterIcon.of(m("왼쪽에 지하 차도 옆길")), ClusterIcon.UNDERPASS_SIDE_L);
        eq("naver underpass side right", ClusterIcon.of(m("오른쪽에 지하 차도 옆길")), ClusterIcon.UNDERPASS_SIDE_R);
        eq("naver overpass centre spaced", ClusterIcon.of(m("전방에 고가 차로 진입")), ClusterIcon.OVERPASS_ENTRY_LC);
        eq("naver overpass side left", ClusterIcon.of(m("왼쪽에 고가 차도 옆길")), ClusterIcon.OVERPASS_SIDE_L);
        eq("naver overpass side right", ClusterIcon.of(m("오른쪽에 고가 차도 옆길")), ClusterIcon.OVERPASS_SIDE_R);
        eq("tmap underpass side", ClusterIcon.of(m("지하차도옆")), ClusterIcon.UNDERPASS_SIDE_L);
        eq("tmap overpass side", ClusterIcon.of(m("고가도로옆")), ClusterIcon.OVERPASS_SIDE_L);
        eq("kakao left direction road", ClusterIcon.of(m("왼쪽 방향")), 0x47);
        eq("kakao right direction road", ClusterIcon.of(m("오른쪽 방향")), 0x42);
        Maneuver noTurn = m("고가도로"); noTurn.type = 0;
        eq("NoTurn cannot be overridden by road text", ClusterIcon.of(noTurn), ClusterIcon.NONE);
        noTurn.type = 999;
        eq("unknown turn cannot be overridden by road text", ClusterIcon.of(noTurn), ClusterIcon.NONE);
        Maneuver opposite = m("좌측 지하차도"); opposite.type = 2;
        eq("explicit right turn wins over conflicting text", ClusterIcon.of(opposite), ClusterIcon.UNDERPASS_ENTRY_R);
        opposite.type = 1; opposite.afterRoad = "우측 고가도로";
        eq("explicit left turn wins over conflicting text", ClusterIcon.of(opposite), ClusterIcon.OVERPASS_ENTRY_LC);
        eq("null -> none", ClusterIcon.of(null), ClusterIcon.NONE);

        // lanes: 5 lanes, lanes 3,4 (index 2,3) go onto the overpass
        boolean[] rec = {false, false, true, true, false};
        byte[] f = new byte[81];
        LaneBits.entry(f, rec, ClusterIcon.OVERPASS_ENTRY_LC);
        eqs("overpass entry bits (0x43)", hex(f, LaneBits.OFF_OVER), "0c00"); // bits 2,3 = 0x0c
        byte[] f2 = new byte[81];
        LaneBits.entry(f2, rec, ClusterIcon.UNDERPASS_ENTRY_LC);
        eqs("underpass uses 0x45", hex(f2, LaneBits.OFF_UNDER), "0c00");
        eqs("overpass offset untouched for under", hex(f2, LaneBits.OFF_OVER), "0000");
        // side road right: mark lanes left of first recommended (index 0,1 = 0x03)
        byte[] f3 = new byte[81];
        LaneBits.side(f3, rec, ClusterIcon.OVERPASS_SIDE_R, true);
        eqs("side right marks lanes left of block", hex(f3, LaneBits.OFF_OVER), "0300");
        // side road left: mark lanes right of last recommended (index 4 = 0x10)
        byte[] f4 = new byte[81];
        LaneBits.side(f4, rec, ClusterIcon.OVERPASS_SIDE_L, false);
        eqs("side left marks lanes right of block", hex(f4, LaneBits.OFF_OVER), "1000");

        GuidanceParser.Lanes lanes = new GuidanceParser.Lanes();
        GuidanceParser.Lane lane = new GuidanceParser.Lane();
        lane.index = 1; lane.status = 255; lane.angles = new int[]{0,90,-90}; lane.highlights = new int[]{90};
        lanes.lanes.add(lane);
        byte[] encoded = LaneFrame.encode(lanes, ClusterIcon.OVERPASS_ENTRY_LC);
        eq("lane frame size", encoded.length, 81);
        eq("lane frame header", encoded[0] & 255, 0xf1);
        eq("lane count", encoded[1], 1);
        eq("per-slot 2-bit possibilities ignore numeric status", encoded[3], 1 | (2<<2) | (1<<4));
        eq("straight direction code", encoded[0x13], 1);
        eq("right direction code", encoded[0x14], 5);
        eq("left direction code", encoded[0x15], 3);
        eq("highlight marks overpass mask", encoded[0x43], 1);
        lane.highlights = new int[]{45};
        eq("highlight absent from angles clears", LaneFrame.encode(lanes,0)[1], 0);
        lane.highlights = new int[0]; lane.angles = new int[]{17};
        eq("unknown angle clears rather than guesses", LaneFrame.encode(lanes,0)[1], 0);
        lane.angles = new int[]{0,45,90,135};
        eq("more than three directions clears rather than truncates", LaneFrame.encode(lanes,0)[1], 0);
        Maneuver turn = m(""); turn.type = 5;
        eq("continue road stock icon", ClusterIcon.of(turn), 0xac);
        for (int type = 0; type <= 53; type++) {
            turn.type = type; turn.exitAngle = 90;
            if (type != 0) eq("defined turn has icon " + type, ClusterIcon.of(turn) == ClusterIcon.NONE ? 0 : 1, 1);
        }

        System.out.println(fails == 0 ? "hud all match" : fails + " failed");
        System.exit(fails == 0 ? 0 : 1);
    }
}
