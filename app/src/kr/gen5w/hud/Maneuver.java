package kr.gen5w.hud;

/** One turn, as read from a route-guidance message (field meanings filled from probe results). */
public final class Maneuver {
    public static final int UNKNOWN_ANGLE = Integer.MIN_VALUE;
    public static final int UNKNOWN_DRIVING_SIDE = -1;
    public int component;
    public int index;
    public int type;        // iAP2 maneuver/turn type
    public int drivingSide = UNKNOWN_DRIVING_SIDE; // stock iAP2: 0 right-hand, 1 left-hand
    public int exitAngle = UNKNOWN_ANGLE;
    public int junctionType = -1;
    public int roundaboutExit = -1;
    /** iAP2 junction geometry, when the sender supplied it. */
    public int[] junctionElementAngles = new int[0];
    public boolean hasJunctionElementAngles;
    public long distanceMeters = -1;
    public String afterRoad; // name of the road after the turn; never used to invent maneuver type
    public String desc;      // free-text description if present
    public String appSource; // source app bundle/identifier if known (e.g. Naver, TMAP, Kakao)

    public Maneuver copy() {
        Maneuver m = new Maneuver();
        m.component = component;
        m.index = index;
        m.type = type;
        m.drivingSide = drivingSide;
        m.exitAngle = exitAngle;
        m.junctionType = junctionType;
        m.roundaboutExit = roundaboutExit;
        m.junctionElementAngles = junctionElementAngles == null ? new int[0] : junctionElementAngles.clone();
        m.hasJunctionElementAngles = hasJunctionElementAngles;
        m.distanceMeters = distanceMeters;
        m.afterRoad = afterRoad;
        m.desc = desc;
        m.appSource = appSource;
        return m;
    }
}
