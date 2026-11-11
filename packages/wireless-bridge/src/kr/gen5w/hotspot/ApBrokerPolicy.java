package kr.gen5w.hotspot;

/** The privileged AP broker accepts only its installed, non-system host app. */
public final class ApBrokerPolicy {
    private ApBrokerPolicy() { }
    public static boolean allowed(int expectedUid, int peerUid, int operation) {
        return expectedUid >= 10000 && peerUid == expectedUid && (operation == 'E' || operation == 'D');
    }
    /** A LocalSocket read that hit its SO_RCVTIMEO. Android 4.x (V039) does not
     * throw SocketTimeoutException there: it throws IOException("Try again")
     * (EAGAIN). Treating that as a failure cancelled every AP start 200 ms in. */
    public static boolean readTimedOut(java.io.IOException e) {
        if (e instanceof java.net.SocketTimeoutException) return true;
        String m = e.getMessage();
        return "Try again".equals(m) || "Resource temporarily unavailable".equals(m)
                || "EAGAIN".equals(m) || "EWOULDBLOCK".equals(m);
    }
}
