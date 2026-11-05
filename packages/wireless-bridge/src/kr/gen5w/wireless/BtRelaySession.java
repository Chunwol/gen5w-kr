package kr.gen5w.wireless;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Pure, generation-checked lifecycle for one Bluetooth CarPlay relay attempt. */
public final class BtRelaySession {
    public static final long SPP_TIMEOUT_MS = 10000L;
    public static final long IAP2_TIMEOUT_MS = 15000L;
    public static final long HANDOVER_TIMEOUT_MS = 30000L;
    public static final long AP_TIMEOUT_MS = 30000L;
    public static final long ACTIVATION_TIMEOUT_MS = 60000L;

    public enum Phase {
        IDLE, SPP_CONNECTING, IAP2_BLUETOOTH, CARPLAY_HANDOVER,
        ACTIVE, STOPPING, FAILED, CANCELLED
    }

    public enum CommandType {
        CONNECT_SPP, START_IAP2, START_AP, STOP_AP, STOP_IAP2, DISCONNECT_SPP
    }

    public enum CancelReason { REQUESTED, WIRED, FOREIGN_OWNER, BLUETOOTH_LOST, PHONE_LOST, SHUTDOWN }
    public enum FailureReason { SPP_TIMEOUT, IAP2_TIMEOUT, HANDOVER_TIMEOUT, AP_TIMEOUT, ACTIVATION_TIMEOUT }

    public static final class Command {
        public final CommandType type;
        public final int component;

        private Command(CommandType type, int component) {
            this.type = type;
            this.component = component;
        }
    }

    public static final class Update {
        public final long generation;
        public final Phase phase;
        public final List<Command> commands;
        public final FailureReason failure;
        public final CancelReason cancellation;

        private Update(long generation, Phase phase, List<Command> commands,
                FailureReason failure, CancelReason cancellation) {
            this.generation = generation;
            this.phase = phase;
            this.commands = Collections.unmodifiableList(new ArrayList<Command>(commands));
            this.failure = failure;
            this.cancellation = cancellation;
        }
    }

    private Phase phase = Phase.IDLE;
    private long generation;
    private long deadline;
    private boolean sppRequested;
    private boolean component4Requested;
    private boolean component5Requested;
    private boolean component5Connected;
    private boolean credentialsReady;
    private boolean apRequested;
    private boolean apReady;
    private FailureReason failure;
    private CancelReason cancellation;

    public synchronized Update start(long now) {
        List<Command> commands = new ArrayList<Command>();
        if (phase != Phase.IDLE && phase != Phase.FAILED && phase != Phase.CANCELLED) return update(commands);
        generation++;
        clearResources();
        failure = null;
        cancellation = null;
        sppRequested = true;
        phase = Phase.SPP_CONNECTING;
        deadline = now + SPP_TIMEOUT_MS;
        commands.add(command(CommandType.CONNECT_SPP, 0));
        return update(commands);
    }

    public synchronized Update sppConnected(long callbackGeneration, long now) {
        List<Command> commands = new ArrayList<Command>();
        if (current(callbackGeneration) && phase == Phase.SPP_CONNECTING) {
            phase = Phase.IAP2_BLUETOOTH;
            component4Requested = true;
            deadline = now + IAP2_TIMEOUT_MS;
            commands.add(command(CommandType.START_IAP2, 4));
        }
        return update(commands);
    }

    public synchronized Update iap2Connected(long callbackGeneration, int component, long now) {
        List<Command> commands = new ArrayList<Command>();
        if (!current(callbackGeneration)) return update(commands);
        if (component == 4 && phase == Phase.IAP2_BLUETOOTH && component4Requested) {
            phase = Phase.CARPLAY_HANDOVER;
            deadline = now + HANDOVER_TIMEOUT_MS;
        } else if (component == 5 && phase == Phase.CARPLAY_HANDOVER && component5Requested &&
                !component5Connected) {
            component5Connected = true;
            deadline = now + HANDOVER_TIMEOUT_MS;
            requestApIfReady(now, commands);
        }
        return update(commands);
    }

    /** Called when DiPO has created the wireless CarPlay session that accepts component 5. */
    public synchronized Update handoverRequested(long callbackGeneration, long now) {
        List<Command> commands = new ArrayList<Command>();
        if (current(callbackGeneration) && phase == Phase.CARPLAY_HANDOVER &&
                component4Requested && !component5Requested) {
            component5Requested = true;
            deadline = now + HANDOVER_TIMEOUT_MS;
            commands.add(command(CommandType.START_IAP2, 5));
        }
        return update(commands);
    }

    /** Credentials are represented only by readiness; values are never retained. */
    public synchronized Update credentialsReady(long callbackGeneration, long now) {
        List<Command> commands = new ArrayList<Command>();
        if (current(callbackGeneration) && phase == Phase.CARPLAY_HANDOVER) {
            credentialsReady = true;
            requestApIfReady(now, commands);
        }
        return update(commands);
    }

    public synchronized Update apReady(long callbackGeneration, long now) {
        List<Command> commands = new ArrayList<Command>();
        if (current(callbackGeneration) && phase == Phase.CARPLAY_HANDOVER && apRequested && !apReady) {
            apReady = true;
            deadline = now + ACTIVATION_TIMEOUT_MS;
        }
        return update(commands);
    }

    public synchronized Update projectionActivated(long callbackGeneration, long now) {
        List<Command> commands = new ArrayList<Command>();
        if (current(callbackGeneration) && phase == Phase.CARPLAY_HANDOVER && apReady && component5Connected) {
            phase = Phase.ACTIVE;
            deadline = 0;
        }
        return update(commands);
    }

    public synchronized Update tick(long callbackGeneration, long now) {
        List<Command> commands = new ArrayList<Command>();
        if (!current(callbackGeneration) || !waiting() || now < deadline) return update(commands);
        failure = timeoutReason();
        phase = Phase.STOPPING;
        cleanup(commands);
        return update(commands);
    }

    public synchronized Update cancel(long callbackGeneration, CancelReason reason) {
        List<Command> commands = new ArrayList<Command>();
        if (!current(callbackGeneration) || phase == Phase.IDLE || phase == Phase.STOPPING ||
                phase == Phase.FAILED || phase == Phase.CANCELLED) return update(commands);
        cancellation = reason == null ? CancelReason.REQUESTED : reason;
        phase = Phase.STOPPING;
        cleanup(commands);
        return update(commands);
    }

    /** Completes adapter teardown and only then releases the single-owner gate. */
    public synchronized Update cleanupCompleted(long callbackGeneration) {
        List<Command> commands = new ArrayList<Command>();
        if (!current(callbackGeneration) || phase != Phase.STOPPING) return update(commands);
        phase = failure == null ? Phase.CANCELLED : Phase.FAILED;
        Update completed = updateFor(callbackGeneration, commands);
        generation++;
        return completed;
    }

    public synchronized Phase phase() { return phase; }
    public synchronized long generation() { return generation; }

    private void requestApIfReady(long now, List<Command> commands) {
        if (component5Connected && credentialsReady && !apRequested) {
            apRequested = true;
            deadline = now + AP_TIMEOUT_MS;
            commands.add(command(CommandType.START_AP, 0));
        }
    }

    private void cleanup(List<Command> commands) {
        if (apRequested) commands.add(command(CommandType.STOP_AP, 0));
        if (component5Requested) commands.add(command(CommandType.STOP_IAP2, 5));
        if (component4Requested) commands.add(command(CommandType.STOP_IAP2, 4));
        if (sppRequested) commands.add(command(CommandType.DISCONNECT_SPP, 0));
        clearResources();
    }

    private void clearResources() {
        sppRequested = false;
        component4Requested = false;
        component5Requested = false;
        component5Connected = false;
        credentialsReady = false;
        apRequested = false;
        apReady = false;
        deadline = 0;
    }

    private FailureReason timeoutReason() {
        if (phase == Phase.SPP_CONNECTING) return FailureReason.SPP_TIMEOUT;
        if (phase == Phase.IAP2_BLUETOOTH) return FailureReason.IAP2_TIMEOUT;
        if (apReady) return FailureReason.ACTIVATION_TIMEOUT;
        if (apRequested) return FailureReason.AP_TIMEOUT;
        return FailureReason.HANDOVER_TIMEOUT;
    }

    private boolean current(long callbackGeneration) { return callbackGeneration == generation; }

    private boolean waiting() {
        return phase == Phase.SPP_CONNECTING || phase == Phase.IAP2_BLUETOOTH ||
                phase == Phase.CARPLAY_HANDOVER;
    }

    private Update update(List<Command> commands) { return updateFor(generation, commands); }

    private Update updateFor(long updateGeneration, List<Command> commands) {
        return new Update(updateGeneration, phase, commands, failure, cancellation);
    }

    private static Command command(CommandType type, int component) { return new Command(type, component); }
}
