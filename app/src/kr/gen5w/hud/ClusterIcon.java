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

        if (hasAny(text, "지하차도", "지하도로", "지하차로")) {
            if (isSide(text)) return side > 0 ? UNDERPASS_SIDE_R : UNDERPASS_SIDE_L;
            return side > 0 ? UNDERPASS_ENTRY_R : UNDERPASS_ENTRY_LC;
        }
        if (hasAny(text, "고가차도", "고가도로", "고가")) {
            if (isSide(text)) return side > 0 ? OVERPASS_SIDE_R : OVERPASS_SIDE_L;
            return side > 0 ? OVERPASS_ENTRY_R : OVERPASS_ENTRY_LC;
        }
        if (hasAny(text, "휴게소", "졸음쉼터")) return REST_AREA;
        if (hasAny(text, "요금소", "톨게이트", "하이패스")) return TOLL;
        if (hasAny(text, "나들목", "분기점") || interchangeAbbreviation(text)) {
            if (m.type == 8 || m.type == 22 || m.type == 23
                    || (m.type != 9 && hasAny(text, "진출", "나가", "빠져"))) {
                return pick(side, IC_EXIT_C, IC_EXIT_R, IC_EXIT_L);
            }
            return pick(side, IC_ENTER_C, IC_ENTER_R, IC_ENTER_L);
        }
        return ordinary(m);
    }
    private static boolean interchangeAbbreviation(String text) {
        return java.util.regex.Pattern.compile("(?i)(?:^|[^a-z])(?:i\\.?c|j\\.?c)(?=$|[^a-z])").matcher(text).find();
    }

    // Numeric cluster IDs verified against the stock DiPO ManeuverType mapping.
    // A named turn remains usable when an angle is absent or not an exact multiple
    // of 30/45 degrees. Never infer the opposite turn from a conflicting angle.
    private static int ordinary(Maneuver m) {
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
            default: return NONE;
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
        // Stock DiPO explicitly emits C0 for the left-driving circle at angle0.
        // Other left-driving directional IDs are unproven: retain the verified
        // circle rather than manufacturing a numeric family offset.
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
    static boolean isSide(String s) { return hasAny(s, "옆길", "측도", "우측 도로", "좌측 도로"); }

    /** direction side from the text, falling back to centre/unknown. */
    static int side(Maneuver m) {
        String t = ((m.afterRoad == null ? "" : m.afterRoad) + " " + (m.desc == null ? "" : m.desc));
        switch (m.type) {
            case 1: case 13: case 20: case 22: case 47: case 49: case 52: return -1;
            case 2: case 14: case 21: case 23: case 48: case 50: case 53: return 1;
            default: break;
        }
        if (hasAny(t, "우측", "오른쪽", "우회전")) return 1;
        if (hasAny(t, "좌측", "왼쪽", "좌회전")) return -1;
        return 0;
    }
}
