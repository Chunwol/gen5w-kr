package kr.gen5w.ui;

import java.util.HashMap;
import java.util.Map;

/**
 * Screen texts. The program text is Korean (the default); this table gives the English version of
 * each Korean sentence. A sentence without an entry is shown as it is, so a missing entry never
 * breaks the screen. "{0}" marks a value that is filled in. Free of Android types.
 */
public final class I18n {
    private static volatile boolean english;
    private static final Map<String, String> EN = new HashMap<String, String>();

    private I18n() { }

    public static void setEnglish(boolean value) { english = value; }
    public static boolean english() { return english; }

    /** The text in the current language. */
    public static String t(String korean) {
        if (!english || korean == null) return korean;
        String en = EN.get(korean);
        return en == null ? korean : en;
    }

    /** Same, with "{0}" replaced. */
    public static String t(String korean, String value) { return t(korean).replace("{0}", value); }

    public static boolean has(String korean) { return EN.containsKey(korean); }

    private static void add(String ko, String en) { EN.put(ko, en); }

    static {
        // Menu
        add("정보", "Info"); add("켜기/끄기", "On/Off"); add("기록", "Log"); add("관리", "Manage");
        add("불러오는 중...", "Loading...");
        // Info
        add("상태를 읽을 수 없음", "Cannot read the status");
        add("상태 수집 서비스가 아직 실행되지 않았거나, 이 앱이 상태 폴더를 읽을 권한이 없을 수 있습니다. 잠시 뒤 다시 확인하고, 계속 이러면 진단을 저장해 주세요.",
            "The status collector may not be running yet, or this app may not be allowed to read the status folder. Check again in a moment; if it keeps happening, save a diagnosis.");
        add("기록이 오래됨", "Status is old");
        add("이전 부팅 때의 기록입니다. 새 기록을 기다리는 중입니다.", "This is from an earlier boot. Waiting for a new one.");
        add("마지막 갱신이 {0}초 전입니다. 아래 값이 지금과 다를 수 있습니다.", "Last updated {0} seconds ago. The values below may differ from now.");
        add("무선 대기 중", "Wireless is waiting");
        add("무선 사용 가능", "Wireless is ready");
        add("무선 호스트가 실행 중입니다.", "The wireless host is running.");
        add("연결", "Connection");
        add("무선 호스트", "Wireless host");
        add("● 실행 중", "● Running"); add("● 실행 안 됨", "● Not running"); add("확인 못 함", "Unknown");
        add("릴레이 구성", "Relay setup");
        add("● 포함됨", "● Included"); add("● 없음", "● Missing");
        add("유선 전용 모드", "Wired-only mode"); add("켜짐", "On"); add("꺼짐", "Off");
        add("재시작 보호", "Restart guard");
        add("● 걸림(무선 꺼짐)", "● Active (wireless off)"); add("● 정상", "● Normal");
        add("설치", "Install");
        add("설치 버전", "Installed version");
        add("Wi-Fi 방식", "Wi-Fi type"); add("내장 Wi-Fi", "Built-in Wi-Fi"); add("USB 동글", "USB dongle");
        add("원인을 확인하지 못했습니다", "The reason is unknown");
        // On/Off
        add("끄면 몇 초 안에 반영됩니다. 설치된 파일은 그대로 남아 있어 언제든 다시 켤 수 있습니다. (제거가 아닙니다)",
            "Changes apply within a few seconds. Installed files stay, so you can turn them on again any time. (This is not removal.)");
        add("무선", "Wireless");
        add("설치 때 유선 전용으로 설치되어 여기서 켤 수 없습니다", "Installed as wired-only, so it cannot be turned on here");
        add("재시작 보호가 걸려 있어 여기서 켤 수 없습니다", "The restart guard is active, so it cannot be turned on here");
        add("상태를 읽을 수 없어 바꿀 수 없습니다", "Cannot change it because the status cannot be read");
        add("무선 CarPlay / Android Auto", "Wireless CarPlay / Android Auto");
        add("무선 연결 담당 서비스를 켜고 끕니다. 유선 연결은 그대로 동작합니다.", "Turns the wireless connection service on or off. Wired connection keeps working.");
        add("안내창", "Pop-ups");
        add("시동 안내창 자동 닫기", "Auto-close start-up notice");
        add("끄면 차 순정 10초 타이머로 돌아갑니다.", "When off, the car's own 10-second timer is used.");
        add("블루링크 월간 안내 숨기기", "Hide monthly Bluelink notice");
        add("끄면 차의 원래 안내 시간 값을 되돌립니다.", "When off, the car's original notice time values are restored.");
        add("HUD", "HUD");
        add("CarPlay HUD 연동", "CarPlay HUD link");
        add("끄면 이 앱의 HUD 서비스를 멈춥니다. 켜면 바로 다시 시작합니다.", "When off, this app's HUD service is stopped. Turning it on starts it again right away.");
        add("개발자 접속 (이번 부팅만)", "Developer access (this boot only)");
        add("차 Wi-Fi", "Car Wi-Fi");
        add("● 켜짐", "● On");
        add("● 꺼짐 (휴대폰이 접속할 Wi-Fi가 없음)", "● Off (no Wi-Fi for the phone to join)");
        add("이 스위치는 차의 Wi-Fi를 켜지 않고 접속 포트만 엽니다. 차가 이미 Wi-Fi에 연결돼 있어야 PC에서 adb connect <차 주소>:5555 로 접속할 수 있습니다. 차를 껐다 켜면 자동으로 꺼집니다. 순정 ADB 키 승인은 그대로 필요합니다.",
            "This switch does not turn the car's Wi-Fi on; it only opens the port. The car must already be on a Wi-Fi network before a PC can connect with adb connect <car address>:5555. It turns off by itself after a restart. The stock ADB key approval is still required.");
        add("이 화면에서 바꿀 수 없는 것", "Not changeable on this screen");
        add("오디오 모듈", "Audio module"); add("설치 / 제거로만", "Install / remove only");
        add("주행 기록", "Drive log"); add("USB 키트가 필요", "Needs the USB kit");
        add("Wi-Fi 동글", "Wi-Fi dongle");
        add("동글 방식으로 설치됨 (설치 때 정함)", "Installed in dongle mode (chosen at install)");
        add("해당 없음 (이 차는 내장 Wi-Fi)", "Not applicable (this car has built-in Wi-Fi)");
        // Manage
        add("전체 제거", "Remove everything");
        add("제거하는 중입니다", "Removing");
        add("끄지 말고 기다려 주세요. 패키지를 하나씩 되돌리며 제거합니다. {0}", "Please wait and do not switch off. Packages are rolled back and removed one by one. {0}");
        add("지금: {0}", "Now: {0}");
        add("거의 끝났습니다", "Almost done");
        add("Gen5W KR 패키지를 제거했습니다. 마지막으로 NEMESIS Manager의 My Packages에서 \"Gen5W KR - CarPlay HUD\"를 눌러 Uninstall 하세요. 이 앱 자체라서 화면에서는 지울 수 없습니다.",
            "The Gen5W KR packages were removed. Finally, open My Packages in NEMESIS Manager and tap Uninstall on \"Gen5W KR - CarPlay HUD\". This is the app itself, so it cannot be removed from this screen.");
        add("제거를 멈췄습니다", "Removal stopped");
        add("{0} 단계에서 멈췄습니다. 이 패키지와 이후 패키지는 그대로 남아 있습니다. 진단을 저장해 두고 다시 시도하거나 USB 제거 키트를 쓰세요.",
            "Stopped at {0}. This package and the ones after it are still installed. Save a diagnosis and try again, or use the USB removal kit.");
        add("Gen5W KR 전부 제거", "Remove all of Gen5W KR");
        add("무선, 오디오, 안내창, 블루링크, 주행 기록을 제거하고 차 설정을 처음 값으로 되돌립니다. 앱(CarPlay HUD)은 마지막에 NEMESIS Manager에서 지웁니다.",
            "Removes wireless, audio, notices, Bluelink and drive log, and restores the car settings. The app (CarPlay HUD) is removed last in NEMESIS Manager.");
        add("제거...", "Remove...");
        add("정말 제거할까요?", "Remove for real?");
        add("제거하는 동안 차를 끄거나 USB를 빼지 마세요. 중간에 실패하면 그 단계에서 멈추고 아무것도 강제로 지우지 않습니다.",
            "Do not switch off the car or pull the USB while removing. If a step fails, it stops there and nothing is force-removed.");
        add("제거 시작", "Start removal");
        add("되돌릴 수 없습니다. 다시 쓰려면 설치 키트로 다시 설치해야 합니다.", "This cannot be undone. To use it again you must reinstall with the install kit.");
        add("취소", "Cancel");
        add("아무것도 바꾸지 않습니다.", "Nothing is changed.");
        add("기능만 멈추기", "Only stop features");
        add("제거하지 않고 기능만 멈추려면 켜기/끄기 화면의 스위치를 쓰세요. 스위치를 꺼도 설치된 파일은 그대로 남습니다.",
            "To stop features without removing, use the switches on the On/Off screen. Installed files stay when a switch is off.");
        add("진단 저장", "Save diagnosis");
        add("저장하는 중입니다...", "Saving...");
        add("USB의 gen5w-kr-diag 폴더에 저장했습니다. USB를 PC에서 확인하세요.", "Saved to the gen5w-kr-diag folder on the USB. Check the USB on a PC.");
        add("USB가 연결되어 있지 않아 차 안에만 저장했습니다. USB를 꽂고 다시 누르세요.", "No USB is connected, so it was saved in the car only. Insert a USB and press again.");
        add("USB에 쓰지 못했습니다. USB를 확인하고 다시 누르세요.", "Could not write to the USB. Check the USB and press again.");
        add("상태, 최근 기록, 이 차의 시스템 정보를 한 파일로 USB에 저장합니다. 개인정보가 들어 있을 수 있는 줄은 뺍니다.",
            "Saves the status, recent log and this car's system information to one file on the USB. Lines that may hold personal data are left out.");
        add("저장", "Save");
        // Log
        add("표시할 기록이 없습니다.", "There is no log to show.");
        add("이 조건에 맞는 기록이 없습니다.", "No log lines match.");
        add("전체", "All"); add("오류", "Errors"); add("설치", "Install");
        add("모든 출처", "All sources");
        add("M월 d일 (E)", "EEE, MMM d");
        add("출처", "Source"); add("모두", "All");
        // Right-hand descriptions
        add("무선 연결 상태와 설치된 구성 요소를 보여 줍니다.", "Shows the wireless connection status and the installed parts.");
        add("기능을 켜고 끕니다. 설치된 파일은 지워지지 않습니다.", "Turns features on or off. Installed files are not deleted.");
        add("최근 기록을 보여 줍니다. 종류와 출처로 걸러 볼 수 있습니다.", "Shows the recent log. You can filter by kind and source.");
        add("진단 저장과 제거 같은 관리 작업을 합니다.", "Management tasks such as saving a diagnosis or removing.");
    }
}
