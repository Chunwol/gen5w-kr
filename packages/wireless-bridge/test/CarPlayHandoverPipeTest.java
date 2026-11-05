package kr.gen5w.wireless;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public final class CarPlayHandoverPipeTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class FakeIap2 implements CarPlayHandoverPipe.Iap2Endpoint {
        final List<byte[]> received = new ArrayList<byte[]>();
        final List<Integer> components = new ArrayList<Integer>();
        boolean writeResult = true;
        int stops;
        CountDownLatch writeEntered;
        CountDownLatch releaseWrite;
        public boolean readDone(int component, byte[] payload, int length) {
            if (writeEntered != null) {
                writeEntered.countDown();
                try { releaseWrite.await(); }
                catch (InterruptedException e) { Thread.currentThread().interrupt(); return false; }
            }
            components.add(component);
            received.add(Arrays.copyOf(payload, length));
            return writeResult;
        }
        public void stop(int component) { check(component == 5, "handover cleanup stops component 5"); stops++; }
    }

    private static final class FakeDipo implements CarPlayHandoverPipe.DipoEndpoint {
        final List<byte[]> received = new ArrayList<byte[]>();
        boolean writeResult = true;
        int closes;
        public boolean receive(byte[] payload, int length) {
            received.add(Arrays.copyOf(payload, length));
            return writeResult;
        }
        public void close() { closes++; }
    }

    private static final class FakeDiagnostics implements CarPlayHandoverPipe.Diagnostics {
        final List<CarPlayHandoverPipe.Event> events = new ArrayList<CarPlayHandoverPipe.Event>();
        final List<Integer> components = new ArrayList<Integer>();
        public void event(CarPlayHandoverPipe.Event event, int component) {
            events.add(event);
            components.add(component);
        }
    }

    private static final class Fixture {
        final FakeIap2 iap2 = new FakeIap2();
        final FakeDipo dipo = new FakeDipo();
        final FakeDiagnostics diagnostics = new FakeDiagnostics();
        final CarPlayHandoverPipe pipe = new CarPlayHandoverPipe(iap2, dipo, diagnostics);
    }

    private static void forwardsCopiedFramesInBothDirectionsOnlyForOwner() {
        Fixture f = new Fixture();
        check(f.pipe.attach(70), "first generation claims component-5 handover");
        check(!f.pipe.attach(71), "second generation cannot become a concurrent owner");
        byte[] fromDipo = new byte[] {1, 2, 3};
        byte[] fromIap2 = new byte[] {4, 5, 6};
        check(f.pipe.dipoToIap2(70, fromDipo, 2), "DiPO frame reaches iAP2");
        fromDipo[0] = 99;
        check(f.pipe.iap2ToDipo(70, fromIap2, 1), "iAP2 frame reaches DiPO");
        fromIap2[0] = 99;
        check(f.iap2.components.equals(Arrays.asList(5)), "DiPO data uses component 5");
        check(Arrays.equals(f.iap2.received.get(0), new byte[] {1, 2}), "iAP2 receives a bounded copy");
        check(Arrays.equals(f.dipo.received.get(0), new byte[] {4}), "DiPO receives a bounded copy");
        check(!f.pipe.iap2ToDipo(71, new byte[] {7}, 1), "non-owner callback is rejected");
    }

    private static void eitherDisconnectClosesBothEndpointsOnce() {
        Fixture f = new Fixture();
        f.pipe.attach(80);
        check(f.pipe.iap2Disconnected(80), "iAP2 disconnect is handled");
        check(f.iap2.stops == 1 && f.dipo.closes == 1, "iAP2 disconnect closes both endpoints");
        check(!f.pipe.dipoDisconnected(80), "duplicate disconnect is ignored");
        check(f.iap2.stops == 1 && f.dipo.closes == 1, "duplicate disconnect does not repeat cleanup");
        check(f.pipe.attach(81), "cleanup releases ownership for a newer generation");
        check(f.pipe.dipoDisconnected(81), "DiPO disconnect is handled");
        check(f.iap2.stops == 2 && f.dipo.closes == 2, "DiPO disconnect closes both endpoints");
    }

    private static void eitherWriteFailureClosesTheWholeHandover() {
        Fixture iap2Failure = new Fixture();
        iap2Failure.pipe.attach(90);
        iap2Failure.iap2.writeResult = false;
        check(!iap2Failure.pipe.dipoToIap2(90, new byte[] {8}, 1), "failed iAP2 write is reported");
        check(!iap2Failure.pipe.isActive() && iap2Failure.iap2.stops == 1 && iap2Failure.dipo.closes == 1,
                "iAP2 failure cleans both endpoints");
        check(iap2Failure.diagnostics.events.contains(CarPlayHandoverPipe.Event.IAP2_WRITE_FAILED),
                "iAP2 failure uses a stable diagnostic event");

        Fixture dipoFailure = new Fixture();
        dipoFailure.pipe.attach(91);
        dipoFailure.dipo.writeResult = false;
        check(!dipoFailure.pipe.iap2ToDipo(91, new byte[] {9}, 1), "failed DiPO write is reported");
        check(!dipoFailure.pipe.isActive() && dipoFailure.iap2.stops == 1 && dipoFailure.dipo.closes == 1,
                "DiPO failure cleans both endpoints");
        check(dipoFailure.diagnostics.events.contains(CarPlayHandoverPipe.Event.DIPO_WRITE_FAILED),
                "DiPO failure uses a stable diagnostic event");
    }

    private static void blockedWriteDoesNotBlockCancellationOrPermitOverlap() throws Exception {
        final Fixture f = new Fixture();
        final CountDownLatch entered = new CountDownLatch(1);
        final CountDownLatch release = new CountDownLatch(1);
        f.iap2.writeEntered = entered;
        f.iap2.releaseWrite = release;
        check(f.pipe.attach(100), "first owner attached");
        final AtomicBoolean forwarded = new AtomicBoolean(true);
        Thread writer = new Thread(new Runnable() {
            public void run() { forwarded.set(f.pipe.dipoToIap2(100, new byte[] {1}, 1)); }
        });
        writer.start();
        check(entered.await(1, TimeUnit.SECONDS), "write reached the external endpoint");

        long before = System.nanoTime();
        check(f.pipe.cancel(100, CarPlayHandoverPipe.StopReason.WIRED), "cancellation accepted");
        long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - before);
        check(elapsedMs < 500, "cancellation does not wait for the blocked endpoint write");
        check(f.iap2.stops == 1 && f.dipo.closes == 1, "cancellation closes endpoints while write is blocked");
        check(!f.pipe.attach(101), "new owner is held while the old write remains in flight");

        release.countDown();
        writer.join(1000);
        check(!writer.isAlive() && !forwarded.get(), "late write completion cannot revive the old generation");
        check(f.pipe.attach(101), "new generation attaches after the old write exits");
    }

    private static void diagnosticsExposeOnlyFixedCategories() {
        Fixture f = new Fixture();
        f.pipe.attach(110);
        f.pipe.dipoToIap2(110, new byte[] {0x41, 0x42}, 2);
        f.pipe.iap2ToDipo(110, new byte[] {0x51}, 1);
        f.pipe.dipoDisconnected(110);
        check(f.diagnostics.events.equals(Arrays.asList(CarPlayHandoverPipe.Event.STARTED,
                CarPlayHandoverPipe.Event.DIPO_TO_IAP2, CarPlayHandoverPipe.Event.IAP2_TO_DIPO,
                CarPlayHandoverPipe.Event.DIPO_DISCONNECTED, CarPlayHandoverPipe.Event.STOPPED)),
                "diagnostics carry fixed categories only");
        for (Integer component : f.diagnostics.components) check(component == 5, "diagnostics carry only component 5");
    }

    public static void main(String[] args) throws Exception {
        forwardsCopiedFramesInBothDirectionsOnlyForOwner();
        eitherDisconnectClosesBothEndpointsOnce();
        eitherWriteFailureClosesTheWholeHandover();
        blockedWriteDoesNotBlockCancellationOrPermitOverlap();
        diagnosticsExposeOnlyFixedCategories();
        System.out.println("PASS CarPlay handover pipe");
    }
}
