import kr.gen5w.hud.ClusterIcon;
import kr.gen5w.hud.Maneuver;
import kr.gen5w.hud.StockTurn;

public final class StockTurnTest {
    private static void check(String n, int e, int a) {
        if (e != a) throw new AssertionError(n + " expected=0x" + Integer.toHexString(e) + " got=0x" + Integer.toHexString(a));
    }
    private static void check(String n, boolean a) { if (!a) throw new AssertionError(n); }

    public static void main(String[] args) {
        // Proven 15-spoke SetSideStreetBit masks from stock drive-00.log and libExSLNavi.so.
        check("straight+slight-right", 0x0003, StockTurn.maskFromAngles(0, 22));
        check("straight+left", 0x0801, StockTurn.maskFromAngles(0, 270));
        check("straight+diagonal-left", 0x1001, StockTurn.maskFromAngles(0, 292));
        check("three-way", 0x4003, StockTurn.maskFromAngles(0, 22, 337));
        check("incoming excluded when non-main", 0x0001, StockTurn.maskFromAngles(0, 180));
        check("near-uturn main right-of-180", 0x0081, StockTurn.maskFromAnglesAndMain(new int[]{0}, 175));
        check("near-uturn main left-of-180", 0x0101, StockTurn.maskFromAnglesAndMain(new int[]{0}, 185));
        for (int deg = 0; deg < 360; deg++) {
            int bit = StockTurn.maskFromAnglesAndMain(new int[]{deg}, deg);
            check("bit 15 never set at " + deg, (bit & 0x8000) == 0);
        }
        check("right direction", 12, StockTurn.directionFromAngle(90));
        check("left direction", 36, StockTurn.directionFromAngle(270));
        check("near bar at 400m", 10, StockTurn.remainRatio(400));
        check("near bar at 0m drains to 1", 1, StockTurn.remainRatio(0));
        check("far bar hidden", 15, StockTurn.remainRatio(401));
        check("stock drive 290/340", 8, StockTurn.remainRatio(290, true, 340));
        check("stock drive 250/340", 7, StockTurn.remainRatio(250, true, 340));
        check("stock drive 90/340", 2, StockTurn.remainRatio(90, true, 340));
        check("stock drive 60/340", 1, StockTurn.remainRatio(60, true, 340));
        check("guideDistance caps at 400", 400, (int) StockTurn.guideDistance(700));
        check("guideDistance keeps entry < 400", 250, (int) StockTurn.guideDistance(250));
        check("clear frame uses idle displayType 8", 8, StockTurn.build(null, 0, -1, false).displayType);

        // Near/far hysteresis (400m enter, 550m exit).
        check("far stays far above 400", !StockTurn.near(401, false));
        check("near hysteresis enters at 400", StockTurn.near(400, false));
        check("near hysteresis holds at 550", StockTurn.near(550, true));
        check("near hysteresis exits at 551", !StockTurn.near(551, true));

        // Ordinary turn: far keeps icon, near switches to SetCaseTurnPoint (0x0d) with real angles & combi=0.
        Maneuver turn = new Maneuver();
        turn.type = 1; turn.drivingSide = 0; turn.junctionType = 0;
        turn.exitAngle = -90;
        turn.hasJunctionElementAngles = true;
        turn.junctionElementAngles = new int[]{0, 22, 270};
        int icon = ClusterIcon.of(turn);
        check("left turn icon", 0x46, icon);
        StockTurn.Frame farTurn = StockTurn.build(turn, icon, 700, false);
        check("far keeps Korean icon", icon, farTurn.displayType);
        check("far clears sideStreet", 0, farTurn.sideStreet);
        check("far clears direction", 0, farTurn.directionType);
        check("far clears combi", 0, farTurn.combiSideStreet);
        StockTurn.Frame nearTurn = StockTurn.build(turn, icon, 400, farTurn.near);
        check("near switches to TURN 0x0d", StockTurn.DISPLAY_TURN, nearTurn.displayType);
        check("near uses junction angles + exit", 0x0803, nearTurn.sideStreet);
        check("near uses clockwise exit dir", 36, nearTurn.directionType);
        check("near keeps combi 0", 0, nearTurn.combiSideStreet);

        // Fallback when angles are absent.
        Maneuver noAngles = new Maneuver();
        noAngles.type = 2; noAngles.drivingSide = 0; noAngles.junctionType = 0; noAngles.exitAngle = 90;
        StockTurn.Frame nearFallback = StockTurn.build(noAngles, ClusterIcon.of(noAngles), 200, false);
        check("fallback turn 0x0d", StockTurn.DISPLAY_TURN, nearFallback.displayType);
        check("fallback right mask", 0x0011, nearFallback.sideStreet);
        check("fallback right dir", 12, nearFallback.directionType);

        // U-turn, Fork, ExpExit, Overpass, Underpass, Rotary, Tunnel/Toll, Dest.
        Maneuver uturn = new Maneuver(); uturn.type = 4; uturn.drivingSide = 0; uturn.junctionType = 0;
        StockTurn.Frame uFrame = StockTurn.build(uturn, 0x48, 250, false);
        check("uturn 0x1f", StockTurn.DISPLAY_UTURN, uFrame.displayType);
        check("uturn rhd dir 36", 36, uFrame.directionType);

        Maneuver fork = new Maneuver(); fork.type = 52; fork.drivingSide = 0; fork.junctionType = 0;
        StockTurn.Frame fFrame = StockTurn.build(fork, 0xae, 300, false);
        check("fork without angles 0x19", StockTurn.DISPLAY_FORK_Y, fFrame.displayType);
        check("left fork dir 36", 36, fFrame.directionType);

        Maneuver exitR = new Maneuver(); exitR.type = 23; exitR.drivingSide = 0; exitR.junctionType = 0;
        StockTurn.Frame erFrame = StockTurn.build(exitR, ClusterIcon.IC_EXIT_R, 300, false);
        check("exit right 0x11", StockTurn.DISPLAY_EXP_EXIT_RIGHT, erFrame.displayType);
        check("exit right dir 12", 12, erFrame.directionType);

        StockTurn.Frame overL = StockTurn.build(null, ClusterIcon.OVERPASS_SIDE_L, 200, false);
        check("overpass left 0x2c", StockTurn.DISPLAY_OVERPASS_LEFT, overL.displayType);
        check("overpass left dir 36", 36, overL.directionType);

        StockTurn.Frame underL = StockTurn.build(null, ClusterIcon.UNDERPASS_ENTRY_LC, 200, false);
        check("underpass left 0x2e", StockTurn.DISPLAY_UNDERPASS_LEFT, underL.displayType);

        Maneuver rotary = new Maneuver(); rotary.type = 6; rotary.drivingSide = 0; rotary.junctionType = 1; rotary.exitAngle = 90;
        StockTurn.Frame rotFrame = StockTurn.build(rotary, 0x63, 250, false);
        check("rotary ccw 0x20", StockTurn.DISPLAY_ROTARY_CCW, rotFrame.displayType);
        check("rotary dir 12", 12, rotFrame.directionType);
        check("rotary mask 0x11", 0x0011, rotFrame.sideStreet);

        // Type 47..50 (sharp/slight turns) must NOT be treated as rotary.
        Maneuver slightR = new Maneuver(); slightR.type = 50; slightR.drivingSide = 0; slightR.junctionType = 0; slightR.exitAngle = 45;
        StockTurn.Frame srFrame = StockTurn.build(slightR, 0x90, 250, false);
        check("type 50 is ordinary turn not rotary", StockTurn.DISPLAY_TURN, srFrame.displayType);

        // Tunnel, toll, dest keep Korean far icon even when near.
        Maneuver tunnel = new Maneuver(); tunnel.type = 3; tunnel.drivingSide = 0; tunnel.junctionType = 0; tunnel.afterRoad = "남산1호터널";
        check("tunnel keeps icon", 0x41, StockTurn.build(tunnel, 0x41, 150, false).displayType);
        check("toll keeps 0xb2", ClusterIcon.TOLL, StockTurn.build(null, ClusterIcon.TOLL, 150, false).displayType);
        check("dest keeps 0x70", 0x70, StockTurn.build(null, 0x70, 50, false).displayType);

        System.out.println("== StockTurn: all passed");
    }
}
