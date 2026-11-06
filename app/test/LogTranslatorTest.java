import kr.gen5w.ui.LogTranslator;

public final class LogTranslatorTest {
    static int failures;
    static void same(String name, String expected, String got) {
        if (expected.equals(got)) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name + " expected [" + expected + "] got [" + got + "]"); }
    }
    static String repeat(char c, int n) { StringBuilder b = new StringBuilder(); for (int i = 0; i < n; i++) b.append(c); return b.toString(); }
    public static void main(String[] args) {
        same("reboot pending", "설치 후 재부팅을 기다리는 중입니다",
                LogTranslator.translate("WAIT bridge: installer reboot is pending (noreboot marker present)"));
        same("ap match", "핫스팟 설정이 아직 일치하지 않아 기다리는 중입니다",
                LogTranslator.translate("WAIT bridge: wireless is not in match mode (ap-match is not 'match')"));
        same("wired only", "유선 전용 모드라 무선을 쓰지 않습니다",
                LogTranslator.translate("WAIT bridge: wired-only mode is set"));
        same("restart guard", "재시작 보호가 걸려 무선이 꺼져 있습니다",
                LogTranslator.translate("WAIT bridge: restart guard is off (too many unfinished starts); wireless stays off"));
        same("dongle", "USB 동글 Wi-Fi가 아직 인식되지 않았습니다",
                LogTranslator.translate("WAIT bridge: dongle edition: no wlan0 yet"));
        same("host failed", "무선 호스트가 반복해서 시작에 실패해 무선을 멈췄습니다",
                LogTranslator.translate("FAIL bridge: host repeatedly failed to start; wireless suspended until restart"));
        same("host starting", "무선 호스트를 시작하는 중입니다",
                LogTranslator.translate("WAIT bridge: starting the host (relay=0)"));
        same("host alive", "무선 호스트가 실행 중입니다", LogTranslator.translate("STEP bridge: host alive"));
        same("relay failure", "릴레이를 켜지 못했습니다 (NoClassDefFoundError)",
                LogTranslator.translate("relay start failure: java.lang.NoClassDefFoundError: x"));
        same("relay failure from logcat", "릴레이를 켜지 못했습니다 (NoClassDefFoundError)",
                LogTranslator.translate("11-06 12:00:00.000 E/gen5w-wireless( 1430): relay start failure: java.lang.NoClassDefFoundError: x"));
        same("bluelink", "블루링크 월간 안내를 숨겼습니다", LogTranslator.translate("bluelink: monthly reminder hidden"));
        same("install keyword keeps detail", "설치됨: bluelink: original values saved",
                LogTranslator.translate("INSTALLED bluelink: original values saved"));
        same("unknown stays raw", "something new", LogTranslator.translate("something new"));
        same("null is empty", "", LogTranslator.translate(null));
        same("long lines are cut", repeat('a', 200), LogTranslator.translate(repeat('a', 300)));
        same("category error", "error", LogTranslator.category("FAIL bridge: x"));
        same("category error relay", "error", LogTranslator.category("relay start failure: x"));
        same("category install failed", "error", LogTranslator.category("FAILED postinstall x rc=1"));
        same("category wireless", "wireless", LogTranslator.category("WAIT bridge: x"));
        same("category install", "install", LogTranslator.category("INSTALLED bluelink: x"));
        same("category other", "other", LogTranslator.category("hello"));
        same("category null", "other", LogTranslator.category(null));
        if (failures != 0) { System.out.println("== LogTranslator: " + failures + " failed"); System.exit(1); }
        System.out.println("== LogTranslator: all passed");
    }
}
