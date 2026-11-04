package kr.gen5w.hud;

import java.util.Locale;

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
     * straight/no-turn maneuvers to TOLL (0xb2) or REST_AREA (0xb7) and straight or
     * slight/keep turns to overpass/underpass icons (0x51..0x5b) when road/description
     * text indicates a highway facility or grade-separated ramp/side road.
     */
    public static int of(Maneuver m) {
        if (m == null || m.type < 0 || m.type > 53) return NONE;
        final int d = m.drivingSide, j = m.junctionType, a = m.exitAngle;
        switch (m.type) {
            case 0:
                if (j == 1) return d == 0 ? roundaboutByAngle(a) : NONE;
                if (d == 0 && j == 0) {
                    if (a == 0 || a == Maneuver.UNKNOWN_ANGLE) {
                        int grade = gradeSeparatedIcon(0, m.afterRoad, m.desc);
                        return grade != NONE ? grade : facilityIcon(m.afterRoad, m.desc);
                    }
                    return intersectionByAngle(a);
                }
                return NONE;
            case 1:
                if (j == 0 && a == -120) return 0x45;
                if (d == 0 && j == 0 && a == -90) return 0x46;
                if (j == 0 && a == -60) return 0x47;
                if (j == 0 && a == -45) return 0x91;
                if (d == 0 && j == 1) return roundaboutByAngle(a);
                if (d == 1 && j == 1 && a == -120) return 0xc8;
                if (d == 1 && j == 1 && a == -90) return 0xc9;
                if (d == 1 && j == 1 && a == -30) return 0xcb;
                return noAngle(d, j, a) ? 0x46 : NONE;
            case 2:
                if (j == 0 && a == 60) return 0x42;
                if (d == 0 && j == 0 && a == 90) return 0x43;
                if (j == 0 && a == 120) return 0x44;
                if (d == 0 && j == 1 && a == 0) return 0x60;
                if (d == 0 && j == 1) return roundaboutByAngle(a);
                if (d == 1 && j == 1 && a == 0) return 0xc1;
                if (d == 1 && j == 1 && a == 90) return 0xc3;
                if (d == 1 && j == 1 && a == 120) return 0xc4;
                if (d == 1 && j == 1 && a == 180) return 0xc6;
                if (d == 0 && j == 0 && a == 45) return 0x90;
                return noAngle(d, j, a) ? 0x43 : NONE;
            case 3:
                if (d == 0 && j == 1) return roundaboutByAngle(a);
                return d == 0 && j == 0 && a == 0 ? refineManeuver(0x41, m.afterRoad, m.desc) : NONE;
            case 4:
                if (j != 0) return NONE;
                return d == 0 ? 0x48 : d == 1 ? 0x49 : NONE;
            case 5:
                return d == 0 && j == 0 && a == 0 ? refineManeuver(0xac, m.afterRoad, m.desc) : NONE;
            case 6:
                if (d != 0) return NONE;
                if (j == 1) return roundaboutByAngle(a);
                return j == 0 && a != 0 && a != Maneuver.UNKNOWN_ANGLE ? roundaboutByAngle(a) : NONE;
            case 8: return noAngle(d, j, a) ? IC_EXIT_C : NONE;
            case 9: return d == 0 && j == 0 && a == 0 ? 0xa0 : NONE;
            case 10: case 12: return d == 0 && j == 0 ? 0x70 : NONE;
            case 15: return d == 0 && j == 0 && a == 0 ? 0xb0 : NONE;
            case 19: return d == 0 && j == 1 && (a == -180 || a == 180) ? 0x66 : NONE;
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
                if (d == 0 && j == 1) return roundaboutByAngle(a);
                if (j == 0 && a >= -150 && a <= -135) return 0x45;
                if (j == 0 && a == -30) return 0x47;
                return noAngle(d, j, a) ? 0x45 : NONE;
            case 48:
                if (d == 0 && j == 1) return roundaboutByAngle(a);
                if (j == 0 && a == 30) return 0x42;
                if (j == 0 && a >= 135 && a <= 150) return 0x44;
                return noAngle(d, j, a) ? 0x44 : NONE;
            case 49:
                if (d == 0 && j == 1) return roundaboutByAngle(a);
                return j == 0 && a == -45 || noAngle(d, j, a) ? refineManeuver(0x47, m.afterRoad, m.desc) : NONE;
            case 50:
                if (d == 0 && j == 1) return roundaboutByAngle(a);
                return j == 0 && a == 45 || noAngle(d, j, a) ? refineManeuver(0x42, m.afterRoad, m.desc) : NONE;
            case 13: return noAngle(d, j, a) ? refineManeuver(0x47, m.afterRoad, m.desc) : NONE;
            case 14: return noAngle(d, j, a) ? refineManeuver(0x42, m.afterRoad, m.desc) : NONE;
            case 52: return d == 0 && j == 0 && a == 0 ? 0xae : NONE;
            case 53: return d == 0 && j == 0 && a == 0 ? 0xad : NONE;
            default: return NONE;
        }
    }

    /**
     * Clock-face intersection turns sent by Naver CarPlay as NoTurn(0) + Intersection(0) + exitAngle.
     */
    private static int intersectionByAngle(int a) {
        switch (a) {
            case -120: return 0x45;
            case -90: return 0x46;
            case -60: case -45: return 0x47;
            case 45: case 60: return 0x42;
            case 90: return 0x43;
            case 120: return 0x44;
            default: return NONE;
        }
    }

    /**
     * Roundabout exit angles emitted by V039 stock DiPO (45° steps) and Korean CarPlay apps
     * (Tmap 45° steps with +45°/+180°, Naver/Kakao 30° steps in signed -180..+180 or 30..360).
     */
    private static int roundaboutByAngle(int a) {
        switch (a) {
            case 0: case 360: return 0x61;
            case 30: case 45: case 60: case 90: return 0x63;
            case 120: case 135: case 150: return 0x64;
            case 180: case -180: return 0x66;
            case -30: case -45: case -60: case -120: case -135: case -150:
            case 210: case 225: case 240: case 300: case 315: case 330:
                return 0x68;
            case -90: case 270: return 0x69;
            default: return NONE;
        }
    }

    private static boolean noAngle(int d, int j, int a) {
        return d == 0 && j == 0 && (a == Maneuver.UNKNOWN_ANGLE || a == 0);
    }

    /**
     * Upgrades straight/slight icons (0x41, 0xac, 0x47, 0x42) to overpass/underpass icons (0x51..0x5b),
     * and non-directional straight icons (0x41, 0xac) to TOLL (0xb2) or REST_AREA (0xb7).
     * Normal 90° turns, sharp turns, ramps, forks, and roundabouts are always preserved.
     */
    public static int refineManeuver(int baseIcon, String road, String desc) {
        if (baseIcon == 0x41 || baseIcon == 0xac || baseIcon == 0x47 || baseIcon == 0x42) {
            int grade = gradeSeparatedIcon(baseIcon, road, desc);
            if (grade != NONE) return grade;
        }
        if (baseIcon != 0x41 && baseIcon != 0xac) return baseIcon;
        int facility = facilityIcon(road, desc);
        return facility != NONE ? facility : baseIcon;
    }

    private static int gradeSeparatedIcon(int baseIcon, String road, String desc) {
        if (isIntersectionName(road) || isIntersectionName(desc)) return NONE;
        String text = ((road == null ? "" : road) + " " + (desc == null ? "" : desc)).trim();
        if (text.isEmpty()) return NONE;
        boolean under = isUnderpassText(text);
        boolean over = !under && isOverpassText(text);
        if (!under && !over) return NONE;
        int side = gradeSide(baseIcon, text);
        boolean sideRoad = isSideRoadText(text);
        if (under) {
            if (sideRoad) return side > 0 ? UNDERPASS_SIDE_R : UNDERPASS_SIDE_L;
            return side > 0 ? UNDERPASS_ENTRY_R : UNDERPASS_ENTRY_LC;
        }
        if (sideRoad) return side > 0 ? OVERPASS_SIDE_R : OVERPASS_SIDE_L;
        return side > 0 ? OVERPASS_ENTRY_R : OVERPASS_ENTRY_LC;
    }

    private static int gradeSide(int baseIcon, String text) {
        if (baseIcon == 0x42) return 1;
        if (baseIcon == 0x47) return -1;
        if (hasAny(text, "오른쪽", "우측", "오른편")) return 1;
        if (hasAny(text, "왼쪽", "좌측", "왼편")) return -1;
        return 0;
    }

    private static boolean isUnderpassText(String text) {
        return hasAny(text, "지하차도", "지하 차도", "지하도로", "지하 도로", "지하차로", "지하 차로",
                "지하차선", "지하 차선", "지하길", "언더패스", "underpass", "지하 옆길", "지하옆길");
    }

    private static boolean isOverpassText(String text) {
        return hasAny(text, "고가차도", "고가 차도", "고가도로", "고가 도로", "고가차로", "고가 차로",
                "고가차선", "고가 차선", "고가교", "고가길", "오버패스", "overpass",
                "고가 옆길", "고가옆길", "고가 옆", "고가옆");
    }

    private static boolean isSideRoadText(String text) {
        if (hasAny(text, "진입", "본선", "올라")) return false;
        return hasAny(text, "옆길", "옆 길", "측도", "우측 도로", "좌측 도로", "우측도로", "좌측도로",
                "오른쪽 도로", "왼쪽 도로", "오른쪽길", "왼쪽길", "바깥길",
                "옆 차로", "옆차로", "옆 차선", "옆차선", "옆길 도로", "측면 도로", "측면도로",
                "지하차도옆", "지하차도 옆", "고가도로옆", "고가도로 옆", "고가차도옆", "고가차도 옆",
                "고가 옆", "고가옆", "지하 옆", "지하옆");
    }

    private static boolean hasAny(String s, String... keys) {
        String low = s.toLowerCase(Locale.ROOT);
        for (String k : keys) if (low.contains(k)) return true;
        return false;
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
