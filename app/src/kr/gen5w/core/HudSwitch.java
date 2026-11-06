package kr.gen5w.core;

import java.io.File;
import java.io.IOException;

/**
 * The HUD on/off switch of the in-car screen: one flag file in this app's own data folder.
 * Both the screen and the HUD service run as this app, so no other privilege is involved.
 * Free of Android types so it can be unit tested.
 */
public final class HudSwitch {
    static final String FLAG = "hud-disabled";

    private HudSwitch() { }

    /** True only when the flag file exists as a regular file in the folder. */
    public static boolean isOff(File dataDir) {
        if (dataDir == null) return false;
        try { return new File(dataDir, FLAG).isFile(); }
        catch (SecurityException e) { return false; }
    }

    /** Creates or removes the flag. Returns false when the change could not be made. */
    public static boolean setOff(File dataDir, boolean off) {
        if (dataDir == null || !dataDir.isDirectory()) return false;
        File flag = new File(dataDir, FLAG);
        try {
            if (off) return flag.isFile() || flag.createNewFile();
            return !flag.exists() || flag.delete();
        } catch (IOException e) {
            return false;
        } catch (SecurityException e) {
            return false;
        }
    }
}
