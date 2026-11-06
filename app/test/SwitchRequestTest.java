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
        check("writes all three", SwitchRequest.write(dir, "off", "on", "off", null, null, null)
                && read(target).equals("wireless=off\ntimer=on\nbluelink=off\n"));
        check("unknown values are left out", SwitchRequest.write(dir, "unknown", "off", "", null, null, null)
                && read(target).equals("timer=off\n"));
        check("injected text is never written", SwitchRequest.write(dir, "off\nrm -rf /", "on", null, null, null, null)
                && read(target).equals("timer=on\n"));
        check("a replaced file leaves no temp file", !new File(dir, "ui-request.tmp").exists());
        check("missing folder fails", !SwitchRequest.write(new File("no-such-dir-xyz"), "on", "on", "on", null, null, null));
        check("null folder fails", !SwitchRequest.write(null, "on", "on", "on", null, null, null));
        check("adb is written with its number", SwitchRequest.write(dir, null, null, null, "on:123456", null, null) && read(target).equals("adb=on:123456" + (char) 10));
        check("adb without a number is left out", SwitchRequest.write(dir, "on", null, null, "on", null, null) && read(target).equals("wireless=on" + (char) 10));
        check("adb with injected text is left out", SwitchRequest.write(dir, "on", null, null, "on:1\nrm", null, null) && read(target).equals("wireless=on" + (char) 10));
        check("save number is written", SwitchRequest.write(dir, "on", "on", "on", null, "1730000000", null)
                && read(target).equals("wireless=on\ntimer=on\nbluelink=on\nsave=1730000000\n"));
        check("a bad save number is left out", SwitchRequest.write(dir, "on", null, null, null, "12; rm", null) && read(target).equals("wireless=on\n"));
        check("a too long save number is left out", SwitchRequest.write(dir, "on", null, null, null, "12345678901", null) && read(target).equals("wireless=on\n"));
        check("remove number is written", SwitchRequest.write(dir, null, null, null, null, null, "42") && read(target).equals("remove=42" + (char) 10));
        check("a bad remove number is left out", SwitchRequest.write(dir, "on", null, null, null, null, "4 2; x") && read(target).equals("wireless=on" + (char) 10));
        target.delete();
        if (failures != 0) { System.out.println("== SwitchRequest: " + failures + " failed"); System.exit(1); }
        System.out.println("== SwitchRequest: all passed");
    }
}
