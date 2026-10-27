import kr.gen5w.probe.Dump;
import kr.gen5w.probe.Item;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** JVM test for Dump (no Android needed). Exit 1 on the first mismatch. */
public final class DumpTest {
    static int fails;

    static Item item(int id, int type) { Item i = new Item(); i.id = id; i.type = type; return i; }

    static void eq(String name, String got, String want) {
        if (!got.equals(want)) { System.out.println("FAIL " + name + "\n  got  " + got + "\n  want " + want); fails++; }
        else System.out.println("PASS " + name);
    }

    public static void main(String[] a) {
        Item s = item(0x13, 10); s.strings = new String[] {"Maps \"x\"\nnext"};
        Item n = item(0x2, 6); n.ints = new int[] {120};
        Item l = item(0x5, 7); l.longs = new long[] {1234567890123L};
        Item b = item(0x9, 11); b.bytes = new byte[] {0x01, (byte) 0xab};
        Item e = item(0xa, 12);
        eq("plain items", Dump.line(Arrays.asList(s, n, l, b, e)),
                "13:10=\"Maps \\\"x\\\" next\" 2:6=120 5:7=1234567890123 9:11=0x01ab a:12=-");

        Item g = item(0x10, 13);
        Item g1 = item(0x0, 5); g1.ints = new int[] {1};
        Item g2 = item(0x1, 10); g2.strings = new String[] {"A"};
        g.groups.add(new ArrayList<Item>(Arrays.asList(g1, g2)));
        Item g3 = item(0x0, 5); g3.ints = new int[] {2};
        g.groups.add(new ArrayList<Item>(Arrays.asList(g3)));
        eq("groups", Dump.line(Arrays.asList(g)), "10:13=[0:5=1 1:10=\"A\"][0:5=2]");

        Item many = item(0x1, 6); many.ints = new int[] {1, 2, 3};
        eq("int array", Dump.line(Arrays.asList(many)), "1:6=1,2,3");

        Item big = item(0x7, 11); big.bytes = new byte[200];
        String bl = Dump.line(Arrays.asList(big));
        eq("long blob cut", bl.substring(bl.length() - 5), "(200)");

        List<Item> lots = new ArrayList<Item>();
        for (int i = 0; i < 2000; i++) { Item x = item(i, 10); x.strings = new String[] {"abcdef"}; lots.add(x); }
        String cut = Dump.line(lots);
        eq("whole line capped", String.valueOf(cut.endsWith("...(cut)") && cut.length() <= 4008), "true");

        eq("empty", Dump.line(new ArrayList<Item>()), "");
        System.out.println(fails == 0 ? "dump all match" : fails + " failed");
        System.exit(fails == 0 ? 0 : 1);
    }
}
