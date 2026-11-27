package kr.gen5w.hud;

/**
 * Pure V039 Navi::CLUSTER::Turn::CInformation builder (libExSLNavi.so).
 * Far maneuvers preserve the Korean icon code; near maneuvers switch with
 * hysteresis (<= 400m enter, > 550m exit) to stock main-guide SetCase* geometry.
 */
public final class StockTurn {
    private StockTurn() {}

    public static final long NEAR_ENTER_M = 400L;
    public static final long NEAR_EXIT_M = 550L;
    public static final int COMBI_NONE = 0;

    public static final int DISPLAY_TURN = 0x0d;
    public static final int DISPLAY_EXP_EXIT_RIGHT = 0x11;
    public static final int DISPLAY_EXP_EXIT_LEFT = 0x12;
    public static final int DISPLAY_FORK = 0x10;
    public static final int DISPLAY_FORK_Y = 0x19;
    public static final int DISPLAY_UTURN = 0x1f;
    public static final int DISPLAY_ROTARY_CCW = 0x20;
    public static final int DISPLAY_ROTARY_CW = 0x21;
    public static final int DISPLAY_OVERPASS_RIGHT = 0x2b;
    public static final int DISPLAY_OVERPASS_LEFT = 0x2c;
    public static final int DISPLAY_UNDERPASS_RIGHT = 0x2d;
    public static final int DISPLAY_UNDERPASS_LEFT = 0x2e;

    public static final class Frame {
        public final int displayType;
        public final int sideStreet;
        public final int directionType;
        public final float directionDegrees;
        public final int combiSideStreet;
        public final boolean near;

        public Frame(int displayType, int sideStreet, int directionType, int combiSideStreet, boolean near) {
            this.displayType = displayType;
            this.sideStreet = sideStreet;
            this.directionType = directionType;
            this.directionDegrees = directionType * 7.5f;
            this.combiSideStreet = combiSideStreet;
            this.near = near;
        }
    }

    /** Stable maneuver identity for resetting near/far hysteresis on turn transitions. */
    public static String maneuverKey(Maneuver m, int icon, String road) {
        String r = road != null ? road : (m != null && m.afterRoad != null ? m.afterRoad : "");
        int comp = m != null ? m.component : -1;
        int idx = m != null ? m.index : -1;
        int type = m != null ? m.type : -1;
        return comp + "|" + idx + "|" + type + "|" + icon + "|" + r;
    }

    /** 400m enter / 550m exit hysteresis matching real stock switching between 700m and 400m. */
    public static boolean near(long meters, boolean previousNear) {
        if (meters < 0) return false;
        return previousNear ? meters <= NEAR_EXIT_M : meters <= NEAR_ENTER_M;
    }

    public static Frame build(Maneuver m, int icon, long meters, boolean previousNear) {
        if (icon <= 0) return new Frame(TurnFrame.TBT_DISPLAY_IDLE, 0, 0, COMBI_NONE, false);
        int farDisplayType = TurnFrame.tbtDisplayType(icon);
        boolean isNear = near(meters, previousNear);
        if (isDestWaypoint(m, icon)) {
            return new Frame(farDisplayType, 0, 0, COMBI_NONE, isNear);
        }
        if (!isNear) {
            return new Frame(farDisplayType, 0, 0, COMBI_NONE, false);
        }
        // Grade-separated overpasses/underpasses (SetCaseOverPass/UnderPass).
        if (icon == ClusterIcon.OVERPASS_ENTRY_R || icon == ClusterIcon.OVERPASS_SIDE_R) {
            return new Frame(DISPLAY_OVERPASS_RIGHT, 0, 12, COMBI_NONE, true);
        }
        if (icon == ClusterIcon.OVERPASS_ENTRY_LC || icon == ClusterIcon.OVERPASS_SIDE_L) {
            return new Frame(DISPLAY_OVERPASS_LEFT, 0, 36, COMBI_NONE, true);
        }
        if (icon == ClusterIcon.UNDERPASS_ENTRY_R || icon == ClusterIcon.UNDERPASS_SIDE_R) {
            return new Frame(DISPLAY_UNDERPASS_RIGHT, 0, 12, COMBI_NONE, true);
        }
        if (icon == ClusterIcon.UNDERPASS_ENTRY_LC || icon == ClusterIcon.UNDERPASS_SIDE_L) {
            return new Frame(DISPLAY_UNDERPASS_LEFT, 0, 36, COMBI_NONE, true);
        }
        // Tunnel/Toll keep icon with empty sideStreet/direction/combi (SetCaseTunnelToll).
        String after = m != null ? m.afterRoad : null;
        String desc = m != null ? m.desc : null;
        if (icon == ClusterIcon.TOLL || ClusterIcon.isTunnelText(after, desc)) {
            return new Frame(farDisplayType, 0, 0, COMBI_NONE, true);
        }
        // Highway exits (SetCaseExpExit). Entries (0xa0..0xa2), 0xa3, 0xb0 keep icon.
        if (icon == ClusterIcon.IC_EXIT_R || (m != null && m.type == 23)) {
            return new Frame(DISPLAY_EXP_EXIT_RIGHT, 0, 12, COMBI_NONE, true);
        }
        if (icon == ClusterIcon.IC_EXIT_L || (m != null && m.type == 22)) {
            return new Frame(DISPLAY_EXP_EXIT_LEFT, 0, 36, COMBI_NONE, true);
        }
        if (icon == ClusterIcon.IC_ENTER_C || icon == ClusterIcon.IC_ENTER_R || icon == ClusterIcon.IC_ENTER_L
                || icon == ClusterIcon.IC_EXIT_C || icon == 0xb0) {
            return new Frame(farDisplayType, 0, 0, COMBI_NONE, true);
        }
        // Service/rest area (SetCaseServiceArea): stock draws turn+mask only when geometry is known.
        if (icon == ClusterIcon.REST_AREA) {
            if (m != null && m.hasJunctionElementAngles) {
                return new Frame(DISPLAY_TURN, mask(m, icon), direction(m, icon), COMBI_NONE, true);
            }
            return new Frame(farDisplayType, 0, 0, COMBI_NONE, true);
        }
        // Roundabouts (SetCaseRotary): exclude type 47..50 (sharp/slight turns).
        if (isRotary(m, icon)) {
            boolean cw = (m != null && m.drivingSide == 1) || (icon >= 0xc0 && icon <= 0xcb);
            return new Frame(cw ? DISPLAY_ROTARY_CW : DISPLAY_ROTARY_CCW, mask(m, icon), direction(m, icon), COMBI_NONE, true);
        }
        // U-turns (SetCaseTurnPoint 0x1f).
        if (icon == 0x48 || icon == 0x49 || (m != null && m.type == 4)) {
            boolean lhd = icon == 0x49 || (m != null && m.drivingSide == 1);
            return new Frame(DISPLAY_UTURN, 0, lhd ? 12 : 36, COMBI_NONE, true);
        }
        // Forks / Keep left-right (SetImprovedArrowTypeFork / SetCaseTurnPoint).
        if (icon == AaNavigationParser.FORK_LEFT || icon == AaNavigationParser.FORK_RIGHT
                || (m != null && (m.type == 52 || m.type == 53 || m.type == 13 || m.type == 14))) {
            if (m != null && m.hasJunctionElementAngles) {
                return new Frame(DISPLAY_TURN, mask(m, icon), direction(m, icon), COMBI_NONE, true);
            }
            boolean left = icon == AaNavigationParser.FORK_LEFT || (m != null && (m.type == 52 || m.type == 13));
            return new Frame(DISPLAY_FORK_Y, 0, left ? 36 : 12, COMBI_NONE, true);
        }
        // Ordinary turn (SetCaseTurnPoint 0x0d TURN).
        return new Frame(DISPLAY_TURN, mask(m, icon), direction(m, icon), COMBI_NONE, true);
    }

    public static int displayType(Maneuver m) {
        return build(m, ClusterIcon.of(m), 0L, true).displayType;
    }

    public static int mask(Maneuver m) {
        return mask(m, ClusterIcon.of(m));
    }

    public static int mask(Maneuver m, int icon) {
        if (m != null && m.hasJunctionElementAngles && m.junctionElementAngles.length > 0) {
            return maskFromAnglesAndMain(m.junctionElementAngles, m.exitAngle);
        }
        if (m != null && m.exitAngle != Maneuver.UNKNOWN_ANGLE) {
            return maskFromAnglesAndMain(new int[]{0}, m.exitAngle);
        }
        return maskForIcon(icon);
    }

    public static int direction(Maneuver m) {
        return direction(m, ClusterIcon.of(m));
    }

    public static int direction(Maneuver m, int icon) {
        if (m != null && m.exitAngle != Maneuver.UNKNOWN_ANGLE) {
            return directionFromAngle(m.exitAngle);
        }
        return directionForIcon(icon);
    }

    public static int combi(Maneuver m) {
        return COMBI_NONE;
    }

    /** SetSideStreetBit at libExSLNavi.so:0x02d7ba2c (non-main elements skip [168, 192]). */
    public static int maskFromAngles(int... angles) {
        return maskFromAnglesAndMain(angles, Maneuver.UNKNOWN_ANGLE);
    }

    /** SetSideStreetBit with explicit route exit angle (main [168..179]->0x80, [180..192]->0x100). */
    public static int maskFromAnglesAndMain(int[] angles, int mainExitAngle) {
        int mask = 0;
        if (angles != null) {
            for (int i = 0; i < angles.length; i++) {
                mask |= spokeBit(angles[i], false);
            }
        }
        if (mainExitAngle != Maneuver.UNKNOWN_ANGLE) {
            mask |= spokeBit(mainExitAngle, true);
        }
        return mask & 0x7fff;
    }

    /** Returns stock directionType (7.5-degree units) for the route exit. */
    public static int directionFromAngle(int angle) {
        if (angle == Maneuver.UNKNOWN_ANGLE) return 0;
        int a = normalize(angle);
        if (a < 12 || a > 348) return 0;
        if (a >= 168 && a <= 179) return 21;
        if (a >= 180 && a <= 192) return 27;
        int k = spoke(a);
        return k < 0 ? 0 : (k + 1) * 3;
    }

    /** Safe fallback when the phone omitted junction angles. */
    public static int maskForIcon(int icon) {
        switch (icon) {
            case 0x42: case 0x90: case 0x61: case 0x62: case 0xc2: return 0x0005;
            case 0x43: case 0x63: case 0xc3: case 0x72: case 0xa4: return 0x0011;
            case 0x44: case 0x64: case 0x65: case 0xc4: case 0xc5: return 0x0041;
            case 0x45: case 0x67: case 0x68: case 0xc7: case 0xc8: return 0x0201;
            case 0x46: case 0x4c: case 0x69: case 0xc9: case 0x71: case 0xa5: return 0x0801;
            case 0x47: case 0x91: case 0x6a: case 0x6b: case 0xca: case 0xcb: return 0x2001;
            case 0x48: case 0x49: case 0x66: case 0xc6: return 0x0101;
            default: return 0x0001;
        }
    }

    public static int directionForIcon(int icon) {
        switch (icon) {
            case 0x42: case 0x90: case 0x61: case 0x62: case 0xc2: return 6;
            case 0x43: case 0x63: case 0xc3: case 0x72: case 0xa4: return 12;
            case 0x44: case 0x64: case 0x65: case 0xc4: case 0xc5: return 18;
            case 0x45: case 0x67: case 0x68: case 0xc7: case 0xc8: return 30;
            case 0x46: case 0x4c: case 0x69: case 0xc9: case 0x71: case 0xa5: return 36;
            case 0x47: case 0x91: case 0x6a: case 0x6b: case 0xca: case 0xcb: return 42;
            case 0x48: case 0x49: case 0x66: case 0xc6: return 24;
            default: return 0;
        }
    }

    /** Caps the dynamic guide distance at NEAR_ENTER_M when entering near view. */
    public static long guideDistance(long entryMeters) {
        if (entryMeters <= 0L) return NEAR_ENTER_M;
        return Math.min(NEAR_ENTER_M, entryMeters);
    }

    /** Stock CJunctionViewGuidance::GetRemainDistRatio + SetCase* (10..1 draining in near view, 0x0f far/idle). */
    public static int remainRatio(long meters, boolean near, long guideDistMeters) {
        if (!near || meters < 0) return 0x0f;
        long guide = guideDistMeters > 0L ? guideDistMeters : NEAR_ENTER_M;
        int elapsedPct = meters >= guide ? 0
                : (int) Math.min(100L, 100L - Math.min(100L, (meters * 100L) / guide));
        int remPct = 100 - Math.min(100, elapsedPct);
        return remPct <= 9 ? 1 : Math.min(10, remPct / 10);
    }

    public static int remainRatio(long meters) {
        return remainRatio(meters, meters >= 0 && meters <= NEAR_ENTER_M, NEAR_ENTER_M);
    }

    private static boolean isDestWaypoint(Maneuver m, int icon) {
        if (icon == 0x70 || icon == 0x71 || icon == 0x72) return true;
        if (m == null) return false;
        return m.type == 10 || m.type == 12 || m.type == 24 || m.type == 25;
    }

    private static boolean isRotary(Maneuver m, int icon) {
        if ((icon >= 0x60 && icon <= 0x6b) || (icon >= 0xc0 && icon <= 0xcb)) return true;
        if (m == null) return false;
        if (m.junctionType == 1) return true;
        return m.type == 6 || m.type == 7 || m.type == 18 || m.type == 19 || (m.type >= 28 && m.type <= 46);
    }

    private static boolean isRoundaboutIcon(int icon) {
        return (icon >= 0x60 && icon <= 0x6b) || (icon >= 0xc0 && icon <= 0xcb);
    }

    private static int spokeBit(int angle, boolean isMain) {
        if (angle == Maneuver.UNKNOWN_ANGLE) return 0;
        int a = normalize(angle);
        if (a < 12 || a > 348) return 1;
        if (a >= 168 && a <= 192) {
            if (!isMain) return 0;
            return a <= 179 ? 0x0080 : 0x0100;
        }
        int k = spoke(a);
        return k < 0 ? 0 : (1 << (k < 7 ? k + 1 : k));
    }

    private static int normalize(int a) {
        int n = a % 360;
        return n < 0 ? n + 360 : n;
    }

    private static int spoke(int a) {
        final int[] edges = {12, 34, 57, 79, 102, 124, 147, 169, 192, 214, 237, 259, 282, 304, 327, 349};
        for (int k = 0; k < 15; k++) {
            if (a >= edges[k] && a < edges[k + 1]) {
                return k == 7 ? -1 : k;
            }
        }
        return -1;
    }
}
