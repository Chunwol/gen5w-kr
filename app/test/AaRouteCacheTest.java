import kr.gen5w.hud.AaRouteCache;

public final class AaRouteCacheTest {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    public static void main(String[] args) {
        check(AaRouteCache.endsGuidance("com.telechips.android.gpm.finish"));
        check(!AaRouteCache.endsGuidance("android.hardware.usb.action.USB_STATE"));
        check(!AaRouteCache.endsGuidance(null));
        AaRouteCache cache = new AaRouteCache();
        check(!cache.isActive());
        cache.setOutputAllowed(true);
        check(cache.update(0x41, 0x42, 800, "road A", 0));
        check(cache.isActive() && cache.icon() == 0x41 && cache.secondIcon() == 0x42 && cache.distance() == 800);
        cache.setOutputAllowed(false);
        check(!cache.isActive() && cache.icon() == 0 && cache.road() == null);
        check(!cache.update(0x43, 0, 700, "suppressed road", 0));
        check(!cache.isActive());
        cache.setOutputAllowed(true);
        check(!cache.isActive());
        cache.update(0x44, 0, 600, "road B", 0);
        check(cache.isActive() && cache.icon() == 0x44 && "road B".equals(cache.road()));
        cache.clear();
        check(!cache.isActive());

        // A turn stays pending until a write succeeds; a new turn is pending again.
        cache.update(0x41, 0, 500, "road C", 1000);
        check(cache.routePending());
        check(cache.routePending());
        cache.routeSent();
        check(!cache.routePending());
        cache.update(0x41, 0, 400, "road C", 2000);
        check(cache.routePending());
        cache.routeSent();

        // Lanes are retried only while a turn is shown.
        byte[] lane = {1, 2, 3};
        check(cache.updateLanes(lane, 2500));
        lane[0] = 9;
        check(cache.lanePending() && cache.lanes()[0] == 1);
        cache.laneSent();
        check(!cache.lanePending());
        cache.updateLanes(new byte[]{4}, 2600);
        cache.clear();
        check(!cache.lanePending() && cache.lanes() == null);
        cache.updateLanes(new byte[]{5}, 2700);
        check(!cache.lanePending());
        check(!cache.routePending());

        // A turn with no update for EXPIRE_MS has expired; any update restarts the clock.
        cache.clear();
        cache.update(0x41, 0, 300, "road D", 10000);
        check(!cache.expired(10000 + AaRouteCache.EXPIRE_MS - 1));
        check(cache.expired(10000 + AaRouteCache.EXPIRE_MS));
        cache.update(0x41, 0, 300, "road D", 50000);
        check(!cache.expired(10000 + AaRouteCache.EXPIRE_MS));
        cache.updateLanes(new byte[]{6}, 100000);
        check(!cache.expired(50000 + AaRouteCache.EXPIRE_MS));
        check(cache.expired(100000 + AaRouteCache.EXPIRE_MS));
        cache.clear();
        check(!cache.expired(Long.MAX_VALUE));
        check(AaRouteCache.EXPIRE_MS >= 60000);
        System.out.println("AaRouteCacheTest passed");
    }
}
