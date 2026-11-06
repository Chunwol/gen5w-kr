package kr.gen5w.ui;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;

/**
 * Read-only status and log screen. It only reads the two files the collector service writes
 * (status and log in /data/nemesis/gen5wkr.ui, a root-owned folder) and changes nothing.
 * Built in code because the development build has no resource files.
 */
public final class MainActivity extends Activity {
    private static final int INFO = 0, ONOFF = 1, LOG = 2, MANAGE = 3;
    private static final String[] TABS = {"INFO", "ONOFF", "LOG", "관리"};
    private static final long REFRESH_MS = 5000;
    private static final String UI_DIR = "/data/nemesis/gen5wkr.ui";
    private static final int BG = 0xFF0B0E12, TOP = 0xFF14181E, SIDE = 0xFF10141A, SELECTED = 0xFF1A212B,
            ACCENT = 0xFF00AAD2, TEXT = 0xFFF2F4F6, DIM = 0xFF7D8896, GREEN = 0xFF3DDC84, YELLOW = 0xFFFFB020,
            RED = 0xFFFF5A5F, LINE = 0xFF222831;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final LinearLayout[] menuItems = new LinearLayout[TABS.length];
    private FrameLayout content;
    private int tab = INFO;
    private String categoryFilter = "all", sourceFilter = "all";
    private StatusModel model = StatusModel.unreadable();
    private List<String> logLines = new ArrayList<String>();
    private boolean loaded;
    private volatile boolean loading;
    private boolean resumed;

    private final Runnable tick = new Runnable() {
        public void run() {
            if (!resumed) return;
            load();
            handler.postDelayed(this, REFRESH_MS);
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        TextView title = label("Gen5W KR", 17, TEXT, true);
        title.setBackgroundColor(TOP);
        title.setPadding(dp(20), dp(12), dp(20), dp(12));
        root.addView(title, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout side = new LinearLayout(this);
        side.setOrientation(LinearLayout.VERTICAL);
        side.setBackgroundColor(SIDE);
        for (int i = 0; i < TABS.length; i++) {
            final int index = i;
            LinearLayout item = new LinearLayout(this);
            item.setGravity(Gravity.CENTER_VERTICAL);
            item.setPadding(dp(18), 0, dp(18), 0);
            item.addView(label(TABS[i], 15, DIM, false));
            item.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) { tab = index; render(); }
            });
            menuItems[i] = item;
            side.addView(item, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)));
        }
        body.addView(side, new LinearLayout.LayoutParams(dp(200), ViewGroup.LayoutParams.MATCH_PARENT));
        content = new FrameLayout(this);
        body.addView(content, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f));
        root.addView(body, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
        render();
    }

    @Override protected void onResume() {
        super.onResume();
        resumed = true;
        handler.removeCallbacks(tick);
        handler.post(tick);
    }

    @Override protected void onPause() {
        resumed = false;
        handler.removeCallbacks(tick);
        super.onPause();
    }

    /** Reads both files on a worker thread, then redraws. Overlapping reads are skipped. */
    private void load() {
        if (loading) return;
        loading = true;
        final File dir = new File(UI_DIR);
        new Thread(new Runnable() {
            public void run() {
                List<String> status = BoundedLines.read(new File(dir, "status"), 16 * 1024, 50);
                List<String> log = BoundedLines.read(new File(dir, "log"), 64 * 1024, 300);
                final StatusModel next = StatusModel.parse(status, log, SystemClock.elapsedRealtime() / 1000);
                final List<String> lines = log == null ? new ArrayList<String>() : log;
                handler.post(new Runnable() {
                    public void run() {
                        loading = false;
                        if (isFinishing()) return;
                        model = next; logLines = lines; loaded = true;
                        render();
                    }
                });
            }
        }, "gen5w-ui-read").start();
    }

    private void render() {
        for (int i = 0; i < menuItems.length; i++) {
            boolean on = i == tab;
            menuItems[i].setBackgroundColor(on ? SELECTED : SIDE);
            ((TextView) menuItems[i].getChildAt(0)).setTextColor(on ? TEXT : DIM);
            ((TextView) menuItems[i].getChildAt(0)).setTypeface(Typeface.DEFAULT, on ? Typeface.BOLD : Typeface.NORMAL);
        }
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(22), dp(8), dp(22), dp(16));
        if (tab == INFO) buildInfo(page);
        else if (tab == LOG) buildLog(page);
        else if (tab == ONOFF) note(page, "기능 켜기/끄기는 다음 버전에서 제공됩니다.\n지금 버전은 상태와 기록을 보기만 하고 아무것도 바꾸지 않습니다.");
        else note(page, "전체 제거는 아직 이 화면에서 지원하지 않습니다.\n제거는 설치 때 사용한 USB의 제거 키트로 하세요.");
        ScrollView scroll = new ScrollView(this);
        scroll.addView(page);
        content.removeAllViews();
        content.addView(scroll, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    }

    private void buildInfo(LinearLayout page) {
        if (!loaded) { note(page, "불러오는 중..."); return; }
        if (!model.readable()) {
            box(page, "상태를 읽을 수 없음", "상태 수집 서비스가 아직 실행되지 않았거나, 이 앱이 상태 폴더를 읽을 권한이 없을 수 있습니다. 잠시 뒤 다시 확인하고, 계속 이러면 진단을 저장해 주세요.", RED);
            return;
        }
        boolean stale = model.stale();
        if (stale) {
            long age = model.ageSeconds();
            box(page, "기록이 오래됨", age < 0 ? "이전 부팅 때의 기록입니다. 새 기록을 기다리는 중입니다." : "마지막 갱신이 " + age + "초 전입니다. 아래 값이 지금과 다를 수 있습니다.", YELLOW);
        } else if (model.why().length() > 0) {
            box(page, "무선 대기 중", model.why(), YELLOW);
        }
        section(page, "연결");
        String host = model.host();
        row(page, "무선 호스트", host.equals("alive") ? "● 실행 중" : host.equals("dead") ? "● 실행 안 됨" : "확인 못 함",
                stale ? DIM : host.equals("alive") ? GREEN : host.equals("dead") ? YELLOW : DIM);
        String relay = model.relay();
        row(page, "릴레이 구성", relay.equals("on") ? "● 포함됨" : relay.equals("off") ? "● 없음" : "확인 못 함",
                stale ? DIM : relay.equals("on") ? GREEN : relay.equals("off") ? YELLOW : DIM);
        row(page, "유선 전용 모드", model.wiredOnly() ? "켜짐" : "꺼짐", model.wiredOnly() ? YELLOW : TEXT);
        row(page, "재시작 보호", model.apguardOff() ? "● 걸림(무선 꺼짐)" : "● 정상", model.apguardOff() ? RED : stale ? DIM : GREEN);
        section(page, "설치");
        row(page, "설치 버전", model.bridgeVersion().length() > 0 ? "v" + model.bridgeVersion() : "확인 못 함", TEXT);
        String backend = model.backend();
        row(page, "Wi-Fi 방식", backend.equals("builtin") ? "내장 Wi-Fi" : backend.equals("dongle") ? "USB 동글" : "확인 못 함", TEXT);
    }

    private void buildLog(LinearLayout page) {
        if (!loaded) { note(page, "불러오는 중..."); return; }
        if (logLines.isEmpty()) { note(page, "표시할 기록이 없습니다."); return; }
        LinkedHashSet<String> sources = new LinkedHashSet<String>();
        for (String line : logLines) { int bar = line.indexOf('|'); if (bar > 0) sources.add(line.substring(0, bar)); }
        if (!sources.contains(sourceFilter)) sourceFilter = "all";
        LinearLayout categories = new LinearLayout(this);
        chip(categories, "전체", "all", true); chip(categories, "오류", "error", true);
        chip(categories, "무선", "wireless", true); chip(categories, "설치", "install", true);
        page.addView(categories);
        LinearLayout from = new LinearLayout(this);
        chip(from, "모든 출처", "all", false);
        for (String source : sources) chip(from, source, source, false);
        page.addView(from);
        int shown = 0;
        for (String line : logLines) {
            int bar = line.indexOf('|');
            String source = bar > 0 ? line.substring(0, bar) : "";
            String raw = bar > 0 ? line.substring(bar + 1) : line;
            if (!sourceFilter.equals("all") && !sourceFilter.equals(source)) continue;
            if (!categoryFilter.equals("all") && !categoryFilter.equals(LogTranslator.category(raw))) continue;
            String korean = LogTranslator.translate(raw);
            boolean error = LogTranslator.category(raw).equals("error");
            LinearLayout entry = new LinearLayout(this);
            entry.setOrientation(LinearLayout.VERTICAL);
            entry.setPadding(0, dp(6), 0, dp(6));
            entry.addView(label((source.length() > 0 ? "[" + source + "] " : "") + korean, 14, error ? RED : TEXT, false));
            if (!korean.equals(raw)) entry.addView(label(raw, 11, DIM, false));
            page.addView(entry);
            page.addView(divider());
            shown++;
        }
        if (shown == 0) note(page, "이 조건에 맞는 기록이 없습니다.");
    }

    private void chip(LinearLayout row, String text, final String value, final boolean category) {
        boolean on = category ? categoryFilter.equals(value) : sourceFilter.equals(value);
        TextView chip = label(text, 13, on ? 0xFF00232B : DIM, on);
        chip.setPadding(dp(14), dp(10), dp(14), dp(10));
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(dp(18));
        shape.setColor(on ? ACCENT : BG);
        shape.setStroke(dp(1), on ? ACCENT : 0xFF333C49);
        chip.setBackgroundDrawable(shape);
        chip.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                if (category) categoryFilter = value; else sourceFilter = value;
                render();
            }
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, dp(6), dp(8), dp(2));
        row.addView(chip, lp);
    }

    private void section(LinearLayout page, String title) {
        TextView t = label(title, 13, ACCENT, true);
        t.setPadding(0, dp(12), 0, dp(4));
        page.addView(t);
    }

    private void row(LinearLayout page, String name, String value, int color) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(48));
        TextView n = label(name, 15, TEXT, false);
        r.addView(n, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        r.addView(label(value, 15, color, false));
        page.addView(r);
        page.addView(divider());
    }

    private void box(LinearLayout page, String title, String text, int color) {
        LinearLayout b = new LinearLayout(this);
        b.setOrientation(LinearLayout.VERTICAL);
        b.setPadding(dp(14), dp(10), dp(14), dp(10));
        b.setBackgroundDrawable(new ColorDrawable(0xFF1B2230));
        b.addView(label(title, 15, color, true));
        b.addView(label(text, 14, TEXT, false));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, dp(8), 0, dp(8));
        page.addView(b, lp);
    }

    private void note(LinearLayout page, String text) {
        TextView t = label(text, 15, DIM, false);
        t.setPadding(0, dp(16), 0, 0);
        page.addView(t);
    }

    private View divider() {
        View v = new View(this);
        v.setBackgroundColor(LINE);
        v.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1));
        return v;
    }

    private TextView label(String text, int sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private int dp(int value) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, getResources().getDisplayMetrics());
    }
}
