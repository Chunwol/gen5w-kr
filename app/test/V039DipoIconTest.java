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
        int U = Maneuver.UNKNOWN_ANGLE;
        icon("left, no angle", 0x46, m(1, 0, 0, U));
        icon("right, no angle", 0x43, m(2, 0, 0, U));
        icon("sharp left, no angle", 0x45, m(47, 0, 0, U));
        icon("sharp right, no angle", 0x44, m(48, 0, 0, U));
        icon("slight left, no angle", 0x47, m(49, 0, 0, 0));
        icon("slight right, no angle", 0x42, m(50, 0, 0, 0));
        icon("keep left", 0x47, m(13, 0, 0, U));
        icon("keep right", 0x42, m(14, 0, 0, U));
        icon("off ramp without side uses the centre exit", ClusterIcon.IC_EXIT_C, m(8, 0, 0, U));
        icon("arrive end of navigation (type 10) maps to destination", 0x70, m(10, 0, 0, 0));
        icon("left-hand traffic stays empty", ClusterIcon.NONE, m(13, 1, 0, U));
        Maneuver rest = m(3, 0, 0, 0); rest.afterRoad = "안성휴게소";
        icon("rest area text", ClusterIcon.REST_AREA, rest);
        rest.afterRoad = "휴게소삼거리";
        icon("junction name is not a rest area", 0x41, rest);
        Maneuver toll = m(0, 0, 0, 0); toll.desc = "서울TG";
        icon("toll text on no-turn", ClusterIcon.TOLL, toll);
        Maneuver overEntry = m(3, 0, 0, 0); overEntry.afterRoad = "성산고가차도 진입";
        icon("overpass entry straight", ClusterIcon.OVERPASS_ENTRY_LC, overEntry);
        Maneuver overEntryR = m(50, 0, 0, 0); overEntryR.afterRoad = "고가차도 진입";
        icon("overpass entry slight right (Kakao/Naver RightOverpass)", ClusterIcon.OVERPASS_ENTRY_R, overEntryR);
        Maneuver overSideL = m(13, 0, 0, U); overSideL.afterRoad = "고가차도 옆길";
        icon("overpass side left (Kakao/Naver LeftOverpathSide)", ClusterIcon.OVERPASS_SIDE_L, overSideL);
        Maneuver overSideR = m(14, 0, 0, U); overSideR.afterRoad = "고가도로옆";
        icon("overpass side right (Tmap/Kakao/Naver RightOverpathSide)", ClusterIcon.OVERPASS_SIDE_R, overSideR);
        Maneuver underEntry = m(3, 0, 0, 0); underEntry.afterRoad = "전방에 지하 차도 진입";
        icon("underpass entry straight", ClusterIcon.UNDERPASS_ENTRY_LC, underEntry);
        Maneuver underEntryR = m(50, 0, 0, 0); underEntryR.afterRoad = "지하차도 진입";
        icon("underpass entry slight right", ClusterIcon.UNDERPASS_ENTRY_R, underEntryR);
        Maneuver underSideL = m(3, 0, 0, 0); underSideL.afterRoad = "지하차도옆";
        icon("underpass side straight defaults to left/centre side", ClusterIcon.UNDERPASS_SIDE_L, underSideL);
        Maneuver underSideR = m(14, 0, 0, U); underSideR.afterRoad = "오른쪽에 지하 차도 옆길";
        icon("underpass side right", ClusterIcon.UNDERPASS_SIDE_R, underSideR);
        Maneuver overJunc = m(3, 0, 0, 0); overJunc.afterRoad = "고가사거리";
        icon("intersection name with 고가 stays straight", 0x41, overJunc);
        Maneuver turn90Over = m(1, 0, 0, -90); turn90Over.afterRoad = "고가차도 진입";
        icon("90-degree turn is not overridden by overpass text", 0x46, turn90Over);
        icon("naver clock-face intersection -120", 0x45, m(0, 0, 0, -120));
        icon("naver clock-face intersection -90", 0x46, m(0, 0, 0, -90));
        icon("naver clock-face intersection -45", 0x47, m(0, 0, 0, -45));
        icon("naver clock-face intersection +45", 0x42, m(0, 0, 0, 45));
        icon("naver clock-face intersection +90", 0x43, m(0, 0, 0, 90));
        icon("naver clock-face intersection +120", 0x44, m(0, 0, 0, 120));
        icon("noturn roundabout 90", 0x63, m(0, 0, 1, 90));
        icon("noturn roundabout 30 (Naver/Kakao 1 o'clock)", 0x63, m(0, 0, 1, 30));
        icon("noturn roundabout 120 (Naver/Kakao 4 o'clock)", 0x64, m(0, 0, 1, 120));
        icon("noturn roundabout +180 (Naver U-turn)", 0x66, m(0, 0, 1, 180));
        icon("noturn roundabout -150 (Naver 7 o'clock)", 0x68, m(0, 0, 1, -150));
        icon("tmap roundabout dir1/2 (type 50 + j=1 + 45)", 0x63, m(50, 0, 1, 45));
        icon("tmap roundabout dir3 (type 2 + j=1 + 90)", 0x63, m(2, 0, 1, 90));
        icon("tmap roundabout dir4/5 (type 48 + j=1 + 135)", 0x64, m(48, 0, 1, 135));
        icon("tmap roundabout dir6 (type 19 + j=1 + 180)", 0x66, m(19, 0, 1, 180));
        icon("tmap roundabout dir7/8 (type 47 + j=1 + -135)", 0x68, m(47, 0, 1, -135));
        icon("tmap roundabout dir9 (type 1 + j=1 + -90)", 0x69, m(1, 0, 1, -90));
        icon("tmap roundabout dir10/11 (type 49 + j=1 + -45)", 0x68, m(49, 0, 1, -45));
        icon("tmap roundabout dir12 (type 3 + j=1 + 0)", 0x61, m(3, 0, 1, 0));
        icon("enter roundabout -90", 0x69, m(6, 0, 1, -90));
        icon("enter roundabout 135", 0x64, m(6, 0, 1, 135));
        icon("kakao rotary (type 6 + j=0 + 360)", 0x61, m(6, 0, 0, 360));
        icon("kakao rotary (type 6 + j=0 + 270)", 0x69, m(6, 0, 0, 270));
        icon("roundabout arbitrary unmapped angle stays empty", ClusterIcon.NONE, m(6, 0, 1, 77));
        icon("roundabout without exit angle stays empty", ClusterIcon.NONE, m(6, 0, 1, U));
        icon("odd angle on keep stays empty", ClusterIcon.NONE, m(14, 0, 0, 77));
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
        icon("generic off ramp, centre exit", ClusterIcon.IC_EXIT_C, m(8, 0, 0, 0));
        // Stock shows nothing without an exit angle; the type alone names the side, so the
        // default icon is used (see the angle-less cases above).
        icon("left without exit angle uses default", 0x46,
                m(1, 0, 0, Maneuver.UNKNOWN_ANGLE));
        icon("enter roundabout with stock angle", 0x63, m(6, 0, 1, 90));
        icon("ordinal alone does not imply angle", ClusterIcon.NONE, m(30, 0, 1, 90));
        icon("end road left unsupported", ClusterIcon.NONE, m(20, 0, 0, -90));
        icon("change highway generic unsupported", ClusterIcon.NONE, m(51, 0, 0, 0));

        System.out.println("V039 DiPO icons: " + passed + " passed");
    }
}
