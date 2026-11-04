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
        eq("generic off-ramp not invented", ClusterIcon.of(m(8, "동탄IC 진출")), ClusterIcon.NONE);
        eq("JC text does not create a maneuver", ClusterIcon.of(m(6, "판교JC")), ClusterIcon.NONE);
        eq("TG text does not replace straight", ClusterIcon.of(m(3, "서울TG")), 0x41);
        int[] icons = {0, -1, 0x43, ClusterIcon.IC_EXIT_R, ClusterIcon.TOLL, ClusterIcon.REST_AREA};
        for (int icon : icons) eq("AA stock icon preserved", ClusterIcon.refineManeuver(icon, "좌측 서울TG", "우측"), icon);
        System.out.println("PASS HighwayIconTest " + checks);
    }
}
