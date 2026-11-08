import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;
import kr.gen5w.ui.SwitchRequest;
import kr.gen5w.ui.StatusModel;

public final class RequestSafetyTest {
    static final String BOOT = "12345678-1234-1234-1234-123456789abc";
    static void check(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        File dir = Files.createTempDirectory("request-safety").toFile();
        File target = new File(dir, SwitchRequest.FILE);
        SwitchRequest.Writer writer = new SwitchRequest.Writer();
        long older = writer.issue(), newer = writer.issue();
        check(writer.write(newer, dir, 100, 130, BOOT, "on", "off", "on", null, null, null), "newest request writes");
        check(!writer.write(older, dir, 100, 130, BOOT, "off", "on", "on", null, null, null), "older execution cannot overwrite newer request");
        String saved = new String(Files.readAllBytes(target.toPath()), "UTF-8");
        check(saved.contains("wireless=on\ntimer=off\n") && saved.contains("boot=" + BOOT + "\n") && saved.contains("expires=130\n"), "latest state and bounded envelope reach collector");
        long expired = writer.issue();
        check(!writer.write(expired, dir, 131, 130, BOOT, "off", null, null, null, null, null), "expired queued work is discarded");
        check(!writer.write(expired, dir, 100, 131, BOOT, "off", null, null, null, null, null), "excessively future request is rejected");
        check(!writer.write(expired, dir, 100, 130, "bad\nboot", "off", null, null, null, null, null), "invalid boot identity is rejected");
        writer.close();
        check(!writer.write(writer.issue(), dir, 100, 130, BOOT, "off", null, null, null, null, null), "destroyed activity cannot publish delayed work");
        check(saved.equals(new String(Files.readAllBytes(target.toPath()), "UTF-8")), "rejected requests leave the last accepted file unchanged");
        StatusModel model = StatusModel.parse(Arrays.asList("ts=100", "boot=" + BOOT), null, 100);
        check(model.canControl(100), "fresh valid snapshot permits requests");
        check(!model.canControl(161), "snapshot ages at the moment of action, not only at parsing");
        check(!model.canControl(90), "future uptime is not accepted");
        check(!StatusModel.parse(Arrays.asList("ts=100"), null, 100).canControl(100), "legacy snapshot without boot identity cannot authorize requests");
        check("STOCK".equals(StatusModel.hudOwner(Arrays.asList("100 STOCK"), 105)), "fresh stock ownership stays visible");
        check("NO_RESPONSE".equals(StatusModel.hudOwner(Arrays.asList("100 CARPLAY"), 106)), "old idle ownership cannot imply a running HUD service");
        check("NO_RESPONSE".equals(StatusModel.hudOwner(Arrays.asList("110 CARPLAY"), 100)), "future HUD heartbeat is rejected");
        check("UNKNOWN".equals(StatusModel.hudOwner(Arrays.asList("100 UNKNOWN"), 100)), "fresh unknown ownership remains blocked");
        check("NO_RESPONSE".equals(StatusModel.hudOwner(Arrays.asList("100 forged"), 100)), "unexpected owner cannot imply readiness");
        Files.delete(target.toPath()); Files.delete(dir.toPath());
        System.out.println("PASS request ordering, freshness, boot envelope and lifecycle cancellation");
    }
}
