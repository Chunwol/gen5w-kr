import java.io.File;
import java.nio.file.Files;
import kr.gen5w.ui.SwitchRequest;

public final class SwitchRequestTest {
    static int failures;
    static void check(String name, boolean ok) {
        if (ok) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name); }
    }
    static String read(File f) throws Exception { return new String(Files.readAllBytes(f.toPath()), "UTF-8"); }
    public static void main(String[] args) throws Exception {
        File dir = File.createTempFile("req", "dir"); dir.delete(); dir.mkdir(); dir.deleteOnExit();
        File target = new File(dir, "ui-request");
        check("writes all three", SwitchRequest.write(dir, "off", "on", "off")
                && read(target).equals("wireless=off\ntimer=on\nbluelink=off\n"));
        check("unknown values are left out", SwitchRequest.write(dir, "unknown", "off", "")
                && read(target).equals("timer=off\n"));
        check("injected text is never written", SwitchRequest.write(dir, "off\nrm -rf /", "on", null)
                && read(target).equals("timer=on\n"));
        check("a replaced file leaves no temp file", !new File(dir, "ui-request.tmp").exists());
        check("missing folder fails", !SwitchRequest.write(new File("no-such-dir-xyz"), "on", "on", "on"));
        check("null folder fails", !SwitchRequest.write(null, "on", "on", "on"));
        target.delete();
        if (failures != 0) { System.out.println("== SwitchRequest: " + failures + " failed"); System.exit(1); }
        System.out.println("== SwitchRequest: all passed");
    }
}
