package kr.gen5w.ui;

/**
 * Turns raw log lines into Korean for the screen only. Log files keep their English
 * text because the installer, tests and diagnostics read it. Free of Android types.
 */
public final class LogTranslator {
    static final int MAX_LINE = 200;

    /** First needle found in the line wins, so put the more specific ones first. */
    private static final String[][] PHRASES = {
        {"noreboot marker present", "설치 후 재부팅을 기다리는 중입니다"},
        {"ap-match is not 'match'", "핫스팟 설정이 아직 일치하지 않아 기다리는 중입니다"},
        {"wireless is turned off from the screen", "화면에서 무선을 꺼 두었습니다"},
        {"wired-only mode is set", "유선 전용 모드라 무선을 쓰지 않습니다"},
        {"restart guard is off", "재시작 보호가 걸려 무선이 꺼져 있습니다"},
        {"restart guard unusable", "재시작 보호를 쓸 수 없어 유선만 사용합니다"},
        {"no wlan0 yet", "USB 동글 Wi-Fi가 아직 인식되지 않았습니다"},
        {"host repeatedly failed to start", "무선 호스트가 반복해서 시작에 실패해 무선을 멈췄습니다"},
        {"AP broker repeatedly stopped", "핫스팟 중개 프로그램이 반복해서 멈춰 무선을 중단했습니다"},
        {"relay gate missing", "릴레이 확인 파일이 없어 무선을 중단했습니다"},
        {"incomplete V039 relay package", "릴레이 구성이 불완전해 무선을 중단했습니다"},
        {"starting the host", "무선 호스트를 시작하는 중입니다"},
        {"host alive", "무선 호스트가 실행 중입니다"},
        {"monthly reminder hidden", "블루링크 월간 안내를 숨겼습니다"},
        {"worker=owner", "세션 감시 프로세스(owner)가 비정상 종료되었습니다"},
        {"worker=broker", "핫스팟 중개 프로세스(broker)가 비정상 종료되었습니다"},
        {"active diagnosis incomplete", "진단 스냅샷 일부 수집이 시간 초과로 중단되었습니다"},
        {"error log collector failed", "실시간 오류 로그 수집에 실패했습니다"},
        {"FAIL projection setting", "폰 프로젝션 숨김 설정 적용에 실패했습니다"},
        {"UNSUPPORTED Wi-Fi adb", "이 버전에서는 Wi-Fi ADB 변경을 지원하지 않습니다"},
        {"session: host/AP/HUD supervisor running", "무선 호스트·AP·HUD 감시 서비스가 정상 실행 중입니다"},
    };

    /** Leading keywords the installer and services use; the rest of the line is kept as is. */
    private static final String[][] KEYWORDS = {
        {"INSTALLED ", "설치됨: "}, {"READY ", "준비됨: "}, {"RESTORED ", "복원됨: "},
        {"SKIP ", "건너뜀: "}, {"FAILED ", "실패: "}, {"REFUSED ", "거부됨: "},
        {"FAIL ", "실패: "}, {"WAIT ", "대기: "}, {"STEP ", "진행: "},
    };

    private LogTranslator() { }

    private static String cut(String s) { return s.length() > MAX_LINE ? s.substring(0, MAX_LINE) : s; }

    /** Korean text for a known line, otherwise the raw line (cut to 200 characters). */
    public static String translate(String raw) {
        if (raw == null) return "";
        int diagErr = raw.indexOf("Gen5wDiag ERR code=");
        if (diagErr >= 0) {
            String rest = raw.substring(diagErr + "Gen5wDiag ERR code=".length());
            int end = 0;
            while (end < rest.length() && rest.charAt(end) != ' ') end++;
            String code = rest.substring(0, end);
            return "내부 진단 오류" + (code.length() > 0 ? " (" + code + ")" : "");
        }
        int failure = raw.indexOf("relay start failure: ");
        if (failure >= 0) {
            String rest = raw.substring(failure + "relay start failure: ".length());
            int end = 0;
            while (end < rest.length() && rest.charAt(end) != ':' && rest.charAt(end) != ' ') end++;
            String name = rest.substring(0, end);
            int dot = name.lastIndexOf('.');
            if (dot >= 0) name = name.substring(dot + 1);
            return "릴레이를 켜지 못했습니다" + (name.length() > 0 ? " (" + name + ")" : "");
        }
        for (String[] phrase : PHRASES) if (raw.contains(phrase[0])) return phrase[1];
        for (String[] keyword : KEYWORDS) {
            if (raw.startsWith(keyword[0])) return cut(keyword[1] + raw.substring(keyword[0].length()));
        }
        return cut(raw);
    }

    private static boolean hasNonZeroCode(String raw, String prefix) {
        int from = 0;
        while (true) {
            int pos = raw.indexOf(prefix, from);
            if (pos < 0) return false;
            if (pos == 0 || !Character.isLetterOrDigit(raw.charAt(pos - 1))) {
                int start = pos + prefix.length();
                if (start < raw.length() && raw.charAt(start) == '-') start++;
                int end = start;
                boolean nonZero = false;
                while (end < raw.length() && Character.isDigit(raw.charAt(end))) {
                    if (raw.charAt(end) != '0') nonZero = true;
                    end++;
                }
                if (end > start && nonZero) return true;
            }
            from = pos + prefix.length();
        }
    }

    private static boolean hasToken(String raw, String word) {
        int from = 0;
        while (true) {
            int pos = raw.indexOf(word, from);
            if (pos < 0) return false;
            int end = pos + word.length();
            boolean startOk = pos == 0 || !Character.isLetterOrDigit(raw.charAt(pos - 1));
            boolean endOk = end == raw.length() || !Character.isLetterOrDigit(raw.charAt(end));
            if (startOk && endOk) {
                // Do not treat zero counters like "failed=0" or "timeout=0" as errors.
                if (end + 1 < raw.length() && raw.charAt(end) == '=' && raw.charAt(end + 1) == '0') {
                    int k = end + 1;
                    boolean nonZero = false;
                    while (k < raw.length() && Character.isDigit(raw.charAt(k))) {
                        if (raw.charAt(k) != '0') nonZero = true;
                        k++;
                    }
                    if (!nonZero) { from = end; continue; }
                }
                return true;
            }
            from = end;
        }
    }

    /** "error", "wireless", "install" or "other", for the filter chips. */
    public static String category(String raw) {
        return category(null, raw);
    }

    /** "error", "wireless", "install" or "other", considering log source as well. */
    public static String category(String source, String raw) {
        if (raw == null || raw.length() == 0) return "other";
        if (raw.startsWith("FAIL") || raw.contains(" FAIL")
                || hasToken(raw, "FAILED") || hasToken(raw, "failed") || hasToken(raw, "failure")
                || hasToken(raw, "blocked") || hasToken(raw, "timeout")
                || raw.contains("timed out") || raw.contains("incomplete")
                || raw.contains("Gen5wDiag ERR") || raw.contains(" ERR ") || raw.startsWith("ERR ")
                || raw.contains("ERROR") || raw.contains("error:")
                || raw.contains("FATAL EXCEPTION") || raw.contains("Exception")
                || raw.contains(" E/") || raw.startsWith("E/")
                || raw.contains(" F/") || raw.startsWith("F/")
                || raw.contains("SIGBUS") || raw.contains("SIGSEGV") || raw.contains("SIGABRT")
                || raw.contains("health-lost") || raw.contains("phase=failed")
                || hasNonZeroCode(raw, "exit=") || hasNonZeroCode(raw, "rc=")) {
            return "error";
        }
        if (raw.contains("bridge") || raw.contains("wireless")
                || raw.contains("CarPlay") || raw.contains("carplay")
                || raw.contains("iAP2") || raw.contains("iap2")
                || raw.contains("dipo") || raw.contains("Dipo")
                || raw.contains("wlan0") || raw.contains("dongle")
                || raw.contains("session:") || raw.contains("ap:")) {
            return "wireless";
        }
        if (raw.startsWith("INSTALLED") || raw.startsWith("READY") || raw.startsWith("RESTORED")
                || raw.startsWith("SKIP") || raw.startsWith("REFUSED")) return "install";
        return "other";
    }
}
