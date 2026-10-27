package kr.gen5w.hud;

/** Tickets connect binder callbacks to the route session that accepted them. */
public final class NotificationEpoch {
    private long generation;
    private boolean connected;
    public synchronized long open() {
        if (!connected) { connected = true; generation++; }
        return generation;
    }
    public synchronized long close() { connected = false; return ++generation; }
    public synchronized long ticket() { return connected ? generation : -1; }
    public synchronized boolean isCurrent(long ticket) { return connected && ticket >= 0 && ticket == generation; }
}
