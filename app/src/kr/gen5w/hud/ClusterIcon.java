package kr.gen5w.hud;

/** Exact V039 HKMC_DiPO RouteGuidance maneuver-to-cluster mapping. */
public final class ClusterIcon {
    public static final int NONE = -1;
    public static final int OVERPASS_ENTRY_LC = 0x58, OVERPASS_ENTRY_R = 0x57;
    public static final int OVERPASS_SIDE_L = 0x52, OVERPASS_SIDE_R = 0x51;
    public static final int UNDERPASS_ENTRY_LC = 0x5b, UNDERPASS_ENTRY_R = 0x5a;
    public static final int UNDERPASS_SIDE_L = 0x55, UNDERPASS_SIDE_R = 0x54;
    public static final int IC_ENTER_C = 0xa0, IC_ENTER_R = 0xa1, IC_ENTER_L = 0xa2;
    public static final int IC_EXIT_C = 0xa3, IC_EXIT_R = 0xa4, IC_EXIT_L = 0xa5;
    public static final int TOLL = 0xb2, REST_AREA = 0xb7;

    private ClusterIcon() {}

    /**
     * Maps structured iAP2 RouteGuidance fields to V039 cluster icons, upgrading
     * non-directional straight/no-turn maneuvers to TOLL (0xb2) or REST_AREA (0xb7)
     * when road/description text indicates a tollgate or rest area/drowsiness shelter.
     */
    public static int of(Maneuver m) {
        if (m == null || m.type < 0 || m.type > 53) return NONE;
        final int d = m.drivingSide, j = m.junctionType, a = m.exitAngle;
        switch (m.type) {
            case 0:
                if (j == 1) return d == 0 ? roundaboutByAngle(a) : NONE;
                return d == 0 && j == 0 && a == 0 ? facilityIcon(m.afterRoad, m.desc) : NONE;
            case 1:
                if (j == 0 && a == -120) return 0x45;
                if (d == 0 && j == 0 && a == -90) return 0x46;
                if (j == 0 && a == -60) return 0x47;
                if (j == 0 && a == -45) return 0x91;
                if (d == 1 && j == 1 && a == -120) return 0xc8;
                if (d == 1 && j == 1 && a == -90) return 0xc9;
                if (d == 1 && j == 1 && a == -30) return 0xcb;
                return noAngle(d, j, a) ? 0x46 : NONE;
            case 2:
                if (j == 0 && a == 60) return 0x42;
                if (d == 0 && j == 0 && a == 90) return 0x43;
                if (j == 0 && a == 120) return 0x44;
                if (d == 0 && j == 1 && a == 0) return 0x60;
                if (d == 1 && j == 1 && a == 0) return 0xc1;
                if (d == 1 && j == 1 && a == 90) return 0xc3;
                if (d == 1 && j == 1 && a == 120) return 0xc4;
                if (d == 1 && j == 1 && a == 180) return 0xc6;
                if (d == 0 && j == 0 && a == 45) return 0x90;
                return noAngle(d, j, a) ? 0x43 : NONE;
            case 3:
                return d == 0 && j == 0 && a == 0 ? refineManeuver(0x41, m.afterRoad, m.desc) : NONE;
            case 4:
                if (j != 0) return NONE;
                return d == 0 ? 0x48 : d == 1 ? 0x49 : NONE;
            case 5:
                return d == 0 && j == 0 && a == 0 ? refineManeuver(0xac, m.afterRoad, m.desc) : NONE;
            case 6: return j == 1 && d == 0 ? roundaboutByAngle(a) : NONE;
            case 8: case 10: return noAngle(d, j, a) ? IC_EXIT_C : NONE;
            case 9: return d == 0 && j == 0 && a == 0 ? 0xa0 : NONE;
            case 12: return d == 0 && j == 0 ? 0x70 : NONE;
            case 15: return d == 0 && j == 0 && a == 0 ? 0xb0 : NONE;
            case 19: return d == 0 && j == 1 && a == -180 ? 0x66 : NONE;
            case 22: return d == 0 && j == 0 && a == 0 ? 0xa5 : NONE;
            case 23: return d == 0 && j == 0 && a == 0 ? 0xa4 : NONE;
            case 24: return d == 0 && j == 0 && a == 0 ? 0x72 : NONE;
            case 25: return d == 0 && j == 0 && a == 0 ? 0x71 : NONE;
            case 28: return d == 0 && j == 1 && a == 135 ? 0x64 : NONE;
            case 29: return d == 0 && j == 1 && a == 90 ? 0x63 : NONE;
            case 31:
                if (j == 1 && a == 0 && d == 0) return 0x61;
                return j == 1 && a == 0 && d == 1 ? 0xc0 : NONE;
            case 32: return d == 0 && j == 1 && a == -45 ? 0x68 : NONE;
            case 33: return d == 0 && j == 1 && a == -90 ? 0x69 : NONE;
            case 34: return d == 0 && j == 1 && a == -135 ? 0x68 : NONE;
            case 35: return d == 0 && j == 1 && a == -180 ? 0x66 : NONE;
            case 47:
                if (j == 0 && a >= -150 && a <= -135) return 0x45;
                if (j == 0 && a == -30) return 0x47;
                return noAngle(d, j, a) ? 0x45 : NONE;
            case 48:
                if (j == 0 && a == 30) return 0x42;
                if (j == 0 && a >= 135 && a <= 150) return 0x44;
                return noAngle(d, j, a) ? 0x44 : NONE;
            case 49: return j == 0 && a == -45 || noAngle(d, j, a) ? 0x47 : NONE;
            case 50: return j == 0 && a == 45 || noAngle(d, j, a) ? 0x42 : NONE;
            case 13: return noAngle(d, j, a) ? 0x47 : NONE;
            case 14: return noAngle(d, j, a) ? 0x42 : NONE;
            case 52: return d == 0 && j == 0 && a == 0 ? 0xae : NONE;
            case 53: return d == 0 && j == 0 && a == 0 ? 0xad : NONE;
            default: return NONE;
        }
    }

    /**
     * The type itself names the direction but the phone sent no exit angle (field absent, or 0),
     * right-hand traffic, ordinary intersection. Stock DiPO would show nothing here; the type is
     * still structured data, so the matching default icon is used. Roundabouts are not covered.
     */
    /**
     * Roundabout sent as NoTurn(0) or EnterRoundabout(6) with junction type 1: stock only accepts
     * types 28..35, but those use these same exact angles. Other angles stay empty.
     */
    private static int roundaboutByAngle(int a) {
        switch (a) {
            case 0: return 0x61;
            case 90: return 0x63;
            case 135: return 0x64;
            case -45: case -135: return 0x68;
            case -90: return 0x69;
            case -180: return 0x66;
            default: return NONE;
        }
    }

    private static boolean noAngle(int d, int j, int a) {
        return d == 0 && j == 0 && (a == Maneuver.UNKNOWN_ANGLE || a == 0);
    }

    /**
     * Upgrades non-directional straight icons (0x41, 0xac) to TOLL (0xb2) or REST_AREA (0xb7)
     * when road/description text matches highway tollgate or rest area/drowsiness shelter keywords.
     * Directional turns, ramps, forks, and roundabouts are always preserved.
     */
    public static int refineManeuver(int baseIcon, String road, String desc) {
        if (baseIcon != 0x41 && baseIcon != 0xac) return baseIcon;
        int facility = facilityIcon(road, desc);
        return facility != NONE ? facility : baseIcon;
    }

    private static int facilityIcon(String road, String desc) {
        if (isIntersectionName(road) || isIntersectionName(desc)) return NONE;
        if (isTollText(road) || isTollText(desc)) return TOLL;
        if (isRestAreaText(road) || isRestAreaText(desc)) return REST_AREA;
        return NONE;
    }

    /** Ordinary junction names such as "휴게소삼거리" are not the facility itself. */
    private static boolean isIntersectionName(String s) {
        if (s == null) return false;
        return s.contains("삼거리") || s.contains("사거리") || s.contains("오거리")
                || s.contains("네거리") || s.contains("교차로") || s.contains("로터리");
    }

    private static boolean isTollText(String s) {
        if (s == null || s.isEmpty()) return false;
        return s.contains("톨게이트")
                || s.contains("요금소")
                || s.contains("하이패스")
                || s.contains("원톨링")
                || s.contains("통행료")
                || s.contains("요금:")
                || s.contains("요금 :")
                || hasTgToken(s);
    }

    private static boolean isRestAreaText(String s) {
        if (s == null || s.isEmpty()) return false;
        return s.contains("휴게소") || s.contains("졸음쉼터");
    }

    private static boolean hasTgToken(String s) {
        int idx = 0;
        while ((idx = s.indexOf("TG", idx)) >= 0) {
            boolean leftOk = idx == 0 || !isAsciiLetterOrDigit(s.charAt(idx - 1));
            int end = idx + 2;
            boolean rightOk = end == s.length() || !isAsciiLetterOrDigit(s.charAt(end));
            if (leftOk && rightOk) return true;
            idx = end;
        }
        return false;
    }

    private static boolean isAsciiLetterOrDigit(char c) {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
    }

}
