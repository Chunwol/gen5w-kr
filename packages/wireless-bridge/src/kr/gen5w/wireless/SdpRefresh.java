package kr.gen5w.wireless;

import java.util.HashMap;
import java.util.Map;

/** Tracks asynchronous SDP refreshes without trusting stale Bluetooth UUID cache entries. */
public final class SdpRefresh {
    private static final long REQUEST_TIMEOUT_MS = 15000;
    private static final long RETRY_DELAY_MS = 15000;
    private static final int MAX_ATTEMPTS = 2;
    private static final int MAX_REJECTED_ATTEMPTS = 4;

    private static final class State {
        long pendingUntil;
        long retryAfter;
        int attempts;
        int rejectedAttempts;
        boolean ready;
    }

    private final Map<String, State> states = new HashMap<String, State>();

    public synchronized boolean canBegin(String address, long now) {
        if (address == null) return false;
        State state = states.get(address);
        if (state == null) return true;
        if (state.ready) return false;
        if (state.pendingUntil > now) return false;
        if (state.retryAfter > now) return false;
        if (state.attempts >= MAX_ATTEMPTS) return false;
        if (state.rejectedAttempts >= MAX_REJECTED_ATTEMPTS) return false;
        return true;
    }

    /** Returns true when the caller should issue fetchUuidsWithSdp now. */
    public synchronized boolean begin(String address, long now) {
        if (address == null) return false;
        State state = states.get(address);
        if (state == null) {
            state = new State();
            states.put(address, state);
        }
        if (state.ready) return false;
        if (state.pendingUntil > now) return false;
        if (state.retryAfter > now) return false;
        if (state.attempts >= MAX_ATTEMPTS) return false;
        if (state.rejectedAttempts >= MAX_REJECTED_ATTEMPTS) return false;
        state.attempts++;
        state.pendingUntil = now + REQUEST_TIMEOUT_MS;
        return true;
    }

    /** Records an immediate false from fetchUuidsWithSdp without consuming query quota. */
    public synchronized void rejected(String address, long now) {
        if (address == null) return;
        State state = states.get(address);
        if (state == null || state.ready) return;
        if (state.attempts > 0) state.attempts--;
        state.rejectedAttempts++;
        state.pendingUntil = 0;
        state.retryAfter = now + RETRY_DELAY_MS;
    }

    /** Completes a request when ACTION_UUID arrives, or records a rejected request. */
    public synchronized void complete(String address, long now, boolean success) {
        if (address == null) return;
        State state = states.get(address);
        if (state == null) {
            state = new State();
            states.put(address, state);
        }
        state.pendingUntil = 0;
        state.ready = success;
        state.retryAfter = success ? 0 : now + RETRY_DELAY_MS;
    }

    public synchronized boolean ready(String address) {
        State state = address == null ? null : states.get(address);
        return state != null && state.ready;
    }

    public synchronized void reset(String address) {
        if (address != null) states.remove(address);
    }

    public synchronized void clear() {
        states.clear();
    }
}
