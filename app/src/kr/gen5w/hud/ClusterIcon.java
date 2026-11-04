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

    /** Uses structured type/side/junction/angle fields only; unknown combinations stay empty. */
    public static int of(Maneuver m) {
        if (m == null || m.type < 1 || m.type > 53) return NONE;
        final int d = m.drivingSide, j = m.junctionType, a = m.exitAngle;
        switch (m.type) {
            case 1:
                if (j == 0 && a == -120) return 0x45;
                if (d == 0 && j == 0 && a == -90) return 0x46;
                if (j == 0 && a == -60) return 0x47;
                if (j == 0 && a == -45) return 0x91;
                if (d == 1 && j == 1 && a == -120) return 0xc8;
                if (d == 1 && j == 1 && a == -90) return 0xc9;
                if (d == 1 && j == 1 && a == -30) return 0xcb;
                return NONE;
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
                return NONE;
            case 3: return d == 0 && j == 0 && a == 0 ? 0x41 : NONE;
            case 4:
                if (j != 0) return NONE;
                return d == 0 ? 0x48 : d == 1 ? 0x49 : NONE;
            case 5: return d == 0 && j == 0 && a == 0 ? 0xac : NONE;
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
                return j == 0 && a == -30 ? 0x47 : NONE;
            case 48:
                if (j == 0 && a == 30) return 0x42;
                return j == 0 && a >= 135 && a <= 150 ? 0x44 : NONE;
            case 49: return j == 0 && a == -45 ? 0x47 : NONE;
            case 50: return j == 0 && a == 45 ? 0x42 : NONE;
            case 52: return d == 0 && j == 0 && a == 0 ? 0xae : NONE;
            case 53: return d == 0 && j == 0 && a == 0 ? 0xad : NONE;
            default: return NONE;
        }
    }

    /** Preserve a stock Android Auto icon; free text cannot prove another maneuver. */
    public static int refineManeuver(int baseIcon, String road, String desc) { return baseIcon; }

}
