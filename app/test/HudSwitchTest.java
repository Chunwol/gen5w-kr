import java.io.File;
import kr.gen5w.core.HudSwitch;

public final class HudSwitchTest {
    static int failures;
    static void check(String name, boolean ok) {
        if (ok) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name); }
    }
    public static void main(String[] args) throws Exception {
        File dir = File.createTempFile("hud", "dir"); dir.delete(); dir.mkdir(); dir.deleteOnExit();
        check("no flag means the HUD is on", !HudSwitch.isOff(dir));
        check("turning off succeeds", HudSwitch.setOff(dir, true));
        check("flag means the HUD is off", HudSwitch.isOff(dir));
        check("turning off twice succeeds", HudSwitch.setOff(dir, true));
        check("turning on succeeds", HudSwitch.setOff(dir, false));
        check("no flag again", !HudSwitch.isOff(dir));
        check("turning on twice succeeds", HudSwitch.setOff(dir, false));
        File odd = new File(dir, "hud-disabled"); odd.mkdir();
        check("a folder with the flag name does not count", !HudSwitch.isOff(dir));
        check("turning off with a folder in the way fails", !HudSwitch.setOff(dir, true));
        odd.delete();
        check("null folder is on", !HudSwitch.isOff(null));
        check("null folder cannot be changed", !HudSwitch.setOff(null, true));
        check("missing folder cannot be changed", !HudSwitch.setOff(new File("no-such-dir-xyz"), true));
        new File(dir, "hud-disabled").delete();
        if (failures != 0) { System.out.println("== HudSwitch: " + failures + " failed"); System.exit(1); }
        System.out.println("== HudSwitch: all passed");
    }
}
