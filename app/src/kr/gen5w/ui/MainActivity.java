package kr.gen5w.ui;

import android.app.Activity;
import android.content.Intent;
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
import kr.gen5w.core.CoreService;
import kr.gen5w.core.HudSwitch;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;

/**
 * Status, switches and log screen. It reads the two files the collector service writes (status and
 * log in /data/nemesis/gen5wkr.ui, a root-owned folder). Switches are only requests: a small file in
 * this app's own folder that the collector (root) reads; the HUD switch is a flag in this app's folder.
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
    private static final long PENDING_MS = 40000;
    // Switch order: wireless, timer, bluelink, adb. A click shows its new state at once, until the collector confirms it.
    private final String[] pending = new String[4];
    private final long[] pendingAt = new long[4];
    private String saveToken; // digits; a new number asks the collector for one diagnosis save
    private long saveAskedAt;

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
        else if (tab == ONOFF) buildSwitches(page);
        else buildManage(page);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(page);
        content.removeAllViews();
        content.addView(scroll, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    }

    /** What a switch shows: a recent click wins over the collector's last snapshot. */
    private String effective(int i, String reported) {
        if (pending[i] != null && SystemClock.elapsedRealtime() - pendingAt[i] < PENDING_MS) return pending[i];
        pending[i] = null;
        return reported;
    }

    private void buildSwitches(LinearLayout page) {
        if (!loaded) { note(page, "불러오는 중..."); return; }
        final boolean readable = model.readable();
        note(page, "끄면 몇 초 안에 반영됩니다. 설치된 파일은 그대로 남아 있어 언제든 다시 켤 수 있습니다. (제거가 아닙니다)");
        section(page, "무선");
        final String wireless = effective(0, model.switchWireless());
        String wlock = model.wiredOnly() ? "설치 때 유선 전용으로 설치되어 여기서 켤 수 없습니다"
                : model.apguardOff() ? "재시작 보호가 걸려 있어 여기서 켤 수 없습니다" : null;
        switchRow(page, "무선 CarPlay / Android Auto", "무선 연결 담당 서비스를 켜고 끕니다. 유선 연결은 그대로 동작합니다.",
                wlock != null ? wlock : readable ? null : "상태를 읽을 수 없어 바꿀 수 없습니다", wireless, 0);
        section(page, "안내창");
        switchRow(page, "시동 안내창 자동 닫기", "끄면 차 순정 10초 타이머로 돌아갑니다.",
                readable ? null : "상태를 읽을 수 없어 바꿀 수 없습니다", effective(1, model.switchTimer()), 1);
        switchRow(page, "블루링크 월간 안내 숨기기", "끄면 차의 원래 안내 시간 값을 되돌립니다.",
                readable ? null : "상태를 읽을 수 없어 바꿀 수 없습니다", effective(2, model.switchBluelink()), 2);
        section(page, "HUD");
        final boolean hudOff = HudSwitch.isOff(new File(getApplicationInfo().dataDir));
        switchRowView(page, "CarPlay HUD 연동", "끄면 이 앱의 HUD 서비스를 멈춥니다. 켜면 바로 다시 시작합니다.",
                null, hudOff ? "off" : "on", new View.OnClickListener() {
                    public void onClick(View v) {
                        boolean nowOff = HudSwitch.isOff(new File(getApplicationInfo().dataDir));
                        if (!HudSwitch.setOff(new File(getApplicationInfo().dataDir), !nowOff)) return;
                        Intent svc = new Intent(MainActivity.this, CoreService.class);
                        if (nowOff) startService(svc); else stopService(svc);
                        render();
                    }
                });
        section(page, "개발자 접속 (이번 부팅만)");
        switchRow(page, "Wi-Fi ADB", "켜면 같은 Wi-Fi의 PC에서 adb connect <차 주소>:5555 로 접속할 수 있습니다. 차를 껐다 켜면 자동으로 꺼집니다. 순정 ADB 키 승인은 그대로 필요하고, PC가 차 핫스팟에 붙으면 인터넷이 끊깁니다.",
                readable ? null : "상태를 읽을 수 없어 바꿀 수 없습니다", effective(3, model.switchAdb()), 3);
        section(page, "이 화면에서 바꿀 수 없는 것");
        row(page, "오디오 모듈", "설치 / 제거로만", DIM);
        row(page, "주행 기록", "USB 키트가 필요", DIM);
        row(page, "Wi-Fi 동글", model.backend().equals("dongle") ? "동글 방식으로 설치됨 (설치 때 정함)" : "해당 없음 (이 차는 내장 Wi-Fi)", DIM);
    }

    /** Sends the three switch states to the collector. Runs off the main thread. */
    private void sendRequest() {
        final String w = effective(0, model.switchWireless()), t = effective(1, model.switchTimer()), b = effective(2, model.switchBluelink()), a = effective(3, model.switchAdb());
        final File dir = getFilesDir();
        final String token = saveToken;
        new Thread(new Runnable() {
            public void run() {
                final boolean ok = SwitchRequest.write(dir, w, t, b, a, token);
                handler.post(new Runnable() {
                    public void run() {
                        if (!ok) { pending[0] = pending[1] = pending[2] = pending[3] = null; }
                        render();
                    }
                });
            }
        }, "gen5w-ui-request").start();
    }

    private void switchRow(LinearLayout page, String name, String help, String locked, String state, final int index) {
        switchRowView(page, name, help, locked, state, new View.OnClickListener() {
            public void onClick(View v) {
                String current = effective(index, "unknown");
                if (!"on".equals(current) && !"off".equals(current)) {
                    current = index == 0 ? model.switchWireless() : index == 1 ? model.switchTimer() : index == 2 ? model.switchBluelink() : model.switchAdb();
                }
                pending[index] = "on".equals(current) ? "off" : "on";
                pendingAt[index] = SystemClock.elapsedRealtime();
                sendRequest();
            }
        });
    }

    private void switchRowView(LinearLayout page, String name, String help, String locked, String state, View.OnClickListener click) {
        boolean known = "on".equals(state) || "off".equals(state);
        boolean on = "on".equals(state);
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(84));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(label(name, 18, TEXT, false));
        text.addView(label(locked != null ? locked : help, 14, locked != null ? YELLOW : DIM, false));
        r.addView(text, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        boolean enabled = locked == null && known;
        TextView button = label(!known ? "확인 못 함" : on ? "켜짐" : "꺼짐", 18, enabled ? (on ? 0xFF00232B : TEXT) : DIM, true);
        button.setGravity(Gravity.CENTER);
        button.setMinWidth(dp(120));
        button.setMinHeight(dp(56));
        button.setPadding(dp(20), dp(14), dp(20), dp(14));
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(dp(22));
        shape.setColor(enabled && on ? GREEN : BG);
        shape.setStroke(dp(1), enabled && on ? GREEN : 0xFF333C49);
        button.setBackgroundDrawable(shape);
        if (enabled) button.setOnClickListener(click);
        r.addView(button);
        page.addView(r);
        page.addView(divider());
    }

    private void buildManage(LinearLayout page) {
        section(page, "전체 제거");
        box(page, "차 안에서는 제거하지 않습니다", "제거는 설치 때 사용한 USB의 제거 키트로 합니다. 제거하는 동안 이 앱도 함께 지워지고 차 시스템 파일을 건드리는 단계가 있어, 안전을 확인하기 전까지는 이 화면에 넣지 않았습니다.", YELLOW);
        section(page, "기능만 멈추기");
        note(page, "제거하지 않고 기능만 멈추려면 ONOFF 화면의 스위치를 쓰세요. 스위치를 꺼도 설치된 파일은 그대로 남습니다.");
        section(page, "진단 저장");
        String saved = model.savedState();
        String result = saved.substring(saved.indexOf(':') + 1);
        boolean askedNow = saveToken != null && SystemClock.elapsedRealtime() - saveAskedAt < PENDING_MS
                && !saved.startsWith(saveToken + ":");
        String help = askedNow || result.equals("working") ? "저장하는 중입니다..."
                : result.equals("usb") ? "USB의 gen5w-kr-diag 폴더에 저장했습니다. USB를 PC에서 확인하세요."
                : result.equals("nousb") ? "USB가 연결되어 있지 않아 차 안에만 저장했습니다. USB를 꽂고 다시 누르세요."
                : result.equals("fail") ? "USB에 쓰지 못했습니다. USB를 확인하고 다시 누르세요."
                : "상태, 최근 기록, 이 차의 시스템 정보를 한 파일로 USB에 저장합니다. 개인정보가 들어 있을 수 있는 줄은 뺍니다.";
        buttonRow(page, "진단 저장", help, "저장", model.readable() && !askedNow, new View.OnClickListener() {
            public void onClick(View v) {
                saveToken = String.valueOf((System.currentTimeMillis() / 1000) % 1000000000L);
                saveAskedAt = SystemClock.elapsedRealtime();
                sendRequest();
            }
        });
    }

    private void buttonRow(LinearLayout page, String name, String help, String buttonText, boolean enabled, View.OnClickListener click) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(84));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(label(name, 18, TEXT, false));
        text.addView(label(help, 14, DIM, false));
        r.addView(text, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView button = label(buttonText, 18, enabled ? 0xFF00232B : DIM, true);
        button.setGravity(Gravity.CENTER);
        button.setMinWidth(dp(120));
        button.setMinHeight(dp(56));
        button.setPadding(dp(20), dp(14), dp(20), dp(14));
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(dp(22));
        shape.setColor(enabled ? ACCENT : BG);
        shape.setStroke(dp(1), enabled ? ACCENT : 0xFF333C49);
        button.setBackgroundDrawable(shape);
        if (enabled) button.setOnClickListener(click);
        r.addView(button);
        page.addView(r);
        page.addView(divider());
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
            entry.addView(label((source.length() > 0 ? "[" + source + "] " : "") + korean, 16, error ? RED : TEXT, false));
            if (!korean.equals(raw)) entry.addView(label(raw, 12, DIM, false));
            page.addView(entry);
            page.addView(divider());
            shown++;
        }
        if (shown == 0) note(page, "이 조건에 맞는 기록이 없습니다.");
    }

    private void chip(LinearLayout row, String text, final String value, final boolean category) {
        boolean on = category ? categoryFilter.equals(value) : sourceFilter.equals(value);
        TextView chip = label(text, 15, on ? 0xFF00232B : DIM, on);
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
        TextView t = label(title, 15, ACCENT, true);
        t.setPadding(0, dp(12), 0, dp(4));
        page.addView(t);
    }

    private void row(LinearLayout page, String name, String value, int color) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(60));
        TextView n = label(name, 18, TEXT, false);
        r.addView(n, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        r.addView(label(value, 18, color, false));
        page.addView(r);
        page.addView(divider());
    }

    private void box(LinearLayout page, String title, String text, int color) {
        LinearLayout b = new LinearLayout(this);
        b.setOrientation(LinearLayout.VERTICAL);
        b.setPadding(dp(14), dp(10), dp(14), dp(10));
        b.setBackgroundDrawable(new ColorDrawable(0xFF1B2230));
        b.addView(label(title, 18, color, true));
        b.addView(label(text, 16, TEXT, false));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, dp(8), 0, dp(8));
        page.addView(b, lp);
    }

    private void note(LinearLayout page, String text) {
        TextView t = label(text, 16, DIM, false);
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
