package kr.gen5w.hud;

import java.util.Arrays;

/** Native route-component discovery and one successful shared request per link.
 * No stop operation: stopping the shared stream could disrupt stock consumers.
 * Serialized by the caller, independent of Android for JVM verification.
 */
public final class GuidanceRequest {
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
    public static boolean reviewedCanonicalProfile(String product) {
        if (product == null) return false;
        // Shared V039 policy: model, market and build date do not restrict this fallback.
        for (String part : product.split("\\.", -1)) {
            if ("V039".equals(part)) return true;
        }
        return false;
    }
    private long successfulEpoch = -1;
    public boolean ensure(long epoch, Backend backend) throws Exception {
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
        if (!backend.start(Arrays.copyOf(names,received))) return false;
        successfulEpoch = epoch;
        return true;
    }
}
