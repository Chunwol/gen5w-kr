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
import android.widget.HorizontalScrollView;
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
    private static final String[] TABS = {"정보", "켜기/끄기", "기록", "관리"};
    private static final long REFRESH_MS = 5000;
    private static final String LANG_FILE = "lang-en"; // present = English; absent = Korean (default)
    private static final String UI_DIR = "/data/nemesis/gen5wkr.ui";
    // Colors from Hyundai's published brand palette (hyundai.com CI page): Hyundai Blue #002C5F for the top
    // bar, Active Blue #00AAD2 as the accent, Light Sand #F6F3F2 for text, Active Red #E63312 for errors,
    // Sky Blue #AACAE6 toned down for secondary text. Dark surfaces are a navy-tinted black (our choice:
    // the palette has no dark theme). Green and yellow have no brand color; they are plain status colors.
    private static final int BG = 0xFF070D16, TOP = 0xFF002C5F, SIDE = 0xFF0B1422, SELECTED = 0xFF12325C,
            ACCENT = 0xFF00AAD2, TEXT = 0xFFF6F3F2, DIM = 0xFF8EAACB, GREEN = 0xFF3DDC84, YELLOW = 0xFFFFB020,
            RED = 0xFFE63312, LINE = 0xFF1B2A40, BOX = 0xFF14243B, OUTLINE = 0xFF2F4565,
            PANEL = 0xFF0F1A2B, RAISED = 0xFF182A44;
    private static final java.util.Random RANDOM = new java.util.Random();

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
    private ScrollView scrollView;
    private int shownTab = -1;
    private int requestSeq;     // only the newest write may undo the clicked states when it fails
    private String adbToken;    // digits; a new number asks the collector for one Wi-Fi adb change
    private TextView langButton;
    private LinearLayout panel;   // the grouped block rows are added to; null = rows go straight on the page
    private int panelRows;
    private Widgets.Icon[] menuIcons = new Widgets.Icon[TABS.length];
    private String saveToken; // digits; a new number asks the collector for one diagnosis save
    private long saveAskedAt;
    private String removeToken; // digits; sent only after the second confirmation
    private long removeAskedAt;
    private boolean confirmRemove;

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
        I18n.setEnglish(new File(getFilesDir(), LANG_FILE).exists());
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        GradientDrawable barShape = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, new int[] {TOP, 0xFF05213F});
        bar.setBackgroundDrawable(barShape);
        bar.setPadding(dp(24), dp(8), dp(16), dp(8));
        TextView title = label("Gen5W KR", 24, TEXT, true);
        bar.addView(title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        langButton = new TextView(this);
        langButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        langButton.setTypeface(Typeface.DEFAULT_BOLD);
        langButton.setTextColor(TEXT);
        langButton.setGravity(Gravity.CENTER);
        langButton.setMinWidth(dp(120));
        langButton.setMinHeight(dp(46));
        GradientDrawable langShape = new GradientDrawable();
        langShape.setCornerRadius(dp(23));
        langShape.setColor(alpha(0xFFFFFFFF, 0x26));
        langButton.setBackgroundDrawable(langShape);
        langButton.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { setLanguage(!I18n.english()); }
        });
        bar.addView(langButton);
        root.addView(bar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        View accentLine = new View(this);
        accentLine.setBackgroundColor(alpha(ACCENT, 0xCC));
        root.addView(accentLine, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)));
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout side = new LinearLayout(this);
        side.setOrientation(LinearLayout.VERTICAL);
        side.setBackgroundColor(SIDE);
        side.setPadding(dp(12), dp(14), dp(12), dp(8));
        for (int i = 0; i < TABS.length; i++) {
            final int index = i;
            LinearLayout item = new LinearLayout(this);
            item.setGravity(Gravity.CENTER_VERTICAL);
            item.setPadding(dp(16), 0, dp(12), 0);
            menuIcons[i] = new Widgets.Icon(this, i, DIM);
            LinearLayout.LayoutParams iconLp = new LinearLayout.LayoutParams(dp(30), dp(30));
            iconLp.setMargins(0, 0, dp(14), 0);
            item.addView(menuIcons[i], iconLp);
            item.addView(label(TABS[i], 21, DIM, false));
            item.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) { tab = index; render(); }
            });
            menuItems[i] = item;
            LinearLayout.LayoutParams itemLp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(66));
            itemLp.setMargins(0, 0, 0, dp(6));
            side.addView(item, itemLp);
        }
        body.addView(side, new LinearLayout.LayoutParams(dp(236), ViewGroup.LayoutParams.MATCH_PARENT));
        content = new FrameLayout(this);
        body.addView(content, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f));
        root.addView(body, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
        render();
    }

    private void setLanguage(boolean english) {
        File flag = new File(getFilesDir(), LANG_FILE);
        try {
            if (english) { if (!flag.exists()) flag.createNewFile(); } else { flag.delete(); }
        } catch (java.io.IOException e) { /* the choice then only lasts until the screen is closed */ }
        I18n.setEnglish(english);
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
        langButton.setText(I18n.english() ? "한국어" : "English"); // the language it switches to
        for (int i = 0; i < menuItems.length; i++) {
            boolean on = i == tab;
            GradientDrawable pick = new GradientDrawable();
            pick.setCornerRadius(dp(18));
            pick.setColor(on ? SELECTED : 0x00000000);
            menuItems[i].setBackgroundDrawable(pick);
            menuIcons[i].setColor(on ? ACCENT : DIM);
            TextView name = (TextView) menuItems[i].getChildAt(1);
            name.setText(I18n.t(TABS[i]));
            name.setTextColor(on ? TEXT : DIM);
            name.setTypeface(Typeface.DEFAULT, on ? Typeface.BOLD : Typeface.NORMAL);
        }
        panel = null;
        panelRows = 0;
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(28), dp(10), dp(28), dp(24));
        if (tab == INFO) buildInfo(page);
        else if (tab == LOG) buildLog(page);
        else if (tab == ONOFF) buildSwitches(page);
        else buildManage(page);
        // The screen is redrawn every few seconds: keep the scroll position while the same tab stays open.
        final int keepY = scrollView != null && shownTab == tab ? scrollView.getScrollY() : 0;
        shownTab = tab;
        final ScrollView scroll = new ScrollView(this);
        scrollView = scroll;
        scroll.addView(page);
        if (keepY > 0) scroll.post(new Runnable() { public void run() { scroll.scrollTo(0, keepY); } });
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
        final String adb = adbToken != null && ("on".equals(a) || "off".equals(a)) ? a + ":" + adbToken : null;
        final int seq = ++requestSeq;
        final String token = saveToken;
        final String rtoken = removeToken;
        new Thread(new Runnable() {
            public void run() {
                final boolean ok = SwitchRequest.write(dir, w, t, b, adb, token, rtoken);
                handler.post(new Runnable() {
                    public void run() {
                        if (!ok && seq == requestSeq) { pending[0] = pending[1] = pending[2] = pending[3] = null; }
                        render();
                    }
                });
            }
        }, "gen5w-ui-request").start();
    }

    /** A random number (not the clock: the car's clock may be unset or repeat after a restart). */
    private static String newToken() { return String.valueOf(1 + (long) (RANDOM.nextDouble() * 999999998L)); }

    private void switchRow(LinearLayout page, String name, String help, String locked, String state, final int index) {
        switchRowView(page, name, help, locked, state, new View.OnClickListener() {
            public void onClick(View v) {
                String current = effective(index, "unknown");
                if (!"on".equals(current) && !"off".equals(current)) {
                    current = index == 0 ? model.switchWireless() : index == 1 ? model.switchTimer() : index == 2 ? model.switchBluelink() : model.switchAdb();
                }
                pending[index] = "on".equals(current) ? "off" : "on";
                pendingAt[index] = SystemClock.elapsedRealtime();
                if (index == 3) adbToken = newToken();
                sendRequest();
            }
        });
    }

    private void switchRowView(LinearLayout page, String name, String help, String locked, String state, View.OnClickListener click) {
        boolean known = "on".equals(state) || "off".equals(state);
        boolean on = "on".equals(state);
        boolean enabled = locked == null && known;
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(88));
        r.setPadding(0, dp(12), 0, dp(12));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(label(name, 19, TEXT, false));
        TextView hint = label(locked != null ? locked : help, 14, locked != null ? YELLOW : DIM, false);
        hint.setLineSpacing(dp(2), 1f);
        text.addView(hint);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tl.setMargins(0, 0, dp(18), 0);
        r.addView(text, tl);
        TextView word = label(!known ? "확인 못 함" : on ? "켜짐" : "꺼짐", 16, enabled && on ? ACCENT : DIM, true);
        LinearLayout.LayoutParams wl = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        wl.setMargins(0, 0, dp(14), 0);
        r.addView(word, wl);
        Widgets.Toggle toggle = new Widgets.Toggle(this, ACCENT, 0xFF2A3B55, 0xFF00232B, 0xFFB9C8DA);
        toggle.set(on, enabled);
        r.addView(toggle, new LinearLayout.LayoutParams(dp(78), dp(44)));
        if (enabled) r.setOnClickListener(click); // the whole row is the touch target
        add(page, r);
    }

    /** tone: 0 accent fill, 1 danger fill, 2 outline, 3 danger outline. */
    private void buttonRow(LinearLayout page, String name, String help, String buttonText, boolean enabled, int tone, View.OnClickListener click) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(88));
        r.setPadding(0, dp(12), 0, dp(12));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(label(name, 19, TEXT, false));
        TextView hint = label(help, 14, DIM, false);
        hint.setLineSpacing(dp(2), 1f);
        text.addView(hint);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tl.setMargins(0, 0, dp(18), 0);
        r.addView(text, tl);
        boolean filled = tone == 0 || tone == 1;
        int tint = tone == 1 || tone == 3 ? RED : ACCENT;
        TextView button = label(buttonText, 18, !enabled ? DIM : tone == 0 ? 0xFF00232B : tone == 1 ? 0xFFFFFFFF : tone == 3 ? RED : TEXT, true);
        button.setGravity(Gravity.CENTER);
        button.setMinWidth(dp(132));
        button.setMinHeight(dp(58));
        button.setPadding(dp(24), dp(14), dp(24), dp(14));
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(dp(29));
        shape.setColor(enabled && filled ? tint : 0x00000000);
        shape.setStroke(dp(2), enabled ? (tone == 2 ? OUTLINE : tint) : OUTLINE);
        button.setBackgroundDrawable(shape);
        if (enabled) button.setOnClickListener(click);
        r.addView(button);
        add(page, r);
    }

    private void buildManage(LinearLayout page) {
        section(page, "전체 제거");
        String removed = model.removedState();
        String[] parts = removed.split(":");
        String result = parts.length > 1 ? parts[1] : "none";
        String failedId = parts.length > 2 ? parts[2] : "";
        boolean askedNow = removeToken != null && SystemClock.elapsedRealtime() - removeAskedAt < 10 * 60 * 1000
                && !removed.startsWith(removeToken + ":");
        if (askedNow || result.equals("working")) {
            box(page, "제거하는 중입니다", I18n.t("끄지 말고 기다려 주세요. 패키지를 하나씩 되돌리며 제거합니다. {0}", parts.length > 2 && result.equals("working") ? I18n.t("지금: {0}", failedId) : ""), YELLOW);
        } else if (result.equals("done") && removeToken != null && removed.startsWith(removeToken + ":")) {
            box(page, "거의 끝났습니다", "Gen5W KR 패키지를 제거했습니다. 마지막으로 NEMESIS Manager의 My Packages에서 \"Gen5W KR - CarPlay HUD\"를 눌러 Uninstall 하세요. 이 앱 자체라서 화면에서는 지울 수 없습니다.", GREEN);
        } else {
            if (result.equals("failed") && removeToken != null && removed.startsWith(removeToken + ":")) {
                box(page, "제거를 멈췄습니다", I18n.t("{0} 단계에서 멈췄습니다. 이 패키지와 이후 패키지는 그대로 남아 있습니다. 진단을 저장해 두고 다시 시도하거나 USB 제거 키트를 쓰세요.", failedId), RED);
            }
            if (!confirmRemove) {
                buttonRow(page, "Gen5W KR 전부 제거", "무선, 오디오, 안내창, 블루링크, 주행 기록을 제거하고 차 설정을 처음 값으로 되돌립니다. 앱(CarPlay HUD)은 마지막에 NEMESIS Manager에서 지웁니다.",
                        "제거...", model.readable(), 3, new View.OnClickListener() {
                            public void onClick(View v) { confirmRemove = true; render(); }
                        });
            } else {
                box(page, "정말 제거할까요?", "제거하는 동안 차를 끄거나 USB를 빼지 마세요. 중간에 실패하면 그 단계에서 멈추고 아무것도 강제로 지우지 않습니다.", YELLOW);
                buttonRow(page, "제거 시작", "되돌릴 수 없습니다. 다시 쓰려면 설치 키트로 다시 설치해야 합니다.", "제거 시작", true, 1, new View.OnClickListener() {
                    public void onClick(View v) {
                        confirmRemove = false;
                        removeToken = newToken();
                        removeAskedAt = SystemClock.elapsedRealtime();
                        sendRequest();
                    }
                });
                buttonRow(page, "취소", "아무것도 바꾸지 않습니다.", "취소", true, 2, new View.OnClickListener() {
                    public void onClick(View v) { confirmRemove = false; render(); }
                });
            }
        }
        section(page, "기능만 멈추기");
        note(page, "제거하지 않고 기능만 멈추려면 켜기/끄기 화면의 스위치를 쓰세요. 스위치를 꺼도 설치된 파일은 그대로 남습니다.");
        section(page, "진단 저장");
        String saved = model.savedState();
        String saveResult = saved.substring(saved.indexOf(':') + 1);
        boolean saveNow = saveToken != null && SystemClock.elapsedRealtime() - saveAskedAt < PENDING_MS
                && !saved.startsWith(saveToken + ":");
        String help = saveNow || saveResult.equals("working") ? "저장하는 중입니다..."
                : saveResult.equals("usb") ? "USB의 gen5w-kr-diag 폴더에 저장했습니다. USB를 PC에서 확인하세요."
                : saveResult.equals("nousb") ? "USB가 연결되어 있지 않아 차 안에만 저장했습니다. USB를 꽂고 다시 누르세요."
                : saveResult.equals("fail") ? "USB에 쓰지 못했습니다. USB를 확인하고 다시 누르세요."
                : "상태, 최근 기록, 이 차의 시스템 정보를 한 파일로 USB에 저장합니다. 개인정보가 들어 있을 수 있는 줄은 뺍니다.";
        buttonRow(page, "진단 저장", help, "저장", model.readable() && !saveNow, 0, new View.OnClickListener() {
            public void onClick(View v) {
                saveToken = newToken();
                saveAskedAt = SystemClock.elapsedRealtime();
                sendRequest();
            }
        });
    }

    private void buildInfo(LinearLayout page) {
        if (!loaded) { note(page, "불러오는 중..."); return; }
        if (!model.readable()) {
            box(page, "상태를 읽을 수 없음", "상태 수집 서비스가 아직 실행되지 않았거나, 이 앱이 상태 폴더를 읽을 권한이 없을 수 있습니다. 잠시 뒤 다시 확인하고, 계속 이러면 진단을 저장해 주세요.", RED);
            return;
        }
        boolean stale = model.stale();
        String host = model.host();
        if (stale) {
            long age = model.ageSeconds();
            box(page, "기록이 오래됨", age < 0 ? "이전 부팅 때의 기록입니다. 새 기록을 기다리는 중입니다." : I18n.t("마지막 갱신이 {0}초 전입니다. 아래 값이 지금과 다를 수 있습니다.", String.valueOf(age)), YELLOW);
        } else if (host.equals("alive")) {
            hero(page, "무선 사용 가능", "무선 호스트가 실행 중입니다.", GREEN);
        } else if (host.equals("dead")) {
            String why = I18n.english() ? (model.whyRaw().length() > 0 ? model.whyRaw() : I18n.t(model.why())) : model.why();
            hero(page, "무선 대기 중", why.length() > 0 ? why : "원인을 확인하지 못했습니다", YELLOW);
        } else {
            hero(page, "확인 못 함", "", DIM);
        }
        section(page, "연결");
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
        HorizontalScrollView fromScroll = new HorizontalScrollView(this);
        fromScroll.setHorizontalScrollBarEnabled(false);
        fromScroll.addView(from);
        page.addView(fromScroll);
        panel = null;
        openPanel(page, dp(14));
        int shown = 0;
        for (String line : logLines) {
            int bar = line.indexOf('|');
            String source = bar > 0 ? line.substring(0, bar) : "";
            String raw = bar > 0 ? line.substring(bar + 1) : line;
            if (!sourceFilter.equals("all") && !sourceFilter.equals(source)) continue;
            if (!categoryFilter.equals("all") && !categoryFilter.equals(LogTranslator.category(raw))) continue;
            String korean = I18n.english() ? raw : LogTranslator.translate(raw);
            boolean error = LogTranslator.category(raw).equals("error");
            LinearLayout entry = new LinearLayout(this);
            entry.setPadding(0, dp(12), 0, dp(12));
            if (source.length() > 0) {
                TextView tag = label(source, 12, error ? RED : ACCENT, true);
                tag.setGravity(Gravity.CENTER);
                tag.setMinWidth(dp(76));
                tag.setPadding(dp(8), dp(3), dp(8), dp(3));
                GradientDrawable tagShape = new GradientDrawable();
                tagShape.setCornerRadius(dp(10));
                tagShape.setColor(alpha(error ? RED : ACCENT, 0x26));
                tag.setBackgroundDrawable(tagShape);
                LinearLayout.LayoutParams tagLp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                tagLp.setMargins(0, dp(2), dp(14), 0);
                entry.addView(tag, tagLp);
            }
            LinearLayout col = new LinearLayout(this);
            col.setOrientation(LinearLayout.VERTICAL);
            TextView msg = label(korean, 16, error ? RED : TEXT, error);
            msg.setLineSpacing(dp(2), 1f);
            col.addView(msg);
            if (!korean.equals(raw)) col.addView(label(raw, 12, DIM, false));
            entry.addView(col, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            add(page, entry);
            shown++;
        }
        if (shown == 0) note(page, "이 조건에 맞는 기록이 없습니다.");
    }

    private void chip(LinearLayout row, String text, final String value, final boolean category) {
        boolean on = category ? categoryFilter.equals(value) : sourceFilter.equals(value);
        TextView chip = label(text, 16, on ? 0xFF00232B : TEXT, on);
        chip.setGravity(Gravity.CENTER);
        chip.setMinHeight(dp(44));
        chip.setPadding(dp(18), dp(8), dp(18), dp(8));
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(dp(22));
        shape.setColor(on ? ACCENT : RAISED);
        chip.setBackgroundDrawable(shape);
        chip.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                if (category) categoryFilter = value; else sourceFilter = value;
                render();
            }
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, dp(10), dp(10), dp(2));
        row.addView(chip, lp);
    }

    /** A grouped block: rows added until the next section go inside it. */
    private void openPanel(LinearLayout page, int topMargin) {
        LinearLayout p = new LinearLayout(this);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setPadding(dp(22), dp(4), dp(22), dp(4));
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(dp(20));
        shape.setColor(PANEL);
        p.setBackgroundDrawable(shape);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, topMargin, 0, 0);
        page.addView(p, lp);
        panel = p;
        panelRows = 0;
    }

    /** Adds a row to the open block (with a thin line above all but the first), or to the page when none is open. */
    private void add(LinearLayout page, View view) {
        if (panel == null) { page.addView(view); return; }
        if (panelRows > 0) panel.addView(divider());
        panel.addView(view);
        panelRows++;
    }

    private void section(LinearLayout page, String title) {
        TextView t = label(title, 16, DIM, true);
        t.setPadding(dp(6), dp(22), 0, 0);
        page.addView(t);
        openPanel(page, dp(8));
    }

    private void row(LinearLayout page, String name, String value, int color) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(68));
        r.addView(label(name, 19, TEXT, false), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView v = label(value, 17, color, color != TEXT && color != DIM);
        if (color == GREEN || color == YELLOW || color == RED) {
            v.setPadding(dp(14), dp(6), dp(14), dp(6));
            GradientDrawable pill = new GradientDrawable();
            pill.setCornerRadius(dp(16));
            pill.setColor(alpha(color, 0x26));
            v.setBackgroundDrawable(pill);
        }
        r.addView(v);
        add(page, r);
    }

    /** The big status card at the top of the info page. */
    private void hero(LinearLayout page, String title, String text, int color) {
        LinearLayout h = new LinearLayout(this);
        h.setGravity(Gravity.CENTER_VERTICAL);
        h.setPadding(dp(26), dp(22), dp(26), dp(22));
        GradientDrawable shape = new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, new int[] {alpha(color, 0x2E), PANEL});
        shape.setCornerRadius(dp(22));
        shape.setStroke(dp(1), alpha(color, 0x66));
        h.setBackgroundDrawable(shape);
        LinearLayout.LayoutParams dl = new LinearLayout.LayoutParams(dp(44), dp(44));
        dl.setMargins(0, 0, dp(20), 0);
        h.addView(new Widgets.Dot(this, color), dl);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.addView(label(title, 27, TEXT, true));
        if (text.length() > 0) {
            TextView sub = label(text, 17, DIM, false);
            sub.setLineSpacing(dp(2), 1f);
            col.addView(sub);
        }
        h.addView(col, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, dp(8), 0, 0);
        page.addView(h, lp);
    }

    /** A notice with a colored edge: errors, warnings, progress. */
    private void box(LinearLayout page, String title, String text, int color) {
        LinearLayout b = new LinearLayout(this);
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(dp(16));
        shape.setColor(BOX);
        b.setBackgroundDrawable(shape);
        View edge = new View(this);
        GradientDrawable edgeShape = new GradientDrawable();
        edgeShape.setCornerRadii(new float[] {dp(16), dp(16), 0, 0, 0, 0, dp(16), dp(16)});
        edgeShape.setColor(color);
        edge.setBackgroundDrawable(edgeShape);
        b.addView(edge, new LinearLayout.LayoutParams(dp(7), ViewGroup.LayoutParams.MATCH_PARENT));
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(18), dp(14), dp(18), dp(14));
        col.addView(label(title, 19, color, true));
        TextView body = label(text, 16, TEXT, false);
        body.setLineSpacing(dp(2), 1f);
        col.addView(body);
        b.addView(col, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, dp(10), 0, dp(6));
        if (panel != null) panel.addView(b, lp); else page.addView(b, lp);
    }

    private void note(LinearLayout page, String text) {
        TextView t = label(text, 16, DIM, false);
        t.setLineSpacing(dp(2), 1f);
        if (panel != null) {
            t.setPadding(0, dp(16), 0, dp(16));
            add(page, t);
        } else {
            t.setPadding(dp(6), dp(16), 0, 0);
            page.addView(t);
        }
    }

    private View divider() {
        View v = new View(this);
        v.setBackgroundColor(LINE);
        v.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1));
        return v;
    }

    private TextView label(String text, int sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(I18n.t(text));
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private static int alpha(int color, int a) { return (a << 24) | (color & 0x00FFFFFF); }

    private int dp(int value) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, getResources().getDisplayMetrics());
    }
}
