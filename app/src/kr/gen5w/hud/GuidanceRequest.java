package kr.gen5w.hud;

import java.util.Arrays;

/** Native route-component discovery, initial settle, and bounded Stop+Start
 * recovery if CarPlay sends no 0x78/0x79/0x7a data. Serialized internally
 * so binder callbacks and the main retry loop cannot race.
 */
public final class GuidanceRequest {
    public static final long INITIAL_SETTLE_MS = 1000L;
    public static final long STOP_TO_START_DELAY_MS = 200L;
    public static final long DISCOVERY_RETRY_MS = 2000L;
    public static final long[] RETRY_BACKOFF_MS = { 2000L, 5000L, 10000L, 30000L, 30000L, 30000L };

    public interface Backend {
        int count() throws Exception;
        int components(int[] ids, String[] names) throws Exception;
        boolean start(String[] names) throws Exception;
    }
    public interface LookupBackend extends Backend {
        int componentId(String name) throws Exception;
    }
    public interface ReviewedOemBackend extends LookupBackend {
        boolean canonicalFallbackAllowed() throws Exception;
    }
    public interface StopBackend extends ReviewedOemBackend {
        boolean stop(String[] names) throws Exception;
    }
    public static final class Step {
        public final boolean done;
        public final long nextDelayMs;
        public final int attempt;
        public Step(boolean done, long nextDelayMs, int attempt) {
            this.done = done;
            this.nextDelayMs = nextDelayMs;
            this.attempt = attempt;
        }
    }
    public static boolean reviewedCanonicalProfile(String product) {
        if (product == null) return false;
        // Shared V039 policy: model, market and build date do not restrict this fallback.
        for (String part : product.split("\\.", -1)) {
            if ("V039".equals(part)) return true;
        }
        return false;
    }
    private long successfulEpoch = -1;
    private long confirmedEpoch = -1;
    private long recoveryEpoch = -1;
    private String[] lastNames;
    private int retryCount;
    private boolean pendingStartAfterStop;

    public synchronized void confirmData(long epoch) {
        if (epoch >= 0) confirmedEpoch = epoch;
    }
    public synchronized boolean isConfirmed(long epoch) {
        return epoch >= 0 && confirmedEpoch == epoch;
    }
    public synchronized void reset() {
        successfulEpoch = -1;
        confirmedEpoch = -1;
        recoveryEpoch = -1;
        lastNames = null;
        retryCount = 0;
        pendingStartAfterStop = false;
    }
    public synchronized boolean ensure(long epoch, Backend backend) throws Exception {
        if (epoch < 0) return false;
        if (successfulEpoch == epoch) return true;
        int count = backend.count();
        if (count <= 0 || count > 16) return false;
        int[] ids = new int[count]; Arrays.fill(ids,-1);
        String[] names = new String[count];
        int received = backend.components(ids,names);
        // V039's stock DiPO requests this canonical component directly.
        // Its native-list parser can return zero despite count=1. A zero from
        // name->id is also ambiguous (component zero or unavailable). Request
        // only the single advertised OEM component and require start acceptance;
        // never select a fallback for an absent or ambiguous advertisement.
        if (received == 0 && count == 1 && backend instanceof LookupBackend) {
            String name = "RouteGuidanceComponent0";
            int id = ((LookupBackend)backend).componentId(name);
            boolean reviewed = id == 0 && backend instanceof ReviewedOemBackend
                    && ((ReviewedOemBackend)backend).canonicalFallbackAllowed();
            if ((id > 0 && id <= 65535) || (id == 0 && reviewed)) {
                ids[0] = id;
                names[0] = name;
                received = 1;
            }
        }
        if (received <= 0 || received > count) return false;
        for (int i = 0; i < received; i++) {
            if (ids[i] < 0 || ids[i] > 65535 || names[i] == null
                    || names[i].length() == 0 || names[i].length() > 128) return false;
            for (int j = 0; j < i; j++) if (ids[j] == ids[i] || names[j].equals(names[i])) return false;
        }
        String[] selected = Arrays.copyOf(names, received);
        if (!backend.start(selected)) return false;
        successfulEpoch = epoch;
        lastNames = selected;
        return true;
    }
    public synchronized Step step(long epoch, Backend backend) throws Exception {
        if (epoch < 0) return new Step(true, -1L, 0);
        if (confirmedEpoch == epoch) {
            pendingStartAfterStop = false;
            return new Step(true, -1L, retryCount);
        }
        if (recoveryEpoch != epoch) {
            recoveryEpoch = epoch;
            lastNames = null;
            retryCount = 0;
            pendingStartAfterStop = false;
        }
        if (successfulEpoch != epoch) {
            if (!ensure(epoch, backend)) return new Step(false, DISCOVERY_RETRY_MS, 0);
            return new Step(false, RETRY_BACKOFF_MS[0], 0);
        }
        if (pendingStartAfterStop) {
            pendingStartAfterStop = false;
            if (lastNames != null) backend.start(lastNames);
            long nextDelay = retryCount < RETRY_BACKOFF_MS.length ? RETRY_BACKOFF_MS[retryCount] : -1L;
            return new Step(nextDelay < 0, nextDelay, retryCount);
        }
        if (retryCount >= RETRY_BACKOFF_MS.length || lastNames == null) {
            return new Step(true, -1L, retryCount);
        }
        retryCount++;
        if (backend instanceof StopBackend) ((StopBackend) backend).stop(lastNames);
        pendingStartAfterStop = true;
        return new Step(false, STOP_TO_START_DELAY_MS, retryCount);
    }
}
