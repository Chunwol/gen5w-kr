import kr.gen5w.ui.ProjectionSettings;

public final class ProjectionSettingsTest {
    static int failures;

    static void check(String name, boolean ok) {
        if (ok) System.out.println("PASS " + name);
        else { failures++; System.out.println("FAIL " + name); }
    }

    public static void main(String[] args) {
        ProjectionSettings.Snapshot unk = ProjectionSettings.Snapshot.unknown();
        check("unknown snapshot defaults all keys to unknown",
                "unknown".equals(unk.cpSplit()) && "unknown".equals(unk.aaSplit())
                        && "unknown".equals(unk.cpEnable()) && "unknown".equals(unk.aaEnable())
                        && "unknown".equals(unk.cpRhd()) && "unknown".equals(unk.state("bogus")));

        ProjectionSettings.Snapshot def = ProjectionSettings.Snapshot.fromValues(null, -1, null, null, -1);
        check("unset V039 PhoneProjection keys all default off",
                "off".equals(def.cpSplit()) && "off".equals(def.aaSplit())
                        && "off".equals(def.cpEnable()) && "off".equals(def.aaEnable())
                        && "off".equals(def.cpRhd()));

        ProjectionSettings.Snapshot expl = ProjectionSettings.Snapshot.fromValues(1, 0, 1, 0, 1);
        check("explicit Settings.System values map cleanly to on/off",
                "on".equals(expl.cpSplit()) && "off".equals(expl.aaSplit())
                        && "on".equals(expl.cpEnable()) && "off".equals(expl.aaEnable())
                        && "on".equals(expl.cpRhd())
                        && "on".equals(expl.state(ProjectionSettings.KEY_CP_SPLIT))
                        && "on".equals(expl.state(ProjectionSettings.KEY_CP_RHD)));

        check("working result is non-terminal and stays pending",
                !ProjectionSettings.isTerminalResult("55", "55:working")
                        && ProjectionSettings.isPending("55", false, 5000L, 120000L, "55:working")
                        && !ProjectionSettings.isTimedOut("55", false, 5000L, 120000L, "55:working"));
        check("ok and failed results terminate pending and prevent timeout",
                ProjectionSettings.isTerminalResult("55", "55:ok")
                        && ProjectionSettings.isTerminalResult("55", "55:failed busy")
                        && !ProjectionSettings.isPending("55", false, 5000L, 120000L, "55:ok")
                        && !ProjectionSettings.isPending("55", false, 5000L, 120000L, "55:failed")
                        && !ProjectionSettings.isTimedOut("55", false, 150000L, 120000L, "55:ok"));
        check("timeout triggers at deadline while result non-terminal",
                ProjectionSettings.isTimedOut("55", false, 120000L, 120000L, "55:working")
                        && !ProjectionSettings.isPending("55", false, 120000L, 120000L, "55:working"));
        check("effectiveState reflects optimistic pending toggle only for matching pending key",
                "off".equals(ProjectionSettings.effectiveState(
                        ProjectionSettings.KEY_CP_SPLIT, ProjectionSettings.KEY_CP_SPLIT, "off", true, expl))
                        && "on".equals(ProjectionSettings.effectiveState(
                                ProjectionSettings.KEY_CP_RHD, ProjectionSettings.KEY_CP_SPLIT, "off", true, expl))
                        && "on".equals(ProjectionSettings.effectiveState(
                                ProjectionSettings.KEY_CP_SPLIT, ProjectionSettings.KEY_CP_SPLIT, "off", false, expl)));

        if (failures != 0) {
            System.out.println("== ProjectionSettings: " + failures + " failed");
            System.exit(1);
        }
        System.out.println("== ProjectionSettings: all passed");
    }
}
