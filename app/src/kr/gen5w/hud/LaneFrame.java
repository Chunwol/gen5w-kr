package kr.gen5w.hud;

/** Own encoder for stock updateLaneInfo's 81-byte F1 buffer, not a CAN frame. */
public final class LaneFrame {
    private LaneFrame() {}
    public static byte[] clear() { byte[] f = new byte[81]; f[0] = (byte)0xf1; return f; }

    public static byte[] encode(GuidanceParser.Lanes lanes, int icon) {
        byte[] out = clear();
        if (lanes == null || lanes.lanes.isEmpty() || lanes.lanes.size() > 8) return out;
        int base = lanes.lanes.get(0).index;
        if (base != 0 && base != 1) return out;
        boolean[] recommended = new boolean[lanes.lanes.size()];
        for (int i = 0; i < lanes.lanes.size(); i++) {
            GuidanceParser.Lane lane = lanes.lanes.get(i);
            if (lane.index != base+i || lane.angles == null || lane.highlights == null
                    || lane.angles.length == 0 || lane.angles.length > 3) return clear();
            int seen = 0;
            for (int j = 0; j < lane.angles.length; j++) {
                int direction = direction(lane.angles[j]);
                if (direction == 0 || (seen & (1 << direction)) != 0) return clear();
                seen |= 1 << direction;
                boolean highlight = false;
                for (int angle : lane.highlights) if (direction(angle) == direction) highlight = true;
                out[0x13+3*i+j] = (byte)direction;
                out[3+i] |= (highlight ? 2 : 1) << (2*j);
                recommended[i] |= highlight;
            }
            int highlights = 0;
            for (int angle : lane.highlights) {
                int direction = direction(angle);
                if (direction == 0 || (seen & (1 << direction)) == 0
                        || (highlights & (1 << direction)) != 0) return clear();
                highlights |= 1 << direction;
            }
        }
        out[1] = (byte)lanes.lanes.size();
        LaneBits.entry(out, recommended, icon);
        LaneBits.side(out, recommended, icon,
            icon == ClusterIcon.OVERPASS_SIDE_R || icon == ClusterIcon.UNDERPASS_SIDE_R);
        return out;
    }
    // Direction identities cross-checked with two stock native conversion tables.
    // Unsupported angles cannot be represented exactly by these eight identities.
    static int direction(int angle) {
        switch (angle) {
            case 0: return 1;
            case -45: return 2;
            case -90: return 3;
            case 45: return 4;
            case 90: return 5;
            case -135: return 6;
            case 135: return 7;
            case -180: case 180: return 8;
            default: return 0;
        }
    }
}
