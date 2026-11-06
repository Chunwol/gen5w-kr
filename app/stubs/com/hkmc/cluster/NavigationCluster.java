package com.hkmc.cluster;

/** Compile-only declarations. The head unit provides the implementation. */
public class NavigationCluster {
    public static final class CrossroadName {
        public String name;
        public CrossroadName() {}
    }

    public static final class HighwayMode {
        public int type;
        public int direction;
        public int traffic;
        public int unit;
        public float distance;
        public String name;
        public HighwayMode() {}
    }

    public static final class DestinationName {
        public int type;
        public String name;
        public DestinationName() {}
    }

    public NavigationCluster(android.content.Context context) { throw new RuntimeException("stub"); }
    public void updateTPTurnListNew(byte[] data) { throw new RuntimeException("stub"); }
    public void updateLaneInfo(byte[] data) { throw new RuntimeException("stub"); }
    public void updateTPCrossroadName(CrossroadName crossroadName) { throw new RuntimeException("stub"); }
    public void updateTPHighwayMode(HighwayMode[] modes) { throw new RuntimeException("stub"); }
    public void updateTBTInfo(int displayType, int sideStreet, float direction,
            float distance, int distanceErr, int combiSideStreet, int scale,
            int barGraphLevel, int barGraphLevelErr) { throw new RuntimeException("stub"); }
    public void updateTPFlexibleDestinationName(DestinationName destName) { throw new RuntimeException("stub"); }
    public void updateTBTSubInfo(float distance, int distanceErr, int unit, int hours,
            int minutes, int timeType, int timeFormat, float compassDegree,
            int compassDegreeErr) { throw new RuntimeException("stub"); }
}
