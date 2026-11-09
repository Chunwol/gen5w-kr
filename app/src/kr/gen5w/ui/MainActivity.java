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
    private static final String[] HELP = {
        "무선 연결 상태와 설치된 구성 요소를 보여 줍니다.",
        "기능을 켜고 끕니다. 설치된 파일은 지워지지 않습니다.",
        "최근 기록을 보여 줍니다. 종류와 출처로 걸러 볼 수 있습니다.",
        "진단 저장과 제거 같은 관리 작업을 합니다."};
    private static final String LANG_FILE = "lang-en"; // present = English; absent = Korean (default)
    private static final String UI_DIR = "/data/nemesis/gen5wkr.ui";
    // The installed Korean V039 Settings skin takes precedence over corporate CI colors.
    private static final int BLACK = 0xFF000000, WHITE = StockSkin.WHITE, BLUE = StockSkin.BOTTOM, SAND = StockSkin.SUMMARY,
            GOLD = 0xFFCAA675, ACTIVE_BLUE = StockSkin.CYAN, ACTIVE_RED = 0xFFE63312;
    private static final int ACCENT = ACTIVE_BLUE, TEXT = WHITE, DIM = StockSkin.SUMMARY, OK = ACTIVE_BLUE, WARN = GOLD, RED = ACTIVE_RED,
            LINE = StockSkin.LINE, BAR = StockSkin.TOP, OUTLINE = 0xFF5B606A, TILE = 0x00000000, DISABLED = StockSkin.DISABLED;
    private static final int ROUND = 2; // dp: the stock screen uses almost square corners
    private static final java.util.Random RANDOM = new java.util.Random();

    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView helpText;
    private StockSkin skin;
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
    private long requestSeq;
    private final SwitchRequest.Writer requests = new SwitchRequest.Writer();
    private String adbToken;    // digits; a new number asks the collector for one Wi-Fi adb change
    private TextView langButton;
    private LinearLayout panel;   // the grouped block rows are added to; null = rows go straight on the page
    private int panelRows;
    private String saveToken; // digits; a new number asks the collector for one diagnosis save
    private long saveAskedAt;
    private String removeToken; // digits; sent only after the second confirmation
    private long removeAskedAt;
    private boolean confirmRemove;
    private boolean confirmRecovery, recoveryDetails;
    private String recoveryToken;
    private long recoveryAskedAt;
    private boolean recoveryWriteFailed;

    private final Runnable tick = new Runnable() {
        public void run() {
            if (!resumed) return;
            load();
            handler.postDelayed(this, REFRESH_MS);
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        skin = new StockSkin(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundDrawable(background()); // the one background gradient, like the stock settings
        I18n.setEnglish(new File(getFilesDir(), LANG_FILE).exists());
        FrameLayout bar = new FrameLayout(this);
        // The vehicle's SystemUI already supplies back/home, clock, date and status icons.
        // Do not draw another fake status bar inside the application.
        bar.setBackgroundDrawable(skin.drawable("co_bg_title_bar", new ColorDrawable(BAR)));
        bar.setMinimumHeight(dp(60));
        TextView back = label("‹", 44, TEXT, false);
        back.setGravity(Gravity.CENTER);
        back.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { finish(); }
        });
        bar.addView(back, new FrameLayout.LayoutParams(dp(68), dp(60), Gravity.LEFT | Gravity.CENTER_VERTICAL));
        TextView title = label("Gen5W KR", 28, TEXT, true);
        title.setGravity(Gravity.CENTER);
        bar.addView(title, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(60), Gravity.CENTER));
        langButton = new TextView(this);
        langButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        langButton.setTextColor(TEXT);
        langButton.setGravity(Gravity.CENTER);
        langButton.setMinWidth(dp(100));
        langButton.setMinHeight(dp(42));
        langButton.setPadding(dp(18), 0, dp(18), 0);
        langButton.setBackgroundDrawable(skin.button());
        langButton.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { setLanguage(!I18n.english()); }
        });
        FrameLayout.LayoutParams langLp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.RIGHT | Gravity.CENTER_VERTICAL);
        langLp.setMargins(0, 0, dp(24), 0);
        bar.addView(langButton, langLp);
        // An OEM nodpi background may have a larger intrinsic minimum on low-density screens.
        root.addView(bar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(60)));
        root.addView(divider());
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout side = new LinearLayout(this);
        side.setOrientation(LinearLayout.VERTICAL);
        side.setBackgroundColor(0x28000000);
        for (int i = 0; i < TABS.length; i++) {
            final int index = i;
            LinearLayout item = new LinearLayout(this);
            item.setGravity(Gravity.CENTER_VERTICAL);
            item.setPadding(dp(22), 0, dp(8), 0);
            item.setBackgroundDrawable(skin.menu());
            item.setFocusable(true);
            item.addView(label(TABS[i], 26, TEXT, true));
            item.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) { tab = index; render(); }
            });
            menuItems[i] = item;
            side.addView(item, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(72)));
            side.addView(divider());
        }
        // GeneralSettings tab_content_setting: 197dp slot, not the tab child's 250dp width.
        body.addView(side, new LinearLayout.LayoutParams(dp(197), ViewGroup.LayoutParams.MATCH_PARENT));
        View sideLine = new View(this);
        sideLine.setBackgroundDrawable(skin.drawable("co_bg_list_tabline", new ColorDrawable(LINE)));
        body.addView(sideLine, new LinearLayout.LayoutParams(dp(2), ViewGroup.LayoutParams.MATCH_PARENT));
        content = new FrameLayout(this);
        boolean wide = getResources().getConfiguration().screenWidthDp >= 1000;
        body.addView(content, wide ? new LinearLayout.LayoutParams(dp(603), ViewGroup.LayoutParams.MATCH_PARENT)
                : new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f));
        if (wide) {
            View helpLine = new View(this);
            helpLine.setBackgroundColor(LINE);
            body.addView(helpLine, new LinearLayout.LayoutParams(dp(2), ViewGroup.LayoutParams.MATCH_PARENT));
            helpText = label(HELP[0], 22, TEXT, false);
            helpText.setGravity(Gravity.TOP | Gravity.LEFT);
            helpText.setLineSpacing(dp(2), 1f);
            helpText.setPadding(dp(24), dp(18), dp(22), dp(18));
            body.addView(helpText, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f));
        }
        root.addView(body, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
        render();
    }

    /** Wallpaper approximation measured from the user's photo; native controls remain native. */
    private static android.graphics.drawable.Drawable background() {
        android.graphics.drawable.ShapeDrawable d = new android.graphics.drawable.ShapeDrawable(new android.graphics.drawable.shapes.RectShape());
        d.setShaderFactory(new android.graphics.drawable.ShapeDrawable.ShaderFactory() {
            @Override public android.graphics.Shader resize(int width, int height) {
                return new android.graphics.LinearGradient(0, 0, 0, height, new int[] {StockSkin.TOP, StockSkin.TOP, BLUE},
                        new float[] {0f, 0.30f, 1f}, android.graphics.Shader.TileMode.CLAMP);
            }
        });
        return d;
    }

    private void setLanguage(boolean english) {
        File flag = new File(getFilesDir(), LANG_FILE);
        try {
            if (english) { if (!flag.exists()) flag.createNewFile(); } else { flag.delete(); }
        } catch (java.io.IOException e) { kr.gen5w.diag.SafeDiagnostic.failure("ui.settings.write",e); }
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

    @Override protected void onDestroy() {
        requests.close();
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    private boolean canRequest() { return model.canControl(SystemClock.elapsedRealtime() / 1000) && !model.recovery().blocksChanges() && !recoveryPending(); }
    private boolean recoveryPending() {
        return recoveryToken != null && !recoveryWriteFailed && SystemClock.elapsedRealtime()-recoveryAskedAt < PENDING_MS
                && !recoveryToken.equals(model.recovery().request());
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
                        if (isFinishing() || isDestroyed()) return;
                        model = next; logLines = lines; loaded = true;
                        if (adbToken != null && (adbToken + ":failed").equals(model.adbResult())) {
                            pending[3] = null;
                            adbToken = null;
                        }
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
            menuItems[i].setSelected(on);
            TextView name = (TextView) menuItems[i].getChildAt(0);
            name.setText(I18n.t(TABS[i]));
            name.setTextColor(on ? StockSkin.SELECTED : TEXT);
        }
        if (helpText != null) helpText.setText(I18n.t(HELP[tab]));
        panel = null;
        panelRows = 0;
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(0, 0, 0, dp(16));
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
        if (keepY > 0) {
            scroll.getViewTreeObserver().addOnPreDrawListener(new android.view.ViewTreeObserver.OnPreDrawListener() {
                public boolean onPreDraw() {
                    scroll.getViewTreeObserver().removeOnPreDrawListener(this);
                    scroll.scrollTo(0, keepY);
                    return false; // skip this frame; the next one is already at the right position
                }
            });
        }
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
        final boolean readable = canRequest();
        if (!readable) note(page, "상태가 오래되었거나 수집기가 응답하지 않아 조작을 잠갔습니다.");
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
                readable ? null : "상태를 읽을 수 없어 바꿀 수 없습니다", hudOff ? "off" : "on", new View.OnClickListener() {
                    public void onClick(View v) {
                        boolean nowOff = HudSwitch.isOff(new File(getApplicationInfo().dataDir));
                        if (!HudSwitch.setOff(new File(getApplicationInfo().dataDir), !nowOff)) return;
                        Intent svc = new Intent(MainActivity.this, CoreService.class);
                        if (nowOff) startService(svc); else stopService(svc);
                        render();
                    }
                });
        section(page, "개발자 접속 (이번 부팅만)");
        switchRow(page, "Wi-Fi ADB", "이 스위치는 차의 Wi-Fi를 켜지 않고 접속 포트만 엽니다. 차가 이미 Wi-Fi에 연결돼 있어야 PC에서 adb connect <차 주소>:5555 로 접속할 수 있습니다. 차를 껐다 켜면 자동으로 꺼집니다. 순정 ADB 키 승인은 그대로 필요합니다.",
                readable ? null : "상태를 읽을 수 없어 바꿀 수 없습니다", effective(3, model.switchAdb()), 3);
        row(page, "ADB 접속 상태", adbHealthText(), DIM);
        if (model.adbResult().endsWith(":failed")) note(page, "ADB 설정 적용에 실패했습니다. 새 상태를 확인하고 다시 시도하세요.");
        section(page, "이 화면에서 바꿀 수 없는 것");
        row(page, "오디오 모듈", "설치 / 제거로만", DIM);
        row(page, "주행 기록", "USB 키트가 필요", DIM);
        row(page, "Wi-Fi 동글", model.backend().equals("dongle") ? "동글 방식으로 설치됨 (설치 때 정함)" : "해당 없음 (이 차는 내장 Wi-Fi)", DIM);
    }

    /** Sends the three switch states to the collector. Runs off the main thread. */
    private void sendRequest() {
        if (!model.canControl(SystemClock.elapsedRealtime()/1000) || "working".equals(model.recovery().state()) || recoveryPending()) {
            pending[0] = pending[1] = pending[2] = pending[3] = null;
            android.widget.Toast.makeText(this, I18n.t("새 상태를 기다린 뒤 다시 시도하세요."), android.widget.Toast.LENGTH_SHORT).show();
            load();
            return;
        }
        final boolean blocked = model.recovery().blocksChanges();
        final String w = blocked ? null : effective(0, model.switchWireless()), t = blocked ? null : effective(1, model.switchTimer()), b = blocked ? null : effective(2, model.switchBluelink()), a = blocked ? null : effective(3, model.switchAdb());
        final File dir = getFilesDir();
        final String adb = adbToken != null && ("on".equals(a) || "off".equals(a)) ? a + ":" + adbToken : null;
        final long seq = requests.issue();
        requestSeq = seq;
        final String boot = model.bootId();
        final long expires = SystemClock.elapsedRealtime() / 1000 + 30;
        final String token = saveToken;
        final String rtoken = blocked ? null : removeToken;
        new Thread(new Runnable() {
            public void run() {
                final boolean ok = requests.write(seq, dir, SystemClock.elapsedRealtime() / 1000, expires, boot, w, t, b, adb, token, rtoken);
                handler.post(new Runnable() {
                    public void run() {
                        if (isFinishing() || isDestroyed()) return;
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
        r.setMinimumHeight(dp(84));
        r.setPadding(dp(22), dp(8), dp(22), dp(8));
        Widgets.Toggle toggle = new Widgets.Toggle(this);
        toggle.set(on, enabled);
        toggle.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        LinearLayout.LayoutParams checkLayout = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        checkLayout.setMargins(0, 0, dp(8), 0);
        r.addView(toggle, checkLayout);
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(label(name, 26, enabled ? TEXT : DISABLED, true));
        TextView hint = label(locked != null ? locked : help, 22, DIM, false);
        hint.setLineSpacing(dp(2), 1f);
        text.addView(hint);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tl.setMargins(0, 0, dp(18), 0);
        r.addView(text, tl);
        if (!known) r.addView(label("확인 못 함", 18, DIM, false));
        r.setEnabled(enabled);
        final boolean checked = on;
        r.setAccessibilityDelegate(new View.AccessibilityDelegate() {
            @Override public void onInitializeAccessibilityNodeInfo(View host,
                    android.view.accessibility.AccessibilityNodeInfo info) {
                super.onInitializeAccessibilityNodeInfo(host, info);
                info.setClassName("android.widget.CheckBox");
                info.setCheckable(true);
                info.setChecked(checked);
            }
        });
        r.setContentDescription(I18n.t(name) + ": " + I18n.t(!known ? "확인 못 함" : on ? "켜짐" : "꺼짐")
                + (locked == null ? "" : ". " + I18n.t(locked)));
        r.setBackgroundDrawable(skin.menu());
        if (enabled) r.setOnClickListener(click); // the whole row is the touch target
        add(page, r);
    }

    /** tone: 0 accent fill, 1 danger fill, 2 outline, 3 danger outline. */
    private void buttonRow(LinearLayout page, String name, String help, String buttonText, boolean enabled, int tone, View.OnClickListener click) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(dp(84));
        r.setPadding(dp(22), dp(8), dp(22), dp(8));
        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(label(name, 26, TEXT, true));
        TextView hint = label(help, 22, DIM, false);
        hint.setLineSpacing(dp(2), 1f);
        text.addView(hint);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tl.setMargins(0, 0, dp(18), 0);
        r.addView(text, tl);
        TextView button = label(buttonText, 24, !enabled ? DISABLED : tone == 1 || tone == 3 ? RED : TEXT, false);
        button.setGravity(Gravity.CENTER);
        button.setMinWidth(dp(132));
        button.setMinHeight(dp(56));
        button.setPadding(dp(24), dp(14), dp(24), dp(14));
        button.setBackgroundDrawable(skin.button());
        button.setEnabled(enabled);
        if (enabled) button.setOnClickListener(click);
        r.addView(button);
        add(page, r);
    }

    private void buildRecovery(LinearLayout page, boolean manage) {
        final RecoveryStatus r = model.recovery();
        if (!manage && "none".equals(r.state())) return;
        section(page, "설치 복구");
        String title = "working".equals(r.state()) || recoveryPending() ? "복구하는 중입니다"
                : "required".equals(r.state()) ? "설치 중단 · 복구 필요"
                : "restored".equals(r.state()) ? "이전 상태로 복구됨"
                : "none".equals(r.state()) ? "복구 필요 없음" : "복구 상태 확인 불가";
        String help = !model.canControl(SystemClock.elapsedRealtime()/1000) ? "새 상태를 기다린 뒤 다시 시도하세요."
                : "working".equals(r.state()) || recoveryPending() ? "전원을 끄거나 USB를 분리하지 마세요. 성공하면 재부팅합니다."
                : "required".equals(r.state()) ? "설치가 끝나지 않아 추가 변경을 중단했습니다. 이전 상태로 복구한 뒤 다시 설치하세요."
                : "restored".equals(r.state()) ? "설치 직전 상태로 되돌렸습니다. 순정 초기화나 재설치 완료를 뜻하지 않습니다."
                : "none".equals(r.state()) ? "설치 복구가 필요한 기록이 없습니다."
                : "복구 기록을 읽을 수 없습니다. 정상 상태로 확인된 것은 아닙니다.";
        box(page, title, help, r.blocksChanges() ? WARN : DIM);
        if (!manage) {
            buttonRow(page,"설치 복구","관리 화면에서 원인과 다음 행동을 확인하세요.","관리",true,0,new View.OnClickListener(){
                public void onClick(View v){ tab=MANAGE; render(); }
            });
            return;
        }
        if (recoveryWriteFailed) note(page,"복구 요청을 저장하지 못했습니다. 다시 확인하고 요청하세요.");
        if (recoveryToken != null && !recoveryPending() && !recoveryToken.equals(r.request()) && !recoveryWriteFailed)
            note(page,"복구 요청 응답을 확인하지 못했습니다. 진단을 저장하고 USB 복구 안내를 확인하세요.");
        if ("failed".equals(r.result()) || "interrupted".equals(r.result()))
            note(page,"복구가 실패했거나 중단되었습니다. 원본과 진단을 보존하고 오류 상세를 확인하세요.");
        buttonRow(page,"오류 상세","실패 단계와 복구 가능 여부를 확인합니다.","상세",true,0,new View.OnClickListener(){
            public void onClick(View v){ recoveryDetails=!recoveryDetails; render(); }
        });
        if (recoveryDetails) {
            row(page,"실패 단계", "localhotspot".equals(r.stage()) ? "순정 핫스팟 스위치" : r.stage(),DIM);
            String why = "runner-unavailable".equals(r.reason()) ? "복구 USB 준비가 필요합니다."
                    : "snapshot-invalid".equals(r.reason()) ? "복구 백업이 없거나 검증되지 않았습니다."
                    : "busy".equals(r.reason()) ? "다른 작업이 진행 중입니다."
                    : "rollback-failed".equals(r.reason()) || "interrupted".equals(r.reason()) ? "복구가 실패했거나 중단되었습니다. 원본과 진단을 보존하고 오류 상세를 확인하세요."
                    : "ready".equals(r.reason()) ? "실행 전에 백업과 복구 도구를 다시 검사합니다." : "원인 기록을 읽을 수 없습니다.";
            note(page,why);
        }
        final boolean ready = r.canRequest(model.canControl(SystemClock.elapsedRealtime()/1000)) && !recoveryPending();
        if (!ready && "required".equals(r.state()) && !"busy".equals(r.reason()))
            note(page,"앱에서 복구할 수 없으면 새 복구 USB에서 recovery-prepare 후 rollback을 실행하세요. 복구 표식을 지우지 마세요.");
        if (!confirmRecovery) {
            buttonRow(page,"이전 상태로 복구","주차 후 실행하세요. 공장 초기화가 아닙니다.","복구...",ready,3,new View.OnClickListener(){
                public void onClick(View v){ if(model.recovery().canRequest(model.canControl(SystemClock.elapsedRealtime()/1000))){confirmRecovery=true;render();} }
            });
        } else {
            box(page,"이전 상태로 복구","설치 전 상태로 되돌립니다. 성공하면 재부팅됩니다. 전원을 끄거나 USB를 분리하지 마세요.",WARN);
            buttonRow(page,"복구 시작","주차 후 실행하세요. 공장 초기화가 아닙니다.","복구 시작",ready,1,new View.OnClickListener(){
                public void onClick(View v){ sendRecovery(); }
            });
            buttonRow(page,"취소","아무것도 바꾸지 않습니다.","취소",true,2,new View.OnClickListener(){
                public void onClick(View v){ confirmRecovery=false;render(); }
            });
        }
    }

    private void sendRecovery() {
        if (!model.recovery().canRequest(model.canControl(SystemClock.elapsedRealtime()/1000)) || recoveryPending()) { load(); return; }
        confirmRecovery=false;
        recoveryToken=newToken(); recoveryAskedAt=SystemClock.elapsedRealtime(); recoveryWriteFailed=false;
        final String token=recoveryToken, boot=model.bootId(); final File dir=getFilesDir();
        final long seq=requests.issue(), expires=SystemClock.elapsedRealtime()/1000+30;
        requestSeq=seq;
        new Thread(new Runnable(){public void run(){
            final boolean ok=requests.writeRecovery(seq,dir,SystemClock.elapsedRealtime()/1000,expires,boot,token);
            handler.post(new Runnable(){public void run(){
                if(isFinishing() || isDestroyed())return;
                if(token.equals(recoveryToken)) recoveryWriteFailed=!ok;
                render();load();
            }});
        }},"gen5w-recovery-request").start();
        render();
    }

    private void buildManage(LinearLayout page) {
        buildRecovery(page, true);
        section(page, "전체 제거");
        String removed = model.removedState();
        String[] parts = removed.split(":");
        String result = parts.length > 1 ? parts[1] : "none";
        String failedId = parts.length > 2 ? parts[2] : "";
        boolean askedNow = removeToken != null && SystemClock.elapsedRealtime() - removeAskedAt < 10 * 60 * 1000
                && !removed.startsWith(removeToken + ":");
        if (askedNow || result.equals("working")) {
            box(page, "제거하는 중입니다", I18n.t("끄지 말고 기다려 주세요. 패키지를 하나씩 되돌리며 제거합니다. {0}", parts.length > 2 && result.equals("working") ? I18n.t("지금: {0}", failedId) : ""), WARN);
        } else if (result.equals("done") && removeToken != null && removed.startsWith(removeToken + ":")) {
            box(page, "거의 끝났습니다", "Gen5W KR 패키지를 제거했습니다. 마지막으로 NEMESIS Manager의 My Packages에서 \"Gen5W KR - CarPlay HUD\"를 눌러 Uninstall 하세요. 이 앱 자체라서 화면에서는 지울 수 없습니다.", OK);
        } else {
            if (result.equals("failed") && removeToken != null && removed.startsWith(removeToken + ":")) {
                box(page, "제거를 멈췄습니다", I18n.t("{0} 단계에서 멈췄습니다. 이 패키지와 이후 패키지는 그대로 남아 있습니다. 진단을 저장해 두고 다시 시도하거나 USB 제거 키트를 쓰세요.", failedId), RED);
            }
            if (!confirmRemove) {
                buttonRow(page, "Gen5W KR 전부 제거", "무선, 오디오, 안내창, 블루링크, 주행 기록을 제거하고 차 설정을 처음 값으로 되돌립니다. 앱(CarPlay HUD)은 마지막에 NEMESIS Manager에서 지웁니다.",
                        "제거...", canRequest(), 3, new View.OnClickListener() {
                            public void onClick(View v) { if (canRequest()) confirmRemove = true; render(); }
                        });
            } else {
                box(page, "정말 제거할까요?", "제거하는 동안 차를 끄거나 USB를 빼지 마세요. 중간에 실패하면 그 단계에서 멈추고 아무것도 강제로 지우지 않습니다.", WARN);
                buttonRow(page, "제거 시작", "되돌릴 수 없습니다. 다시 쓰려면 설치 키트로 다시 설치해야 합니다.", "제거 시작", canRequest(), 1, new View.OnClickListener() {
                    public void onClick(View v) {
                        if (!canRequest()) { render(); return; }
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
        buttonRow(page, "진단 저장", help, "저장", model.canControl(SystemClock.elapsedRealtime()/1000) && !"working".equals(model.recovery().state()) && !recoveryPending() && !saveNow, 0, new View.OnClickListener() {
            public void onClick(View v) {
                if (!model.canControl(SystemClock.elapsedRealtime()/1000) || "working".equals(model.recovery().state()) || recoveryPending()) { render(); return; }
                saveToken = newToken();
                saveAskedAt = SystemClock.elapsedRealtime();
                sendRequest();
            }
        });
    }

    private void buildInfo(LinearLayout page) {
        if (!loaded) { note(page, "불러오는 중..."); return; }
        buildRecovery(page, false);
        if (!model.readable()) {
            box(page, "상태를 읽을 수 없음", "상태 수집 서비스가 아직 실행되지 않았거나, 이 앱이 상태 폴더를 읽을 권한이 없을 수 있습니다. 잠시 뒤 다시 확인하고, 계속 이러면 진단을 저장해 주세요.", RED);
            return;
        }
        boolean stale = model.stale();
        String host = model.host();
        if (stale) {
            long age = model.ageSeconds();
            box(page, "기록이 오래됨", age < 0 ? "이전 부팅 때의 기록입니다. 새 기록을 기다리는 중입니다." : I18n.t("마지막 갱신이 {0}초 전입니다. 아래 값이 지금과 다를 수 있습니다.", String.valueOf(age)), WARN);
        } else if (host.equals("alive")) {
            hero(page, "무선 호스트 준비", "호스트 실행은 Wi-Fi나 휴대폰 연결 성공을 뜻하지 않습니다.", OK);
        } else if (host.equals("dead")) {
            String why = I18n.english() ? (model.whyRaw().length() > 0 ? model.whyRaw() : I18n.t(model.why())) : model.why();
            hero(page, "무선 대기 중", why.length() > 0 ? why : "원인을 확인하지 못했습니다", WARN);
        } else {
            hero(page, "확인 못 함", "", DIM);
        }
        section(page, "연결");
        row(page, "무선 호스트", host.equals("alive") ? "● 실행 중" : host.equals("dead") ? "● 실행 안 됨" : "확인 못 함",
                stale ? DIM : host.equals("alive") ? OK : host.equals("dead") ? WARN : DIM);
        String relay = model.relay();
        row(page, "릴레이 구성", relay.equals("on") ? "● 포함됨" : relay.equals("off") ? "● 없음" : "확인 못 함",
                stale ? DIM : relay.equals("on") ? OK : relay.equals("off") ? WARN : DIM);
        String wlan = model.wlan();
        row(page, "차 Wi-Fi", wlan.equals("present") ? "인터페이스 있음 (AP 연결 여부는 별도)" : wlan.equals("missing") ? "인터페이스 없음" : "확인 못 함",
                stale ? DIM : wlan.equals("present") ? OK : wlan.equals("missing") ? WARN : DIM);
        row(page, "유선 전용 모드", model.wiredOnly() ? "켜짐" : "꺼짐", model.wiredOnly() ? WARN : TEXT);
        row(page, "재시작 보호", model.apguardOff() ? "● 걸림(무선 꺼짐)" : "● 정상", model.apguardOff() ? RED : stale ? DIM : OK);
        row(page, "ADB 접속 상태", adbHealthText(), DIM);
        row(page, "HUD 소유권 상태", hudHealthText(), DIM);
        note(page, "Android Auto는 순정 무선 지원과 등록이 필요합니다. CarPlay 전용 중계는 적용되지 않습니다.");
        section(page, "설치");
        row(page, "설치 버전", model.bridgeVersion().length() > 0 ? "v" + model.bridgeVersion() : "확인 못 함", TEXT);
        String backend = model.backend();
        row(page, "Wi-Fi 방식", backend.equals("builtin") ? "내장 Wi-Fi" : backend.equals("dongle") ? "USB 동글" : "확인 못 함", TEXT);
    }

    private String adbHealthText() {
        if (!canRequest()) return "확인 못 함";
        String health = model.adbHealth();
        if (health.equals("listening")) return "리스닝 확인 (IP·키 승인은 별도)";
        if (health.equals("daemon-down")) return "포트 설정됨 / adbd 중단";
        if (health.equals("not-listening")) return "포트 설정됨 / 리스닝 없음";
        if (health.equals("unexpected-listener")) return "예상 밖의 ADB 리스너 감지";
        return health.equals("off") ? "꺼짐" : "확인 못 함";
    }

    private String hudHealthText() {
        if (HudSwitch.isOff(new File(getApplicationInfo().dataDir))) return "앱에서 꺼짐";
        String owner = StatusModel.hudOwner(BoundedLines.read(new File(getFilesDir(), "hud-health.status"), 256, 2),
                SystemClock.elapsedRealtime() / 1000);
        if (owner.equals("STOCK")) return "순정 내비 우선 (출력 차단)";
        if (owner.equals("UNKNOWN")) return "소유권 확인 실패 (출력 차단)";
        if (owner.equals("CARPLAY") || owner.equals("AA")) return "출력 허용 (실제 표시는 별도 확인)";
        return "서비스 응답 없음";
    }

    private void buildLog(LinearLayout page) {
        if (!loaded) { note(page, "불러오는 중..."); return; }
        if (logLines.isEmpty()) { note(page, "표시할 기록이 없습니다."); return; }
        LinkedHashSet<String> sources = new LinkedHashSet<String>();
        for (String line : logLines) { int bar = line.indexOf('|'); if (bar > 0) sources.add(line.substring(0, bar)); }
        if (!sources.contains(sourceFilter)) sourceFilter = "all";
        LinearLayout filters = new LinearLayout(this);
        filters.setGravity(Gravity.BOTTOM);
        filters.setPadding(dp(8), 0, 0, 0);
        tab(filters, "전체", "all"); tab(filters, "오류", "error"); tab(filters, "무선", "wireless"); tab(filters, "설치", "install");
        View gap = new View(this);
        filters.addView(gap, new LinearLayout.LayoutParams(0, 1, 1f));
        final ArrayList<String> order = new ArrayList<String>();
        order.add("all");
        order.addAll(sources);
        TextView from = label(I18n.t("출처") + ": " + (sourceFilter.equals("all") ? I18n.t("모두") : sourceFilter), 22, TEXT, false);
        from.setGravity(Gravity.CENTER);
        from.setMinHeight(dp(44));
        from.setPadding(dp(12), dp(6), dp(12), dp(6));
        GradientDrawable fromShape = new GradientDrawable();
        fromShape.setCornerRadius(dp(ROUND));
        fromShape.setColor(TILE);
        fromShape.setStroke(dp(1), OUTLINE);
        from.setBackgroundDrawable(fromShape);
        from.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                sourceFilter = order.get((order.indexOf(sourceFilter) + 1) % order.size());
                render();
            }
        });
        LinearLayout.LayoutParams fromLp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        fromLp.setMargins(0, 0, dp(8), dp(6));
        filters.addView(from, fromLp);
        page.addView(filters);
        page.addView(divider());
        panel = null;
        openPanel(page, 0);
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
            entry.setPadding(dp(22), dp(12), dp(22), dp(12));
            if (source.length() > 0) {
                TextView tag = label(source, 16, error ? RED : ACTIVE_BLUE, false);
                tag.setGravity(Gravity.CENTER);
                tag.setMinWidth(dp(76));
                tag.setPadding(dp(8), dp(3), dp(8), dp(3));
                GradientDrawable tagShape = new GradientDrawable();
                tagShape.setCornerRadius(dp(ROUND));
                tagShape.setColor(TILE);
                tagShape.setStroke(dp(1), error ? RED : OUTLINE);
                tag.setBackgroundDrawable(tagShape);
                LinearLayout.LayoutParams tagLp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                tagLp.setMargins(0, dp(2), dp(14), 0);
                entry.addView(tag, tagLp);
            }
            LinearLayout col = new LinearLayout(this);
            col.setOrientation(LinearLayout.VERTICAL);
            TextView msg = label(korean, 22, error ? RED : TEXT, false);
            msg.setLineSpacing(dp(2), 1f);
            col.addView(msg);
            if (!korean.equals(raw)) col.addView(label(raw, 16, DIM, false));
            entry.addView(col, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            add(page, entry);
            shown++;
        }
        if (shown == 0) note(page, "이 조건에 맞는 기록이 없습니다.");
    }

    /** A text tab with a cyan underline when chosen, like the stock tab strips. */
    private void tab(LinearLayout row, String text, final String value) {
        boolean on = categoryFilter.equals(value);
        LinearLayout t = new LinearLayout(this);
        t.setOrientation(LinearLayout.VERTICAL);
        t.setBackgroundDrawable(skin.tab());
        t.setSelected(on);
        TextView name = label(text, 24, on ? ACTIVE_BLUE : TEXT, on);
        name.setGravity(Gravity.CENTER);
        name.setPadding(0, dp(12), 0, dp(10));
        int width = (int) name.getPaint().measureText(name.getText().toString()) + dp(24); // a MATCH_PARENT underline would stretch the tab
        t.addView(name, new LinearLayout.LayoutParams(width, ViewGroup.LayoutParams.WRAP_CONTENT));
        View underline = new View(this);
        underline.setBackgroundColor(0x00000000); // OEM tab drawable already carries its highlight line.
        t.addView(underline, new LinearLayout.LayoutParams(width, dp(3)));
        t.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { categoryFilter = value; render(); }
        });
        row.addView(t);
    }

    /** A group of rows: they are added until the next section starts, with a thin line between them. */
    private void openPanel(LinearLayout page, int topMargin) {
        LinearLayout p = new LinearLayout(this);
        p.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, topMargin, 0, 0);
        page.addView(p, lp);
        panel = p;
        panelRows = 0;
    }

    /** Adds a row to the open group (with a thin line above all but the first), or to the page when none is open. */
    private void add(LinearLayout page, View view) {
        if (panel == null) { page.addView(view); return; }
        if (panelRows > 0) panel.addView(divider());
        panel.addView(view);
        panelRows++;
    }

    private void section(LinearLayout page, String title) {
        TextView t = label(title, 22, ACTIVE_BLUE, false);
        t.setPadding(dp(22), dp(14), 0, dp(8));
        page.addView(t);
        page.addView(divider());
        openPanel(page, 0);
    }

    /** Title in white over the value in a pale color, like the stock settings list. */
    private void row(LinearLayout page, String name, String value, int color) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.VERTICAL);
        r.setMinimumHeight(dp(72));
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setPadding(dp(22), dp(6), dp(22), dp(6));
        r.addView(label(name, 26, TEXT, true));
        r.addView(label(value, 22, color, false));
        add(page, r);
    }

    /** Use the same title/summary hierarchy as stock list rows, not a dashboard card. */
    private void hero(LinearLayout page, String title, String text, int color) {
        row(page, title, text, color);
        page.addView(divider());
    }

    /** A notice with a colored edge: errors, warnings, progress. */
    private void box(LinearLayout page, String title, String text, int color) {
        LinearLayout b = new LinearLayout(this);
        View edge = new View(this);
        edge.setBackgroundColor(color);
        b.addView(edge, new LinearLayout.LayoutParams(dp(6), ViewGroup.LayoutParams.MATCH_PARENT));
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(18), dp(14), dp(18), dp(14));
        col.addView(label(title, 26, color, false));
        TextView body = label(text, 20, TEXT, false);
        body.setLineSpacing(dp(2), 1f);
        col.addView(body);
        b.addView(col, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, 0, 0, 0);
        if (panel != null) panel.addView(b, lp); else page.addView(b, lp);
    }

    private void note(LinearLayout page, String text) {
        TextView t = label(text, 20, DIM, false);
        t.setLineSpacing(dp(2), 1f);
        if (panel != null) {
            t.setPadding(dp(22), dp(16), dp(22), dp(16));
            add(page, t);
        } else {
            t.setPadding(dp(22), dp(18), dp(22), 0);
            page.addView(t);
        }
    }

    private View divider() {
        View v = new View(this);
        v.setBackgroundDrawable(skin.drawable("co_bg_list_line", new ColorDrawable(LINE)));
        v.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)));
        return v;
    }

    private TextView label(String text, int sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(I18n.t(text));
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        t.setIncludeFontPadding(false);
        t.setShadowLayer(1f, 0f, 1f, BLACK);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private int dp(int value) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, getResources().getDisplayMetrics());
    }
}
