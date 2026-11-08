package kr.gen5w.ui;

import android.app.Instrumentation;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.List;

/** Exercises the real UI on Android. Only OEM service I/O is replaced by fixtures. */
public final class UiProbe extends Instrumentation {
    private Activity activity;
    private File output;
    private final List<String> failures = new ArrayList<String>();
    private String scenario;
    private boolean requireNative;
    private boolean captureOnly;

    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        scenario = args == null ? "normal" : args.getString("scenario", "normal");
        requireNative = args != null && "yes".equals(args.getString("native"));
        captureOnly = args != null && "yes".equals(args.getString("capture-only"));
        start();
    }
    private void check(String name, boolean condition) {
        if (captureOnly) return;
        if (!condition) failures.add(name);
        Bundle message = new Bundle();
        message.putString("stream", (condition ? "PASS " : "FAIL ") + name + "\n");
        sendStatus(0, message);
    }
    private void write(File file, String text) throws Exception {
        FileOutputStream stream = new FileOutputStream(file);
        try { stream.write(text.getBytes("UTF-8")); } finally { stream.close(); }
    }
    private TextView text(View root, String value) {
        if (root instanceof TextView && value.contentEquals(((TextView) root).getText())) return (TextView) root;
        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) {
                TextView found = text(group.getChildAt(i), value);
                if (found != null) return found;
            }
        }
        return null;
    }
    private int clocks(View root) {
        int count = root instanceof android.widget.TextClock ? 1 : 0;
        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) count += clocks(group.getChildAt(i));
        }
        return count;
    }
    private View clickTarget(TextView label) {
        View target = label;
        while (target != null && !target.isClickable() && target.getParent() instanceof View) target = (View) target.getParent();
        return target;
    }
    private TextView clickableText(View root, String value) {
        if (root instanceof TextView && root.isClickable() && value.contentEquals(((TextView) root).getText())) return (TextView) root;
        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) {
                TextView found = clickableText(group.getChildAt(i), value);
                if (found != null) return found;
            }
        }
        return null;
    }
    private void click(final String label) {
        runOnMainSync(new Runnable() { public void run() {
            TextView view = clickableText(activity.getWindow().getDecorView(), label);
            if (view == null) view = text(activity.getWindow().getDecorView(), label);
            check("control exists: " + label, view != null);
            if (view != null) clickTarget(view).performClick();
        }});
        waitForIdleSync(); SystemClock.sleep(250);
    }
    private void capture(final String name) {
        runOnMainSync(new Runnable() { public void run() {
            View root = activity.findViewById(android.R.id.content);
            Bitmap bitmap = Bitmap.createBitmap(root.getWidth(), root.getHeight(), Bitmap.Config.ARGB_8888);
            root.draw(new Canvas(bitmap));
            save(bitmap, name);
        }});
    }
    private void save(Bitmap bitmap, String name) {
        try {
            FileOutputStream stream = new FileOutputStream(new File(output, name + ".png"));
            try { bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream); } finally { stream.close(); }
        } catch (Exception e) { throw new RuntimeException(e); }
    }
    private Widgets.Toggle newToggle() {
        try {
            java.lang.reflect.Constructor<?> constructor;
            try {
                constructor = Widgets.Toggle.class.getDeclaredConstructor(android.content.Context.class);
                constructor.setAccessible(true);
                return (Widgets.Toggle) constructor.newInstance(activity);
            } catch (NoSuchMethodException oldUi) {
                constructor = Widgets.Toggle.class.getDeclaredConstructor(android.content.Context.class, int.class, int.class, int.class, int.class);
                constructor.setAccessible(true);
                return (Widgets.Toggle) constructor.newInstance(activity, 0xff00aad2, Color.BLACK, Color.WHITE, 0xffaacae6);
            }
        } catch (Exception e) { throw new RuntimeException(e); }
    }
    private Widgets.Toggle firstToggle(View root) {
        if (root instanceof Widgets.Toggle) return (Widgets.Toggle) root;
        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) {
                Widgets.Toggle found = firstToggle(group.getChildAt(i));
                if (found != null) return found;
            }
        }
        return null;
    }
    private void compareControls() throws Exception {
        android.content.res.Resources resources;
        try { resources = activity.getPackageManager().getResourcesForApplication("com.android.generalsettings"); }
        catch (android.content.pm.PackageManager.NameNotFoundException e) {
            if (requireNative) check("required native reference is installed", false);
            else { Bundle message = new Bundle(); message.putString("stream", "SKIP native pixel comparison: fallback-only environment\n"); sendStatus(0, message); }
            return;
        }
        Bitmap board = Bitmap.createBitmap(560, 480, Bitmap.Config.ARGB_8888);
        Canvas sheet = new Canvas(board); sheet.drawColor(0xff101114);
        Paint captions = new Paint(Paint.ANTI_ALIAS_FLAG); captions.setColor(Color.WHITE); captions.setTextSize(18);
        sheet.drawText("V039 reference", 20, 24, captions); sheet.drawText("Our widget", 300, 24, captions);
        for (int i = 0; i < 4; i++) {
            boolean on = i != 1, enabled = i < 2 || i == 3, pressed = i == 3;
            String name = on ? enabled ? "co_bg_switch_on" : "co_bg_switch_on_dis" : "co_bg_switch_off";
            Drawable track = resources.getDrawable(resources.getIdentifier(name, "drawable", "com.android.generalsettings"));
            Drawable handle = resources.getDrawable(resources.getIdentifier("co_bt_switch", "drawable", "com.android.generalsettings"));
            Bitmap expected = Bitmap.createBitmap(120, 44, Bitmap.Config.ARGB_8888);
            Canvas reference = new Canvas(expected);
            track.setBounds(0, 0, 120, 44); track.draw(reference);
            handle.setState(pressed ? new int[] {android.R.attr.state_enabled, android.R.attr.state_pressed} : enabled ? new int[] {android.R.attr.state_enabled} : new int[] {});
            handle.setBounds(on ? 60 : 0, 0, on ? 120 : 60, 44); handle.draw(reference);
            Widgets.Toggle toggle = newToggle();
            toggle.set(on, enabled); toggle.setPressed(pressed); toggle.layout(0, 0, 120, 44);
            Bitmap actual = Bitmap.createBitmap(120, 44, Bitmap.Config.ARGB_8888);
            toggle.draw(new Canvas(actual));
            int changed = 0;
            for (int y = 0; y < 44; y++) for (int x = 0; x < 120; x++) if (expected.getPixel(x, y) != actual.getPixel(x, y)) changed++;
            check("native switch pixels match for state " + i + " (different=" + changed + ")", changed == 0);
            sheet.save(); sheet.translate(20, 40 + i * 106); sheet.scale(2, 2); sheet.drawBitmap(expected, 0, 0, null); sheet.restore();
            sheet.save(); sheet.translate(300, 40 + i * 106); sheet.scale(2, 2); sheet.drawBitmap(actual, 0, 0, null); sheet.restore();
        }
        save(board, "controls-comparison");
    }
    @Override public void onStart() {
        try {
            File fixtures = new File(getTargetContext().getFilesDir(), "fixture"); fixtures.mkdirs();
            output = getTargetContext().getExternalFilesDir(null);
            if (!"unknown".equals(scenario)) write(new File(fixtures, "status"), "ts=" + SystemClock.elapsedRealtime()/1000
                + "\nhost=alive\nrelay=on\nwlan=present\nbackend=builtin\nversion=0.3.55\napguard=on\nwired="
                + ("locked".equals(scenario) ? "yes" : "no")
                + "\nsw_wireless=on\nsw_timer=off\nsw_bluelink=on\nsw_adb=off\nsaved=0:none\nremoved=0:none\n");
            write(new File(fixtures, "log"), "bridge|READY bridge: relay\nwireless|WAIT wireless: phone\ncore|FAIL test fixture\n");
            Intent intent = new Intent(getTargetContext(), MainActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity = startActivitySync(intent);
            waitForIdleSync(); SystemClock.sleep(800);
            runOnMainSync(new Runnable() { public void run() {
                check("SystemUI owns the clock; app does not duplicate it", clocks(activity.getWindow().getDecorView()) == 0);
                TextView menu = text(activity.getWindow().getDecorView(), "정보");
                float density = activity.getResources().getDisplayMetrics().density;
                check("native menu slot is 197dp rather than the child artwork width", Math.abs(((View) menu.getParent()).getWidth() - 197 * density) <= 1);
                TextView title = text(activity.getWindow().getDecorView(), "Gen5W KR");
                check("native title strip is 60dp high", Math.abs(((View) title.getParent()).getHeight() - 60 * density) <= 1);
            }});
            capture("info");
            click("켜기/끄기"); capture("switches");
            runOnMainSync(new Runnable() { public void run() {
                try { compareControls(); } catch (Exception e) { throw new RuntimeException(e); }
                // A pill has transparent corners; the OEM rectangular track must fill this point.
                Widgets.Toggle view = newToggle();
                view.set(true, true);
                view.layout(0, 0, 120, 44);
                Bitmap bitmap = Bitmap.createBitmap(120, 44, Bitmap.Config.ARGB_8888);
                view.draw(new Canvas(bitmap));
                save(bitmap, "toggle-on");
                check("rectangular switch fills near-corner rather than a pill cutout", Color.alpha(bitmap.getPixel(4, 5)) > 240);
                view.set(false, false);
                check("disabled toggle exposes disabled state to Android", !view.isEnabled());
                TextView summary = text(activity.getWindow().getDecorView(), "끄면 차 순정 10초 타이머로 돌아갑니다.");
                check("OEM summary is visibly subordinate to title", !"normal".equals(scenario) || summary != null && summary.getCurrentTextColor() == 0xff888888);
                if ("normal".equals(scenario) && !captureOnly) {
                    Widgets.Toggle first = firstToggle(activity.getWindow().getDecorView());
                    View row = (View) first.getParent();
                    Bitmap before = Bitmap.createBitmap(first.getWidth(), first.getHeight(), Bitmap.Config.ARGB_8888);
                    Bitmap after = Bitmap.createBitmap(first.getWidth(), first.getHeight(), Bitmap.Config.ARGB_8888);
                    first.draw(new Canvas(before));
                    row.setPressed(true);
                    first.draw(new Canvas(after));
                    check("pressing the whole row depresses the switch handle", !before.sameAs(after));
                    row.setPressed(false);
                }
                if (!"normal".equals(scenario)) {
                    Widgets.Toggle first = firstToggle(activity.getWindow().getDecorView());
                    View row = (View) first.getParent();
                    check("locked/unknown row and its switch are both disabled", !row.isEnabled() && !first.isEnabled());
                    check("locked/unknown row cannot emit an action", !row.performClick());
                }
            }});
            if ("normal".equals(scenario)) {
                click("무선 CarPlay / Android Auto");
                SystemClock.sleep(300);
                File request = new File(getTargetContext().getFilesDir(), "ui-request");
                // The filename is the production SwitchRequest contract, not a fake click counter.
                check("row click writes a real switch request", request.exists());
                java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(request));
                boolean switchedOff = false;
                try { for (String line; (line = reader.readLine()) != null;) if (line.equals("wireless=off")) switchedOff = true; }
                finally { reader.close(); }
                check("request contains the toggled state, not the old snapshot", switchedOff);
                capture("switches-clicked");
            }
            click("기록"); capture("log");
            click("관리"); capture("manage");
            if (!"unknown".equals(scenario)) {
                click("제거..."); capture("remove-confirm");
                click("취소");
                runOnMainSync(new Runnable() { public void run() {
                    check("cancel returns to the first removal confirmation", text(activity.getWindow().getDecorView(), "제거...") != null);
                }});
            } else {
                runOnMainSync(new Runnable() { public void run() {
                    check("unreadable snapshot prevents removal", !text(activity.getWindow().getDecorView(), "제거...").isEnabled());
                    check("unreadable snapshot prevents diagnosis requests", !text(activity.getWindow().getDecorView(), "저장").isEnabled());
                }});
            }
            click("English"); capture("manage-en");
            runOnMainSync(new Runnable() { public void run() {
                check("language changes real menu text", text(activity.getWindow().getDecorView(), "Manage") != null);
            }});
            Bundle result = new Bundle();
            result.putString("stream", captureOnly ? "CAPTURE ONLY; assertions not evaluated\n" : "UI failures=" + failures.size() + " " + failures + "\n");
            finish(failures.isEmpty() ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        } catch (Throwable e) {
            Bundle result = new Bundle(); result.putString("stream", android.util.Log.getStackTraceString(e));
            finish(Activity.RESULT_CANCELED, result);
        }
    }
}
