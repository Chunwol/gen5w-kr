import kr.gen5w.core.StockFlag;

public final class StockFlagTest {
    static final class Table implements StockFlag.Rows {
        final int columns; final String[] cells; int at = -1;
        Table(int columns, String... cells) { this.columns = columns; this.cells = cells; }
        public int columns() { return columns; }
        public boolean next() { return ++at < cells.length; }
        public boolean isNull() { return cells[at] == null; }
        public String text() { return cells[at]; }
    }
    static int failures;
    static void check(String name, int expected, StockFlag.Rows rows) {
        int got = StockFlag.decode(rows);
        if (got == expected) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name + " expected " + (char)expected + " got " + (char)got); }
    }
    public static void main(String[] args) {
        check("no result is unknown", '?', null);
        check("no rows is unknown", '?', new Table(1));
        check("two columns are unknown", '?', new Table(2, "1"));
        check("zero columns are unknown", '?', new Table(0, "1"));
        check("single idle row", '0', new Table(1, "0"));
        check("single active row", '1', new Table(1, "1"));
        check("all idle rows stay idle", '0', new Table(1, "0", "0", "0"));
        check("an active row after idle rows wins", '1', new Table(1, "0", "0", "1"));
        check("active row stops reading", '1', new Table(1, "1", null));
        check("null cell is unknown", '?', new Table(1, (String)null));
        check("null after idle is unknown", '?', new Table(1, "0", null));
        check("unexpected text is unknown", '?', new Table(1, "2"));
        check("empty text is unknown", '?', new Table(1, ""));
        check("whitespace padded text is unknown", '?', new Table(1, " 1"));
        check("text after idle rows must still be valid", '?', new Table(1, "0", "x"));
        String[] many = new String[33]; java.util.Arrays.fill(many, "0");
        check("33 rows are refused", '?', new Table(1, many));
        String[] limit = new String[32]; java.util.Arrays.fill(limit, "0");
        check("32 rows are accepted", '0', new Table(1, limit));
        if (failures != 0) { System.out.println("== StockFlag: " + failures + " failed"); System.exit(1); }
        System.out.println("== StockFlag: all passed");
    }
}
