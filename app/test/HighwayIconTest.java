import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.Maneuver;

/** Synthetic conflicting inputs, not captures from named map applications. */
public final class HighwayIconTest {
    private static int checks;
    private static void eq(String label, int got, int want) {
        checks++;
        if (got != want) throw new AssertionError(label + ": " + got + " != " + want);
    }
    private static Maneuver m(int type, String road) {
        Maneuver m = new Maneuver(); m.type = type; m.afterRoad = road; return m;
    }
    public static void main(String[] args) {
        int[] types = {8, 9, 22, 23};
        int[] icons = {ClusterIcon.IC_EXIT_C, ClusterIcon.IC_ENTER_C,
            ClusterIcon.IC_EXIT_L, ClusterIcon.IC_EXIT_R};
        String[] roads = {"서울TG", "판교JC 진입", "동탄IC 진출", "안성휴게소", ""};
        for (int i = 0; i < types.length; i++) for (String road : roads)
            eq("CarPlay structured ramp wins over destination " + types[i],
                ClusterIcon.of(m(types[i], road)), icons[i]);
        eq("JC name alone does not mean enter", ClusterIcon.of(m(3, "판교JC")), 0x41);
        eq("IC destination alone does not mean enter", ClusterIcon.of(m(5, "동탄IC 방면")), 0xac);
        eq("explicit exit right beats conflicting road text",
            ClusterIcon.of(m(23, "좌측 판교JC 진입")), ClusterIcon.IC_EXIT_R);
        int[] fixedIcons = {0, -1, ClusterIcon.IC_EXIT_R, ClusterIcon.IC_ENTER_L,
            ClusterIcon.TOLL, ClusterIcon.REST_AREA, 0x70};
        for (int icon : fixedIcons)
            eq("AA explicit/empty icon preserved " + icon,
                ClusterIcon.refineManeuver(icon, "서울TG 진입", "우측"), icon);
        eq("AA right direction survives left road name",
            ClusterIcon.refineManeuver(0x43, "좌측 동탄IC 진출", ""), ClusterIcon.IC_EXIT_R);
        eq("AA left direction survives right road name",
            ClusterIcon.refineManeuver(0x46, "우측 동탄IC 진출", ""), ClusterIcon.IC_EXIT_L);
        eq("AA ordinary IC destination unchanged",
            ClusterIcon.refineManeuver(0x43, "동탄IC 방면", ""), 0x43);
        System.out.println("PASS HighwayIconTest " + checks);
    }
}
