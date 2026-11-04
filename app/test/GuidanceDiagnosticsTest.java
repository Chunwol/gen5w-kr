import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.List;
import kr.gen5w.probe.Item;

public final class GuidanceDiagnosticsTest {
    private static int checks;
    private static void eq(String label, long got, long want) {
        checks++;
        if (got != want) throw new AssertionError(label + ": " + got + " != " + want);
    }
    private static Item n(int id) { Item item = new Item(); item.id = id; item.ints = new int[]{1}; return item; }
    public static void main(String[] args) throws Exception {
        Class<?> type = Class.forName("kr.gen5w.hud.GuidanceDiagnostics");
        Method sourceCode = type.getMethod("sourceCode", String.class);
        Method fieldMask = type.getMethod("fieldMask", List.class);

        eq("missing source", ((Integer)sourceCode.invoke(null, new Object[]{null})).intValue(), 0);
        eq("naver bundle", ((Integer)sourceCode.invoke(null, "com.nhncorp.NaverMap")).intValue(), 1);
        eq("tmap display name", ((Integer)sourceCode.invoke(null, "T map")).intValue(), 2);
        eq("kakao bundle", ((Integer)sourceCode.invoke(null, "com.locnall.kimgisa")).intValue(), 3);
        eq("apple maps", ((Integer)sourceCode.invoke(null, "Apple Maps")).intValue(), 4);
        eq("unknown source", ((Integer)sourceCode.invoke(null, "another.navigation")).intValue(), 9);

        List<Item> fields = Arrays.asList(n(0), n(3), n(4), n(11), n(63), n(-1));
        long want = (1L << 0) | (1L << 3) | (1L << 4) | (1L << 11);
        eq("field presence mask", ((Long)fieldMask.invoke(null, fields)).longValue(), want);
        eq("missing fields", ((Long)fieldMask.invoke(null, new Object[]{null})).longValue(), 0);
        System.out.println("PASS GuidanceDiagnosticsTest " + checks);
    }
}
