package kr.gen5w.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;

/** Small drawn controls (no image files in this build): toggle switch. */
final class Widgets {
    private Widgets() { }

    /** A switch: rounded track with a round thumb. Size comes from the layout (about 76 x 42 dp). */
    static final class Toggle extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF rect = new RectF();
        private boolean on, enabled = true;
        private int onColor, offColor, thumbOn, thumbOff;

        Toggle(Context c, int onColor, int offColor, int thumbOn, int thumbOff) {
            super(c);
            this.onColor = onColor; this.offColor = offColor; this.thumbOn = thumbOn; this.thumbOff = thumbOff;
        }

        void set(boolean on, boolean enabled) { this.on = on; this.enabled = enabled; invalidate(); }

        @Override protected void onDraw(Canvas canvas) {
            float w = getWidth(), h = getHeight();
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(on ? onColor : offColor);
            paint.setAlpha(enabled ? 255 : 110);
            rect.set(0, 0, w, h);
            canvas.drawRoundRect(rect, h / 2, h / 2, paint);
            float r = h / 2 - h * 0.14f;
            float cx = on ? w - h / 2 : h / 2;
            paint.setColor(on ? thumbOn : thumbOff);
            paint.setAlpha(enabled ? 255 : 140);
            canvas.drawCircle(cx, h / 2, r, paint);
        }
    }
}
