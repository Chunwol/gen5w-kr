package kr.gen5w.hud;

/** Stock NavigationCluster.updateTPTurnListNew payload (TP list, not CAN).
 * Header F2; byte 1 is icon-field count; bytes 2..4 are three icon IDs;
 * road-name UTF-16LE starts at byte 5. The stock buffer is 87 bytes.
 */
public final class TurnFrame {
    private TurnFrame() {}
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
