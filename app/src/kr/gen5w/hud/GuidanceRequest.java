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
    private long successfulEpoch = -1;
    public boolean ensure(long epoch, Backend backend) throws Exception {
        if (epoch < 0) return false;
        if (successfulEpoch == epoch) return true;
        int count = backend.count();
        if (count <= 0 || count > 16) return false;
        int[] ids = new int[count]; Arrays.fill(ids,-1);
        String[] names = new String[count];
        int received = backend.components(ids,names);
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
