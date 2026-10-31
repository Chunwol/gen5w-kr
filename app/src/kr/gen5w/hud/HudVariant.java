package kr.gen5w.hud;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/** Reads a stock configuration value; it cannot establish physical display operation. */
public final class HudVariant {
    private HudVariant() { }

    public static String inspect(Class<?> variantType, Class<?> codesType) {
        try {
            if (variantType == null || codesType == null) return "UNKNOWN";
            int variant = staticInt(variantType, "VARIANT_HUD");
            int on = staticInt(codesType, "ON");
            int off = staticInt(codesType, "OFF");
            int unknown = staticInt(codesType, "UNKNOWN");
            if (variant != 11 || on != 1 || off != 0 || unknown != -1) return "UNKNOWN";
            Method getter = variantType.getMethod("getVariantCode", Integer.TYPE);
            if (!Modifier.isStatic(getter.getModifiers()) || getter.getReturnType() != Integer.TYPE) return "UNKNOWN";
            int value = ((Integer) getter.invoke(null, Integer.valueOf(variant))).intValue();
            return value == on ? "CONFIG_ON" : value == off ? "CONFIG_OFF" : "UNKNOWN";
        } catch (Exception e) { return "UNKNOWN"; }
          catch (LinkageError e) { return "UNKNOWN"; }
    }

    private static int staticInt(Class<?> type, String name) throws Exception {
        Field field = type.getField(name);
        if (!Modifier.isStatic(field.getModifiers()) || field.getType() != Integer.TYPE) throw new IllegalArgumentException();
        return field.getInt(null);
    }
}
