import kr.gen5w.wireless.SdpRefresh;

public final class SdpRefreshTest {
    private static void check(boolean value, String name) {
        if (!value) throw new AssertionError(name);
    }
    public static void main(String[] args) {
        SdpRefresh refresh = new SdpRefresh();
        check(refresh.begin("phone", 100), "first SDP request starts");
        check(!refresh.begin("phone", 200), "duplicate request is suppressed");
        check(!refresh.ready("phone"), "cached UUIDs stay unusable while SDP is pending");

        refresh.complete("phone", 300, true);
        check(refresh.ready("phone"), "UUID event marks the fresh result ready");
        check(!refresh.begin("phone", 400), "fresh result is not immediately fetched again");

        refresh.reset("phone");
        check(refresh.begin("phone", 500), "new ACL session refreshes UUIDs");
        check(refresh.begin("phone", 15500), "timed out SDP request can retry");
        refresh.complete("phone", 15600, false);
        check(!refresh.begin("phone", 20599), "failed fetch observes retry cooldown");
        check(refresh.begin("phone", 20600), "failed fetch retries after cooldown");

        refresh.reset("phone");
        check(!refresh.ready("phone"), "disconnect clears cached readiness");
        check(refresh.begin("phone", 30000), "reconnected device starts a fresh SDP query");
        System.out.println("PASS SdpRefreshTest");
    }
}
