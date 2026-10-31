package kr.gen5w.hud;

/** Stock NavigationCluster.updateTPTurnListNew payload (TP list, not CAN).
 * Header F2; byte 1 is icon-field count; bytes 2..4 are three icon IDs;
 * road-name UTF-16LE starts at byte 5. The stock buffer is 87 bytes.
 */
public final class TurnFrame {
    public static final int SCALE_METER = 0;
    public static final int SCALE_KILOMETER = 1;
    public static final int DIST_ERR_OK = 0;
    public static final int DIST_ERR_UNKNOWN = -3;

    private TurnFrame() {}

    /**
     * Converts distance in meters to the float value expected by stock
     * NavigationCluster.updateTBTInfo. V039's ClusterService converts this
     * float to an integer and separately encodes a tenths digit; the resulting
     * physical display is unverified, as is equivalence to V039 GPM.
     * < 1000m uses meters (scale=0); >= 1000m converts to km (scale=1) and clamps
     * to 32767.9f so signed 16-bit conversion in ClusterService never overflows.
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

    public static byte[] clear() { return new byte[]{(byte)0xf2, 0}; }
    public static byte[] encode(int[] icons, String name) {
        if (icons == null || icons.length == 0 || icons[0] <= 0 || icons[0] > 0xee) return clear();
        byte[] out = new byte[87];
        out[0] = (byte)0xf2; out[1] = 3;
        for (int i = 0; i < Math.min(3, icons.length); i++) {
            if (icons[i] > 0 && icons[i] <= 0xee) out[2+i] = (byte)icons[i];
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
