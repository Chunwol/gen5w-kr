package kr.gen5w.hud;

/** Last auxiliary Android Auto turn; never retains a route while output yields.
 * A turn that could not be written stays pending until a retry succeeds, and a
 * turn with no update for EXPIRE_MS is treated as ended (a missed end signal). */
public final class AaRouteCache {
    public static final String GPM_FINISH = "com.telechips.android.gpm.finish";
    /** Longer than a long red light, so a stopped car keeps its arrow. */
    public static final long EXPIRE_MS = 120000;
    public static boolean endsGuidance(String action) { return GPM_FINISH.equals(action); }
    private boolean allowed;
    private int icon, secondIcon;
    private long distance = -1;
    private String road;
    private boolean tunnel;
    private Maneuver maneuver;
    private long updatedAt;
    private boolean routePending, lanePending;
    private byte[] lanes;

    public synchronized void setOutputAllowed(boolean value) {
        allowed = value;
        if (!value) clear();
    }

    /** Returns false when the update was not accepted (output yielded or no turn). */
    public synchronized boolean update(int first, int second, long meters, String name, long now) {
        return update(first, second, meters, name, false, null, now);
    }

    /** Returns false when the update was not accepted (output yielded or no turn). */
    public synchronized boolean update(int first, int second, long meters, String name, boolean isTunnel, long now) {
        return update(first, second, meters, name, isTunnel, null, now);
    }

    /** Returns false when the update was not accepted (output yielded or no turn). */
    public synchronized boolean update(int first, int second, long meters, String name, boolean isTunnel, Maneuver m, long now) {
        if (!allowed || first <= 0 || meters < 0) return false;
        icon = first;
        secondIcon = second;
        distance = meters;
        road = name;
        tunnel = isTunnel;
        maneuver = m == null ? null : m.copy();
        updatedAt = now;
        routePending = true;
        return true;
    }

    /** Keep the latest lane frame so a failed write can be retried with the turn. */
    public synchronized boolean updateLanes(byte[] frame, long now) {
        if (!allowed || frame == null) return false;
        lanes = frame.clone();
        lanePending = true;
        if (isActive()) updatedAt = now;
        return true;
    }

    public synchronized void clear() {
        icon = 0; secondIcon = 0; distance = -1; road = null; tunnel = false; maneuver = null;
        routePending = false; lanePending = false; lanes = null; updatedAt = 0;
    }
    public synchronized boolean isActive() { return distance >= 0 && icon > 0; }
    public synchronized boolean allowCarPlay(boolean stockIdle) { return stockIdle && !isActive(); }
    public synchronized boolean expired(long now) { return isActive() && now - updatedAt >= EXPIRE_MS; }
    public synchronized boolean routePending() { return routePending && isActive(); }
    public synchronized boolean lanePending() { return lanePending && lanes != null && isActive(); }
    public synchronized void routeSent() { routePending = false; }
    public synchronized void laneSent() { lanePending = false; }
    public synchronized int icon() { return icon; }
    public synchronized int secondIcon() { return secondIcon; }
    public synchronized long distance() { return distance; }
    public synchronized String road() { return road; }
    public synchronized boolean tunnel() { return tunnel; }
    public synchronized Maneuver maneuver() { return maneuver == null ? null : maneuver.copy(); }
    public synchronized byte[] lanes() { return lanes == null ? null : lanes.clone(); }
}
