package kr.gen5w.wireless;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public final class BtRelayPipeTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class FakeSpp implements BtRelayPipe.SppEndpoint {
        final List<byte[]> writes = new ArrayList<byte[]>();
        final List<String> order;
        boolean writeResult = true;
        int disconnects;
        FakeSpp(List<String> order) { this.order = order; }
        public boolean write(byte[] payload, int length) {
            writes.add(Arrays.copyOf(payload, length));
            order.add("spp-write");
            return writeResult;
        }
        public void disconnect() { disconnects++; order.add("spp-disconnect"); }
    }

    private static final class FakeIap2 implements BtRelayPipe.Iap2Endpoint {
        final List<byte[]> received = new ArrayList<byte[]>();
        final List<Integer> components = new ArrayList<Integer>();
        final List<String> order;
        boolean receiveResult = true;
        int stops;
        FakeIap2(List<String> order) { this.order = order; }
        public boolean readDone(int component, byte[] payload, int length) {
            components.add(component);
            received.add(Arrays.copyOf(payload, length));
            order.add("iap2-read");
            return receiveResult;
        }
        public void stop(int component) { check(component == 4, "pipe only stops the Bluetooth CarPlay component"); stops++; order.add("iap2-stop"); }
    }

    private static final class FakeDiagnostics implements BtRelayPipe.Diagnostics {
        final List<BtRelayPipe.Event> events = new ArrayList<BtRelayPipe.Event>();
        final List<Integer> components = new ArrayList<Integer>();
        public void event(BtRelayPipe.Event event, int component) {
            events.add(event);
            components.add(component);
        }
    }

    private static final class Fixture {
        final List<String> order = new ArrayList<String>();
        final FakeSpp spp = new FakeSpp(order);
        final FakeIap2 iap2 = new FakeIap2(order);
        final FakeDiagnostics diagnostics = new FakeDiagnostics();
        final BtRelayPipe pipe = new BtRelayPipe(spp, iap2, diagnostics);
    }

    private static void onlyOneGenerationOwnsThePipe() {
        Fixture f = new Fixture();
        check(f.pipe.attach(10), "first generation claims the pipe");
        check(!f.pipe.attach(11), "second generation cannot replace the owner");
        check(f.pipe.phoneToIap2(10, new byte[] {1, 2}, 2), "current owner can forward");
        check(f.iap2.received.size() == 1 && f.iap2.components.get(0) == 4,
                "the selected owner is forwarded to component 4");
        check(f.pipe.activeGeneration() == 10, "rejected contender does not replace the owner");
    }

    private static void bothDirectionsPreserveCallOrderAndFrameBytes() {
        Fixture f = new Fixture();
        f.pipe.attach(4);
        byte[] phoneFrame = new byte[] {10, 11, 12, 13};
        byte[] iap2Frame = new byte[] {20, 21, 22};
        check(f.pipe.phoneToIap2(4, phoneFrame, 3), "phone frame accepted");
        phoneFrame[0] = 99;
        check(f.pipe.iap2ToPhone(4, iap2Frame, 2), "iAP2 frame accepted");
        iap2Frame[0] = 99;
        check(Arrays.equals(f.iap2.received.get(0), new byte[] {10, 11, 12}), "phone bytes are copied to iAP2");
        check(Arrays.equals(f.spp.writes.get(0), new byte[] {20, 21}), "iAP2 bytes are copied to SPP");
        check(f.order.equals(Arrays.asList("iap2-read", "spp-write")), "forwarding preserves callback order");
    }

    private static void disconnectCleansUpAndReleasesOnlyAfterBothSidesStop() {
        Fixture f = new Fixture();
        f.pipe.attach(21);
        check(f.pipe.phoneDisconnected(21), "phone disconnect is handled");
        check(!f.pipe.isActive(), "disconnect releases current owner");
        check(f.iap2.stops == 1 && f.spp.disconnects == 1, "disconnect stops iAP2 then SPP");
        check(f.order.equals(Arrays.asList("iap2-stop", "spp-disconnect")), "cleanup order is deterministic");
        check(!f.pipe.phoneToIap2(21, new byte[] {1}, 1), "late frame from old generation is ignored");
        check(f.pipe.attach(22), "a newer generation can claim the released pipe");
    }

    private static void phoneToIap2WriteFailureClosesBothEndpoints() {
        Fixture f = new Fixture();
        f.pipe.attach(31);
        f.iap2.receiveResult = false;
        check(!f.pipe.phoneToIap2(31, new byte[] {4, 5}, 2), "failed iAP2 write is reported");
        check(!f.pipe.isActive() && f.iap2.stops == 1 && f.spp.disconnects == 1,
                "iAP2 write failure releases and closes the whole pipe");
        check(f.diagnostics.events.contains(BtRelayPipe.Event.IAP2_WRITE_FAILED), "failure has a stable diagnostic category");
    }

    private static void sppWriteFailureClosesBothEndpoints() {
        Fixture f = new Fixture();
        f.pipe.attach(41);
        f.spp.writeResult = false;
        check(!f.pipe.iap2ToPhone(41, new byte[] {6, 7}, 2), "failed SPP write is reported");
        check(!f.pipe.isActive() && f.iap2.stops == 1 && f.spp.disconnects == 1,
                "SPP write failure releases and closes the whole pipe");
        check(f.diagnostics.events.contains(BtRelayPipe.Event.SPP_WRITE_FAILED), "SPP failure has a stable category");
    }

    private static void diagnosticsCannotCarryIdentifiersOrPayloads() {
        Fixture f = new Fixture();
        f.pipe.attach(51);
        f.pipe.phoneToIap2(51, new byte[] {0x41, 0x42}, 2);
        f.pipe.iap2ToPhone(51, new byte[] {0x51}, 1);
        f.pipe.iap2Disconnected(51);
        check(f.diagnostics.events.equals(Arrays.asList(BtRelayPipe.Event.STARTED,
                BtRelayPipe.Event.PHONE_TO_IAP2, BtRelayPipe.Event.IAP2_TO_PHONE,
                BtRelayPipe.Event.IAP2_DISCONNECTED, BtRelayPipe.Event.STOPPED)),
                "diagnostics expose only fixed event categories");
        for (Integer component : f.diagnostics.components) check(component == 4, "diagnostics expose only the fixed component");
    }

    private static void blockedTransportDoesNotBlockCancellation() {
        final CountDownLatch entered = new CountDownLatch(1);
        final CountDownLatch release = new CountDownLatch(1);
        final FakeSpp spp = new FakeSpp(new ArrayList<String>());
        BtRelayPipe.Iap2Endpoint blocked = new BtRelayPipe.Iap2Endpoint() {
            public boolean readDone(int component, byte[] payload, int length) {
                entered.countDown();
                try { release.await(2, TimeUnit.SECONDS); }
                catch (InterruptedException e) { throw new RuntimeException(e); }
                return true;
            }
            public void stop(int component) { }
        };
        final BtRelayPipe pipe = new BtRelayPipe(spp, blocked, new FakeDiagnostics());
        check(pipe.attach(61), "blocked transport fixture attaches");
        Thread writer = new Thread(new Runnable() {
            public void run() { pipe.phoneToIap2(61, new byte[] {1}, 1); }
        });
        writer.setDaemon(true);
        writer.start();
        try { check(entered.await(1, TimeUnit.SECONDS), "transport call reached endpoint"); }
        catch (InterruptedException e) { throw new AssertionError(e); }
        long start = System.currentTimeMillis();
        check(pipe.close(61), "cancellation claims the owner while transport is blocked");
        check(System.currentTimeMillis() - start < 500, "blocked endpoint does not hold ownership lock");
        release.countDown();
        try { writer.join(1000); }
        catch (InterruptedException e) { throw new AssertionError(e); }
        check(!writer.isAlive() && !pipe.isActive(), "late write completion cannot revive closed pipe");
    }

    public static void main(String[] args) {
        onlyOneGenerationOwnsThePipe();
        bothDirectionsPreserveCallOrderAndFrameBytes();
        disconnectCleansUpAndReleasesOnlyAfterBothSidesStop();
        phoneToIap2WriteFailureClosesBothEndpoints();
        sppWriteFailureClosesBothEndpoints();
        diagnosticsCannotCarryIdentifiersOrPayloads();
        blockedTransportDoesNotBlockCancellation();
        System.out.println("PASS Bluetooth relay pipe");
    }
}
