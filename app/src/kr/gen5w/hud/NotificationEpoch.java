package kr.gen5w.hud;

/** Tickets connect binder callbacks to the route session that accepted them. */
public final class NotificationEpoch {
    private long generation;
    private boolean connected;
    private int component = -1;
    public synchronized long open() {
        if (!connected) { connected = true; generation++; }
        return generation;
    }
    /** A new transport owns a new subscription even without an intervening disconnect. */
    public synchronized long open(int nextComponent) {
        if (!connected || component != nextComponent) {
            connected = true; component = nextComponent; generation++;
        }
        return generation;
    }
    /** Ignore a delayed departure from the transport preceding a handover. */
    public synchronized long close(int departingComponent) {
        if (!connected || (component != -1 && component != departingComponent)) return -1;
        return close();
    }
    public synchronized long close() { connected = false; component = -1; return ++generation; }
    public synchronized long ticket() { return connected ? generation : -1; }
    public synchronized boolean isCurrent(long ticket) { return connected && ticket >= 0 && ticket == generation; }
}
