package kr.gen5w.wireless;

import java.util.List;

public final class BtRelaySessionTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static void commands(BtRelaySession.Update update, BtRelaySession.CommandType... expected) {
        List<BtRelaySession.Command> actual = update.commands;
        check(actual.size() == expected.length, "command count: expected " + expected.length + ", got " + actual.size());
        for (int i = 0; i < expected.length; i++) {
            check(actual.get(i).type == expected[i], "command " + i + ": expected " + expected[i] + ", got " + actual.get(i).type);
        }
    }

    private static void startsOneOrderedRelayAndActivatesAfterApReady() {
        BtRelaySession session = new BtRelaySession();
        BtRelaySession.Update started = session.start(100);
        long generation = started.generation;
        commands(started, BtRelaySession.CommandType.CONNECT_SPP);
        check(session.phase() == BtRelaySession.Phase.SPP_CONNECTING, "start waits for SPP");
        BtRelaySession.Update component4 = session.sppConnected(generation, 200);
        commands(component4, BtRelaySession.CommandType.START_IAP2);
        check(component4.commands.get(0).component == 4, "SPP starts Bluetooth component 4");
        check(session.phase() == BtRelaySession.Phase.IAP2_BLUETOOTH, "SPP starts component 4");
        session.iap2Connected(generation, 4, 300);
        check(session.phase() == BtRelaySession.Phase.CARPLAY_HANDOVER, "component 4 enters handover phase");
        BtRelaySession.Update component5 = session.handoverRequested(generation, 400);
        commands(component5, BtRelaySession.CommandType.START_IAP2);
        check(component5.commands.get(0).component == 5, "handover starts component 5");
        session.iap2Connected(generation, 5, 500);
        commands(session.credentialsReady(generation, 600), BtRelaySession.CommandType.START_AP);
        check(session.phase() == BtRelaySession.Phase.CARPLAY_HANDOVER, "AP startup is not projection activation");
        session.apReady(generation, 700);
        check(session.phase() == BtRelaySession.Phase.CARPLAY_HANDOVER, "AP readiness alone is not activation");
        session.projectionActivated(generation, 800);
        check(session.phase() == BtRelaySession.Phase.ACTIVE, "projection activation completes relay");
    }

    private static void credentialsStartApWithoutWaitingForComponentFive() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        session.iap2Connected(generation, 4, 2);
        commands(session.credentialsReady(generation, 3), BtRelaySession.CommandType.START_AP);
        session.handoverRequested(generation, 4);
        commands(session.iap2Connected(generation, 5, 5), new BtRelaySession.CommandType[0]);
    }

    private static void firstConnectionStartsApBeforeCarPlayChannelExists() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        commands(session.credentialsReady(generation, 1));
        commands(session.sppConnected(generation, 2), BtRelaySession.CommandType.START_AP,
                BtRelaySession.CommandType.START_IAP2);
        commands(session.apReady(generation, 3));
        commands(session.iap2Connected(generation, 4, 4));
        check(session.phase() == BtRelaySession.Phase.CARPLAY_HANDOVER, "AP precedes Wi-Fi handover");
        commands(session.handoverRequested(generation, 5), BtRelaySession.CommandType.START_IAP2);
        commands(session.iap2Connected(generation, 5, 6));
        session.projectionActivated(generation, 7);
        check(session.phase() == BtRelaySession.Phase.ACTIVE, "first connection completes without pre-existing AP");
    }

    private static void lateCredentialsStartApWhileBluetoothAuthenticationRuns() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        commands(session.credentialsReady(generation, 2), BtRelaySession.CommandType.START_AP);
        commands(session.credentialsReady(generation, 3));
        session.iap2Connected(generation, 4, 4);
        session.handoverRequested(generation, 100);
        session.iap2Connected(generation, 5, 200);
        check(session.tick(generation, 2 + BtRelaySession.AP_TIMEOUT_MS).failure ==
                BtRelaySession.FailureReason.AP_TIMEOUT, "handover callbacks do not postpone AP timeout");
    }

    private static void earlyApIsCleanedUpAndStaleCredentialsCannotRestartIt() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        commands(session.credentialsReady(generation, 2), BtRelaySession.CommandType.START_AP);
        commands(session.cancel(generation, BtRelaySession.CancelReason.WIRED),
                BtRelaySession.CommandType.STOP_AP, BtRelaySession.CommandType.STOP_IAP2,
                BtRelaySession.CommandType.DISCONNECT_SPP);
        commands(session.credentialsReady(generation, 3));
        commands(session.apReady(generation, 4));
        session.cleanupCompleted(generation);
        long next = session.start(5).generation;
        commands(session.credentialsReady(generation, 6));
        commands(session.sppConnected(next, 7), BtRelaySession.CommandType.START_IAP2);
    }

    private static void duplicateAndWrongComponentEventsDoNotStartExtraWork() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        BtRelaySession.Update component4 = session.sppConnected(generation, 1);
        commands(component4, BtRelaySession.CommandType.START_IAP2);
        check(component4.commands.get(0).component == 4, "first session is component 4");
        commands(session.sppConnected(generation, 2), new BtRelaySession.CommandType[0]);
        commands(session.iap2Connected(generation, 5, 3), new BtRelaySession.CommandType[0]);
        session.iap2Connected(generation, 4, 4);
        BtRelaySession.Update component5 = session.handoverRequested(generation, 5);
        commands(component5, BtRelaySession.CommandType.START_IAP2);
        check(component5.commands.get(0).component == 5, "second session is component 5");
        commands(session.handoverRequested(generation, 6), new BtRelaySession.CommandType[0]);
        check(session.phase() == BtRelaySession.Phase.CARPLAY_HANDOVER, "duplicates leave phase unchanged");
    }

    private static void timeoutFailsAndCleansUpOnlyStartedStages() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(10).generation;
        BtRelaySession.Update sppTimeout = session.tick(generation, 10 + BtRelaySession.SPP_TIMEOUT_MS);
        commands(sppTimeout,
                BtRelaySession.CommandType.DISCONNECT_SPP);
        check(sppTimeout.failure == BtRelaySession.FailureReason.SPP_TIMEOUT, "SPP timeout reason is observable");
        check(session.phase() == BtRelaySession.Phase.STOPPING, "SPP timeout waits for cleanup");
        check(session.tick(generation, 100000).commands.isEmpty(), "terminal attempt does not repeat cleanup");
        session.cleanupCompleted(generation);
        check(session.phase() == BtRelaySession.Phase.FAILED, "SPP timeout fails attempt after cleanup");

        generation = session.start(200000).generation;
        session.sppConnected(generation, 200001);
        BtRelaySession.Update iap2Timeout = session.tick(generation, 200001 + BtRelaySession.IAP2_TIMEOUT_MS);
        commands(iap2Timeout,
                BtRelaySession.CommandType.STOP_IAP2, BtRelaySession.CommandType.DISCONNECT_SPP);
        check(iap2Timeout.failure == BtRelaySession.FailureReason.IAP2_TIMEOUT, "component 4 timeout reason is observable");
        check(session.phase() == BtRelaySession.Phase.STOPPING, "component 4 timeout waits for cleanup");
        session.cleanupCompleted(generation);
        check(session.phase() == BtRelaySession.Phase.FAILED, "component 4 timeout fails after cleanup");
    }

    private static void cancellationInvalidatesOldCallbacksAndCleansUpInReverseOrder() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        session.iap2Connected(generation, 4, 2);
        session.handoverRequested(generation, 3);
        session.iap2Connected(generation, 5, 4);
        session.credentialsReady(generation, 5);
        commands(session.apReady(generation, 6), new BtRelaySession.CommandType[0]);
        BtRelaySession.Update cancelled = session.cancel(generation, BtRelaySession.CancelReason.WIRED);
        check(session.phase() == BtRelaySession.Phase.STOPPING, "wired ownership first enters cleanup");
        check(cancelled.cancellation == BtRelaySession.CancelReason.WIRED, "cancellation reason is observable");
        check(cancelled.generation == generation, "cleanup commands retain their attempt generation");
        check(cancelled.commands.size() == 4, "cleanup includes AP, both iAP2 components and SPP");
        check(cancelled.commands.get(0).type == BtRelaySession.CommandType.STOP_AP, "AP stops first");
        check(cancelled.commands.get(1).component == 5 && cancelled.commands.get(2).component == 4,
                "iAP2 components stop in reverse order");
        check(cancelled.commands.get(3).type == BtRelaySession.CommandType.DISCONNECT_SPP,
                "SPP stops last");
        commands(session.sppConnected(generation, 7), new BtRelaySession.CommandType[0]);
        BtRelaySession.Update blockedStart = session.start(8);
        commands(blockedStart, new BtRelaySession.CommandType[0]);
        check(blockedStart.generation == generation && session.phase() == BtRelaySession.Phase.STOPPING,
                "new attempt waits until asynchronous cleanup completes");
        session.cleanupCompleted(generation);
        check(session.phase() == BtRelaySession.Phase.CANCELLED, "wired cancellation completes after cleanup");
        commands(session.sppConnected(generation, 9), new BtRelaySession.CommandType[0]);
        commands(session.start(10), BtRelaySession.CommandType.CONNECT_SPP);
    }

    private static void apAndActivationHaveIndependentTimeouts() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        session.iap2Connected(generation, 4, 2);
        session.handoverRequested(generation, 3);
        session.iap2Connected(generation, 5, 4);
        commands(session.credentialsReady(generation, 5), BtRelaySession.CommandType.START_AP);
        BtRelaySession.Update apTimeout = session.tick(generation, 5 + BtRelaySession.AP_TIMEOUT_MS);
        commands(apTimeout,
                BtRelaySession.CommandType.STOP_AP, BtRelaySession.CommandType.STOP_IAP2,
                BtRelaySession.CommandType.STOP_IAP2, BtRelaySession.CommandType.DISCONNECT_SPP);
        check(apTimeout.failure == BtRelaySession.FailureReason.AP_TIMEOUT, "AP timeout reason is observable");
        check(session.phase() == BtRelaySession.Phase.STOPPING, "AP timeout enters cleanup");
        session.cleanupCompleted(generation);
        check(session.phase() == BtRelaySession.Phase.FAILED, "AP timeout fails after cleanup");

        generation = session.start(100000).generation;
        session.sppConnected(generation, 100001);
        session.iap2Connected(generation, 4, 100002);
        session.handoverRequested(generation, 100003);
        session.iap2Connected(generation, 5, 100004);
        session.credentialsReady(generation, 100005);
        session.apReady(generation, 100006);
        BtRelaySession.Update activationTimeout = session.tick(generation, 100006 + BtRelaySession.ACTIVATION_TIMEOUT_MS);
        check(activationTimeout.failure == BtRelaySession.FailureReason.ACTIVATION_TIMEOUT,
                "projection activation timeout reason is observable");
        session.cleanupCompleted(generation);
        check(session.phase() == BtRelaySession.Phase.FAILED, "projection activation has its own timeout");
    }

    private static void handoverTimeoutHasItsOwnReason() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        session.iap2Connected(generation, 4, 2);
        BtRelaySession.Update timeout = session.tick(generation, 2 + BtRelaySession.HANDOVER_TIMEOUT_MS);
        check(timeout.failure == BtRelaySession.FailureReason.HANDOVER_TIMEOUT,
                "component 5 handover timeout reason is observable");
        session.cleanupCompleted(generation);
    }

    private static void runtimeFailureUsesTheSameOrderedCleanup() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        session.iap2Connected(generation, 4, 2);
        BtRelaySession.Update failed = session.fail(generation, BtRelaySession.FailureReason.TRANSPORT_ERROR);
        commands(failed, BtRelaySession.CommandType.STOP_IAP2, BtRelaySession.CommandType.DISCONNECT_SPP);
        check(failed.commands.get(0).component == 4, "runtime failure stops component 4 first");
        check(failed.failure == BtRelaySession.FailureReason.TRANSPORT_ERROR,
                "runtime failure reason is retained");
        session.cleanupCompleted(generation);
        check(session.phase() == BtRelaySession.Phase.FAILED, "runtime failure completes as failed");
    }

    private static void duplicateReadyEventsDoNotExtendDeadlines() {
        BtRelaySession session = new BtRelaySession();
        long generation = session.start(0).generation;
        session.sppConnected(generation, 1);
        session.iap2Connected(generation, 4, 2);
        session.handoverRequested(generation, 3);
        session.iap2Connected(generation, 5, 4);
        session.credentialsReady(generation, 5);
        commands(session.iap2Connected(generation, 5, 1000), new BtRelaySession.CommandType[0]);
        BtRelaySession.Update apTimeout = session.tick(generation, 5 + BtRelaySession.AP_TIMEOUT_MS);
        check(apTimeout.failure == BtRelaySession.FailureReason.AP_TIMEOUT,
                "duplicate component 5 does not extend AP deadline");
        session.cleanupCompleted(generation);

        generation = session.start(100000).generation;
        session.sppConnected(generation, 100001);
        session.iap2Connected(generation, 4, 100002);
        session.handoverRequested(generation, 100003);
        session.iap2Connected(generation, 5, 100004);
        session.credentialsReady(generation, 100005);
        session.apReady(generation, 100006);
        commands(session.apReady(generation, 101000), new BtRelaySession.CommandType[0]);
        BtRelaySession.Update activationTimeout = session.tick(
                generation, 100006 + BtRelaySession.ACTIVATION_TIMEOUT_MS);
        check(activationTimeout.failure == BtRelaySession.FailureReason.ACTIVATION_TIMEOUT,
                "duplicate AP ready does not extend activation deadline");
    }

    public static void main(String[] args) {
        firstConnectionStartsApBeforeCarPlayChannelExists();
        lateCredentialsStartApWhileBluetoothAuthenticationRuns();
        earlyApIsCleanedUpAndStaleCredentialsCannotRestartIt();
        startsOneOrderedRelayAndActivatesAfterApReady();
        credentialsStartApWithoutWaitingForComponentFive();
        duplicateAndWrongComponentEventsDoNotStartExtraWork();
        timeoutFailsAndCleansUpOnlyStartedStages();
        cancellationInvalidatesOldCallbacksAndCleansUpInReverseOrder();
        apAndActivationHaveIndependentTimeouts();
        handoverTimeoutHasItsOwnReason();
        runtimeFailureUsesTheSameOrderedCleanup();
        duplicateReadyEventsDoNotExtendDeadlines();
        System.out.println("PASS Bluetooth relay session");
    }
}
