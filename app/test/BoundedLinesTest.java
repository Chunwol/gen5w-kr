import java.io.File;
import java.io.FileOutputStream;
import java.util.List;
import kr.gen5w.ui.BoundedLines;

public final class BoundedLinesTest {
    static int failures;
    static void check(String name, boolean ok) {
        if (ok) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name); }
    }
    static File file(byte[] bytes) throws Exception {
        File f = File.createTempFile("bounded", ".txt");
        f.deleteOnExit();
        FileOutputStream out = new FileOutputStream(f);
        out.write(bytes);
        out.close();
        return f;
    }
    static byte[] text(String s) throws Exception { return s.getBytes("UTF-8"); }
    public static void main(String[] args) throws Exception {
        check("missing file is null", BoundedLines.read(new File("no-such-file-xyz"), 100, 10) == null);
        check("null file is null", BoundedLines.read(null, 100, 10) == null);
        File dir = File.createTempFile("bounded", "dir"); dir.delete(); dir.mkdir(); dir.deleteOnExit();
        check("a directory is null", BoundedLines.read(dir, 100, 10) == null);
        check("empty file is an empty list", BoundedLines.read(file(new byte[0]), 100, 10).size() == 0);

        List<String> two = BoundedLines.read(file(text("a=1\nb=2\n")), 100, 10);
        check("trailing newline adds no empty line", two.size() == 2 && two.get(0).equals("a=1") && two.get(1).equals("b=2"));
        List<String> crlf = BoundedLines.read(file(text("x\r\ny")), 100, 10);
        check("CR is stripped and a last line without newline is kept", crlf.size() == 2 && crlf.get(0).equals("x") && crlf.get(1).equals("y"));
        check("Korean text survives", BoundedLines.read(file(text("한국어|줄\n")), 100, 10).get(0).equals("한국어|줄"));

        StringBuilder many = new StringBuilder();
        for (int i = 0; i < 500; i++) many.append("line ").append(i).append('\n');
        List<String> cut = BoundedLines.read(file(text(many.toString())), 1 << 20, 300);
        check("at most 300 lines", cut.size() == 300 && cut.get(299).equals("line 299"));

        StringBuilder big = new StringBuilder();
        for (int i = 0; i < 100000; i++) big.append('a');
        List<String> bytes = BoundedLines.read(file(text(big.toString())), 65536, 300);
        check("reads at most the byte limit", bytes.size() == 1 && bytes.get(0).length() == 65536);

        List<String> bad = BoundedLines.read(file(new byte[] {(byte) 0xff, (byte) 0xfe, 'o', 'k', '\n'}), 100, 10);
        check("invalid UTF-8 does not throw", bad.size() == 1 && bad.get(0).endsWith("ok"));
        check("zero line limit gives an empty list", BoundedLines.read(file(text("a\n")), 100, 0).size() == 0);
        if (failures != 0) { System.out.println("== BoundedLines: " + failures + " failed"); System.exit(1); }
        System.out.println("== BoundedLines: all passed");
    }
}
