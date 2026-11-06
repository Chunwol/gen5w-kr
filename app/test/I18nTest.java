import java.io.File;
import java.nio.file.Files;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import kr.gen5w.ui.I18n;

/** Every Korean sentence in the screen source must have an English version (arg 0 = MainActivity.java). */
public final class I18nTest {
    static int failures;
    static void check(String name, boolean ok) {
        if (ok) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name); }
    }
    public static void main(String[] args) throws Exception {
        I18n.setEnglish(false);
        check("Korean is the default text", I18n.t("관리").equals("관리"));
        check("a sentence without an entry is unchanged", I18n.t("아직 없는 문장").equals("아직 없는 문장"));
        check("null stays null", I18n.t(null) == null);
        I18n.setEnglish(true);
        check("English text for a tab", I18n.t("관리").equals("Manage") && I18n.t("정보").equals("Info"));
        check("a sentence without an entry is unchanged in English", I18n.t("아직 없는 문장").equals("아직 없는 문장"));
        check("a value is filled in", I18n.t("지금: {0}", "audio").equals("Now: audio"));
        I18n.setEnglish(false);
        check("a value is filled in (Korean)", I18n.t("지금: {0}", "audio").equals("지금: audio"));

        String src = new String(Files.readAllBytes(new File(args[0]).toPath()), "UTF-8");
        src = src.replaceAll("(?s)/\\*.*?\\*/", "").replaceAll("(?m)//.*$", "");
        Matcher m = Pattern.compile("\"((?:[^\"\\\\\\n]|\\\\.)*)\"").matcher(src);
        int found = 0, missing = 0;
        while (m.find()) {
            String text = m.group(1).replace("\\\"", "\"");
            if (!Pattern.compile("[\\uAC00-\\uD7A3]").matcher(text).find()) continue;
            if (text.equals("한국어")) continue; // the button that switches back to Korean
            found++;
            if (!I18n.has(text)) { missing++; System.out.println("  no English for: " + text); }
        }
        check("the screen source has Korean sentences to check", found > 40);
        check("every Korean sentence in the screen has an English version", missing == 0);
        if (failures != 0) { System.out.println("== I18n: " + failures + " failed"); System.exit(1); }
        System.out.println("== I18n: all passed");
    }
}
