package kr.gen5w.hud;

/** Last auxiliary Android Auto turn; never retains a route while output yields. */
public final class AaRouteCache {
    public static final String GPM_FINISH = "com.telechips.android.gpm.finish";
    public static boolean endsGuidance(String action) { return GPM_FINISH.equals(action); }
    private boolean allowed;
    private int icon, secondIcon;
    private long distance = -1;
    private String road;

    public synchronized void setOutputAllowed(boolean value) {
        allowed = value;
        if (!value) clear();
    }

    public synchronized void update(int first, int second, long meters, String name) {
        if (!allowed || first <= 0 || meters < 0) return;
        icon = first;
        secondIcon = second;
        distance = meters;
        road = name;
    }

    public synchronized void clear() { icon = 0; secondIcon = 0; distance = -1; road = null; }
    public synchronized boolean isActive() { return distance >= 0 && icon > 0; }
    public synchronized boolean allowCarPlay(boolean stockIdle) { return stockIdle && !isActive(); }
    public synchronized int icon() { return icon; }
    public synchronized int secondIcon() { return secondIcon; }
    public synchronized String road() { return road; }
}
