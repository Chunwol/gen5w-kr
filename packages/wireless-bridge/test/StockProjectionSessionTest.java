import kr.gen5w.wireless.StockProjectionSession;

public final class StockProjectionSessionTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class FakePort implements StockProjectionSession.Port {
        int inspections;
        int requests;
        String requestedAddress;
        long inspectedGeneration;
        long requestedGeneration;
        StockProjectionSession.Observation lastObservation;
        StockProjectionSession.RequestResult requestResult;
        public void inspect(long generation, String address) {
            inspections++;
            inspectedGeneration = generation;
        }
        public void requestConnect(long generation, String address) {
            requests++;
            requestedGeneration = generation;
            requestedAddress = address;
        }
        public void event(String name, String result) {}
        void reply(boolean ignoredAutoSppGate, boolean active, boolean other) {
            lastObservation = new StockProjectionSession.Observation(
                    StockProjectionSession.Result.INVOKED, true, active, other);
        }
        void replyConnecting() {
            lastObservation = new StockProjectionSession.Observation(
                    StockProjectionSession.Result.INVOKED, true, false, true, false);
        }
        void inspectionComplete(StockProjectionSession session, long now) {
            session.inspected(inspectedGeneration, lastObservation, now);
        }
        void requestComplete(StockProjectionSession session, long now) {
            session.requested(requestedGeneration, requestResult, now);
        }
    }

    public static void main(String[] args) {
        FakePort port = new FakePort();
        StockProjectionSession session = new StockProjectionSession(port);
        session.candidate("phone-a", 0);
        session.tick(0);
        long first = port.inspectedGeneration;
        port.reply(true, false, false);
        port.inspectionComplete(session, 1);
        check(port.requests == 1, "eligible device issues one OEM request");
        check("phone-a".equals(port.requestedAddress), "request targets selected candidate");
        check(session.requestAllowed(port.requestedGeneration, "phone-a"),
                "only the live request generation may emit the OEM action");
        port.requestResult = StockProjectionSession.RequestResult.OEM_ACTION_SENT;
        port.requestComplete(session, 2);
        session.tick(1002);
        port.reply(true, false, false);
        port.inspectionComplete(session, 1003);
        check(port.requests == 1, "normal return never triggers a repeated request");
        check(session.phase() == StockProjectionSession.Phase.REQUESTED,
                "request return is not projection success");

        session.tick(2003);
        port.reply(true, true, false);
        port.inspectionComplete(session, 2004);
        check(session.phase() == StockProjectionSession.Phase.ACTIVE,
                "only OEM connected state marks projection active");

        FakePort blockedPort = new FakePort();
        StockProjectionSession blocked = new StockProjectionSession(blockedPort);
        blocked.candidate("phone-b", 0);
        blocked.tick(0);
        blockedPort.reply(false, false, false);
        blockedPort.inspectionComplete(blocked, 1);
        check(blockedPort.requests == 1,
                "auto-SPP gate does not block the distinct saved-profile OEM action");

        FakePort racedGatePort = new FakePort();
        StockProjectionSession racedGate = new StockProjectionSession(racedGatePort);
        racedGate.candidate("phone-gate-race", 0);
        racedGate.tick(0);
        racedGatePort.reply(true, false, false);
        racedGatePort.inspectionComplete(racedGate, 1);
        racedGatePort.requestResult = StockProjectionSession.RequestResult.PROFILE_DISABLED;
        racedGatePort.requestComplete(racedGate, 2);
        check(racedGate.phase() == StockProjectionSession.Phase.BLOCKED,
                "disabled saved profile blocks the current attempt");

        FakePort stalePort = new FakePort();
        StockProjectionSession stale = new StockProjectionSession(stalePort);
        stale.candidate("phone-old", 0);
        stale.tick(0);
        long oldGeneration = stalePort.inspectedGeneration;
        stale.lost("phone-old", 1);
        stale.candidate("phone-new", 2);
        stale.tick(2);
        stalePort.reply(true, false, false);
        stale.inspected(oldGeneration, stalePort.lastObservation, 3);
        check(stalePort.requests == 0, "stale inspection cannot request for a new candidate");
        stalePort.reply(true, false, false);
        stalePort.inspectionComplete(stale, 4);
        check(stalePort.requests == 1, "current candidate can request after stale reply is ignored");

        FakePort timeoutPort = new FakePort();
        StockProjectionSession timeout = new StockProjectionSession(timeoutPort);
        timeout.candidate("phone-timeout", 0);
        timeout.tick(0);
        timeoutPort.reply(true, false, false);
        timeoutPort.inspectionComplete(timeout, 1);
        timeoutPort.requestResult = StockProjectionSession.RequestResult.OEM_ACTION_SENT;
        timeoutPort.requestComplete(timeout, 2);
        timeout.tick(StockProjectionSession.REQUEST_TIMEOUT_MS + 2);
        check(timeout.phase() == StockProjectionSession.Phase.FAILED,
                "request timeout fails closed");
        check(!timeout.requestAllowed(timeoutPort.requestedGeneration, "phone-timeout"),
                "timed-out OEM request cannot emit a late action");
        check(timeoutPort.requests == 1, "timeout never starts another transport or OEM request");

        FakePort wiredPort = new FakePort();
        StockProjectionSession wired = new StockProjectionSession(wiredPort);
        wired.candidate("phone-wired", 0);
        wired.environment(true, false, 1);
        wired.tick(2);
        check(wiredPort.inspections == 0, "wired connection suppresses stock request");
        check(wired.phase() == StockProjectionSession.Phase.IDLE,
                "wired change invalidates the pending generation");

        FakePort latePort = new FakePort();
        StockProjectionSession late = new StockProjectionSession(latePort);
        late.candidate("phone-late", 0);
        late.tick(0);
        latePort.reply(true, false, false);
        latePort.inspectionComplete(late, 1);
        final int[] lateSends = new int[] { 0 };
        boolean lateDispatched = late.dispatchIfRequestAllowed(latePort.requestedGeneration, "phone-late", 6000,
                new StockProjectionSession.RequestAction() {
                    public void send() { lateSends[0]++; }
                });
        check(!lateDispatched && lateSends[0] == 0,
                "dispatch-time deadline check rejects late work even before the main-loop timeout tick");
        late.requested(latePort.requestedGeneration, StockProjectionSession.RequestResult.CANCELLED, 6000);
        late.tick(6001);
        check(late.phase() == StockProjectionSession.Phase.FAILED && latePort.requests == 1,
                "late cancelled request fails instead of retrying the OEM action");

        FakePort connectingPort = new FakePort();
        StockProjectionSession connecting = new StockProjectionSession(connectingPort);
        connecting.candidate("phone-connecting", 0);
        connecting.tick(0);
        connectingPort.replyConnecting();
        connectingPort.inspectionComplete(connecting, 1);
        check(connecting.phase() == StockProjectionSession.Phase.REQUESTED && connectingPort.requests == 0,
                "same-candidate OEM CONNECTING state is observed without duplicating its request");
        connecting.tick(1001);
        connectingPort.replyConnecting();
        connectingPort.inspectionComplete(connecting, 1002);
        check(connecting.phase() == StockProjectionSession.Phase.REQUESTED && connectingPort.requests == 0,
                "continued OEM connection progress remains pending");
        connecting.tick(2002);
        connectingPort.reply(false, false, false);
        connectingPort.inspectionComplete(connecting, 2003);
        check(connectingPort.requests == 1,
                "one OEM request may be issued only after the prior same-device attempt becomes idle");

        FakePort connectingTimeoutPort = new FakePort();
        StockProjectionSession connectingTimeout = new StockProjectionSession(connectingTimeoutPort);
        connectingTimeout.candidate("phone-connecting-timeout", 0);
        connectingTimeout.tick(0);
        connectingTimeoutPort.replyConnecting();
        connectingTimeoutPort.inspectionComplete(connectingTimeout, 1);
        connectingTimeout.tick(StockProjectionSession.REQUEST_TIMEOUT_MS + 1);
        check(connectingTimeout.phase() == StockProjectionSession.Phase.FAILED &&
                connectingTimeoutPort.requests == 0,
                "stalled same-candidate OEM connection fails closed without a parallel request");

        System.out.println("PASS StockProjectionSessionTest");
    }
}
