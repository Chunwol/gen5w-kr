package kr.gen5w.hud;

/** Stock NavigationCluster.updateTPTurnListNew payload (TP list, not CAN).
 * Header F2; byte 1 is icon-field count; bytes 2..4 are three icon IDs;
 * road-name UTF-16LE starts at byte 5. The stock buffer is 87 bytes.
 */
public final class TurnFrame {
    public static final int ICON_STRAIGHT = 0x41;
    /** Far maneuvers keep their real icon (user request 2026-11-26: the stock "straight beyond 3 km" rule hid the next turn); effectively disabled. */
    public static final long FAR_STRAIGHT_THRESHOLD_M = Long.MAX_VALUE;
    public static final int SCALE_METER = 0;
    public static final int SCALE_KILOMETER = 1;
    public static final int DIST_ERR_OK = 0;
    public static final int DIST_ERR_NO_DECIMAL = -2;
    public static final int DIST_ERR_UNKNOWN = -3;
    public static final int BAR_ERR_OK = 0;
    public static final int BAR_ERR_INVALID = -1;
    public static final int BAR_ERR_HIDDEN = -2;
    public static final int SUB2C_UNIT_METER = 0;
    public static final int SUB2C_UNIT_KILOMETER = 1;
    public static final int SUB2C_UNIT_NONE = 0;
    public static final int SUB2C_UNIT_INVALID = 15;
    public static final int SUB2C_FRAC_INVALID = 15;
    public static final int SUB2C_INT_INVALID = 65535;
    /** Stock V039 com.mnsoft.navi idle TBT_DISPLAY_TYPE (0 is treated as an error/spinner). */
    public static final int TBT_DISPLAY_IDLE = 8;

    private TurnFrame() {}

    /** Maps GuidanceSession's clear code (<= 0) to stock idle displayType=8 instead of invalid 0. */
    public static int tbtDisplayType(int icon) {
        return icon > 0 ? icon : TBT_DISPLAY_IDLE;
    }

    /** Projection code 0x40 ("no direction") draws the cluster's loading spinner; never send it. */
    public static final int ICON_NO_DIRECTION = 0x40;

    /** Replaces the spinner code with straight-ahead; far turns are replaced only when FAR_STRAIGHT_THRESHOLD_M is lowered (disabled). */
    public static int effectiveIcon(int icon, long distanceMeters) {
        if (icon <= 0) return icon;
        if (icon == ICON_NO_DIRECTION) return ICON_STRAIGHT;
        return distanceMeters > FAR_STRAIGHT_THRESHOLD_M ? ICON_STRAIGHT : icon;
    }

    /**
     * Converts distance in meters to the float value expected by stock
     * NavigationCluster.updateTBTInfo. This follows V039
     * GpmNaviTBTManager.setDistanceValue for a distance supplied in meters.
     * < 1000m uses meters (scale=0); >= 1000m converts to km (scale=1) and clamps
     * to 32767.9f so the downstream signed 16-bit path cannot overflow.
     */
    public static float tbtDistanceValue(long meters) {
        if (meters < 0) return 0f;
        if (meters < 1000L) return (float) meters;
        double km = meters / 1000.0;
        if (km > 32767.9) km = 32767.9;
        return (float) km;
    }

    public static int tbtDistanceScale(long meters) {
        return meters >= 1000L ? SCALE_KILOMETER : SCALE_METER;
    }

    public static int tbtDistanceError(long meters) {
        return meters < 0 ? DIST_ERR_UNKNOWN : DIST_ERR_OK;
    }

    public static int tbtBarGraphError(int icon, long meters, boolean near) {
        if (icon <= 0 || !near || meters < 0) return BAR_ERR_INVALID;
        return BAR_ERR_OK;
    }

    public static int tbtBarGraphError(int icon, long meters) {
        return tbtBarGraphError(icon, meters, meters >= 0 && meters <= StockTurn.NEAR_ENTER_M);
    }

    /** 0..100 (ClusterService rounds /10 into the 4-bit bar); drains like stock remainDistanceRatio in near view. */
    public static int tbtBarGraphLevel(int icon, long meters, boolean near, long guideDistMeters) {
        if (icon <= 0 || !near || meters < 0) return 0;
        int ratio = StockTurn.remainRatio(meters, near, guideDistMeters);
        return (ratio >= 1 && ratio <= 10) ? ratio * 10 : 0;
    }

    public static int tbtBarGraphLevel(int icon, long meters) {
        return tbtBarGraphLevel(icon, meters, meters >= 0 && meters <= StockTurn.NEAR_ENTER_M, StockTurn.NEAR_ENTER_M);
    }

    public static int subInfo2CUnit(long meters) {
        if (meters < 0) return SUB2C_UNIT_INVALID;
        return meters < 1000L ? SUB2C_UNIT_METER : SUB2C_UNIT_KILOMETER;
    }

    /** Largest kilometre value the 16-bit whole field carries is 65534.9 km (65535 = invalid). */
    private static final long SUB2C_MAX_TENTHS = 655349L;

    /** Rounded tenths of a kilometre, saturated before any arithmetic so huge inputs cannot overflow. */
    private static long subInfo2CTenthsTotal(long meters) {
        long bounded = Math.min(meters, SUB2C_MAX_TENTHS * 100L);
        return Math.min(SUB2C_MAX_TENTHS, (bounded + 50L) / 100L);
    }

    public static int subInfo2CTenths(long meters) {
        if (meters < 0) return SUB2C_FRAC_INVALID;
        if (meters < 1000L) return 0;
        return (int) (subInfo2CTenthsTotal(meters) % 10L);
    }

    public static int subInfo2CWhole(long meters) {
        if (meters < 0) return SUB2C_INT_INVALID;
        if (meters < 1000L) return (int) meters;
        return (int) (subInfo2CTenthsTotal(meters) / 10L);
    }

    public static byte[] clear() { return new byte[]{(byte)0xf2, 0}; }
    public static byte[] encode(int[] icons, String name) {
        if (icons == null || icons.length == 0 || icons[0] <= 0 || icons[0] > 0xee) return clear();
        byte[] out = new byte[87];
        out[0] = (byte)0xf2; out[1] = 3;
        for (int i = 0; i < Math.min(3, icons.length); i++) {
            int code = icons[i] == ICON_NO_DIRECTION ? ICON_STRAIGHT : icons[i];
            if (code > 0 && code <= 0xee) out[2+i] = (byte)code;
        }
        if (name != null) {
            int n = Math.min(39, name.length());
            if (n > 0 && Character.isHighSurrogate(name.charAt(n-1))) n--;
            for (int i = 0; i < n; i++) {
                char c = name.charAt(i);
                if (Character.isISOControl(c)) c = ' ';
                out[5+2*i] = (byte)c;
                out[6+2*i] = (byte)(c >>> 8);
            }
        }
        return out;
    }
}
