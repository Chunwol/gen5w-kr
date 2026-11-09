import java.util.Arrays;
import kr.gen5w.ui.RecoveryStatus;
import kr.gen5w.ui.SwitchRequest;
import java.nio.file.Files;
import java.io.File;
public final class RecoveryStatusTest {
    static void check(boolean yes) { if (!yes) throw new AssertionError("unsafe recovery state/request"); }
    public static void main(String[] args) throws Exception {
        check(!RecoveryStatus.parse(null).canRequest(true));
        RecoveryStatus r = RecoveryStatus.parse(Arrays.asList("recovery_state=required", "recovery_available=yes", "recovery_reason=ready"));
        check(r.canRequest(true)); check(!r.canRequest(false));
        check(!RecoveryStatus.parse(Arrays.asList("recovery_state=working", "recovery_available=yes")).canRequest(true));
        check(!RecoveryStatus.parse(Arrays.asList("recovery_state=required", "recovery_state=none", "recovery_available=yes")).canRequest(true));
        check("unknown".equals(RecoveryStatus.parse(Arrays.asList("recovery_state=garbage")).state()));
        File dir=Files.createTempDirectory("recovery-request").toFile();
        SwitchRequest.Writer writer=new SwitchRequest.Writer();
        check(writer.writeRecovery(writer.issue(),dir,10,30,"12345678-1234-1234-1234-123456789abc","123"));
        String text=new String(Files.readAllBytes(new File(dir,"ui-request").toPath()),"UTF-8");
        check(text.contains("recovery=123\n")); check(!text.contains("wireless=")); check(!text.contains("remove="));
        check(!writer.writeRecovery(writer.issue(),dir,10,30,"12345678-1234-1234-1234-123456789abc","123\nremove=1"));
        System.out.println("PASS recovery unknown/duplicate/freshness/exclusive request");
    }
}
