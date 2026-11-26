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
        SwitchRequest.Writer writer = new SwitchRequest.Writer();
        long seq = writer.issue();
        check("exclusive fresh debug command", writer.writeDebug(seq, dir, 10, 30,
                "12345678-1234-1234-1234-123456789abc", true)
                && read(target).equals("boot=12345678-1234-1234-1234-123456789abc\nexpires=30\ndebug=on\n"));
        for (String key : new String[] { "cp_split", "aa_split", "cp_enable", "aa_enable", "cp_rhd" }) {
            long s = writer.issue();
            check("projection key " + key, writer.writeProjection(s, dir, 10, 30,
                    "12345678-1234-1234-1234-123456789abc", key, true, "77")
                    && read(target).equals("boot=12345678-1234-1234-1234-123456789abc\nexpires=30\npp=" + key + ":on:77\n"));
        }
        check("invalid projection key rejected", !writer.writeProjection(writer.issue(), dir, 10, 30,
                "12345678-1234-1234-1234-123456789abc", "bogus", true, "77"));
        check("invalid projection token rejected", !writer.writeProjection(writer.issue(), dir, 10, 30,
                "12345678-1234-1234-1234-123456789abc", "cp_split", false, "77;rm"));
        check("expired projection envelope rejected", !writer.writeProjection(writer.issue(), dir, 31, 30,
                "12345678-1234-1234-1234-123456789abc", "cp_split", false, "78"));
        check("future projection envelope rejected", !writer.writeProjection(writer.issue(), dir, 10, 41,
                "12345678-1234-1234-1234-123456789abc", "cp_split", false, "79"));
        long staleSeq = writer.issue();
        writer.issue();
        check("stale projection sequence rejected", !writer.writeProjection(staleSeq, dir, 10, 30,
                "12345678-1234-1234-1234-123456789abc", "cp_split", true, "80"));
        writer.close();
        check("closed writer projection rejected", !writer.writeProjection(writer.issue(), dir, 10, 30,
                "12345678-1234-1234-1234-123456789abc", "cp_split", true, "81"));
        target.delete();
        if (failures != 0) { System.out.println("== SwitchRequest: " + failures + " failed"); System.exit(1); }
        System.out.println("== SwitchRequest: all passed");
    }
}
