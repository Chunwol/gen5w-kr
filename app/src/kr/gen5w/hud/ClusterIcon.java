package kr.gen5w.hud;

import java.util.Locale;

/**
 * Maps a CarPlay maneuver to the head unit cluster/HUD icon code. Pure logic, so
 * it is unit-tested on the JVM. Codes are the stock navigation engine's cluster
 * ids (see docs/design.md). NONE means "send nothing / clear the HUD".
 *
 * Korea drives on the right: "left of the recommended lane" etc. follow that.
 * The over/underpass and IC cases are recognised from the road-name text because
 * the CarPlay maneuver type does not distinguish them.
 */
public final class ClusterIcon {
    public static final int NONE = -1;

    // over/underpass: entry (left/centre, right) and the side road beside it
    public static final int OVERPASS_ENTRY_LC = 0x58, OVERPASS_ENTRY_R = 0x57;
    public static final int OVERPASS_SIDE_L = 0x52, OVERPASS_SIDE_R = 0x51;
    public static final int UNDERPASS_ENTRY_LC = 0x5b, UNDERPASS_ENTRY_R = 0x5a;
    public static final int UNDERPASS_SIDE_L = 0x55, UNDERPASS_SIDE_R = 0x54;
    // interchange: ramp enter (centre/right/left) and exit (centre/right/left)
    public static final int IC_ENTER_C = 0xa0, IC_ENTER_R = 0xa1, IC_ENTER_L = 0xa2;
    public static final int IC_EXIT_C = 0xa3, IC_EXIT_R = 0xa4, IC_EXIT_L = 0xa5;
    public static final int TOLL = 0xb2, REST_AREA = 0xb7;

    private ClusterIcon() {}

    /** side: -1 left, 0 centre, +1 right, 9 unknown -> picks the matching code of a triple. */
    static int pick(int side, int center, int right, int left) {
        if (side == 1) return right;
        if (side == -1) return left;
        return center; // centre or unknown
    }

    public static int of(Maneuver m) {
        if (m == null || m.type < 1 || m.type > 53) return NONE;
        String r = m.afterRoad == null ? "" : m.afterRoad;
        String d = m.desc == null ? "" : m.desc;
        String text = r + " " + d;
        int side = side(m);
        if (m.junctionType == 1 || m.type == 6 || m.type == 7 || m.type == 19
                || (m.type >= 28 && m.type <= 46)) return roundabout(m);
        // Keep the existing explicit ramp mapping. A destination
        // name (TG, rest area, or another IC) cannot change its maneuver kind.
        if (m.type == 8 || m.type == 9 || m.type == 22 || m.type == 23) return ordinary(m);

        if (hasAny(text, "터널", "tunnel")) {
            if (isSide(text)) return side > 0 ? UNDERPASS_SIDE_R : UNDERPASS_SIDE_L;
            return side > 0 ? UNDERPASS_ENTRY_R : UNDERPASS_ENTRY_LC;
        }
        if (hasAny(text, "지하차도", "지하 차도", "지하도로", "지하 도로", "지하차로", "지하 차로",
                "지하차선", "지하 차선", "지하길", "지하통로", "지하보차도", "언더패스", "underpass",
                "지하차도옆", "지하차도 옆", "지하차도 옆길", "지하차도옆길")) {
            if (isSide(text)) return side > 0 ? UNDERPASS_SIDE_R : UNDERPASS_SIDE_L;
            return side > 0 ? UNDERPASS_ENTRY_R : UNDERPASS_ENTRY_LC;
        }
        if (hasAny(text, "고가차도", "고가 차도", "고가도로", "고가 도로", "고가차로", "고가 차로",
                "고가차선", "고가 차선", "고가교", "고가길", "오버패스", "overpass",
                "고가도로옆", "고가도로 옆", "고가 옆길", "고가 옆", "고가옆길", "고가옆",
                "고가차도 옆길", "고가차도옆길", "고가차도 옆", "고가차도옆")) {
            if (isSide(text)) return side > 0 ? OVERPASS_SIDE_R : OVERPASS_SIDE_L;
            return side > 0 ? OVERPASS_ENTRY_R : OVERPASS_ENTRY_LC;
        }
        if (hasAny(text, "휴게소", "졸음쉼터", "졸음 쉼터", "간이휴게소", "간이 휴게소", "임시휴게소",
                "화물차라운지", "화물차 라운지", "복합휴게소", "rest area", "service area")) return REST_AREA;
        if (hasAny(text, "요금소", "톨게이트", "하이패스", "원톨링", "민자요금소", "민자 요금소",
                "개방식요금소", "통행료", "toll") || tollgateAbbreviation(text)) return TOLL;
        if (hasAny(text, "나들목", "분기점", "고속도로", "고속 도로", "도시고속도로", "도시 고속 도로",
                "순환도로", "순환 고속도로", "분기도로", "분기 도로", "램프", "램프도로", "onramp", "offramp")
                || interchangeAbbreviation(text)) {
            // Surface intersection turns (type 1/2) without ramp keywords preserve normal turn icons
            if ((m.type == 1 || m.type == 2) && !hasAny(text, "진입", "진출", "램프", "합류", "올라", "빠져", "나가", "출구", "onramp", "offramp")) {
                return ordinary(m);
            }
            if (m.type == 8 || m.type == 22 || m.type == 23
                    || (m.type != 9 && m.type != 24 && m.type != 25 && hasAny(text, "진출", "나가", "빠져", "출구", "방면 출구", "오른쪽 출구", "왼쪽 출구", "exit", "offramp", "off ramp"))) {
                return pick(side, IC_EXIT_C, IC_EXIT_R, IC_EXIT_L);
            }
            if (hasAny(text, "진입", "합류", "올라", "onramp", "on ramp")) {
                return pick(side, IC_ENTER_C, IC_ENTER_R, IC_ENTER_L);
            }
            // An IC/JC or highway name alone does not identify a ramp maneuver.
            return ordinary(m);
        }
        return ordinary(m);
    }

    /**
     * Refines a simplistic or primitive turn icon (e.g. from Android Auto or stock GPM)
     * using Korea's 6 major road categories detected in roadName / description text.
     */
    public static int refineManeuver(int baseIcon, String road, String desc) {
        // Refine only ordinary arrows. Keep explicit stock facility/ramp,
        // arrival, unknown and cleared icons exactly as supplied.
        if (baseIcon < 0x41 || baseIcon > 0x47) return baseIcon;
        String r = road == null ? "" : road;
        String d = desc == null ? "" : desc;
        String text = (r + " " + d).trim();
        if (text.isEmpty()) return baseIcon;

        int side = 0;
        if (baseIcon == 0x42 || baseIcon == 0x43 || baseIcon == 0x44) side = 1;
        else if (baseIcon == 0x45 || baseIcon == 0x46 || baseIcon == 0x47) side = -1;

        if (side == 0) {
            if (hasAny(text, "오른쪽", "오른쪽에", "우측", "우회전", "오른편", "끝차로", "바깥")) side = 1;
            else if (hasAny(text, "왼쪽", "왼쪽에", "좌측", "좌회전", "왼편", "1차로")) side = -1;
        }

        if (hasAny(text, "터널", "tunnel")) {
            if (isSide(text)) return side > 0 ? UNDERPASS_SIDE_R : UNDERPASS_SIDE_L;
            return side > 0 ? UNDERPASS_ENTRY_R : UNDERPASS_ENTRY_LC;
        }
        if (hasAny(text, "지하차도", "지하 차도", "지하도로", "지하 도로", "지하차로", "지하 차로",
                "지하차선", "지하 차선", "지하길", "지하통로", "지하보차도", "언더패스", "underpass",
                "지하차도옆", "지하차도 옆", "지하차도 옆길", "지하차도옆길")) {
            if (isSide(text)) return side > 0 ? UNDERPASS_SIDE_R : UNDERPASS_SIDE_L;
            return side > 0 ? UNDERPASS_ENTRY_R : UNDERPASS_ENTRY_LC;
        }
        if (hasAny(text, "고가차도", "고가 차도", "고가도로", "고가 도로", "고가차로", "고가 차로",
                "고가차선", "고가 차선", "고가교", "고가길", "오버패스", "overpass",
                "고가도로옆", "고가도로 옆", "고가 옆길", "고가 옆", "고가옆길", "고가옆",
                "고가차도 옆길", "고가차도옆길", "고가차도 옆", "고가차도옆")) {
            if (isSide(text)) return side > 0 ? OVERPASS_SIDE_R : OVERPASS_SIDE_L;
            return side > 0 ? OVERPASS_ENTRY_R : OVERPASS_ENTRY_LC;
        }
        if (hasAny(text, "휴게소", "졸음쉼터", "졸음 쉼터", "간이휴게소", "간이 휴게소", "임시휴게소",
                "화물차라운지", "화물차 라운지", "복합휴게소", "rest area", "service area")) return REST_AREA;
        if (hasAny(text, "요금소", "톨게이트", "하이패스", "원톨링", "민자요금소", "민자 요금소",
                "개방식요금소", "통행료", "toll") || tollgateAbbreviation(text)) return TOLL;
        if (hasAny(text, "나들목", "분기점", "고속도로", "고속 도로", "도시고속도로", "도시 고속 도로",
                "순환도로", "순환 고속도로", "분기도로", "분기 도로", "램프", "램프도로", "onramp", "offramp")
                || interchangeAbbreviation(text)) {
            if (hasAny(text, "진출", "나가", "빠져", "출구", "방면 출구", "오른쪽 출구", "왼쪽 출구", "exit", "offramp", "off ramp")) {
                return pick(side, IC_EXIT_C, IC_EXIT_R, IC_EXIT_L);
            }
            if (hasAny(text, "진입", "합류", "올라", "onramp")) {
                return pick(side, IC_ENTER_C, IC_ENTER_R, IC_ENTER_L);
            }
            if (baseIcon > 0) return baseIcon;
            return pick(side, IC_ENTER_C, IC_ENTER_R, IC_ENTER_L);
        }
        return baseIcon;
    }
    private static boolean interchangeAbbreviation(String text) {
        return java.util.regex.Pattern.compile("(?i)(?<![a-z])(i\\.?c|j\\.?c)(?![a-z])").matcher(text).find();
    }
    private static boolean tollgateAbbreviation(String text) {
        return java.util.regex.Pattern.compile("(?i)(?<![a-z])t\\.?g(?![a-z])").matcher(text).find();
    }

    // Numeric cluster IDs verified against the stock DiPO ManeuverType mapping.
    // A named turn remains usable when an angle is absent or not an exact multiple
    // of 30/45 degrees. Never infer the opposite turn from a conflicting angle.
    private static int ordinary(Maneuver m) {
        String t = ((m.afterRoad == null ? "" : m.afterRoad) + " " + (m.desc == null ? "" : m.desc));
        int s = side(m);
        // App-independent fallback text hints for generic maneuver types.
        // This is not evidence of what any named map app or version emits.
        if (m.type == 3 || m.type == 5 || m.type == 11 || m.type == 16 || m.type == 51) {
            if (hasAny(t, "유턴", "u턴")) return m.drivingSide == 1 ? 0x49 : 0x48;
            if (hasAny(t, "좌회전", "왼쪽", "왼쪽에", "좌측", "왼편", "비보호 좌회전")) {
                if (hasAny(t, "급한", "유턴 방향", "크게", "7시", "8시")) return 0x45;
                if (hasAny(t, "완만", "비스듬", "완만한", "10시", "11시", "방향", "도로", "옆길", "옆")) return 0x47;
                return curve(m.exitAngle, false);
            }
            if (hasAny(t, "우회전", "오른쪽", "오른쪽에", "우측", "오른편")) {
                if (hasAny(t, "급한", "크게", "4시", "5시")) return 0x44;
                if (hasAny(t, "완만", "비스듬", "완만한", "1시", "2시", "방향", "도로", "옆길", "옆")) return 0x42;
                return curve(m.exitAngle, true);
            }
            if (m.exitAngle != Maneuver.UNKNOWN_ANGLE && Math.abs(m.exitAngle) >= 15) {
                return curve(m.exitAngle, m.exitAngle > 0);
            }
        }
        switch (m.type) {
            case 1: case 20: return curve(m.exitAngle, false);
            case 2: case 21: return curve(m.exitAngle, true);
            case 3: case 11: case 16: return 0x41;
            case 5: case 51: return 0xac;
            case 4: case 18: case 26: return m.drivingSide == 1 ? 0x49 : 0x48;
            case 13: case 49: return 0x47;
            case 14: case 50: return 0x42;
            case 47: return 0x45;
            case 48: return 0x44;
            case 8: return IC_EXIT_C;
            case 9: return IC_ENTER_C;
            case 22: return IC_EXIT_L;
            case 23: return IC_EXIT_R;
            case 15: case 17: return 0xb0;
            case 52: return 0xae;
            case 53: return 0xad;
            case 10: case 12: case 27: return 0x70;
            case 24: return 0x72;
            case 25: return 0x71;
            default:
                if (s < 0) return curve(m.exitAngle, false);
                if (s > 0) return curve(m.exitAngle, true);
                if (m.exitAngle != Maneuver.UNKNOWN_ANGLE && Math.abs(m.exitAngle) >= 15) {
                    return curve(m.exitAngle, m.exitAngle > 0);
                }
                return 0x41;
        }
    }
    // Exit ordinals do not encode physical direction. Anchors are stock DiPO
    // values; nearest-anchor interpolation is an independent fallback rule.
    private static int roundabout(Maneuver m) {
        if (m.exitAngle == Maneuver.UNKNOWN_ANGLE || m.exitAngle < -180 || m.exitAngle > 180
                || m.drivingSide == Maneuver.UNKNOWN_DRIVING_SIDE) return NONE;
        int a = m.exitAngle, code;
        if (a >= 158 || a <= -158) code = 0x66;
        else if (a >= 113) code = 0x64;
        else if (a >= 45) code = 0x63;
        else if (a >= -22) code = 0x61;
        else if (a >= -67) code = 0x68;
        else if (a >= -112) code = 0x69;
        else code = 0x68; // Stock DiPO also uses 68 at -135 degrees.
        return m.drivingSide == 1 ? 0xc0 : code;
    }
    private static int curve(int angle, boolean right) {
        int normal = right ? 0x43 : 0x46;
        if (angle == Maneuver.UNKNOWN_ANGLE || angle < -180 || angle > 180
                || (right ? angle <= 0 : angle >= 0)) return normal;
        int magnitude = Math.abs(angle);
        if (magnitude < 40) return right ? 0x42 : 0x47;
        if (magnitude > 110) return right ? 0x44 : 0x45;
        return normal;
    }

    static boolean hasAny(String s, String... keys) {
        String low = s.toLowerCase(Locale.ROOT);
        for (String k : keys) if (low.contains(k)) return true;
        return false;
    }
    static boolean isSide(String s) {
        if (hasAny(s, "진입", "본선", "올라")) return false;
        return hasAny(s, "옆길", "옆 길", "측도", "우측 도로", "좌측 도로", "우측도로", "좌측도로", "오른쪽 도로", "왼쪽 도로",
                "오른쪽길", "왼쪽길", "오른쪽 방향", "왼쪽 방향", "바깥길",
                "옆 차로", "옆차로", "옆 차선", "옆차선", "옆길 도로", "측면 도로", "측면도로",
                "지하차도옆", "지하차도 옆", "고가도로옆", "고가도로 옆", "고가 옆", "고가옆",
                "터널 옆", "터널옆", "터널 옆길", "터널옆길");
    }

    /** direction side from the text or exit angle, falling back to centre/unknown. */
    static int side(Maneuver m) {
        String t = ((m.afterRoad == null ? "" : m.afterRoad) + " " + (m.desc == null ? "" : m.desc));
        switch (m.type) {
            case 1: case 13: case 20: case 22: case 24: case 47: case 49: case 52: return -1;
            case 2: case 14: case 21: case 23: case 25: case 48: case 50: case 53: return 1;
            default: break;
        }
        if (hasAny(t, "오른쪽", "오른쪽에", "우측", "우회전", "오른편", "오른 쪽", "오른쪽 방향", "오른쪽길", "우측 도로", "우측도로",
                "오른쪽 도로", "오른쪽도로", "우측차로", "우측차선", "우측 차로", "우측 차선", "끝 차로", "끝차로",
                "바깥차로", "바깥 차로", "하위 차로", "하위차로", "1시", "2시", "3시", "4시", "5시")) return 1;
        if (hasAny(t, "왼쪽", "왼쪽에", "좌측", "좌회전", "왼편", "왼 쪽", "왼쪽 방향", "왼쪽길", "좌측 도로", "좌측도로",
                "왼쪽 도로", "왼쪽도로", "좌측차로", "좌측차선", "좌측 차로", "좌측 차선", "1차로", "1차선",
                "1, 2차로", "1,2차로", "1, 2차선", "1,2차선", "상위 차로", "상위차로", "7시", "8시", "9시", "10시", "11시")) return -1;
        if (m.exitAngle != Maneuver.UNKNOWN_ANGLE) {
            if (m.exitAngle > 10) return 1;
            if (m.exitAngle < -10) return -1;
        }
        return 0;
    }
}
