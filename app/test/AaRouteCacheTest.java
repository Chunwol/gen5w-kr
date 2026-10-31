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
        cache.update(0x41, 0x42, 800, "road A");
        check(cache.isActive() && cache.icon() == 0x41 && cache.secondIcon() == 0x42);
        cache.setOutputAllowed(false);
        check(!cache.isActive() && cache.icon() == 0 && cache.road() == null);
        cache.update(0x43, 0, 700, "suppressed road");
        check(!cache.isActive());
        cache.setOutputAllowed(true);
        check(!cache.isActive());
        cache.update(0x44, 0, 600, "road B");
        check(cache.isActive() && cache.icon() == 0x44 && "road B".equals(cache.road()));
        cache.clear();
        check(!cache.isActive());
        System.out.println("AaRouteCacheTest passed");
    }
}
