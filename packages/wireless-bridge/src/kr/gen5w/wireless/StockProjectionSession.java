package kr.gen5w.wireless;

/** Owns one generation-checked OEM projection bootstrap and connection attempt. */
public final class StockProjectionSession {
    public static final long PROFILE_BOOTSTRAP_TIMEOUT_MS = 60000L;
    public static final long WIFI_TIMEOUT_MS = 30000L;
    public static final long REQUEST_TIMEOUT_MS = 20000L;
    public static final long POLL_INTERVAL_MS = 1000L;
    public static final int WIFI_AP_STATE_ENABLED = 13;

    private static final long INSPECTION_TIMEOUT_MS = 5000L;

    public enum Phase {
        IDLE, INSPECTING, BOOTSTRAP_REQUESTED, WAITING_PROFILE, CONNECT_REQUESTED,
        WAITING_WIFI, ACTIVE, BLOCKED, FAILED, CANCELLED
    }
    public enum Result { INVOKED, SERVICE_UNAVAILABLE, METHOD_UNAVAILABLE, SECURITY, INVOCATION }
    public enum ProfileState { UNKNOWN, MISSING, READY, DISABLED, AUTO_CONNECT_DISABLED, UNSUPPORTED }
    public enum WifiCredentialState { UNKNOWN, MISSING, PRESENT }
    public enum BootstrapResult { OEM_REQUESTED, CANCELLED, SERVICE_UNAVAILABLE, METHOD_UNAVAILABLE, SECURITY, INVOCATION }
    public enum RequestResult {
        OEM_ACTION_SENT, PROFILE_UNAVAILABLE, PROFILE_MISMATCH, PROFILE_DISABLED,
        AUTO_CONNECT_DISABLED, CANCELLED, SERVICE_UNAVAILABLE, METHOD_UNAVAILABLE, SECURITY, INVOCATION
    }

    public interface Port {
        void inspect(long generation, String address);
        /** Legacy adapter; implementations may override the typed overload instead. */
        default void requestConnect(long generation, String address) {}
        default void bootstrap(long generation, String address) {}
        default void requestConnect(long generation, String address, int profileType) {
            requestConnect(generation, address);
        }
        void event(String name, String result);
    }

    public static final class Observation {
        public final Result result;
        public final boolean serviceAvailable;
        public final int profileType;
        public final ProfileState profileState;
        public final boolean active;
        public final boolean connecting;
        public final boolean otherActive;
        public final WifiCredentialState credentials;
        public final int apState;

        // Compatibility fields consumed by existing inspection callers during adapter migration.
        public final boolean projectionActiveForCandidate;
        public final boolean projectionConnectingForCandidate;
        public final boolean otherProjectionActive;

        public Observation(Result result, boolean serviceAvailable, int profileType,
                ProfileState profileState, boolean active, boolean connecting,
                boolean otherActive, WifiCredentialState credentials, int apState) {
            this.result = result == null ? Result.INVOCATION : result;
            this.serviceAvailable = serviceAvailable;
            this.profileType = profileType;
            this.profileState = profileState == null ? ProfileState.UNKNOWN : profileState;
            this.active = active;
            this.connecting = connecting;
            this.otherActive = otherActive;
            this.credentials = credentials == null ? WifiCredentialState.UNKNOWN : credentials;
            this.apState = apState;
            this.projectionActiveForCandidate = active;
            this.projectionConnectingForCandidate = connecting;
            this.otherProjectionActive = otherActive;
        }

        /** Compatibility constructor for the pre-bootstrap adapter. */
        public Observation(Result result, boolean serviceAvailable,
                boolean projectionActiveForCandidate, boolean otherProjectionActive) {
            this(result, serviceAvailable, 1, ProfileState.READY,
                    projectionActiveForCandidate, false, otherProjectionActive,
                    WifiCredentialState.UNKNOWN, 11);
        }

        /** Compatibility constructor for the pre-bootstrap adapter. */
        public Observation(Result result, boolean serviceAvailable,
                boolean projectionActiveForCandidate, boolean projectionConnectingForCandidate,
                boolean otherProjectionActive) {
            this(result, serviceAvailable, 1, ProfileState.READY,
                    projectionActiveForCandidate, projectionConnectingForCandidate,
                    otherProjectionActive, WifiCredentialState.UNKNOWN, 11);
        }
    }

    private final Port port;
    private long generation;
    private String candidate;
    private Phase phase = Phase.IDLE;
    private Phase inspectionReturnPhase = Phase.IDLE;
    private boolean wired;
    private boolean foreignProjection;
    private boolean inspectionPending;
    private boolean bootstrapIssued;
    private boolean bootstrapPending;
    private boolean bootstrapDispatched;
    private boolean bootstrapInvocationClaimed;
    private boolean requestClaimed;
    private boolean connectIssued;
    private boolean connectAccepted;
    private boolean observedConnecting;
    private boolean requestPending;
    private int profileType;
    private WifiCredentialState credentials = WifiCredentialState.UNKNOWN;
    private int apState;
    private long inspectionDeadline;
    private long bootstrapDeadline;
    private long bootstrapExecutionDeadline;
    private long wifiDeadline;
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
        resetAttempt();
        phase = Phase.IDLE;
        nextPoll = now;
        port.event("candidate", "ready");
    }

    public synchronized void lost(String address, long now) {
        if (candidate == null || (address != null && !candidate.equals(address))) return;
        generation++;
        candidate = null;
        resetAttempt();
        phase = Phase.CANCELLED;
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
        if (!wasBlocked || inspectionPending || bootstrapPending || requestPending || phase != Phase.IDLE) {
            generation++;
            resetAttempt();
            phase = Phase.CANCELLED;
            nextPoll = now;
            port.event("cancel", wired ? "wired" : "foreign");
        }
    }

    /** Apply a freshly observed ownership guard only to the generation that requested it. */
    public synchronized boolean refreshOwnership(long value, boolean wired, boolean foreign, long now) {
        if (!current(value)) return false;
        environment(wired, foreign, now);
        return current(value) && !wired && !foreign;
    }

    public synchronized void tick(long now) {
        if (candidate == null || wired || foreignProjection || terminal()) return;
        if (bootstrapPending) {
            if (now >= bootstrapExecutionDeadline) {
                bootstrapPending = false;
                fail("timeout");
            }
            return;
        }
        boolean waitingForBootstrapProfile = phase == Phase.WAITING_PROFILE ||
                phase == Phase.BOOTSTRAP_REQUESTED ||
                (phase == Phase.INSPECTING && (inspectionReturnPhase == Phase.WAITING_PROFILE ||
                        inspectionReturnPhase == Phase.BOOTSTRAP_REQUESTED));
        if (bootstrapIssued && waitingForBootstrapProfile && bootstrapDeadline > 0 &&
                now >= bootstrapDeadline) {
            inspectionPending = false;
            fail("profile-bootstrap-timeout");
            return;
        }
        if (inspectionPending && now >= inspectionDeadline) {
            inspectionPending = false;
            fail("timeout");
            return;
        }
        if (phase == Phase.BOOTSTRAP_REQUESTED || phase == Phase.WAITING_PROFILE) {
            if (now >= bootstrapDeadline) {
                fail("profile-bootstrap-timeout");
                return;
            }
            if (!inspectionPending && now >= nextPoll) inspect(now);
            return;
        }
        if (requestPending && now >= inspectionDeadline) {
            requestPending = false;
            fail("request-timeout");
            return;
        }
        if (phase == Phase.WAITING_WIFI) {
            if (apState != WIFI_AP_STATE_ENABLED && now >= wifiDeadline) {
                fail("wifi-ap-timeout");
                return;
            }
            if (apState == WIFI_AP_STATE_ENABLED && now >= requestDeadline) {
                fail("projection-timeout");
                return;
            }
            if (!inspectionPending && now >= nextPoll) inspect(now);
            return;
        }
        if (phase == Phase.IDLE && now >= nextPoll) inspect(now);
    }

    private void inspect(long now) {
        if (candidate == null || inspectionPending || wired || foreignProjection) return;
        inspectionPending = true;
        inspectionDeadline = now + INSPECTION_TIMEOUT_MS;
        inspectionReturnPhase = phase;
        phase = Phase.INSPECTING;
        port.inspect(generation, candidate);
    }

    public synchronized void inspected(long callbackGeneration, Observation observation, long now) {
        if (!current(callbackGeneration) || !inspectionPending) return;
        inspectionPending = false;
        Phase previousPhase = inspectionReturnPhase;
        inspectionReturnPhase = Phase.IDLE;
        if (bootstrapIssued && (previousPhase == Phase.WAITING_PROFILE ||
                previousPhase == Phase.BOOTSTRAP_REQUESTED) && bootstrapDeadline > 0 &&
                now >= bootstrapDeadline) {
            fail("profile-bootstrap-timeout");
            return;
        }
        if (observation == null || observation.result != Result.INVOKED || !observation.serviceAvailable) {
            fail("unavailable");
            port.event("service", resultName(observation == null ? Result.INVOCATION : observation.result));
            return;
        }
        credentials = observation.credentials;
        apState = observation.apState;
        if (observation.active) {
            phase = Phase.ACTIVE;
            port.event("result", "projection-active");
            return;
        }
        if (observation.otherActive) {
            phase = Phase.BLOCKED;
            port.event("result", "foreign-active");
            return;
        }
        if (connectAccepted && previousPhase == Phase.WAITING_WIFI &&
                !observation.connecting && credentials == WifiCredentialState.MISSING) {
            phase = Phase.BLOCKED;
            port.event("result", "wifi-credentials-unavailable");
            return;
        }
        if (observation.profileState == ProfileState.DISABLED ||
                observation.profileState == ProfileState.AUTO_CONNECT_DISABLED ||
                observation.profileState == ProfileState.UNSUPPORTED) {
            phase = Phase.BLOCKED;
            port.event("result", observation.profileState == ProfileState.AUTO_CONNECT_DISABLED ?
                    "auto-connect-disabled" : "profile-disabled");
            return;
        }
        if (observation.profileState == ProfileState.MISSING) {
            if (!bootstrapIssued) {
                bootstrapIssued = true;
                bootstrapPending = true;
                phase = Phase.BOOTSTRAP_REQUESTED;
                bootstrapExecutionDeadline = now + INSPECTION_TIMEOUT_MS;
                bootstrapDeadline = now + PROFILE_BOOTSTRAP_TIMEOUT_MS;
                port.bootstrap(generation, candidate);
            } else {
                phase = Phase.WAITING_PROFILE;
                nextPoll = now + POLL_INTERVAL_MS;
            }
            return;
        }
        if (observation.profileState == ProfileState.READY) {
            if (observation.profileType != 1 && observation.profileType != 2) {
                phase = Phase.BLOCKED;
                port.event("result", "profile-mismatch");
                return;
            }
            profileType = observation.profileType;
            if (observation.connecting) {
                observedConnecting = true;
                if (previousPhase != Phase.WAITING_WIFI) {
                    requestDeadline = now + REQUEST_TIMEOUT_MS;
                    wifiDeadline = now + WIFI_TIMEOUT_MS;
                }
                phase = Phase.WAITING_WIFI;
                nextPoll = now + POLL_INTERVAL_MS;
                port.event("progress", "connecting");
                return;
            }
            observedConnecting = false;
            bootstrapDeadline = 0;
            if (!connectIssued) {
                connectIssued = true;
                requestPending = true;
                phase = Phase.CONNECT_REQUESTED;
                inspectionDeadline = now + INSPECTION_TIMEOUT_MS;
                port.requestConnect(generation, candidate, profileType);
            } else if (previousPhase == Phase.WAITING_WIFI) {
                phase = Phase.WAITING_WIFI;
                nextPoll = now + POLL_INTERVAL_MS;
            }
        } else if (previousPhase == Phase.WAITING_PROFILE || previousPhase == Phase.BOOTSTRAP_REQUESTED) {
            phase = Phase.WAITING_PROFILE;
            nextPoll = now + POLL_INTERVAL_MS;
        } else if (previousPhase == Phase.WAITING_WIFI) {
            phase = Phase.WAITING_WIFI;
            nextPoll = now + POLL_INTERVAL_MS;
        } else {
            phase = Phase.IDLE;
            nextPoll = now + POLL_INTERVAL_MS;
        }
    }

    public synchronized void bootstrapped(long callbackGeneration, BootstrapResult result, long now) {
        if (!current(callbackGeneration) || !bootstrapPending || phase != Phase.BOOTSTRAP_REQUESTED) return;
        bootstrapPending = false;
        if (now >= bootstrapExecutionDeadline) {
            fail("timeout");
            return;
        }
        if (result != BootstrapResult.OEM_REQUESTED) {
            phase = result == BootstrapResult.CANCELLED ? Phase.CANCELLED : Phase.FAILED;
            port.event("bootstrap", bootstrapName(result));
            if (result != BootstrapResult.CANCELLED) port.event("result", "unavailable");
            return;
        }
        phase = Phase.WAITING_PROFILE;
        nextPoll = now + POLL_INTERVAL_MS;
        port.event("bootstrap", "oem-requested");
    }

    public synchronized void requested(long callbackGeneration, RequestResult result, long now) {
        if (!current(callbackGeneration) || !requestPending || phase != Phase.CONNECT_REQUESTED) return;
        requestPending = false;
        inspectionReturnPhase = Phase.IDLE;
        if (result != RequestResult.OEM_ACTION_SENT) {
            if (result == RequestResult.PROFILE_UNAVAILABLE || result == RequestResult.PROFILE_MISMATCH ||
                    result == RequestResult.PROFILE_DISABLED || result == RequestResult.AUTO_CONNECT_DISABLED) {
                phase = Phase.BLOCKED;
                port.event("request", requestName(result));
            } else if (result == RequestResult.CANCELLED) {
                phase = Phase.CANCELLED;
                port.event("cancel", "stale-request");
            } else {
                phase = Phase.FAILED;
                port.event("request", requestName(result));
                port.event("result", "unavailable");
            }
            return;
        }
        connectAccepted = true;
        phase = Phase.WAITING_WIFI;
        requestDeadline = now + REQUEST_TIMEOUT_MS;
        wifiDeadline = now + WIFI_TIMEOUT_MS;
        nextPoll = now + POLL_INTERVAL_MS;
        port.event("request", "oem-action-sent");
    }

    public synchronized void shutdown() {
        generation++;
        candidate = null;
        resetAttempt();
        phase = Phase.CANCELLED;
        port.event("cancel", "shutdown");
    }

    private void resetAttempt() {
        inspectionPending = false;
        bootstrapIssued = false;
        bootstrapPending = false;
        connectIssued = false;
        bootstrapDispatched = false;
        bootstrapInvocationClaimed = false;
        requestClaimed = false;
        connectAccepted = false;
        observedConnecting = false;
        requestPending = false;
        profileType = 0;
        credentials = WifiCredentialState.UNKNOWN;
        apState = 0;
        inspectionDeadline = bootstrapDeadline = bootstrapExecutionDeadline = wifiDeadline = requestDeadline = 0;
    }

    private boolean terminal() {
        return phase == Phase.ACTIVE || phase == Phase.BLOCKED || phase == Phase.FAILED || phase == Phase.CANCELLED;
    }
    private void fail(String result) { phase = Phase.FAILED; port.event("result", result); }

    public synchronized boolean current(long value) { return candidate != null && generation == value; }
    public synchronized boolean requestAllowed(long value, String address) {
        return current(value) && address != null && address.equals(candidate) && requestPending &&
                phase == Phase.CONNECT_REQUESTED && !wired && !foreignProjection;
    }
    /** Consume one broadcast admission; callers perform external work after this returns. */
    public synchronized boolean claimRequest(long value, String address, long now) {
        if (requestClaimed || now >= inspectionDeadline || !requestAllowed(value, address)) return false;
        requestClaimed = true;
        return true;
    }
    private boolean bootstrapAllowed(long value, String address, long now) {
        return now < bootstrapExecutionDeadline && current(value) && address != null && address.equals(candidate) &&
                bootstrapPending && phase == Phase.BOOTSTRAP_REQUESTED && !wired && !foreignProjection;
    }
    public synchronized boolean claimBootstrapBroadcast(long value, String address, long now) {
        if (bootstrapDispatched || !bootstrapAllowed(value, address, now)) return false;
        bootstrapDispatched = true;
        return true;
    }
    /** Recheck cancellation after the bootstrap broadcast, immediately before the Binder operation. */
    public synchronized boolean claimBootstrapInvocation(long value, String address, long now) {
        if (!bootstrapDispatched || bootstrapInvocationClaimed || !bootstrapAllowed(value, address, now)) return false;
        bootstrapInvocationClaimed = true;
        return true;
    }
    public synchronized long generation() { return generation; }
    public synchronized Phase phase() { return phase; }
    public synchronized String candidate() { return candidate; }
    public synchronized boolean hasPendingOemOwnership() {
        return (bootstrapIssued || connectIssued || observedConnecting) && !terminal() && candidate != null;
    }

    /** Keep stable diagnostic labels while redacting arbitrary identifiers and text. */
    public static String safeDiagnosticToken(String value) {
        if ("candidate".equals(value) || "cancel".equals(value) || "service".equals(value) ||
                "state".equals(value) || "bootstrap".equals(value) || "request".equals(value) ||
                "result".equals(value) || "progress".equals(value)) return value;
        if ("ready".equals(value) || "acl-lost".equals(value) || "wired".equals(value) ||
                "foreign".equals(value) || "shutdown".equals(value) || "invoked".equals(value) ||
                "service-unavailable".equals(value) || "method-unavailable".equals(value) ||
                "security".equals(value) || "invocation".equals(value) || "timeout".equals(value) ||
                "profile-bootstrap-timeout".equals(value) || "wifi-ap-timeout".equals(value) ||
                "projection-timeout".equals(value) || "request-timeout".equals(value) ||
                "projection-active".equals(value) || "foreign-active".equals(value) ||
                "connecting".equals(value) || "stale-request".equals(value) ||
                "unavailable".equals(value) || "profile-unavailable".equals(value) ||
                "profile-mismatch".equals(value) || "profile-disabled".equals(value) ||
                "auto-connect-disabled".equals(value) || "cancelled".equals(value) ||
                "wifi-credentials-unavailable".equals(value) || "oem-requested".equals(value) ||
                "oem-action-sent".equals(value)) return value;
        return "other";
    }

    private static String resultName(Result value) {
        if (value == null) return "invocation";
        switch (value) {
            case SERVICE_UNAVAILABLE: return "service-unavailable";
            case METHOD_UNAVAILABLE: return "method-unavailable";
            case SECURITY: return "security";
            default: return "invocation";
        }
    }
    private static String bootstrapName(BootstrapResult value) {
        if (value == null) return "invocation";
        switch (value) {
            case OEM_REQUESTED: return "oem-requested";
            case CANCELLED: return "cancelled";
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
