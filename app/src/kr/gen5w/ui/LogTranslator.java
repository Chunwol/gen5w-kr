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

    /** "error", "wireless", "install" or "other", for the filter chips. */
    public static String category(String raw) {
        if (raw == null) return "other";
        if (raw.startsWith("FAIL") || raw.contains("relay start failure") || raw.contains("FATAL EXCEPTION")) return "error";
        if (raw.contains("bridge")) return "wireless";
        if (raw.startsWith("INSTALLED") || raw.startsWith("READY") || raw.startsWith("RESTORED")
                || raw.startsWith("SKIP") || raw.startsWith("REFUSED")) return "install";
        return "other";
    }
}
