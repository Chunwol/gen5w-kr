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
    static final long SPP_ACTIVE_FALLBACK_MS = 2000L;
    interface Events { void relayEvent(String name, String result); }

    private final Handler main;
    private final Events events;
    private final BtRelaySession session = new BtRelaySession();
    private final V039BtRelayAdapter adapter;
    private final ExecutorService apCalls = Executors.newSingleThreadExecutor();
    private String candidate;
    private int attempts;
    private long retryAfter;
    /** Start time of the newest attempt; a handover-disconnect sent before it belongs to an older session. */
    private long attemptStartedAt = Long.MIN_VALUE;
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
        attemptStartedAt = now();
        apply(session.start(now()));
    }

    void handoverRequested() {
        apply(session.handoverRequested(session.generation(), now()));
    }

    void handoverConnected() {
        apply(session.iap2Connected(session.generation(), 5, now()));
    }

    void handoverDisconnected() { handoverDisconnected(-1L); }

    void handoverDisconnected(long sentAt) {
        boolean stale = sentAt >= 0 && attemptStartedAt != Long.MIN_VALUE && sentAt < attemptStartedAt;
        observeEnd(1, stale ? 0 : 1, sentAt);
        if (stale) return;
        if (active()) apply(session.cancel(session.generation(), BtRelaySession.CancelReason.PHONE_LOST));
    }

    void credentialsReady() { apply(session.credentialsReady(session.generation(), now())); }
    void apObservedReady() { apply(session.apReady(session.generation(), now())); }
    void projectionActive() { apply(session.projectionActivated(session.generation(), now())); }
    void tick() { if (active()) apply(session.tick(session.generation(), now())); }

    void cancel(BtRelaySession.CancelReason reason) {
        if (active()) apply(session.cancel(session.generation(), reason));
    }

    boolean hasCandidate(String address) { return address != null && address.equalsIgnoreCase(candidate); }

    boolean carPlayOwned() { return session.carPlayOwned(); }

    /** The phone's Bluetooth side is gone (ACL or the stock candidate). A Wi-Fi CarPlay
     * session that DiPO already runs is kept; it ends through handoverDisconnected. */
    void bluetoothLost() {
        if (session.carPlayOwned()) {
            events.relayEvent("relay", "bluetooth-lost-wifi-session-kept");
            return;
        }
        candidateLost();
    }

    /** Clears retry backoff so a user setting toggle (e.g. split screen) retries CarPlay at once. */
    void retryNow() {
        if (closed) return;
        attempts = 0;
        retryAfter = 0;
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
    boolean adapterReady() { return ready; }

    public void ready() {
        post(new Runnable() { public void run() {
            ready = true;
            events.relayEvent("relay", "adapter-ready");
            // Admission (including fresh OEM ownership) belongs to WirelessBridge.
        }});
    }

    public void sppConnected(final long generation) { post(new Runnable() { public void run() {
        events.relayEvent("step", "spp-connected");
        apply(session.sppConnected(generation, now()));
    }}); }
    public void iap2Connected(final long generation, final int component) { post(new Runnable() { public void run() {
        events.relayEvent("step", "iap2-connected-" + component);
        apply(session.iap2Connected(generation, component, now()));
    }}); }
    public void disconnected(final long generation, final int component) { post(new Runnable() { public void run() {
        // Stock Iap2Service.java:3815-3827 delivers disconnected(component); component 5 ends CarPlay transport.
        if (component == 5 && session.generation() == generation) observeEnd(2, 1, now());
        if (component != 5 && session.generation() == generation && session.carPlayOwned()) {
            events.relayEvent("relay", "bluetooth-lost-wifi-session-kept component=" + component);
            return;
        }
        apply(session.cancel(generation, BtRelaySession.CancelReason.BLUETOOTH_LOST));
    }}); }
    public void failed(final long generation, final V039BtRelayAdapter.Failure failure) {
        post(new Runnable() { public void run() {
            long owner = generation == 0 ? session.generation() : generation;
            // BTCM and the SPP data path serve only the Bluetooth side. The iAP2 service
            // also carries component 5, so losing it still ends the session.
            if (owner == session.generation() && session.carPlayOwned() &&
                    (failure == V039BtRelayAdapter.Failure.BTCM_UNAVAILABLE || failure == V039BtRelayAdapter.Failure.TRANSPORT)) {
                events.relayEvent("relay", "bluetooth-failure-wifi-session-kept " + failure.name().toLowerCase());
                return;
            }
            if (owner == session.generation() && failure == V039BtRelayAdapter.Failure.IAP2_UNAVAILABLE)
                observeEnd(3, 1, now()); // V039BtRelayAdapter iap2Binding.onServiceDisconnected:321-324.
            BtRelaySession.FailureReason reason = failure == V039BtRelayAdapter.Failure.SPP_CONNECT
                    ? BtRelaySession.FailureReason.SPP_ERROR
                    : failure == V039BtRelayAdapter.Failure.IAP2_START || failure == V039BtRelayAdapter.Failure.IAP2_UNAVAILABLE
                    ? BtRelaySession.FailureReason.IAP2_ERROR : BtRelaySession.FailureReason.TRANSPORT_ERROR;
            apply(session.fail(owner, reason));
        }});
    }

    private void observeEnd(int source, int accepted, long sentAt) {
        android.util.Log.i("Gen5wWireless", "path=relay event=session-end generation=" + session.generation()
                + " time=" + now() + " sent-at=" + sentAt + " source=" + source
                + " disconnect-delivery=" + (accepted == 1 ? "accepted" : "stale"));
        DriveLog.bridge(41, session.generation(), source, sentAt, accepted, 0, 0);
    }

    public void event(BtRelayPipe.Event value, int component) {
        events.relayEvent("transport", value.name().toLowerCase());
    }

    private long reportedGeneration = -1;

    private void apply(BtRelaySession.Update update) {
        if (closed) return;
        if (update.phase == BtRelaySession.Phase.ACTIVE) {
            attempts = 0;
            retryAfter = 0;
        }
        // An update keeps its failure until the next attempt; report it once per attempt.
        if ((update.failure != null || update.cancellation != null) && update.generation != reportedGeneration) {
            reportedGeneration = update.generation;
            if (update.failure != null) events.relayEvent("relay", "failed-" + update.failure.name().toLowerCase());
            if (update.cancellation != null) events.relayEvent("relay", "cancelled-" + update.cancellation.name().toLowerCase());
        }
        List<BtRelaySession.Command> commands = update.commands;
        if (update.phase == BtRelaySession.Phase.STOPPING && !commands.isEmpty()) cleanupOutstanding = commands.size();
        for (BtRelaySession.Command command : commands) execute(update.generation, command);
        if (update.phase == BtRelaySession.Phase.STOPPING && cleanupOutstanding == 0)
            finishCleanup(update.generation);
    }

    private void execute(final long generation, BtRelaySession.Command command) {
        events.relayEvent("step", command.type.name().toLowerCase() + (command.component != 0 ? "-" + command.component : "")
                + " phase=" + session.phase().name().toLowerCase());
        switch (command.type) {
            case CONNECT_SPP:
                if (!adapter.connect(generation, candidate)) {
                    apply(session.fail(generation, BtRelaySession.FailureReason.SPP_ERROR));
                } else if (session.generation() == generation && session.phase() == BtRelaySession.Phase.SPP_CONNECTING) {
                    main.postDelayed(new Runnable() { public void run() {
                        if (!closed && session.generation() == generation
                                && session.phase() == BtRelaySession.Phase.SPP_CONNECTING) {
                            adapter.requestSppConnect(generation);
                        }
                    }}, SPP_ACTIVE_FALLBACK_MS);
                }
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
                } catch (Exception e) {
                    kr.gen5w.diag.SafeDiagnostic.failure(enable ? "ap.ensure" : "ap.cleanup",e,generation);
                    post(new Runnable() { public void run() {
                    if (enable) apply(session.fail(generation, BtRelaySession.FailureReason.AP_ERROR));
                    else cleanupDone(generation);
                }}); }
            }});
        } catch (RuntimeException e) {
            kr.gen5w.diag.SafeDiagnostic.failure("ap.executor",e,generation);
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
