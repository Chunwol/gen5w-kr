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
        check("readable", ok.readable());
        check("fresh", !ok.stale());
        same("host", "alive", ok.host());
        same("relay", "on", ok.relay());
        same("backend", "builtin", ok.backend());
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
        if (failures != 0) { System.out.println("== StatusModel: " + failures + " failed"); System.exit(1); }
        System.out.println("== StatusModel: all passed");
    }
}
