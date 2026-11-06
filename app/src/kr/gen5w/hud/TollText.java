package kr.gen5w.hud;

/** Diagnostic reading of the toll amount that map apps append to the guidance text (no structured toll field exists). */
public final class TollText {
    private static final String[] TOKENS = {"요금", "통행료"};
    private TollText() {}

    public static boolean mentionsToll(String text) {
        if (text == null) return false;
        for (String token : TOKENS) if (text.indexOf(token) >= 0) return true;
        return false;
    }

    /** First number after a toll token ("요금: 1,200원" gives 1200), or -1. */
    public static long amount(String text) {
        if (text == null) return -1;
        for (String token : TOKENS) {
            int at = text.indexOf(token);
            if (at < 0) continue;
            long value = -1;
            int digits = 0;
            for (int i = at + token.length(); i < text.length() && digits < 10; i++) {
                char c = text.charAt(i);
                if (c >= '0' && c <= '9') { value = (value < 0 ? 0 : value) * 10 + (c - '0'); digits++; }
                else if (c == ',' && digits > 0) continue;
                else if (digits > 0) break;
                else if (i - (at + token.length()) > 8) break;
            }
            if (value >= 0) return value;
        }
        return -1;
    }
}
