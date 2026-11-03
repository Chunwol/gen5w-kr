import java.io.IOException;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import kr.gen5w.hotspot.ApBrokerCancellation;

public final class ApBrokerCancellationTest {
    public static void main(String[] args) throws Exception {
        PipedInputStream in = new PipedInputStream();
        PipedOutputStream out = new PipedOutputStream(in);
        ApBrokerCancellation guard = new ApBrokerCancellation(in);
        guard.check();
        out.close();
        long deadline = System.currentTimeMillis() + 2000;
        boolean cancelled = false;
        while (System.currentTimeMillis() < deadline) {
            try { guard.check(); } catch (IOException e) { cancelled = true; break; }
            Thread.sleep(10);
        }
        if (!cancelled) throw new AssertionError("client disconnect did not cancel AP request");
        in.close();
        System.out.println("ApBrokerCancellationTest passed");
    }
}
