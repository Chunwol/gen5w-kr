package kr.gen5w.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;

/** Small drawn controls (no image files in this build): toggle switch, menu icons, status dot. */
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

    /** Line icons for the menu: 0 info, 1 switches, 2 log, 3 manage. */
    static final class Icon extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF rect = new RectF();
        private final int kind;
        private int color;

        Icon(Context c, int kind, int color) { super(c); this.kind = kind; this.color = color; }

        void setColor(int color) { this.color = color; invalidate(); }

        @Override protected void onDraw(Canvas canvas) {
            float s = Math.min(getWidth(), getHeight());
            paint.setColor(color);
            paint.setStrokeWidth(s * 0.085f);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStyle(Paint.Style.STROKE);
            float c = s / 2;
            if (kind == 0) {
                canvas.drawCircle(c, c, s * 0.40f, paint);
                canvas.drawLine(c, c - s * 0.02f, c, c + s * 0.20f, paint);
                paint.setStyle(Paint.Style.FILL);
                canvas.drawCircle(c, c - s * 0.19f, s * 0.05f, paint);
            } else if (kind == 1) {
                rect.set(s * 0.08f, s * 0.28f, s * 0.92f, s * 0.72f);
                canvas.drawRoundRect(rect, s * 0.22f, s * 0.22f, paint);
                paint.setStyle(Paint.Style.FILL);
                canvas.drawCircle(s * 0.69f, c, s * 0.12f, paint);
            } else if (kind == 2) {
                for (int i = 0; i < 3; i++) {
                    float y = s * (0.27f + 0.23f * i);
                    canvas.drawLine(s * 0.36f, y, s * 0.90f, y, paint);
                    paint.setStyle(Paint.Style.FILL);
                    canvas.drawCircle(s * 0.14f, y, s * 0.05f, paint);
                    paint.setStyle(Paint.Style.STROKE);
                }
            } else {
                canvas.drawCircle(c, c, s * 0.15f, paint);
                for (int i = 0; i < 8; i++) {
                    double a = Math.PI / 4 * i;
                    float cos = (float) Math.cos(a), sin = (float) Math.sin(a);
                    canvas.drawLine(c + cos * s * 0.27f, c + sin * s * 0.27f, c + cos * s * 0.40f, c + sin * s * 0.40f, paint);
                }
                canvas.drawCircle(c, c, s * 0.27f, paint);
            }
        }
    }

    /** A filled round status dot. */
    static final class Dot extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int color;

        Dot(Context c, int color) { super(c); this.color = color; }

        @Override protected void onDraw(Canvas canvas) {
            float s = Math.min(getWidth(), getHeight());
            float cx = getWidth() / 2f, cy = getHeight() / 2f;
            paint.setColor(color);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(s * 0.09f);
            canvas.drawCircle(cx, cy, s / 2 - s * 0.05f, paint);
            paint.setStyle(Paint.Style.FILL);
            canvas.drawCircle(cx, cy, s * 0.26f, paint);
        }
    }
}
