package kr.gen5w.ui;

import android.content.Context;
import android.view.ContextThemeWrapper;
import android.widget.CheckBox;

/** Controls styled by the installed framework without bundling OEM artwork. */
final class Widgets {
    private Widgets() { }

    /** HKMC WifiHotspot uses a CheckBox under Theme.NoTitleBar, not SlideSwitch. */
    static final class Toggle extends CheckBox {
        Toggle(Context c) {
            super(new ContextThemeWrapper(c, android.R.style.Theme_NoTitleBar));
            setClickable(false); // the row owns requests and disabled-state gating
            setFocusable(false);
            setDuplicateParentStateEnabled(true);
        }

        void set(boolean on, boolean enabled) {
            setChecked(on);
            setEnabled(enabled);
        }
    }
}
