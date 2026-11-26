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
    public void updateTBTSubInfo2C(int distToPoint1_unit, int distToPoint1_F, int distToPoint1_I,
            int distToPoint2_unit, int distToPoint2_F, int distToPoint2_I,
            int distToPoint3_unit, int distToPoint3_F, int distToPoint3_I) { throw new RuntimeException("stub"); }
    public void updateTBTTrapInfo(int fixedSpeed, int mobileSpeed, int overSpeedAlarm, int redlineSpeed,
            int nonSpeed, int warningZone, int curveWarning, int mergeWarning, int tollGateCurrency,
            int tollGate, int displayTG, int barGraphLevel, int speedLimit, int busSpeed,
            int speedLimitType, int speedLimitUnit, int speedInfoType) { throw new RuntimeException("stub"); }
    public void updateSTD_NAVI_PE_00_Info(int tunnelDistance, int tunnelRoadClass, int tunnelExist,
            int parkingLot, int airConditionWarning, int airConditionType) { throw new RuntimeException("stub"); }
}
