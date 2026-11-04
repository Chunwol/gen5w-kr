import kr.gen5w.wireless.StockProjectionSession;
import kr.gen5w.wireless.PhoneProjectionAccess;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

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

    private static void repeatedConnectingObservationRestoresWaitingPhase() {
        Attempt a = new Attempt();
        a.port.inspect(a.session, 1, 1, StockProjectionSession.ProfileState.READY,
                false, true, false, StockProjectionSession.WifiCredentialState.PRESENT, 11);
        check(a.session.phase() == StockProjectionSession.Phase.WAITING_WIFI,
                "first OEM connecting observation enters Wi-Fi wait");
        a.session.tick(1001);
        a.port.inspect(a.session, 1002, 1, StockProjectionSession.ProfileState.READY,
                false, true, false, StockProjectionSession.WifiCredentialState.PRESENT, 11);
        check(a.session.phase() == StockProjectionSession.Phase.WAITING_WIFI,
                "repeated connecting observation restores the waiting phase after inspection");
        a.session.tick(StockProjectionSession.WIFI_TIMEOUT_MS + 2);
        check("wifi-ap-timeout".equals(a.port.lastEvent),
                "repeated connecting observations do not reset the original Wi-Fi deadline");
    }

    private static void oemConnectingRetainsOwnershipWithoutAcceptedRequest() {
        Attempt a = new Attempt();
        a.port.inspect(a.session, 1, 1, StockProjectionSession.ProfileState.READY,
                false, true, false, StockProjectionSession.WifiCredentialState.MISSING, 11);
        check(a.session.hasPendingOemOwnership(),
                "OEM-initiated connection retains candidate ownership without a controller request");
        a.session.tick(1001);
        a.port.inspect(a.session, 1002, 1, StockProjectionSession.ProfileState.READY,
                false, true, false, StockProjectionSession.WifiCredentialState.MISSING, 11);
        check(a.session.phase() == StockProjectionSession.Phase.WAITING_WIFI &&
                        a.session.hasPendingOemOwnership(),
                "ongoing OEM connection remains pending across inspection polls");
        check(!"wifi-credentials-unavailable".equals(a.port.lastEvent),
                "OEM connecting state alone does not establish an accepted controller request");
    }

    private static void oemConnectingDoesNotDiagnoseMissingCredentials() {
        Attempt a = new Attempt();
        a.port.inspect(a.session, 1, 1, StockProjectionSession.ProfileState.READY,
                false, true, false, StockProjectionSession.WifiCredentialState.MISSING, 11);
        a.session.tick(1001);
        a.port.inspect(a.session, 1002, 1, StockProjectionSession.ProfileState.READY,
                false, true, false, StockProjectionSession.WifiCredentialState.MISSING, 11);
        check(!"wifi-credentials-unavailable".equals(a.port.lastEvent),
                "OEM connecting alone cannot report missing credentials without accepted request");
    }

    private static void lateBootstrapInspectionCannotDispatchConnect() {
        Attempt a = new Attempt();
        a.missingProfile();
        a.finishBootstrap();
        long deadline = 1 + StockProjectionSession.PROFILE_BOOTSTRAP_TIMEOUT_MS;
        a.session.tick(deadline - 100);
        a.port.inspect(a.session, deadline + 1, 1, StockProjectionSession.ProfileState.READY,
                false, false, false, StockProjectionSession.WifiCredentialState.PRESENT, 11);
        check(a.session.phase() == StockProjectionSession.Phase.FAILED && a.port.requests == 0 &&
                        "profile-bootstrap-timeout".equals(a.port.lastEvent),
                "inspection completing after bootstrap deadline cannot dispatch connection");
    }

    private static void bootstrapDispatchRequiresCurrentEligibleGeneration() {
        Attempt current = new Attempt();
        current.missingProfile();
        check(current.session.claimBootstrapBroadcast(current.port.generation, "phone-a", 2),
                "current bootstrap executes");
        check(!current.session.claimBootstrapBroadcast(current.port.generation, "phone-a", 2),
                "duplicate bootstrap dispatch is denied before its callback");
        check(current.session.claimBootstrapInvocation(current.port.generation, "phone-a", 2),
                "second bootstrap operation gets its own admission");
        check(!current.session.claimBootstrapInvocation(current.port.generation, "phone-a", 2),
                "second bootstrap admission cannot be reused");
        current.finishBootstrap();
        check(!current.session.claimBootstrapBroadcast(current.port.generation, "phone-a", 3),
                "completed bootstrap cannot dispatch twice");
        Attempt stale = new Attempt();
        stale.missingProfile();
        long old = stale.port.generation;
        stale.session.lost("phone-a", 2);
        check(!stale.session.claimBootstrapBroadcast(old, "phone-a", 3), "stale bootstrap denied");
        Attempt wired = new Attempt();
        wired.missingProfile();
        wired.session.environment(true, false, 2);
        check(!wired.session.claimBootstrapBroadcast(wired.port.generation, "phone-a", 3),
                "wired bootstrap denied");
        Attempt foreign = new Attempt();
        foreign.missingProfile();
        foreign.session.environment(false, true, 2);
        check(!foreign.session.claimBootstrapBroadcast(foreign.port.generation, "phone-a", 3),
                "foreign owner bootstrap denied");
        Attempt expired = new Attempt();
        expired.missingProfile();
        check(!expired.session.claimBootstrapBroadcast(expired.port.generation, "phone-a", 5001),
                "expired bootstrap operation denied at deadline");
        check(!expired.session.claimBootstrapBroadcast(expired.port.generation, "phone-b", 2),
                "wrong candidate bootstrap denied");
    }

    private static void connectAdmissionIsConsumedOnce() {
        Attempt a = new Attempt();
        a.readyProfile(1, StockProjectionSession.WifiCredentialState.PRESENT);
        check(a.session.claimRequest(a.port.generation, "phone-a", a.now + 1),
                "current ready profile claims the broadcast permit");
        check(!a.session.claimRequest(a.port.generation, "phone-a", a.now + 1),
                "connect permit cannot be reused before its callback");
    }

    private static void await(CountDownLatch latch) {
        try { check(latch.await(2, TimeUnit.SECONDS), "worker reached expected boundary"); }
        catch (InterruptedException e) { throw new AssertionError(e); }
    }

    private static void blockedExternalOperationDoesNotBlockLifecycle() {
        for (final boolean bootstrap : new boolean[] {true, false}) {
            for (int operation = 0; operation < 4; operation++) {
                final Attempt a = new Attempt();
                if (bootstrap) a.missingProfile();
                else a.readyProfile(1, StockProjectionSession.WifiCredentialState.PRESENT);
                final long generation = a.port.generation;
                final CountDownLatch entered = new CountDownLatch(1);
                final CountDownLatch release = new CountDownLatch(1);
                final CountDownLatch controlDone = new CountDownLatch(1);
                final CountDownLatch workerDone = new CountDownLatch(1);
                final int control = operation;
                Thread worker = new Thread(new Runnable() {
                    public void run() {
                        boolean admitted = bootstrap
                                ? a.session.claimBootstrapBroadcast(generation, "phone-a", a.now + 1)
                                : a.session.claimRequest(generation, "phone-a", a.now + 1);
                        if (admitted) { entered.countDown(); await(release); }
                        if (bootstrap) a.session.bootstrapped(generation, StockProjectionSession.BootstrapResult.OEM_REQUESTED, a.now + 6001);
                        else a.session.requested(generation, StockProjectionSession.RequestResult.OEM_ACTION_SENT, a.now + 6001);
                        workerDone.countDown();
                    }
                });
                worker.setDaemon(true);
                worker.start();
                await(entered);
                Thread lifecycle = new Thread(new Runnable() {
                    public void run() {
                        if (control == 0) a.session.lost("phone-a", a.now + 2);
                        else if (control == 1) a.session.environment(true, false, a.now + 2);
                        else if (control == 2) a.session.shutdown();
                        else a.session.tick(a.now + 6000);
                        controlDone.countDown();
                    }
                });
                lifecycle.setDaemon(true);
                lifecycle.start();
                boolean responsive;
                try { responsive = controlDone.await(500, TimeUnit.MILLISECONDS); }
                catch (InterruptedException e) { throw new AssertionError(e); }
                finally { release.countDown(); }
                await(controlDone);
                await(workerDone);
                check(responsive, (bootstrap ? "bootstrap" : "connect") +
                        " blocked external operation must not delay lifecycle control " + control);
                check(a.session.phase() == (control == 3 ? StockProjectionSession.Phase.FAILED :
                                StockProjectionSession.Phase.CANCELLED),
                        "late external completion cannot undo lifecycle control " + control);
            }
        }
    }

    public static final class BootstrapManager {
        volatile int calls;
        CountDownLatch entered;
        CountDownLatch release;
        public void requestConnectSPP(String address) {
            calls++;
            if (entered != null) { entered.countDown(); await(release); }
        }
    }

    private static void blockedBinderDoesNotBlockShutdownOrReviveSession() {
        final Attempt a = new Attempt();
        a.missingProfile();
        final long generation = a.port.generation;
        final BootstrapManager manager = new BootstrapManager();
        manager.entered = new CountDownLatch(1);
        manager.release = new CountDownLatch(1);
        final CountDownLatch completed = new CountDownLatch(1);
        Thread worker = new Thread(new Runnable() {
            public void run() {
                StockProjectionSession.BootstrapResult result = PhoneProjectionAccess.bootstrap(
                        new PhoneProjectionAccess.ServiceProvider() {
                            public Object get(String name) { return manager; }
                        }, new Object(), new PhoneProjectionAccess.ActionSender() {
                            public boolean send(String action, String packageName, String extra, String address) {
                                return a.session.claimBootstrapBroadcast(generation, address, 2);
                            }
                        }, "phone-a", new PhoneProjectionAccess.BootstrapAdmission() {
                            public boolean claim() { return a.session.claimBootstrapInvocation(generation, "phone-a", 3); }
                        });
                a.session.bootstrapped(generation, result, 5);
                completed.countDown();
            }
        });
        worker.setDaemon(true);
        worker.start();
        await(manager.entered);
        final CountDownLatch stopped = new CountDownLatch(1);
        Thread shutdown = new Thread(new Runnable() {
            public void run() { a.session.shutdown(); stopped.countDown(); }
        });
        shutdown.setDaemon(true);
        shutdown.start();
        boolean responsive;
        try { responsive = stopped.await(500, TimeUnit.MILLISECONDS); }
        catch (InterruptedException e) { throw new AssertionError(e); }
        finally { manager.release.countDown(); }
        await(stopped);
        await(completed);
        check(responsive && manager.calls == 1 && a.session.phase() == StockProjectionSession.Phase.CANCELLED &&
                a.session.candidate() == null && a.port.requests == 0,
                "blocked Binder permits shutdown and its stale completion cannot revive the session");
    }

    private static void cancellationBetweenBootstrapOperationsRejectsContinuation() {
        for (int operation = 0; operation < 5; operation++) {
            final Attempt a = new Attempt();
            a.missingProfile();
            final long generation = a.port.generation;
            final BootstrapManager manager = new BootstrapManager();
            final CountDownLatch broadcast = new CountDownLatch(1);
            final CountDownLatch release = new CountDownLatch(1);
            final CountDownLatch completed = new CountDownLatch(1);
            final StockProjectionSession.BootstrapResult[] result = {null};
            Thread worker = new Thread(new Runnable() {
                public void run() {
                    result[0] = PhoneProjectionAccess.bootstrap(new PhoneProjectionAccess.ServiceProvider() {
                        public Object get(String name) { return manager; }
                    }, new Object(), new PhoneProjectionAccess.ActionSender() {
                        public boolean send(String action, String packageName, String extra, String address) {
                            if (!a.session.claimBootstrapBroadcast(generation, address, 2)) return false;
                            broadcast.countDown();
                            await(release);
                            return true;
                        }
                    }, "phone-a", new PhoneProjectionAccess.BootstrapAdmission() {
                        public boolean claim() { return a.session.claimBootstrapInvocation(generation, "phone-a", 3); }
                    });
                    completed.countDown();
                }
            });
            worker.setDaemon(true);
            worker.start();
            await(broadcast);
            if (operation == 0) a.session.lost("phone-a", 3);
            else if (operation == 1) a.session.environment(true, false, 3);
            else if (operation == 2) a.session.environment(false, true, 3);
            else if (operation == 3) a.session.shutdown();
            else a.session.tick(6000);
            StockProjectionSession.Phase cancelled = a.session.phase();
            release.countDown();
            await(completed);
            check(result[0] == StockProjectionSession.BootstrapResult.CANCELLED && manager.calls == 0,
                    "cancellation after admitted broadcast rejects later Binder operation " + operation);
            a.session.bootstrapped(generation, StockProjectionSession.BootstrapResult.OEM_REQUESTED, 6001);
            check(a.session.phase() == cancelled && a.port.requests == 0,
                    "late bootstrap success cannot revive cancelled/expired attempt " + operation);
        }
    }

    public static void main(String[] args) {
        connectAdmissionIsConsumedOnce();
        blockedBinderDoesNotBlockShutdownOrReviveSession();
        cancellationBetweenBootstrapOperationsRejectsContinuation();
        blockedExternalOperationDoesNotBlockLifecycle();
        bootstrapDispatchRequiresCurrentEligibleGeneration();
        missingProfileBootstrapsOncePerGeneration();
        profileAppearanceDispatchesOnceForCarPlay();
        profileAppearanceDispatchesOnceForAndroidAuto();
        wifiUnknownIsNotMissing();
        activeWinsWhenApBroadcastWasMissed();
        bootstrapWifiAndFinalTimeoutsAreDistinct();
        wiredAndStaleCallbacksCancel();
        restartStartsFromInspectionWithoutPendingState();
        repeatedConnectingObservationRestoresWaitingPhase();
        oemConnectingRetainsOwnershipWithoutAcceptedRequest();
        oemConnectingDoesNotDiagnoseMissingCredentials();
        lateBootstrapInspectionCannotDispatchConnect();
        System.out.println("PASS StockProjectionSessionTest");
    }
}
