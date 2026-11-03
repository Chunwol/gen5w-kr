package kr.gen5w.hotspot;

/** The privileged AP broker accepts only its installed, non-system host app. */
public final class ApBrokerPolicy {
    private ApBrokerPolicy() { }
    public static boolean allowed(int expectedUid, int peerUid, int operation) {
        return expectedUid >= 10000 && peerUid == expectedUid && operation == 'E';
    }
}
