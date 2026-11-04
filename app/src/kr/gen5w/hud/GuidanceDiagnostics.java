package kr.gen5w.hud;

import java.util.List;
import java.util.Locale;
import kr.gen5w.probe.Item;

/** Numeric-only route diagnostics. Source strings and route text are never logged. */
public final class GuidanceDiagnostics {
    public static final int SOURCE_UNKNOWN = 0;
    public static final int SOURCE_NAVER = 1;
    public static final int SOURCE_TMAP = 2;
    public static final int SOURCE_KAKAO = 3;
    public static final int SOURCE_APPLE = 4;
    public static final int SOURCE_OTHER = 9;

    private GuidanceDiagnostics() {}

    public static int sourceCode(String source) {
        if (source == null || source.trim().isEmpty()) return SOURCE_UNKNOWN;
        String value = source.toLowerCase(Locale.ROOT);
        if (contains(value, "naver", "nhn", "네이버")) return SOURCE_NAVER;
        if (contains(value, "tmap", "t map", "skt", "티맵")) return SOURCE_TMAP;
        if (contains(value, "kakao", "locnall", "카카오")) return SOURCE_KAKAO;
        if (contains(value, "apple maps", "com.apple.maps", "애플 지도")) return SOURCE_APPLE;
        return SOURCE_OTHER;
    }

    /** Bit n means field id n was present. Unknown ids are intentionally omitted. */
    public static long fieldMask(List<Item> fields) {
        if (fields == null) return 0;
        long mask = 0;
        for (Item item : fields) {
            if (item != null && item.id >= 0 && item.id < 63) mask |= 1L << item.id;
        }
        return mask;
    }

    private static boolean contains(String value, String... candidates) {
        for (String candidate : candidates) if (value.contains(candidate)) return true;
        return false;
    }
}
