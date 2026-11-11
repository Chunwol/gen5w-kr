import kr.gen5w.hotspot.ApBrokerPolicy;

public final class ApBrokerPolicyTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        check(ApBrokerPolicy.allowed(10234, 10234, 'E'), "owner may request AP setup");
        check(ApBrokerPolicy.allowed(10234, 10234, 'D'), "owner may stop projection AP");
        check(!ApBrokerPolicy.allowed(10234, 10235, 'E'), "other app is rejected");
        check(!ApBrokerPolicy.allowed(-1, -1, 'E'), "unknown owner is rejected");
        check(!ApBrokerPolicy.allowed(10234, 10234, 'X'), "unknown operation is rejected");
        check(!ApBrokerPolicy.allowed(1000, 1000, 'E'), "system UID is not an app identity");
        check(ApBrokerPolicy.readTimedOut(new java.io.IOException("Try again")), "V039 LocalSocket EAGAIN is a timeout, not a failure");
        check(ApBrokerPolicy.readTimedOut(new java.net.SocketTimeoutException()), "standard timeout");
        check(!ApBrokerPolicy.readTimedOut(new java.io.IOException("AP setup unavailable")), "broker refusal stays a failure");
        check(!ApBrokerPolicy.readTimedOut(new java.io.IOException("Connection reset by peer")), "broker loss stays a failure");
        check(!ApBrokerPolicy.readTimedOut(new java.io.IOException()), "unknown error stays a failure");
        System.out.println("ApBrokerPolicyTest passed");
    }
}
