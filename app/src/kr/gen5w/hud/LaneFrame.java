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

    /** Helper for Android Auto or manual lane guidance inputs. */
    public static byte[] encodeSimple(int count, int[] directions, boolean[] recommended, int icon) {
        if (count <= 0 || count > 8) return clear();
        GuidanceParser.Lanes lanes = new GuidanceParser.Lanes();
        for (int i = 0; i < count; i++) {
            GuidanceParser.Lane lane = new GuidanceParser.Lane();
            lane.index = i;
            int dirVal = (directions != null && i < directions.length) ? directions[i] : 0;
            int angle = dirVal;
            if (dirVal >= 1 && dirVal <= 8) {
                switch (dirVal) {
                    case 1: angle = 0; break;
                    case 2: angle = -45; break;
                    case 3: angle = -90; break;
                    case 4: angle = 45; break;
                    case 5: angle = 90; break;
                    case 6: angle = -135; break;
                    case 7: angle = 135; break;
                    case 8: angle = 180; break;
                }
            }
            lane.angles = new int[]{angle};
            boolean rec = recommended != null && i < recommended.length && recommended[i];
            lane.highlights = rec ? new int[]{angle} : new int[0];
            lanes.lanes.add(lane);
        }
        return encode(lanes, icon);
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
