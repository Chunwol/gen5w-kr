import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** The screen may only use the stock-settings palette listed below (args = source files to scan). */
public final class PaletteTest {
    public static void main(String[] args) throws Exception {
        // The head unit's own Settings app values (white, #888888, #505050, #00C2FF, #2DC4F3, #CCCCCC, its
        // translucent white/cyan overlays), the navy background measured from the stock screen, and the
        // three Hyundai published colors kept for status text (Gold, Active Red, Sand).
        Set<String> allowed = new HashSet<String>(Arrays.asList(
                "0xFFFFFFFF", "0xFF000000", "0xFF888888", "0xFF505050", "0xFF00C2FF", "0xFF2DC4F3", "0xFFCCCCCC",
                "0xFF101015", "0xFF1B2B4E", "0xFFA36B4F", "0xFFE63312", "0xFFE4DCD3",
                "0x14FFFFFF", "0x08FFFFFF", "0x3300C2FF", "0x66FFFFFF", "0x00000000"));
        int bad = 0, seen = 0;
        for (String path : args) {
            String src = new String(Files.readAllBytes(new File(path).toPath()), "UTF-8");
            Matcher m = Pattern.compile("0x[0-9A-Fa-f]{8}\\b").matcher(src);
            while (m.find()) {
                seen++;
                String c = "0x" + m.group().substring(2).toUpperCase();
                if (!allowed.contains(c)) { bad++; System.out.println("  not an allowed color: " + m.group() + " in " + path); }
            }
        }
        if (seen < 9) { System.out.println("FAIL palette test found too few colors"); System.exit(1); }
        if (bad != 0) { System.out.println("FAIL screen uses colors outside the allowed palette"); System.exit(1); }
        System.out.println("PASS every color is in the allowed palette");
    }
}
