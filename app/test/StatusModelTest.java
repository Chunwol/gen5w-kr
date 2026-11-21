import java.util.Arrays;
import java.util.List;
import kr.gen5w.ui.StatusModel;

public final class StatusModelTest {
    static int failures;
    static void check(String name, boolean ok) {
        if (ok) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name); }
    }
    static void same(String name, String expected, String got) {
        check(name + " [" + got + "]", expected.equals(got));
    }
    static List<String> l(String... s) { return Arrays.asList(s); }
    public static void main(String[] args) {
        List<String> alive = l("ts=1000", "host=alive", "relay=on", "backend=builtin", "version=0.3.46", "apguard=on", "wired=no");
        StatusModel ok = StatusModel.parse(alive, l("bridge|WAIT bridge: wired-only mode is set"), 1010);
        check("legacy screen keeps legacy lifecycle", !ok.portable() && !ok.portableRemovalDone());
        check("portable done survives activity token loss", StatusModel.parse(l("portable_enabled=0", "removed=42:done"), null, 1000).portableRemovalDone());
        check("rearmed install ignores previous done", !StatusModel.parse(l("portable_enabled=1", "removed=42:done"), null, 1000).portableRemovalDone());
        same("rearmed screen drops old completion", "0:none", StatusModel.parse(l("portable_enabled=1", "removed=42:done"), null, 1000).removedState());
        check("portable failed is not done", !StatusModel.parse(l("portable_enabled=0", "removed=42:failed"), null, 1000).portableRemovalDone());
        check("unknown installation is not portable", !StatusModel.parse(l("portable_enabled=unknown"), null, 1000).portable());
        check("readable", ok.readable());
        check("fresh", !ok.stale());
        same("host", "alive", ok.host());
        same("relay", "on", ok.relay());
        same("backend", "builtin", ok.backend());
        same("built-in type", "내장 Wi-Fi", ok.wifiTypeText());
        same("built-in needs no dongle", "해당 없음 (이 차는 내장 Wi-Fi)", ok.dongleText());
        StatusModel noWifi = StatusModel.parse(l("backend=none", "wifi_why=none"), null, 1000);
        same("no Wi-Fi is not called unknown", "없음 (무선 사용 불가)", noWifi.wifiTypeText());
        same("no Wi-Fi is not called built-in", "지원 동글 없음. 5GHz 동글을 꽂고 다시 설치하세요", noWifi.dongleText());
        same("2.4 GHz-only install says why", "2.4GHz 전용 동글. 5GHz 동글로 다시 설치하세요",
                StatusModel.parse(l("backend=none", "wifi_why=2g-only"), null, 1000).dongleText());
        same("unknown backend stays unknown", "확인 못 함", StatusModel.parse(l("backend=x"), null, 1000).dongleText());
        same("dongle connected", "연결됨", StatusModel.parse(l("backend=dongle", "dongle=ready"), null, 1000).dongleText());
        same("dongle waiting", "5GHz 지원 동글을 꽂아 주세요", StatusModel.parse(l("backend=dongle", "dongle=waiting"), null, 1000).dongleText());
        same("dongle failed", "드라이버 실패. 동글을 뽑았다 다시 꽂으세요", StatusModel.parse(l("backend=dongle", "dongle=failed"), null, 1000).dongleText());
        same("dongle blocked", "재시작 보호로 멈춤. 동글을 뽑았다 다시 꽂으세요", StatusModel.parse(l("backend=dongle", "dongle=blocked"), null, 1000).dongleText());
        same("dongle 2.4 GHz", "2.4GHz 전용 동글. 5GHz 동글을 꽂아 주세요", StatusModel.parse(l("backend=dongle", "dongle=2g"), null, 1000).dongleText());
        same("edition without a dongle state", "동글 방식으로 설치됨 (설치 때 정함)", StatusModel.parse(l("backend=dongle", "dongle=bad"), null, 1000).dongleText());
        same("wlan unknown without the key", "unknown", ok.wlan());
        same("wlan present", "present", StatusModel.parse(l("ts=1000", "wlan=present"), null, 1010).wlan());
        same("wlan missing", "missing", StatusModel.parse(l("ts=1000", "wlan=missing"), null, 1010).wlan());
        same("version", "0.3.46", ok.bridgeVersion());
        check("apguard on is not off", !ok.apguardOff());
        check("not wired only", !ok.wiredOnly());
        same("alive host ignores old wait line", "", ok.why());

        List<String> dead = l("ts=1000", "host=dead");
        same("ap match reason", "핫스팟 설정이 아직 일치하지 않아 기다리는 중입니다",
                StatusModel.parse(dead, l("bridge|WAIT bridge: wireless is not in match mode (ap-match is not 'match')"), 1000).why());
        same("last bridge line wins", "유선 전용 모드라 무선을 쓰지 않습니다",
                StatusModel.parse(dead, l("bridge|WAIT bridge: wireless is not in match mode (ap-match is not 'match')",
                        "core|something", "bridge|WAIT bridge: wired-only mode is set", "core|later line"), 1000).why());
        same("other sources are ignored", "원인을 확인하지 못했습니다",
                StatusModel.parse(dead, l("core|WAIT bridge: wired-only mode is set"), 1000).why());
        same("English reason is the raw line", "WAIT bridge: wired-only mode is set",
                StatusModel.parse(dead, l("bridge|WAIT bridge: wired-only mode is set"), 1000).whyRaw());
        same("no bridge line", "원인을 확인하지 못했습니다", StatusModel.parse(dead, l("bridge|STEP bridge: host alive"), 1000).why());
        same("no log at all", "원인을 확인하지 못했습니다", StatusModel.parse(dead, null, 1000).why());
        same("unknown host gives no reason", "", StatusModel.parse(l("ts=1000", "host="), l("bridge|WAIT bridge: x"), 1000).why());

        check("stale after 60 seconds", StatusModel.parse(alive, null, 1100).stale());
        check("60 seconds is still fresh", !StatusModel.parse(alive, null, 1060).stale());
        check("missing ts is stale", StatusModel.parse(l("host=alive"), null, 5).stale());
        check("a snapshot from a later uptime (earlier boot) is stale", StatusModel.parse(alive, null, 900).stale());
        check("a few seconds of skew is tolerated", !StatusModel.parse(alive, null, 997).stale());
        check("age of a fresh snapshot", StatusModel.parse(alive, null, 1010).ageSeconds() == 10);
        check("age of an earlier-boot snapshot is unknown", StatusModel.parse(alive, null, 900).ageSeconds() == -1);

        StatusModel none = StatusModel.parse(null, null, 0);
        check("null is unreadable", !none.readable());
        check("unreadable() is unreadable", !StatusModel.unreadable().readable());
        same("unreadable host", "unknown", none.host());
        same("unreadable why", "", none.why());
        StatusModel messy = StatusModel.parse(l("garbage", "=novalue", "host=", "ts=abc", "relay=maybe", "apguard=off", "wired=yes"), null, 5);
        same("empty value is unknown", "unknown", messy.host());
        same("bad relay is unknown", "unknown", messy.relay());
        check("bad ts is stale", messy.stale());
        check("apguard off", messy.apguardOff());
        check("wired only", messy.wiredOnly());
                StatusModel sw = StatusModel.parse(java.util.Arrays.asList("ts=10", "sw_wireless=off", "sw_timer=on", "sw_bluelink=weird"), null, 12);
        check("wireless switch off", sw.switchWireless().equals("off"));
        check("timer switch on", sw.switchTimer().equals("on"));
        check("unknown switch word is unknown", sw.switchBluelink().equals("unknown"));
        check("missing switches are unknown", StatusModel.parse(java.util.Arrays.asList("ts=10"), null, 12).switchWireless().equals("unknown"));
        check("unreadable switches are unknown", StatusModel.unreadable().switchTimer().equals("unknown"));
        check("saved state is read", StatusModel.parse(java.util.Arrays.asList("ts=10", "saved=77:usb"), null, 12).savedState().equals("77:usb"));
        check("missing saved state is none", StatusModel.parse(java.util.Arrays.asList("ts=10"), null, 12).savedState().equals("0:none"));
        check("adb switch is read", StatusModel.parse(java.util.Arrays.asList("ts=10", "sw_adb=on"), null, 12).switchAdb().equals("on"));
        check("adb switch missing is unknown", StatusModel.parse(java.util.Arrays.asList("ts=10"), null, 12).switchAdb().equals("unknown"));
        check("removed state is read", StatusModel.parse(java.util.Arrays.asList("ts=10", "removed=5:failed:gen5w.kr.audio"), null, 12).removedState().equals("5:failed:gen5w.kr.audio"));
        check("missing removed state is none", StatusModel.parse(java.util.Arrays.asList("ts=10"), null, 12).removedState().equals("0:none"));
        if (failures != 0) { System.out.println("== StatusModel: " + failures + " failed"); System.exit(1); }
        System.out.println("== StatusModel: all passed");
    }
}
