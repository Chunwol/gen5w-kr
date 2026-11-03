import kr.gen5w.hotspot.ApBrokerPolicy;

public final class ApBrokerPolicyTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        check(ApBrokerPolicy.allowed(10234, 10234, 'E'), "owner may request AP setup");
        check(!ApBrokerPolicy.allowed(10234, 10235, 'E'), "other app is rejected");
        check(!ApBrokerPolicy.allowed(-1, -1, 'E'), "unknown owner is rejected");
        check(!ApBrokerPolicy.allowed(10234, 10234, 'X'), "unknown operation is rejected");
        check(!ApBrokerPolicy.allowed(1000, 1000, 'E'), "system UID is not an app identity");
        System.out.println("ApBrokerPolicyTest passed");
    }
}
