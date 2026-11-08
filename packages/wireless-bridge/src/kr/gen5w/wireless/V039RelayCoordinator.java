package kr.gen5w.wireless;

import android.content.Context;
import android.os.Handler;
import android.os.SystemClock;
import kr.gen5w.hotspot.ApBrokerClient;
import kr.gen5w.hotspot.ApProfiles;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Single owner for the exact-V039 fallback transport and projection AP. */
final class V039RelayCoordinator implements V039BtRelayAdapter.Listener, BtRelayPipe.Diagnostics {
    interface Events { void relayEvent(String name, String result); }

    private final Handler main;
    private final Events events;
    private final BtRelaySession session = new BtRelaySession();
    private final V039BtRelayAdapter adapter;
    private final ExecutorService apCalls = Executors.newSingleThreadExecutor();
    private String candidate;
    private int attempts;
    private long retryAfter;
    private boolean ready;
    private volatile boolean closed;
    private volatile long shutdownDeadline;
    private int cleanupOutstanding;

    V039RelayCoordinator(Context context, Handler main, Events events) {
        this.main = main;
        this.events = events;
        this.adapter = new V039BtRelayAdapter(context, this, this);
    }

    void open() { if (!adapter.open()) events.relayEvent("relay", "adapter-unavailable"); }

    void start(String address) {
        if (closed || address == null || address.length() == 0 || active()) return;
        if (!address.equals(candidate)) { candidate = address; attempts = 0; retryAfter = 0; }
        if (attempts >= 3 || now() < retryAfter) return;
        if (!ready) { events.relayEvent("relay", "adapter-waiting"); return; }
        attempts++;
        apply(session.start(now()));
    }

    void handoverRequested() {
        apply(session.handoverRequested(session.generation(), now()));
    }

    void handoverConnected() {
        apply(session.iap2Connected(session.generation(), 5, now()));
    }

    void handoverDisconnected() {
        if (active()) apply(session.cancel(session.generation(), BtRelaySession.CancelReason.PHONE_LOST));
    }

    void credentialsReady() { apply(session.credentialsReady(session.generation(), now())); }
    void apObservedReady() { apply(session.apReady(session.generation(), now())); }
    void projectionActive() { apply(session.projectionActivated(session.generation(), now())); }
    void tick() { if (active()) apply(session.tick(session.generation(), now())); }

    void cancel(BtRelaySession.CancelReason reason) {
        if (active()) apply(session.cancel(session.generation(), reason));
    }

    void candidateLost() {
        cancel(BtRelaySession.CancelReason.PHONE_LOST);
        attempts = 0;
        retryAfter = 0;
        candidate = null;
    }

    void close() {
        if (closed) return;
        shutdownDeadline = now() + 20000;
        cancel(BtRelaySession.CancelReason.SHUTDOWN);
        closed = true;
        adapter.close();
        // Drain our queued STOP_AP; interrupting the executor loses cleanup.
        apCalls.shutdown();
    }

    boolean active() {
        BtRelaySession.Phase phase = session.phase();
        return phase != BtRelaySession.Phase.IDLE && phase != BtRelaySession.Phase.FAILED &&
                phase != BtRelaySession.Phase.CANCELLED;
    }

    long generation() { return session.generation(); }

    public void ready() {
        post(new Runnable() { public void run() {
            ready = true;
            events.relayEvent("relay", "adapter-ready");
            // Admission (including fresh OEM ownership) belongs to WirelessBridge.
        }});
    }

    public void sppConnected(final long generation) { post(new Runnable() { public void run() {
        apply(session.sppConnected(generation, now()));
    }}); }
    public void iap2Connected(final long generation, final int component) { post(new Runnable() { public void run() {
        apply(session.iap2Connected(generation, component, now()));
    }}); }
    public void disconnected(final long generation, final int component) { post(new Runnable() { public void run() {
        apply(session.cancel(generation, BtRelaySession.CancelReason.BLUETOOTH_LOST));
    }}); }
    public void failed(final long generation, final V039BtRelayAdapter.Failure failure) {
        post(new Runnable() { public void run() {
            long owner = generation == 0 ? session.generation() : generation;
            BtRelaySession.FailureReason reason = failure == V039BtRelayAdapter.Failure.SPP_CONNECT
                    ? BtRelaySession.FailureReason.SPP_ERROR
                    : failure == V039BtRelayAdapter.Failure.IAP2_START || failure == V039BtRelayAdapter.Failure.IAP2_UNAVAILABLE
                    ? BtRelaySession.FailureReason.IAP2_ERROR : BtRelaySession.FailureReason.TRANSPORT_ERROR;
            apply(session.fail(owner, reason));
        }});
    }

    public void event(BtRelayPipe.Event value, int component) {
        events.relayEvent("transport", value.name().toLowerCase());
    }

    private void apply(BtRelaySession.Update update) {
        if (closed) return;
        if (update.failure != null) events.relayEvent("relay", "failed-" + update.failure.name().toLowerCase());
        if (update.cancellation != null) events.relayEvent("relay", "cancelled-" + update.cancellation.name().toLowerCase());
        List<BtRelaySession.Command> commands = update.commands;
        if (update.phase == BtRelaySession.Phase.STOPPING && !commands.isEmpty()) cleanupOutstanding = commands.size();
        for (BtRelaySession.Command command : commands) execute(update.generation, command);
        if (update.phase == BtRelaySession.Phase.STOPPING && cleanupOutstanding == 0)
            finishCleanup(update.generation);
    }

    private void execute(final long generation, BtRelaySession.Command command) {
        switch (command.type) {
            case CONNECT_SPP:
                if (!adapter.connect(generation, candidate)) apply(session.fail(generation, BtRelaySession.FailureReason.SPP_ERROR));
                break;
            case START_IAP2:
                if (!adapter.startIap2(generation, command.component))
                    apply(session.fail(generation, BtRelaySession.FailureReason.IAP2_ERROR));
                break;
            case START_AP: ap(true, generation); break;
            case STOP_AP: ap(false, generation); break;
            case STOP_IAP2: adapter.stop(command.component); cleanupDone(generation); break;
            case DISCONNECT_SPP: adapter.disconnect(); cleanupDone(generation); break;
        }
    }

    private void ap(final boolean enable, final long generation) {
        try {
            apCalls.execute(new Runnable() { public void run() {
                try {
                    ApProfiles.Guard guard = new ApProfiles.Guard() { public void check() throws Exception {
                        if ((closed && (enable || now() > shutdownDeadline)) ||
                                session.generation() != generation) throw new Exception("stale relay");
                    }};
                    if (enable) ApBrokerClient.ensure(guard); else ApBrokerClient.stop(guard);
                    post(new Runnable() { public void run() {
                        if (enable) apply(session.apReady(generation, now())); else cleanupDone(generation);
                    }});
                } catch (Exception e) { post(new Runnable() { public void run() {
                    if (enable) apply(session.fail(generation, BtRelaySession.FailureReason.AP_ERROR));
                    else cleanupDone(generation);
                }}); }
            }});
        } catch (RuntimeException e) {
            if (enable) apply(session.fail(generation, BtRelaySession.FailureReason.AP_ERROR));
            else cleanupDone(generation);
        }
    }

    private void cleanupDone(long generation) {
        if (session.phase() != BtRelaySession.Phase.STOPPING || session.generation() != generation) return;
        if (cleanupOutstanding > 0) cleanupOutstanding--;
        if (cleanupOutstanding == 0) {
            finishCleanup(generation);
        }
    }

    private void finishCleanup(long generation) {
        session.cleanupCompleted(generation);
        retryAfter = now() + attempts * 5000L;
    }

    private void post(Runnable action) { main.post(action); }
    private static long now() { return SystemClock.elapsedRealtime(); }
}
