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
        refresh.complete("phone", 600, false);
        check(!refresh.begin("phone", 15599), "first failure enforces 15s cooldown before quota exhaustion");
        check(refresh.begin("phone", 15600), "second attempt runs after 15s cooldown");
        refresh.complete("phone", 15700, false);
        check(!refresh.begin("phone", 100000), "attempts are capped at 2 per ACL connection");

        refresh.reset("phone");
        check(!refresh.ready("phone"), "disconnect clears cached readiness");
        check(refresh.begin("phone", 200000), "reconnected device starts a fresh SDP query");
        refresh.rejected("phone", 200000);
        check(!refresh.canBegin("phone", 214999), "rejected query respects 15s cooldown");
        check(refresh.begin("phone", 215000), "rejected #1 preserves attempt quota");
        refresh.rejected("phone", 215000);
        check(refresh.begin("phone", 230000), "rejected #2 preserves attempt quota");
        refresh.rejected("phone", 230000);
        check(refresh.begin("phone", 245000), "rejected #3 preserves attempt quota");
        refresh.rejected("phone", 245000);
        check(!refresh.canBegin("phone", 260000) && !refresh.begin("phone", 260000), "4th rejection hits MAX_REJECTED_ATTEMPTS cap until disconnect");
        System.out.println("PASS SdpRefreshTest");
    }
}
