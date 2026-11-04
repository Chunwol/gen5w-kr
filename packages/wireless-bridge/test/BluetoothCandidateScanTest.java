package kr.gen5w.wireless;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class BluetoothCandidateScanTest {
    private static final class Device implements BluetoothCandidateScan.Device {
        final String address;
        final Boolean connected;
        final boolean fails;
        Device(String address, Boolean connected) { this(address, connected, false); }
        Device(String address, Boolean connected, boolean fails) {
            this.address = address;
            this.connected = connected;
            this.fails = fails;
        }
        public String address() { return address; }
        public Boolean isConnected() {
            if (fails) throw new SecurityException("hidden query unavailable");
            return connected;
        }
    }

    private static final class Port implements StockProjectionSession.Port {
        int inspections;
        int requests;
        long generation;
        public void inspect(long generation, String address) {
            inspections++;
            this.generation = generation;
        }
        public void requestConnect(long generation, String address) { requests++; }
        public void event(String name, String result) {}
    }

    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        Set<String> linked = new LinkedHashSet<String>(Arrays.asList("phone-a", "phone-b"));
        Map<String, Long> falseSince = new LinkedHashMap<String, Long>();
        StockProjectionSession session = new StockProjectionSession(new Port());
        session.candidate("phone-a", 0);

        BluetoothCandidateScan.reconcile(linked, falseSince, Arrays.asList(
                new Device("phone-a", Boolean.FALSE),
                new Device("phone-b", Boolean.TRUE)), null, session, 100);

        check(linked.contains("phone-a") && "phone-a".equals(session.candidate()),
                "one false scan after ACL connect is treated as a transient observation");
        check(linked.contains("phone-b"), "connected device remains linked");

        BluetoothCandidateScan.reconcile(linked, falseSince, Arrays.asList(
                new Device("phone-a", Boolean.FALSE),
                new Device("phone-b", Boolean.TRUE)), null, session, 1100);
        check(!linked.contains("phone-a"), "false confirmed after the minimum elapsed interval removes stale cache");
        check("phone-b".equals(session.candidate()),
                "confirmed candidate loss is cancelled before another connected device is selected");
        Port ownerPort = new Port();
        StockProjectionSession ownerSession = new StockProjectionSession(ownerPort);
        ownerSession.candidate("phone-b", 0);
        ownerSession.tick(0);
        ownerSession.inspected(ownerPort.generation, new StockProjectionSession.Observation(
                StockProjectionSession.Result.INVOKED, true, false, false, true), 1);
        check(ownerSession.phase() == StockProjectionSession.Phase.BLOCKED && ownerPort.requests == 0,
                "a different OEM-owned projection blocks a new candidate request");

        Set<String> cached = new LinkedHashSet<String>(Arrays.asList("phone-c"));
        Map<String, Long> cachedFalseSince = new LinkedHashMap<String, Long>();
        StockProjectionSession cachedSession = new StockProjectionSession(new Port());
        cachedSession.candidate("phone-c", 0);
        BluetoothCandidateScan.reconcile(cached, cachedFalseSince,
                Arrays.asList(new Device("phone-c", Boolean.FALSE)), null, cachedSession, 200);
        check(cached.contains("phone-c"), "first false sample does not drop an event candidate");
        BluetoothCandidateScan.reconcile(cached, cachedFalseSince,
                Arrays.asList(new Device("phone-c", null, true)),
                null, cachedSession, 300);
        check(cached.contains("phone-c") && "phone-c".equals(cachedSession.candidate()),
                "failed device-state reflection preserves cache and candidate");
        check(cachedFalseSince.isEmpty(), "failed query resets the false confirmation timer");
        BluetoothCandidateScan.reconcile(cached, cachedFalseSince,
                Arrays.asList(new Device("phone-c", Boolean.FALSE)), null, cachedSession, 400);
        check(cached.contains("phone-c"), "false after failed query starts a fresh streak");
        BluetoothCandidateScan.reconcile(cached, cachedFalseSince,
                Arrays.asList(new Device("phone-c", Boolean.FALSE)), null, cachedSession, 1300);
        check(cached.contains("phone-c"), "rapid repeated scan does not satisfy the elapsed-time threshold");
        BluetoothCandidateScan.reconcile(cached, cachedFalseSince,
                Arrays.asList(new Device("phone-c", Boolean.FALSE)), null, cachedSession, 1400);
        check(!cached.contains("phone-c") && cachedSession.candidate() == null,
                "candidate is lost after two new consecutive successful false queries");

        Set<String> hfp = new LinkedHashSet<String>();
        Map<String, Long> hfpFalseSince = new LinkedHashMap<String, Long>();
        StockProjectionSession hfpSession = new StockProjectionSession(new Port());
        BluetoothCandidateScan.reconcile(hfp, hfpFalseSince,
                Arrays.asList(new Device("phone-d", Boolean.FALSE)),
                "PHONE-D", hfpSession, 300);
        check(hfp.contains("phone-d"), "matching HFP address retains a connected candidate");

        Port pendingPort = new Port();
        StockProjectionSession pending = new StockProjectionSession(pendingPort);
        pending.candidate("phone-a", 0);
        pending.tick(0);
        pending.inspected(pendingPort.generation, new StockProjectionSession.Observation(
                StockProjectionSession.Result.INVOKED, true, false, false, false), 1);
        pending.requested(pendingPort.generation,
                StockProjectionSession.RequestResult.OEM_ACTION_SENT, 2);
        Set<String> pendingLinked = new LinkedHashSet<String>(Arrays.asList("phone-a", "phone-b"));
        Map<String, Long> pendingFalseSince = new LinkedHashMap<String, Long>();
        List<Device> pendingDevices = Arrays.asList(
                new Device("phone-a", Boolean.FALSE), new Device("phone-b", Boolean.TRUE));
        BluetoothCandidateScan.reconcile(pendingLinked, pendingFalseSince, pendingDevices,
                null, pending, 100);
        BluetoothCandidateScan.reconcile(pendingLinked, pendingFalseSince, pendingDevices,
                null, pending, 1100);
        check(!pendingLinked.contains("phone-a") && "phone-a".equals(pending.candidate()) &&
                        pendingPort.requests == 1,
                "confirmed ACL loss does not switch candidates while an OEM request is pending");
        pending.tick(1101);
        check(pending.phase() == StockProjectionSession.Phase.INSPECTING &&
                        pending.hasPendingOemOwnership(),
                "OEM request retains ownership while the next inspection is in flight");
        BluetoothCandidateScan.disconnected(pendingLinked, pendingFalseSince,
                "phone-a", pending, 1200);
        check("phone-a".equals(pending.candidate()) && pendingPort.requests == 1,
                "ACL disconnect also preserves outstanding OEM request ownership");
        pending.tick(StockProjectionSession.REQUEST_TIMEOUT_MS + 2);
        BluetoothCandidateScan.reconcile(pendingLinked, pendingFalseSince, pendingDevices,
                null, pending, StockProjectionSession.REQUEST_TIMEOUT_MS + 3);
        check("phone-b".equals(pending.candidate()),
                "next connected candidate is selected after OEM request ownership expires");

        System.out.println("PASS BluetoothCandidateScanTest");
    }
}
