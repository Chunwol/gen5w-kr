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
            int outSlot = 0;
            boolean highlightAll = lane.status == 2 && lane.highlights.length == 0;
            for (int j = 0; j < lane.angles.length; j++) {
                int direction = direction(lane.angles[j]);
                if (direction == 0) return clear();
                if ((seen & (1 << direction)) != 0) continue;
                seen |= 1 << direction;
                boolean highlight = highlightAll;
                for (int angle : lane.highlights) if (direction(angle) == direction) highlight = true;
                int poss = highlight ? 2 : (lane.status == 0 ? 3 : 1);
                out[0x13 + 3 * i + outSlot] = (byte) direction;
                out[3 + i] |= poss << (2 * outSlot);
                recommended[i] |= highlight;
                outSlot++;
            }
            int highlights = 0;
            for (int angle : lane.highlights) {
                int direction = direction(angle);
                if (direction == 0 || (seen & (1 << direction)) == 0) return clear();
                highlights |= 1 << direction;
            }
            if (outSlot == 0) return clear();
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
                    case 2: angle = 45; break;
                    case 3: angle = 90; break;
                    case 4: angle = 135; break;
                    case 5: angle = 180; break;
                    case 6: angle = -135; break;
                    case 7: angle = -90; break;
                    case 8: angle = -45; break;
                }
            }
            lane.angles = new int[]{angle};
            boolean rec = recommended != null && i < recommended.length && recommended[i];
            lane.status = rec ? 2 : 1;
            lane.highlights = rec ? new int[]{angle} : new int[0];
            lanes.lanes.add(lane);
        }
        return encode(lanes, icon);
    }
    // Clockwise V039 cluster lane direction codes: 1 straight, 2-4 right, 5 back, 6-8 left.
    static int direction(int angle) {
        int a = angle;
        if (a >= 65176 && a <= 65535) a -= 65536;
        if (a > 180 && a <= 360) a -= 360;
        else if (a < -180 && a >= -360) a += 360;
        if (a < -180 || a > 180) return 0;
        if (a >= -22 && a <= 22) return 1;
        if (a <= 67 && a >= 23) return 2;
        if (a <= 112 && a >= 68) return 3;
        if (a <= 157 && a >= 113) return 4;
        if (a >= 158 || a <= -158) return 5;
        if (a <= -113) return 6;
        if (a <= -68) return 7;
        return 8;
    }
}
