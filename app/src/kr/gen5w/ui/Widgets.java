package kr.gen5w.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.drawable.Drawable;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;

/** Stock-shaped controls, reusing installed OEM artwork without shipping it. */
final class Widgets {
    private Widgets() { }

    /** V039 SlideSwitch: ON/OFF track and a rectangular half-width sliding handle. */
    static final class Toggle extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private boolean on;
        private final Drawable trackOn, trackOff, trackDisabled, handle;

        Toggle(Context c) {
            super(c);
            StockSkin skin = new StockSkin(c);
            trackOn = skin.drawable("co_bg_switch_on", StockSkin.rectangle(0xff4c0909, 0xff7b1619, 0xff080808));
            trackOff = skin.drawable("co_bg_switch_off", StockSkin.rectangle(0xff232323, 0xff363636, 0xff080808));
            trackDisabled = skin.drawable("co_bg_switch_on_dis", StockSkin.rectangle(0xff232323, 0xff303030, 0xff080808));
            android.graphics.drawable.StateListDrawable fallback = new android.graphics.drawable.StateListDrawable();
            fallback.addState(new int[] {android.R.attr.state_pressed}, StockSkin.rectangle(0xff080808, 0xff222222, 0xff080808));
            fallback.addState(new int[] {}, StockSkin.rectangle(0xff363636, 0xff252525, 0xff777777));
            handle = skin.drawable("co_bt_switch", fallback);
        }

        void set(boolean on, boolean enabled) {
            this.on = on;
            setEnabled(enabled);
            setContentDescription(on ? "ON" : "OFF");
            invalidate();
        }

        @Override public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info) {
            super.onInitializeAccessibilityNodeInfo(info);
            info.setClassName("android.widget.Switch");
            info.setCheckable(true);
            info.setChecked(on);
        }

        @Override protected void onDraw(Canvas canvas) {
            float w = getWidth(), h = getHeight();
            Drawable track = on ? isEnabled() ? trackOn : trackDisabled : trackOff;
            track.setBounds(0, 0, (int) w, (int) h);
            track.draw(canvas);
            // Native backgrounds contain their own ON/OFF lettering. Only our fallback needs text.
            if (track instanceof android.graphics.drawable.GradientDrawable) {
                paint.setColor(isEnabled() && on ? 0xffeeeeee : 0xff777777);
                paint.setTypeface(android.graphics.Typeface.create("sans-serif-light", 0));
                paint.setTextSize(h * .49f);
                paint.setTextAlign(Paint.Align.CENTER);
                canvas.drawText(on ? "ON" : "OFF", w * (on ? .25f : .75f), h * .69f, paint);
            }
            int left = on ? (int) w / 2 : 0;
            Drawable thumb = handle;
            thumb.setState(getDrawableState());
            thumb.setBounds(left, 0, left + (int) w / 2, (int) h);
            thumb.draw(canvas);
        }
    }
}
