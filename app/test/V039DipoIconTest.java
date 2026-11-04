import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.Maneuver;

/** Exact regression vectors transcribed from V039 HKMC_DiPO RouteGuidanceAnalyzer. */
public final class V039DipoIconTest {
    static int passed;
    static Maneuver m(int type, int drivingSide, int junctionType, int exitAngle) {
        Maneuver m = new Maneuver();
        m.type = type; m.drivingSide = drivingSide;
        m.junctionType = junctionType; m.exitAngle = exitAngle;
        return m;
    }
    static void icon(String name, int expected, Maneuver m) {
        int actual = ClusterIcon.of(m);
        if (actual != expected) throw new AssertionError(name + " expected=0x"
                + Integer.toHexString(expected) + " actual=0x" + Integer.toHexString(actual));
        passed++;
    }
    public static void main(String[] args) {
        icon("left 90", 0x46, m(1, 0, 0, -90));
        icon("right 90", 0x43, m(2, 0, 0, 90));
        icon("left sharp 120", 0x45, m(1, 0, 0, -120));
        icon("left slight 60", 0x47, m(1, 0, 0, -60));
        icon("right slight 60", 0x42, m(2, 0, 0, 60));
        icon("right sharp 120", 0x44, m(2, 0, 0, 120));
        icon("straight", 0x41, m(3, 0, 0, 0));
        icon("right hand traffic uturn", 0x48, m(4, 0, 0, 0));
        icon("continue", 0xac, m(5, 0, 0, 0));
        icon("on ramp", 0xa0, m(9, 0, 0, 0));
        icon("left off ramp", 0xa5, m(22, 0, 0, 0));
        icon("right off ramp", 0xa4, m(23, 0, 0, 0));
        icon("arrive left", 0x72, m(24, 0, 0, 0));
        icon("arrive right", 0x71, m(25, 0, 0, 0));
        icon("roundabout 1st exit", 0x64, m(28, 0, 1, 135));
        icon("roundabout 2nd exit", 0x63, m(29, 0, 1, 90));
        icon("roundabout 4th exit", 0x61, m(31, 0, 1, 0));
        icon("roundabout 5th exit", 0x68, m(32, 0, 1, -45));
        icon("roundabout 6th exit", 0x69, m(33, 0, 1, -90));
        icon("roundabout 7th exit", 0x68, m(34, 0, 1, -135));
        icon("roundabout 8th exit", 0x66, m(35, 0, 1, -180));
        icon("sharp left boundary", 0x45, m(47, 0, 0, -150));
        icon("slight-left value used by sharp-left type", 0x47, m(47, 0, 0, -30));
        icon("sharp right boundary", 0x44, m(48, 0, 0, 150));
        icon("slight-right value used by sharp-right type", 0x42, m(48, 0, 0, 30));
        icon("slight left", 0x47, m(49, 0, 0, -45));
        icon("slight right", 0x42, m(50, 0, 0, 45));
        icon("change highway left", 0xae, m(52, 0, 0, 0));
        icon("change highway right", 0xad, m(53, 0, 0, 0));

        // V039 emits no cluster icon for these combinations. Do not invent one.
        icon("generic off ramp unsupported", ClusterIcon.NONE, m(8, 0, 0, 0));
        icon("left without exit angle unsupported", ClusterIcon.NONE,
                m(1, 0, 0, Maneuver.UNKNOWN_ANGLE));
        icon("generic roundabout enter unsupported", ClusterIcon.NONE, m(6, 0, 1, 90));
        icon("ordinal alone does not imply angle", ClusterIcon.NONE, m(30, 0, 1, 90));
        icon("end road left unsupported", ClusterIcon.NONE, m(20, 0, 0, -90));
        icon("change highway generic unsupported", ClusterIcon.NONE, m(51, 0, 0, 0));

        System.out.println("V039 DiPO icons: " + passed + " passed");
    }
}
