import kr.gen5w.wireless.StockProjectionSession;

public final class StockProjectionSessionTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class FakePort implements StockProjectionSession.Port {
        int inspections;
        int bootstraps;
        int requests;
        long generation;
        String address;
        int profileType;
        StockProjectionSession.BootstrapResult bootstrapResult =
                StockProjectionSession.BootstrapResult.OEM_REQUESTED;
        StockProjectionSession.RequestResult requestResult =
                StockProjectionSession.RequestResult.OEM_ACTION_SENT;
        String lastEvent;

        public void inspect(long generation, String address) {
            inspections++;
            this.generation = generation;
            this.address = address;
        }
        public void bootstrap(long generation, String address) {
            bootstraps++;
            this.generation = generation;
            this.address = address;
        }
        public void requestConnect(long generation, String address, int profileType) {
            requests++;
            this.generation = generation;
            this.address = address;
            this.profileType = profileType;
        }
        public void event(String name, String result) { lastEvent = result; }

        void inspect(StockProjectionSession session, long now, int type,
                StockProjectionSession.ProfileState profile,
                boolean active, boolean connecting, boolean otherActive,
                StockProjectionSession.WifiCredentialState credentials, int apState) {
            session.inspected(generation, new StockProjectionSession.Observation(
                    StockProjectionSession.Result.INVOKED, true, type, profile,
                    active, connecting, otherActive, credentials, apState), now);
        }
        void bootstrapComplete(StockProjectionSession session, long now) {
            session.bootstrapped(generation, bootstrapResult, now);
        }
        void requestComplete(StockProjectionSession session, long now) {
            session.requested(generation, requestResult, now);
        }
    }

    private static final class Attempt {
        final FakePort port = new FakePort();
        final StockProjectionSession session = new StockProjectionSession(port);
        long now;
        Attempt() {
            session.candidate("phone-a", now);
            session.tick(now);
        }
        void missingProfile() {
            port.inspect(session, now + 1, 0, StockProjectionSession.ProfileState.MISSING,
                    false, false, false, StockProjectionSession.WifiCredentialState.UNKNOWN, 11);
            now += 1;
        }
        void finishBootstrap() {
            port.bootstrapComplete(session, now + 1);
            now += 1;
        }
        void readyProfile(int type, StockProjectionSession.WifiCredentialState credentials) {
            now += StockProjectionSession.POLL_INTERVAL_MS;
            session.tick(now);
            port.inspect(session, now + 1, type, StockProjectionSession.ProfileState.READY,
                    false, false, false, credentials, 11);
            now += 1;
        }
        void acceptConnect() {
            port.requestComplete(session, now + 1);
            now += 1;
        }
        void startWifiWait(int type, StockProjectionSession.WifiCredentialState credentials) {
            missingProfile();
            finishBootstrap();
            readyProfile(type, credentials);
            acceptConnect();
        }
    }

    private static void missingProfileBootstrapsOncePerGeneration() {
        Attempt a = new Attempt();
        a.missingProfile();
        check(a.port.bootstraps == 1, "missing profile sends one bootstrap");
        check(a.session.phase() == StockProjectionSession.Phase.BOOTSTRAP_REQUESTED,
                "bootstrap request has its own phase");
        a.port.bootstrapComplete(a.session, ++a.now);
        a.session.tick(a.now + 1000);
        a.port.inspect(a.session, a.now + 1001, 0, StockProjectionSession.ProfileState.MISSING,
                false, false, false, StockProjectionSession.WifiCredentialState.UNKNOWN, 11);
        check(a.port.bootstraps == 1, "polling does not repeat bootstrap in one generation");
        check(a.session.phase() == StockProjectionSession.Phase.WAITING_PROFILE,
                "profile may remain missing while the bootstrap deadline is pending");
    }

    private static void profileAppearanceDispatchesOnceForCarPlay() {
        Attempt a = new Attempt();
        a.missingProfile();
        a.finishBootstrap();
        a.readyProfile(1, StockProjectionSession.WifiCredentialState.PRESENT);
        check(a.port.requests == 1 && a.port.profileType == 1,
                "CarPlay profile dispatches one typed OEM request");
        check(a.session.phase() == StockProjectionSession.Phase.CONNECT_REQUESTED,
                "accepted profile advances to OEM request");
        a.acceptConnect();
        a.session.tick(a.now + StockProjectionSession.POLL_INTERVAL_MS);
        a.port.inspect(a.session, a.now + StockProjectionSession.POLL_INTERVAL_MS + 1,
                1, StockProjectionSession.ProfileState.READY, false, false, false,
                StockProjectionSession.WifiCredentialState.PRESENT, 11);
        check(a.port.requests == 1, "repeated CarPlay inspection does not dispatch a second request");
    }

    private static void profileAppearanceDispatchesOnceForAndroidAuto() {
        Attempt a = new Attempt();
        a.missingProfile();
        a.finishBootstrap();
        a.readyProfile(2, StockProjectionSession.WifiCredentialState.PRESENT);
        check(a.port.requests == 1 && a.port.profileType == 2,
                "Android Auto profile dispatches one typed OEM request");
    }

    private static void wifiUnknownIsNotMissing() {
        Attempt a = new Attempt();
        a.startWifiWait(1, StockProjectionSession.WifiCredentialState.UNKNOWN);
        check(a.session.phase() == StockProjectionSession.Phase.WAITING_WIFI,
                "unknown credentials do not fail an accepted OEM request");
        check(!"wifi-credentials-unavailable".equals(a.port.lastEvent),
                "unknown credentials are not diagnosed as missing");

        Attempt missing = new Attempt();
        missing.startWifiWait(1, StockProjectionSession.WifiCredentialState.MISSING);
        check(missing.session.phase() == StockProjectionSession.Phase.WAITING_WIFI,
                "missing credentials observed before request acceptance do not fail early");
        missing.session.tick(missing.now + StockProjectionSession.POLL_INTERVAL_MS);
        missing.port.inspect(missing.session, missing.now + StockProjectionSession.POLL_INTERVAL_MS + 1,
                1, StockProjectionSession.ProfileState.READY, false, false, false,
                StockProjectionSession.WifiCredentialState.MISSING, 11);
        check(missing.session.phase() == StockProjectionSession.Phase.BLOCKED &&
                        "wifi-credentials-unavailable".equals(missing.port.lastEvent),
                "missing credentials after accepted request stop the current generation");
    }

    private static void activeWinsWhenApBroadcastWasMissed() {
        Attempt a = new Attempt();
        a.startWifiWait(1, StockProjectionSession.WifiCredentialState.PRESENT);
        a.session.tick(a.now + StockProjectionSession.POLL_INTERVAL_MS);
        a.port.inspect(a.session, a.now + StockProjectionSession.POLL_INTERVAL_MS + 1, 1,
                StockProjectionSession.ProfileState.READY, true, false, false,
                StockProjectionSession.WifiCredentialState.PRESENT, 11);
        check(a.session.phase() == StockProjectionSession.Phase.ACTIVE,
                "OEM connected state is active while AP state remains disabled");
    }

    private static void bootstrapWifiAndFinalTimeoutsAreDistinct() {
        Attempt bootstrap = new Attempt();
        bootstrap.missingProfile();
        bootstrap.finishBootstrap();
        bootstrap.session.tick(bootstrap.now + StockProjectionSession.PROFILE_BOOTSTRAP_TIMEOUT_MS);
        check(bootstrap.session.phase() == StockProjectionSession.Phase.FAILED &&
                        "profile-bootstrap-timeout".equals(bootstrap.port.lastEvent),
                "profile bootstrap timeout reports its own boundary");

        Attempt wifi = new Attempt();
        wifi.startWifiWait(1, StockProjectionSession.WifiCredentialState.PRESENT);
        wifi.session.tick(wifi.now + StockProjectionSession.WIFI_TIMEOUT_MS + 1);
        check("wifi-ap-timeout".equals(wifi.port.lastEvent),
                "inactive projection reports AP readiness timeout");

        Attempt request = new Attempt();
        request.startWifiWait(1, StockProjectionSession.WifiCredentialState.PRESENT);
        request.session.tick(request.now + StockProjectionSession.POLL_INTERVAL_MS);
        request.port.inspect(request.session, request.now + StockProjectionSession.POLL_INTERVAL_MS + 1,
                1, StockProjectionSession.ProfileState.READY, false, false, false,
                StockProjectionSession.WifiCredentialState.PRESENT,
                StockProjectionSession.WIFI_AP_STATE_ENABLED);
        request.session.tick(request.now + StockProjectionSession.REQUEST_TIMEOUT_MS + 1);
        check("projection-timeout".equals(request.port.lastEvent),
                "final projection timeout is distinct from profile and AP deadlines: " +
                        request.port.lastEvent + "/" + request.session.phase());
    }

    private static void wiredAndStaleCallbacksCancel() {
        Attempt a = new Attempt();
        long oldGeneration = a.port.generation;
        a.missingProfile();
        a.session.environment(true, false, ++a.now);
        check(a.session.phase() == StockProjectionSession.Phase.CANCELLED,
                "wired ownership cancels the pending generation");
        a.session.bootstrapped(oldGeneration, StockProjectionSession.BootstrapResult.OEM_REQUESTED, ++a.now);
        check(a.port.requests == 0 && a.port.bootstraps == 1,
                "late bootstrap callback cannot dispatch a connection");
    }

    private static void restartStartsFromInspectionWithoutPendingState() {
        Attempt a = new Attempt();
        a.missingProfile();
        a.session.lost("phone-a", ++a.now);
        a.session.candidate("phone-a", ++a.now);
        a.session.tick(a.now);
        check(a.session.phase() == StockProjectionSession.Phase.INSPECTING &&
                        a.port.inspections == 2 && a.port.bootstraps == 1,
                "new Bluetooth generation restarts at inspection");
        check(!a.session.hasPendingOemOwnership(), "new generation has no inherited pending owner");
        a.port.inspect(a.session, a.now + 1, 0, StockProjectionSession.ProfileState.MISSING,
                false, false, false, StockProjectionSession.WifiCredentialState.UNKNOWN, 11);
        check(a.port.bootstraps == 2, "new generation gets its own single bootstrap");
    }

    public static void main(String[] args) {
        missingProfileBootstrapsOncePerGeneration();
        profileAppearanceDispatchesOnceForCarPlay();
        profileAppearanceDispatchesOnceForAndroidAuto();
        wifiUnknownIsNotMissing();
        activeWinsWhenApBroadcastWasMissed();
        bootstrapWifiAndFinalTimeoutsAreDistinct();
        wiredAndStaleCallbacksCancel();
        restartStartsFromInspectionWithoutPendingState();
        System.out.println("PASS StockProjectionSessionTest");
    }
}
