import kr.gen5w.hud.HudVariant;

public final class HudVariantTest {
    public static final class Variant {
        public static final int VARIANT_HUD = 11;
        static int value;
        public static int getVariantCode(int type) {
            if (type != VARIANT_HUD) throw new AssertionError("wrong variant");
            return value;
        }
    }
    public static final class Codes {
        public static final int OFF = 0, ON = 1, UNKNOWN = -1;
    }
    public static final class WrongCodes {
        public static final int OFF = 1, ON = 1, UNKNOWN = -1;
    }
    public static final class Unavailable {
        public static final int VARIANT_HUD = 11;
        public static int getVariantCode(int type) { throw new IllegalStateException(); }
    }
    private static void check(boolean condition) {
        if (!condition) throw new AssertionError();
    }
    public static void main(String[] args) {
        Variant.value = 1;
        check("CONFIG_ON".equals(HudVariant.inspect(Variant.class, Codes.class)));
        Variant.value = 0;
        check("CONFIG_OFF".equals(HudVariant.inspect(Variant.class, Codes.class)));
        Variant.value = -1;
        check("UNKNOWN".equals(HudVariant.inspect(Variant.class, Codes.class)));
        Variant.value = 42;
        check("UNKNOWN".equals(HudVariant.inspect(Variant.class, Codes.class)));
        check("UNKNOWN".equals(HudVariant.inspect(Variant.class, WrongCodes.class)));
        check("UNKNOWN".equals(HudVariant.inspect(Unavailable.class, Codes.class)));
        check("UNKNOWN".equals(HudVariant.inspect(null, null)));
        System.out.println("HudVariantTest passed");
    }
}
