package kr.gen5w.core;

/** Decodes the one OEM navigation flag. Free of Android types so it can be unit tested. */
public final class StockFlag {
    /** The rows of a one-column result. */
    public interface Rows {
        int columns();
        boolean next();
        boolean isNull();
        String text();
    }

    private StockFlag() { }

    /** '1' guidance active, '0' idle, '?' unknown. Anything unexpected is unknown. */
    public static int decode(Rows rows) {
        if (rows == null || rows.columns() != 1) return '?';
        int count = 0;
        while (rows.next()) {
            if (++count > 32 || rows.isNull()) return '?';
            String state = rows.text();
            if ("1".equals(state)) return '1';
            if (!"0".equals(state)) return '?';
        }
        return count > 0 ? '0' : '?';
    }
}
