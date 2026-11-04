package kr.gen5w.wireless;

import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/** Reconciles ACL events with the Bluetooth stack's current connection view. */
final class BluetoothCandidateScan {
    private static final long FALSE_CONFIRMATION_MS = 1000L;

    interface Device {
        String address();
        /** Returns null when the platform query is unavailable or fails. */
        Boolean isConnected();
    }

    private BluetoothCandidateScan() {}

    static void reconcile(Set<String> linked, Map<String, Long> falseSince,
            Iterable<? extends Device> devices, String hfpAddress,
            StockProjectionSession session, long now) {
        Set<String> connectedNow = new LinkedHashSet<String>();
        Set<String> seen = new LinkedHashSet<String>();
        for (Device device : devices) {
            if (device == null) continue;
            String address = device.address();
            if (address == null || address.length() == 0) continue;
            String key = key(address);
            seen.add(key);

            boolean connected = hfpAddress != null && address.equalsIgnoreCase(hfpAddress);
            if (connected) {
                falseSince.remove(key);
            } else {
                Boolean observed = null;
                try { observed = device.isConnected(); }
                catch (RuntimeException ignored) {}

                if (observed == null) {
                    // Older Android builds may not expose the hidden query. In that
                    // case an ACL event remains the best available evidence.
                    connected = containsIgnoreCase(linked, address);
                    falseSince.remove(key);
                } else if (observed.booleanValue()) {
                    connected = true;
                    falseSince.remove(key);
                } else if (containsIgnoreCase(linked, address)) {
                    Long firstFalse = falseSince.get(key);
                    if (firstFalse == null) {
                        // ACL_CONNECTED can be delivered before profile state updates.
                        connected = true;
                        falseSince.put(key, Long.valueOf(now));
                    } else if (now - firstFalse.longValue() < FALSE_CONFIRMATION_MS) {
                        connected = true;
                    } else {
                        falseSince.remove(key);
                    }
                } else {
                    falseSince.remove(key);
                }
            }
            if (connected) connectedNow.add(address);
        }

        falseSince.keySet().retainAll(seen);
        String previousCandidate = session.candidate();
        linked.clear();
        linked.addAll(connectedNow);

        if (previousCandidate != null && !containsIgnoreCase(connectedNow, previousCandidate)) {
            if (!holdsOemRequest(session)) {
                session.lost(previousCandidate, now);
            }
        }
        offerCandidate(linked, session, now);
    }

    static void disconnected(Set<String> linked, Map<String, Long> falseSince,
            String address, StockProjectionSession session, long now) {
        removeIgnoreCase(linked, address);
        falseSince.remove(key(address));
        String candidate = session.candidate();
        if (candidate != null && candidate.equalsIgnoreCase(address) && !holdsOemRequest(session)) {
            session.lost(candidate, now);
        }
        offerCandidate(linked, session, now);
    }

    private static boolean holdsOemRequest(StockProjectionSession session) {
        return session.hasPendingOemOwnership();
    }

    private static void offerCandidate(Set<String> linked, StockProjectionSession session, long now) {
        if (session.candidate() == null) {
            for (String address : linked) {
                session.candidate(address, now);
                break;
            }
        }
    }

    private static boolean containsIgnoreCase(Iterable<String> values, String target) {
        for (String value : values) if (target.equalsIgnoreCase(value)) return true;
        return false;
    }

    private static void removeIgnoreCase(Set<String> values, String target) {
        java.util.Iterator<String> iterator = values.iterator();
        while (iterator.hasNext()) if (target.equalsIgnoreCase(iterator.next())) iterator.remove();
    }

    private static String key(String address) {
        return address.toUpperCase(Locale.US);
    }
}
