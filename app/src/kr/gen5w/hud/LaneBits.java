package kr.gen5w.hud;

/**
 * Sets the over/underpass lane bits in the 81-byte cluster lane frame.
 * Layout (from the stock lane parser): byte 0 = 0xF1, byte 1 = lane count,
 * lane possibility starts at byte 3; direction slots start at 0x13. The masks are at
 * 0x43-0x44 (over) and 0x45-0x46 (under). Bit i marks lane slot i (0 = leftmost).
 *
 * Pure logic, unit-tested on the JVM. "recommended[i]" is true when lane i is a
 * recommended lane. For an entry icon the recommended lanes are the ones onto the
 * ramp; for a side-road icon the marked lanes are the ones beside them.
 */
public final class LaneBits {
    public static final int OFF_OVER = 0x43, OFF_UNDER = 0x45;
    static final int MAX_LANES = 8;

    private LaneBits() {}

    /** Mark the recommended lanes (entry case). icon selects over vs under by its code. */
    public static void entry(byte[] frame, boolean[] recommended, int icon) {
        int off = offsetFor(icon);
        if (off < 0) return;
        int bits = 0, n = Math.min(recommended.length, MAX_LANES);
        for (int i = 0; i < n; i++) if (recommended[i]) bits |= (1 << i);
        write(frame, off, bits);
    }

    /** Mark the lanes beside the recommended block (side-road case). right=true marks
     *  lanes left of the first recommended lane; left marks lanes right of the last. */
    public static void side(byte[] frame, boolean[] recommended, int icon, boolean right) {
        int off = offsetForSide(icon);
        if (off < 0) return;
        int n = Math.min(recommended.length, MAX_LANES);
        int first = -1, last = -1;
        for (int i = 0; i < n; i++) if (recommended[i]) { if (first < 0) first = i; last = i; }
        int bits = 0;
        if (first >= 0) {
            if (right) { for (int i = 0; i < first; i++) bits |= (1 << i); }
            else { for (int i = last + 1; i < n; i++) bits |= (1 << i); }
        }
        write(frame, off, bits);
    }

    static int offsetFor(int icon) {
        if (icon == ClusterIcon.OVERPASS_ENTRY_LC || icon == ClusterIcon.OVERPASS_ENTRY_R) return OFF_OVER;
        if (icon == ClusterIcon.UNDERPASS_ENTRY_LC || icon == ClusterIcon.UNDERPASS_ENTRY_R) return OFF_UNDER;
        return -1;
    }
    static int offsetForSide(int icon) {
        if (icon == ClusterIcon.OVERPASS_SIDE_L || icon == ClusterIcon.OVERPASS_SIDE_R) return OFF_OVER;
        if (icon == ClusterIcon.UNDERPASS_SIDE_L || icon == ClusterIcon.UNDERPASS_SIDE_R) return OFF_UNDER;
        return -1;
    }
    static void write(byte[] frame, int off, int bits) {
        if (frame == null || off + 1 >= frame.length) return;
        frame[off] = (byte) (bits & 0xff);
        frame[off + 1] = 0;
    }
}
