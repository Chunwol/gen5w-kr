package kr.gen5w.ui;

import android.content.Context;
import android.content.pm.PackageManager;
import android.content.res.Resources;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;

/** Read-only skin from the unit's installed Settings APK. No OEM files are shipped.
 * Names and fallback metrics are from Korean V039 GeneralSettings, not Hyundai's CI palette.
 * A missing package/resource falls back to our own drawing; never load OEM executable code.
 */
final class StockSkin {
    static final int WHITE = 0xffffffff, SUMMARY = 0xff888888, DISABLED = 0xff505050;
    static final int CYAN = 0xff00c2ff, SELECTED = 0xff2dc4f3, LINE = 0x26ffffff;
    static final int TOP = 0xff101114, BOTTOM = 0xff213152;
    private final Resources[] resources = new Resources[2];
    private static final String[] PACKAGES = {"com.android.generalsettings", "com.android.settings"};

    StockSkin(Context context) {
        for (int i = 0; i < PACKAGES.length; i++) {
            try { resources[i] = context.getPackageManager().getResourcesForApplication(PACKAGES[i]); }
            catch (PackageManager.NameNotFoundException | RuntimeException ignored) { }
        }
    }

    Drawable drawable(String name, Drawable fallback) {
        for (int i = 0; i < resources.length; i++) {
            if (resources[i] == null) continue;
            try {
                int id = resources[i].getIdentifier(name, "drawable", PACKAGES[i]);
                if (id != 0) return resources[i].getDrawable(id).mutate();
            } catch (Resources.NotFoundException ignored) { }
        }
        return fallback;
    }

    static Drawable rectangle(int top, int bottom, int edge) {
        GradientDrawable shape = new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] {top, bottom});
        shape.setCornerRadius(2);
        shape.setStroke(1, edge);
        return shape;
    }

    Drawable button() {
        StateListDrawable state = new StateListDrawable();
        state.addState(new int[] {-android.R.attr.state_enabled}, drawable("co_bg_box_disable", rectangle(0xff18191d, 0xff18191d, 0xff34363b)));
        state.addState(new int[] {android.R.attr.state_pressed}, drawable("co_btn_bg_push", rectangle(0xff424751, 0xff242a36, 0xff7c8490)));
        state.addState(new int[] {android.R.attr.state_focused}, drawable("co_bg_box_focus", rectangle(0xff303947, 0xff1a2230, CYAN)));
        state.addState(new int[] {}, drawable("co_btn_bg_nor", rectangle(0xff272a31, 0xff1a1c23, 0xff5b606a)));
        return state;
    }

    Drawable menu() {
        StateListDrawable state = new StateListDrawable();
        state.addState(new int[] {android.R.attr.state_pressed}, drawable("co_btn_bg_list_push", rectangle(0x405c91b4, 0x306287ab, LINE)));
        state.addState(new int[] {android.R.attr.state_selected}, drawable("co_btn_bg_list_sel", rectangle(0x001f3450, 0x80406d95, LINE)));
        state.addState(new int[] {android.R.attr.state_focused}, drawable("co_btn_bg_list_focus", rectangle(0x102d516a, 0x60406d95, CYAN)));
        state.addState(new int[] {}, new ColorDrawable(Color.TRANSPARENT));
        return state;
    }

    Drawable tab() {
        StateListDrawable state = new StateListDrawable();
        state.addState(new int[] {android.R.attr.state_pressed}, drawable("co_btn_bg_tab_push", rectangle(0x00334555, 0x80668799, LINE)));
        state.addState(new int[] {android.R.attr.state_selected}, drawable("co_btn_bg_tab_sel", rectangle(0x00204455, 0x805288aa, CYAN)));
        state.addState(new int[] {}, new ColorDrawable(Color.TRANSPARENT));
        return state;
    }
}
