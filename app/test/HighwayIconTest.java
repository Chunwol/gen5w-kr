import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.Maneuver;

/** Ensures highway semantics come from structured fields rather than place-name guesses. */
public final class HighwayIconTest {
    private static int checks;
    private static void eq(String label, int got, int want) {
        checks++; if (got != want) throw new AssertionError(label + ": " + got + " != " + want);
    }
    private static Maneuver m(int type, String road) {
        Maneuver m = new Maneuver(); m.type = type; m.afterRoad = road;
        m.drivingSide = 0; m.junctionType = 0; m.exitAngle = 0; return m;
    }
    public static void main(String[] args) {
        eq("on-ramp structured", ClusterIcon.of(m(9, "일반도로")), ClusterIcon.IC_ENTER_C);
        eq("left off-ramp structured", ClusterIcon.of(m(22, "서울TG")), ClusterIcon.IC_EXIT_L);
        eq("right off-ramp structured", ClusterIcon.of(m(23, "안성휴게소")), ClusterIcon.IC_EXIT_R);
        eq("generic off-ramp shows the centre exit, text gives no side", ClusterIcon.of(m(8, "동탄IC 진출 오른쪽")), ClusterIcon.IC_EXIT_C);
        eq("JC text does not create a maneuver", ClusterIcon.of(m(6, "판교JC")), ClusterIcon.NONE);
        eq("TG text upgrades straight", ClusterIcon.of(m(3, "서울TG")), ClusterIcon.TOLL);
        eq("Tmap toll fee text upgrades straight", ClusterIcon.of(m(3, "경부고속도로\n요금: 1000원")), ClusterIcon.TOLL);
        eq("Kakao NoTurn tollgate text upgrades", ClusterIcon.of(m(0, "서울톨게이트")), ClusterIcon.TOLL);
        eq("Rest area text upgrades straight", ClusterIcon.of(m(3, "안성휴게소")), ClusterIcon.REST_AREA);
        eq("Drowsiness shelter text upgrades straight", ClusterIcon.of(m(3, "졸음쉼터")), ClusterIcon.REST_AREA);
        eq("IC text on straight stays straight", ClusterIcon.of(m(3, "판교IC")), 0x41);
        int[] icons = {0, -1, 0x43, ClusterIcon.IC_EXIT_R, ClusterIcon.TOLL, ClusterIcon.REST_AREA};
        for (int icon : icons) eq("AA directional/facility icon preserved", ClusterIcon.refineManeuver(icon, "좌측 서울TG", "우측"), icon);
        // Verbatim guidance templates found in the 3 apps' packages (Kakao KNSDKWrapper,
        // Naver resources.arsc, Tmap binary/classes30.dex), on the slight-right base they arrive as.
        String[][] app = {
            {"오른쪽 지하차도 옆길", "54"}, {"지하차도 오른쪽 옆길입니다.", "54"}, {"지하차도 옆길 입니다.", "55"},
            {"지하도로 옆", "55"}, {"오른쪽 지하차도 진입", "5a"}, {"지하차도 진입입니다.", "5a"},
            {"오른쪽 고가도로 옆길", "51"}, {"고가차도 오른쪽 옆길입니다.", "51"}, {"고가도로 옆", "51"},
            {"오른쪽 고가도로 진입", "57"}, {"오른쪽 지하차도로 진입하세요.", "5a"}};
        for (String[] c : app) {
            int want = Integer.parseInt(c[1], 16);
            int base = want == 0x55 ? 0x47 : 0x42;
            eq("app template " + c[0], ClusterIcon.refineManeuver(base, "", c[0]), want);
        }
        System.out.println("PASS HighwayIconTest " + checks);
    }
}
