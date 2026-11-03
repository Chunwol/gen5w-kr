package kr.gen5w.wireless;

/** Owns one fail-closed OEM PhoneProjection request at a time. */
public final class StockProjectionSession {
    public static final long REQUEST_TIMEOUT_MS = 20000L;
    private static final long INSPECTION_TIMEOUT_MS = 5000L;
    private static final long POLL_INTERVAL_MS = 1000L;

    public enum Phase { IDLE, INSPECTING, REQUESTING, REQUESTED, ACTIVE, BLOCKED, FAILED }
    public enum Result { INVOKED, SERVICE_UNAVAILABLE, METHOD_UNAVAILABLE, SECURITY, INVOCATION }
    public enum RequestResult {
        OEM_ACTION_SENT, PROFILE_UNAVAILABLE, PROFILE_MISMATCH, PROFILE_DISABLED,
        AUTO_CONNECT_DISABLED, CANCELLED, SERVICE_UNAVAILABLE, METHOD_UNAVAILABLE, SECURITY, INVOCATION
    }

    public interface Port {
        void inspect(long generation, String address);
        void requestConnect(long generation, String address);
        void event(String name, String result);
    }
    public interface RequestAction { void send(); }

    public static final class Observation {
        public final Result result;
        public final boolean serviceAvailable;
        public final boolean projectionActiveForCandidate;
        public final boolean projectionConnectingForCandidate;
        public final boolean otherProjectionActive;

        public Observation(Result result, boolean serviceAvailable,
                boolean projectionActiveForCandidate, boolean otherProjectionActive) {
            this(result, serviceAvailable, projectionActiveForCandidate, false, otherProjectionActive);
        }

        public Observation(Result result, boolean serviceAvailable,
                boolean projectionActiveForCandidate, boolean projectionConnectingForCandidate,
                boolean otherProjectionActive) {
            this.result = result == null ? Result.INVOCATION : result;
            this.serviceAvailable = serviceAvailable;
            this.projectionActiveForCandidate = projectionActiveForCandidate;
            this.projectionConnectingForCandidate = projectionConnectingForCandidate;
            this.otherProjectionActive = otherProjectionActive;
        }
    }

    private final Port port;
    private long generation;
    private String candidate;
    private Phase phase = Phase.IDLE;
    private boolean wired;
    private boolean foreignProjection;
    private boolean inspectionPending;
    private boolean requestPending;
    private boolean requestIssued;
    private boolean observedConnecting;
    private long inspectionDeadline;
    private long requestDeadline;
    private long nextPoll;

    public StockProjectionSession(Port port) {
        if (port == null) throw new IllegalArgumentException("port");
        this.port = port;
    }

    public synchronized void candidate(String address, long now) {
        if (address == null || address.length() == 0) return;
        if (address.equals(candidate)) return;
        generation++;
        candidate = address;
        phase = Phase.IDLE;
        inspectionPending = false;
        requestPending = false;
        requestIssued = false;
        observedConnecting = false;
        inspectionDeadline = 0;
        requestDeadline = 0;
        nextPoll = now;
        port.event("candidate", "ready");
    }

    public synchronized void lost(String address, long now) {
        if (candidate == null || (address != null && !candidate.equals(address))) return;
        generation++;
        candidate = null;
        phase = Phase.IDLE;
        inspectionPending = false;
        requestPending = false;
        requestIssued = false;
        observedConnecting = false;
        inspectionDeadline = 0;
        requestDeadline = 0;
        nextPoll = now;
        port.event("cancel", "acl-lost");
    }

    /** Wired or foreign projection ownership invalidates all pending callbacks. */
    public synchronized void environment(boolean wired, boolean foreignProjection, long now) {
        boolean blocked = wired || foreignProjection;
        boolean wasBlocked = this.wired || this.foreignProjection;
        this.wired = wired;
        this.foreignProjection = foreignProjection;
        if (!blocked) return;
        if (!wasBlocked || inspectionPending || requestPending || phase != Phase.IDLE) {
            generation++;
            inspectionPending = false;
            requestPending = false;
            requestIssued = false;
            observedConnecting = false;
            phase = Phase.IDLE;
            inspectionDeadline = 0;
            requestDeadline = 0;
            nextPoll = now;
            port.event("cancel", wired ? "wired" : "foreign");
        }
    }

    public synchronized void tick(long now) {
        if (candidate == null || wired || foreignProjection) return;
        if (inspectionPending && now >= inspectionDeadline) {
            inspectionPending = false;
            phase = Phase.FAILED;
            port.event("result", "timeout");
            return;
        }
        if (requestPending && now >= inspectionDeadline) {
            requestPending = false;
            phase = Phase.FAILED;
            port.event("result", "timeout");
            return;
        }
        if ((requestIssued || observedConnecting) && !requestPending && phase != Phase.ACTIVE &&
                phase != Phase.BLOCKED && phase != Phase.FAILED && now >= requestDeadline) {
            requestPending = false;
            phase = Phase.FAILED;
            port.event("result", "timeout");
            return;
        }
        if (phase == Phase.IDLE) {
            inspect(now);
        } else if (phase == Phase.REQUESTED && !inspectionPending && now >= nextPoll) {
            inspect(now);
        }
    }

    private void inspect(long now) {
        if (candidate == null || inspectionPending || wired || foreignProjection) return;
        inspectionPending = true;
        inspectionDeadline = now + INSPECTION_TIMEOUT_MS;
        phase = Phase.INSPECTING;
        port.inspect(generation, candidate);
    }

    public synchronized void inspected(long callbackGeneration, Observation observation, long now) {
        if (!current(callbackGeneration) || !inspectionPending) return;
        inspectionPending = false;
        if (observation == null || observation.result != Result.INVOKED || !observation.serviceAvailable) {
            phase = Phase.FAILED;
            port.event("service", resultName(observation == null ? Result.INVOCATION : observation.result));
            port.event("result", "unavailable");
            return;
        }
        if (observation.projectionActiveForCandidate) {
            observedConnecting = false;
            phase = Phase.ACTIVE;
            port.event("result", "projection-active");
            return;
        }
        if (observation.projectionConnectingForCandidate) {
            if (!observedConnecting) {
                requestDeadline = now + REQUEST_TIMEOUT_MS;
                port.event("progress", "connecting");
            }
            observedConnecting = true;
            phase = Phase.REQUESTED;
            nextPoll = now + POLL_INTERVAL_MS;
            return;
        }
        if (observation.otherProjectionActive) {
            observedConnecting = false;
            phase = Phase.BLOCKED;
            port.event("result", "foreign-active");
            return;
        }
        observedConnecting = false;
        if (requestIssued) {
            phase = Phase.REQUESTED;
            nextPoll = now + POLL_INTERVAL_MS;
            return;
        }
        requestIssued = true;
        requestPending = true;
        phase = Phase.REQUESTING;
        inspectionDeadline = now + INSPECTION_TIMEOUT_MS;
        port.requestConnect(generation, candidate);
    }

    public synchronized void requested(long callbackGeneration, RequestResult result, long now) {
        if (!current(callbackGeneration) || !requestPending) return;
        requestPending = false;
        if (result == RequestResult.CANCELLED) {
            if (now >= inspectionDeadline) {
                phase = Phase.FAILED;
                port.event("result", "timeout");
                return;
            }
            requestIssued = false;
            phase = Phase.IDLE;
            port.event("cancel", "stale-request");
            return;
        }
        if (result == RequestResult.PROFILE_UNAVAILABLE || result == RequestResult.PROFILE_MISMATCH ||
                result == RequestResult.PROFILE_DISABLED || result == RequestResult.AUTO_CONNECT_DISABLED) {
            phase = Phase.BLOCKED;
            port.event("request", requestName(result));
            return;
        }
        if (result != RequestResult.OEM_ACTION_SENT) {
            phase = Phase.FAILED;
            port.event("request", requestName(result));
            port.event("result", "unavailable");
            return;
        }
        phase = Phase.REQUESTED;
        requestDeadline = now + REQUEST_TIMEOUT_MS;
        nextPoll = now + POLL_INTERVAL_MS;
        port.event("request", "oem-action-sent");
    }

    public synchronized void shutdown() {
        generation++;
        candidate = null;
        phase = Phase.IDLE;
        inspectionPending = false;
        requestPending = false;
        requestIssued = false;
        observedConnecting = false;
        port.event("cancel", "shutdown");
    }

    public synchronized boolean current(long value) { return candidate != null && generation == value; }
    public synchronized boolean requestAllowed(long value, String address) {
        return current(value) && address != null && address.equals(candidate) && requestPending &&
                phase == Phase.REQUESTING && !wired && !foreignProjection;
    }
    /** Linearizes the final eligibility check with dispatch to prevent late OEM broadcasts. */
    public synchronized boolean dispatchIfRequestAllowed(long value, String address, long now, RequestAction action) {
        if (action == null || now >= inspectionDeadline || !requestAllowed(value, address)) return false;
        action.send();
        return true;
    }
    public synchronized long generation() { return generation; }
    public synchronized Phase phase() { return phase; }
    public synchronized String candidate() { return candidate; }

    private static String resultName(Result value) {
        if (value == null) return "invocation";
        switch (value) {
            case SERVICE_UNAVAILABLE: return "service-unavailable";
            case METHOD_UNAVAILABLE: return "method-unavailable";
            case SECURITY: return "security";
            default: return "invocation";
        }
    }

    private static String requestName(RequestResult value) {
        if (value == null) return "invocation";
        switch (value) {
            case OEM_ACTION_SENT: return "oem-action-sent";
            case PROFILE_UNAVAILABLE: return "profile-unavailable";
            case PROFILE_MISMATCH: return "profile-mismatch";
            case PROFILE_DISABLED: return "profile-disabled";
            case AUTO_CONNECT_DISABLED: return "auto-connect-disabled";
            case CANCELLED: return "cancelled";
            case SERVICE_UNAVAILABLE: return "service-unavailable";
            case METHOD_UNAVAILABLE: return "method-unavailable";
            case SECURITY: return "security";
            default: return "invocation";
        }
    }
}
