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
        add("상태가 오래되었거나 수집기가 응답하지 않아 조작을 잠갔습니다.", "Controls are locked because status is stale or the collector is not responding.");
        add("무선 호스트 준비", "Wireless host ready");
        add("호스트 실행은 Wi-Fi나 휴대폰 연결 성공을 뜻하지 않습니다.", "A running host does not confirm Wi-Fi or phone connection.");
        add("인터페이스 있음 (AP 연결 여부는 별도)", "Interface present (AP connection not confirmed)");
        add("인터페이스 없음", "Interface absent");
        add("ADB 접속 상태", "ADB listener status");
        add("리스닝 확인 (IP·키 승인은 별도)", "Listening verified (network and key approval still required)");
        add("포트 설정됨 / adbd 중단", "Port configured / adbd not running");
        add("포트 설정됨 / 리스닝 없음", "Port configured / not listening");
        add("예상 밖의 ADB 리스너 감지", "Unexpected ADB listener detected");
        add("ADB 설정 적용에 실패했습니다. 새 상태를 확인하고 다시 시도하세요.", "ADB configuration failed. Check fresh status and retry.");
        add("HUD 소유권 상태", "HUD ownership status");
        add("앱에서 꺼짐", "Disabled in this app");
        add("순정 내비 우선 (출력 차단)", "Stock navigation has priority (output blocked)");
        add("소유권 확인 실패 (출력 차단)", "Ownership unknown (output blocked)");
        add("출력 허용 (실제 표시는 별도 확인)", "Output permitted (physical display not verified)");
        add("서비스 응답 없음", "No service heartbeat");
        add("Android Auto는 순정 무선 지원과 등록이 필요합니다. CarPlay 전용 중계는 적용되지 않습니다.", "Android Auto requires stock wireless support and registration. The CarPlay-only relay does not apply.");
        add("새 상태를 기다린 뒤 다시 시도하세요.", "Wait for a fresh status update, then try again.");
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
        add("제거하는 동안 차를 끄거나 USB를 빼지 마세요. 중간에 실패하면 그 단계에서 멈추고 아무것도 강제로 지우지 않습니다. 다 지우면 차가 한 번 재부팅됩니다.",
            "Do not switch off the car or pull the USB while removing. If a step fails, it stops there and nothing is force-removed. When everything is removed, the car restarts once.");
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
        add("설치 복구", "Installation recovery");
        add("복구하는 중입니다", "Recovery in progress");
        add("설치 중단 · 복구 필요", "Installation stopped - recovery needed");
        add("이전 상태로 복구됨", "Previous state restored");
        add("복구 필요 없음", "No recovery required");
        add("복구 상태 확인 불가", "Recovery status unavailable");
        add("전원을 끄거나 USB를 분리하지 마세요. 성공하면 재부팅합니다.", "Do not turn off power or disconnect USB. Successful recovery will reboot.");
        add("설치가 끝나지 않아 추가 변경을 중단했습니다. 이전 상태로 복구한 뒤 다시 설치하세요.", "Installation did not finish. Further changes are blocked. Restore the previous state before reinstalling.");
        add("설치 직전 상태로 되돌렸습니다. 순정 초기화나 재설치 완료를 뜻하지 않습니다.", "Restored the pre-installation state. This is not a factory reset or a completed reinstall.");
        add("설치 복구가 필요한 기록이 없습니다.", "No installation recovery is recorded as necessary.");
        add("복구 기록을 읽을 수 없습니다. 정상 상태로 확인된 것은 아닙니다.", "Recovery records cannot be read. This does not confirm a healthy state.");
        add("관리 화면에서 원인과 다음 행동을 확인하세요.", "See Manage for the cause and next action.");
        add("복구 요청을 저장하지 못했습니다. 다시 확인하고 요청하세요.", "Could not save the recovery request. Check and try again.");
        add("복구 요청 응답을 확인하지 못했습니다. 진단을 저장하고 USB 복구 안내를 확인하세요.", "No recovery response confirmed. Save a diagnosis and follow the USB recovery instructions.");
        add("복구가 실패했거나 중단되었습니다. 원본과 진단을 보존하고 오류 상세를 확인하세요.", "Recovery failed or was interrupted. Preserve originals and diagnosis; check error details.");
        add("오류 상세", "Error details");
        add("실패 단계와 복구 가능 여부를 확인합니다.", "Check the failed stage and recovery availability.");
        add("상세", "Details"); add("실패 단계", "Failed stage"); add("순정 핫스팟 스위치", "Stock hotspot switch");
        add("복구 USB 준비가 필요합니다.", "Prepare the recovery USB first.");
        add("복구 백업이 없거나 검증되지 않았습니다.", "Recovery backup is missing or unverified.");
        add("다른 작업이 진행 중입니다.", "Another operation is running.");
        add("다른 작업이 진행 중입니다. 중단된 작업이라면 재부팅 후 상태를 다시 확인하세요.", "Another operation is running. If it was interrupted, reboot and check the status again.");
        add("실행 전에 백업과 복구 도구를 다시 검사합니다.", "Backups and recovery tools are checked again before execution.");
        add("원인 기록을 읽을 수 없습니다.", "The cause record cannot be read.");
        add("순정 복구가 끝나지 않았습니다. 이전 상태로 되돌리기는 쓸 수 없습니다.", "Stock recovery did not finish. Rolling back to the previous state is not available.");
        add("순정 복구 USB(GEN5W-ACTION=stock-recover)를 다시 꽂아 순정 복구를 끝내세요. 복구 표식을 지우지 마세요.", "Insert the stock recovery USB (GEN5W-ACTION=stock-recover) again to finish stock recovery. Do not delete recovery markers.");
        add("앱에서 복구할 수 없으면 새 복구 USB에서 recovery-prepare 후 rollback을 실행하세요. 복구 표식을 지우지 마세요.","If app recovery is unavailable, run recovery-prepare then rollback using the new recovery USB. Do not delete recovery markers.");
        add("이전 상태로 복구", "Restore previous state");
        add("주차 후 실행하세요. 공장 초기화가 아닙니다.", "Park before running. This is not a factory reset.");
        add("복구...", "Recover..."); add("복구 시작", "Start recovery");
        add("설치 전 상태로 되돌립니다. 성공하면 재부팅됩니다. 전원을 끄거나 USB를 분리하지 마세요.", "Restores the pre-installation state and reboots on success. Do not turn off power or disconnect USB.");
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
