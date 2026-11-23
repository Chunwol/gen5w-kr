package kr.gen5w.hud;

/** Starts the shared OEM Now Playing feed once accepted for this connection.
 * Never stops it: the stock DiPO/INFO consumers share the native subscription.
 */
public final class MediaSubscription {
    public interface Backend { boolean start() throws Exception; }
    private long acceptedEpoch = -1;
    public boolean ensure(long epoch, Backend backend) throws Exception {
        if (epoch < 0) return false;
        if (acceptedEpoch == epoch) return true;
        if (!backend.start()) return false;
        acceptedEpoch = epoch;
        return true;
    }
}
