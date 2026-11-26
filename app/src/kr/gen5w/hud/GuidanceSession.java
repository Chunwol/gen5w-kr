package kr.gen5w.hud;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.List;
import kr.gen5w.probe.Item;

/** One serialized route-guidance session. No Android dependencies. Only explicit
 * current-index selections are displayed; transitions invalidate cached turns.
 */
public final class GuidanceSession {
    public interface Sink { boolean turns(byte[] frame); }
    public interface LaneSink extends Sink { boolean lanes(byte[] frame); }
    public interface TbtSink extends LaneSink { boolean tbt(int icon, int secondIcon, long distanceMeters); }
    /** Optional: remaining distance to the destination; -1 clears. */
    public interface RemainSink extends TbtSink { boolean remaining(long distanceMeters); }
    /** Optional: destination name; empty string clears. */
    public interface DestinationSink extends RemainSink { boolean destination(String name); }
    /** Optional: seconds until arrival, -1 clears. Sent when the minute changes. */
    public interface TimeSink extends DestinationSink { boolean timeRemaining(long seconds); }
    /** Optional: auxiliary tunnel HVAC/ADASIS signal (PE_00). Clear is emitted only after an active tunnel was sent. */
    public interface TunnelSink extends TimeSink { boolean tunnel(boolean active, long distanceMeters); }
    public static final int STATE_LOCATING = 4;
    /** Maximum hold across tunnel/underpass GPS loss before clearing cluster/HUD output. */
    public static final long LOCATING_GRACE_MS = 60000L;
    public static final long TUNNEL_MAX_DISTANCE_M = 1000L;
    private final Sink sink;
    private boolean outputAllowed = true;
    private boolean holdingLocating;
    private boolean phoneRoute;
    private long locatingSinceMs = -1L;
    private final Map<Long, Maneuver> maneuvers = new LinkedHashMap<Long, Maneuver>();
    private int component = -1, state = -1;
    private String source;
    private int[] current = new int[0];
    private byte[] lastFrame;
    private byte[] lastLanes;
    private byte[] desiredFrame, desiredLanes;
    private boolean desiredTbt;
    private int desiredIcon, desiredSecondIcon;
    private long desiredDistance;
    private boolean desiredTunnelActive, sentTunnelActive, requestedTunnelActive;
    private long desiredTunnelBucket = -1L, sentTunnelBucket = Long.MIN_VALUE;
    private final Map<Long, GuidanceParser.Lanes> laneSets = new LinkedHashMap<Long, GuidanceParser.Lanes>();
    private int laneIndex = -1, laneTotal = -1;
    private boolean laneVisible;
    private long distance = -1, sentDistance = Long.MIN_VALUE;
    private long remaining = -1, sentRemaining = Long.MIN_VALUE;
    private String destination = "", sentDestination;
    private long timeLeft = -1, sentTimeMinute = Long.MIN_VALUE, timeLeftAtMs = System.currentTimeMillis();
    private int sentIcon = Integer.MIN_VALUE, sentSecondIcon = Integer.MIN_VALUE;

    public GuidanceSession(Sink sink) { this.sink = sink; }
    /** Yield without emitting clears; retain only the latest desired CarPlay data. */
    public void setOutputAllowed(boolean allowed) {
        if (outputAllowed == allowed) return;
        outputAllowed = allowed;
        invalidateOutput();
    }
    public void message(int what, List<Item> fields) {
        List<Item> selected = GuidanceParser.forComponent(fields, component);
        if (selected == null) { disconnect(); return; }
        if (what == GuidanceParser.STATUS) status(GuidanceParser.status(selected));
        else if (what == GuidanceParser.MANEUVER) {
            int[] address = GuidanceParser.address(selected);
            Maneuver old = address == null ? null : maneuvers.get(key(address[0], address[1]));
            maneuver(GuidanceParser.maneuver(selected, old));
        } else if (what == GuidanceParser.LANES) {
            int[] address = GuidanceParser.address(selected);
            GuidanceParser.Lanes old = address == null ? null : laneSets.get(key(address[0], address[1]));
            GuidanceParser.Lanes next = GuidanceParser.lanes(selected, old);
            if (next == null) { clearLaneState(); emitLanes(LaneFrame.clear()); return; }
            if (laneSets.size() >= 128 && !laneSets.containsKey(key(next.component,next.index))) {
                Long victim = null;
                for (Long candidate : laneSets.keySet()) if (candidate.longValue() != key(component,laneIndex)) { victim = candidate; break; }
                if (victim != null) laneSets.remove(victim);
            }
            laneSets.put(key(next.component,next.index), next);
            if (component >= 0) renderLanes();
        }
    }
    public void maneuver(Maneuver m) {
        if (m == null) { disconnect(); return; }
        if (m.appSource == null) m.appSource = this.source;
        long newKey = key(m.component, m.index);
        if (!maneuvers.containsKey(newKey) && maneuvers.size() >= 128) {
            Long victim = null;
            for (Long candidate : maneuvers.keySet()) {
                boolean selected = false;
                for (int index : current) if (candidate.longValue() == key(component, index)) selected = true;
                if (!selected) { victim = candidate; break; }
            }
            if (victim == null) return;
            maneuvers.remove(victim);
        }
        maneuvers.put(newKey, m);
        if (component >= 0) render();
    }
    public void status(GuidanceParser.Status update) {
        if (update == null) { disconnect(); return; }
        boolean wasActive = isDisplayActive();
        boolean changed = component >= 0 && component != update.component;
        if (changed) { phoneRoute = false; maneuvers.clear(); clearLaneState(); current = new int[0]; state = -1; holdingLocating = false; locatingSinceMs = -1L; source = null; distance = -1; remaining = -1; destination = ""; timeLeft = -1; wasActive = false; }
        component = update.component;
        if (update.hasSource) {
            if (source != null && !source.equals(update.source)) {
                phoneRoute = false;
                maneuvers.clear(); current = new int[0];
                clearLaneState();
                holdingLocating = false; locatingSinceMs = -1L;
                distance = -1; remaining = -1; destination = ""; timeLeft = -1;
                wasActive = false;
            }
            source = update.source;
        }
        if (update.hasState) {
            state = update.state;
            // Route ownership is independent of a selected/loaded turn. States 4/5 are
            // locating/rerouting; only retain a previously established route there.
            if (isNavigating(state)) phoneRoute = true;
            else if (state != STATE_LOCATING && state != 5) phoneRoute = false;
            if (isNavigating(state)) {
                holdingLocating = false;
                locatingSinceMs = -1L;
            } else if (state == STATE_LOCATING && wasActive) {
                holdingLocating = true;
            } else {
                holdingLocating = false;
                locatingSinceMs = -1L;
            }
        }
        boolean keepEmptyLocatingCurrent = holdingLocating && update.hasCurrent && update.current.length == 0;
        if (update.hasCurrent && !Arrays.equals(current,update.current) && !update.hasLaneIndex && !keepEmptyLocatingCurrent) {
            clearLaneState();
        }
        if (update.hasCurrent && !keepEmptyLocatingCurrent) {
            if (!Arrays.equals(current,update.current)) distance = -1;
            current = update.current.clone();
        }
        if (update.hasDistance) distance = update.distanceToNext;
        if (update.hasRemaining && (update.distanceRemaining >= 0 || !phoneRoute)) remaining = update.distanceRemaining;
        if (update.hasTime && (update.timeRemaining >= 0 || !phoneRoute)) { timeLeft = update.timeRemaining; timeLeftAtMs = System.currentTimeMillis(); }
        if (update.hasDestination) destination = update.destination == null ? "" : update.destination;
        if (update.hasLaneIndex) laneIndex = update.laneIndex;
        if (update.hasLaneTotal) laneTotal = update.laneTotal;
        if (update.hasLaneVisible) laneVisible = update.laneVisible;
        if (!isDisplayActive()) {
            // A long tunnel outlives the locating grace: the phone still owns its route (state 4)
            // and only resends maneuver definitions when they change, so keep them for the GPS
            // recovery and hide the output instead (0.3.93 car log: HUD stayed blank after tunnels).
            // Rerouting (5) and every other state still drop the old route's maneuvers.
            if (!(phoneRoute && state == STATE_LOCATING)) { maneuvers.clear(); current = new int[0]; }
            clearLaneState();
            distance = -1;
            if (!phoneRoute) { remaining = -1; destination = ""; timeLeft = -1; }
        }
        render();
    }
    public static boolean isNavigating(int s) { return s == 1 || s == 6; }
    private boolean isDisplayActive() { return isNavigating(state) || holdingLocating; }
    /** Clears held underpass/tunnel locating state once LOCATING_GRACE_MS elapses without recovery. */
    public void expireLocating(long nowMs) {
        if (!holdingLocating) return;
        if (locatingSinceMs < 0L || nowMs < locatingSinceMs) {
            locatingSinceMs = nowMs;
            return;
        }
        if (nowMs - locatingSinceMs < LOCATING_GRACE_MS) return;
        holdingLocating = false;
        locatingSinceMs = -1L;
        if (!(phoneRoute && state == STATE_LOCATING)) { maneuvers.clear(); current = new int[0]; }
        clearLaneState();
        distance = -1;
        // Expire stale maneuver output, not route totals, ownership or the route's maneuver list.
        render();
    }
    public void disconnect() {
        phoneRoute = false;
        component = -1; state = -1; source = null;
        holdingLocating = false; locatingSinceMs = -1L;
        current = new int[0]; maneuvers.clear();
        clearLaneState();
        distance = -1; remaining = -1; destination = ""; timeLeft = -1;
        emit(TurnFrame.clear());
        emitLanes(LaneFrame.clear());
        emitTbt(0, 0, -1);
        emitRemaining(-1);
        emitDestination("");
        emitTime(-1);
        emitTunnel(false, -1L);
    }
    private void render() {
        renderLanes();
        boolean active = isDisplayActive();
        Maneuver selected = current.length == 0 ? null : maneuvers.get(key(component,current[0]));
        int rawIcon = active ? ClusterIcon.of(selected) : ClusterIcon.NONE;
        int selectedIcon = TurnFrame.effectiveIcon(rawIcon, distance);
        boolean farStraight = rawIcon > 0 && distance > TurnFrame.FAR_STRAIGHT_THRESHOLD_M;
        int secondIcon = ClusterIcon.NONE;
        if (!farStraight && active && current.length > 1) {
            Maneuver second = maneuvers.get(key(component, current[1]));
            secondIcon = ClusterIcon.of(second);
        }
        int firstCode = selectedIcon < 0 ? 0 : selectedIcon;
        int secondCode = secondIcon < 0 ? 0 : secondIcon;
        emitTbt(firstCode, secondCode, selectedIcon < 0 ? -1 : distance);
        emitRemaining(phoneRoute ? remaining : -1);
        emitDestination(phoneRoute ? destination : "");
        emitTime(phoneRoute ? timeLeft : -1);
        boolean tunnelAhead = active && selected != null && ClusterIcon.isTunnelText(selected.afterRoad, selected.desc);
        boolean inTunnelRange = distance >= 0 && distance <= TUNNEL_MAX_DISTANCE_M;
        // GPS loss only keeps a tunnel that was already near (active before the loss); an unknown
        // distance never promotes a distant tunnel to an active 0m tunnel.
        boolean tunnelActive = tunnelAhead && (inTunnelRange || (holdingLocating && desiredTunnelActive));
        emitTunnel(tunnelActive, tunnelActive ? (holdingLocating ? 0L : distance) : -1L);
        if (!active || current.length == 0) { emit(TurnFrame.clear()); return; }
        Maneuver first = maneuvers.get(key(component, current[0]));
        if (first == null) { emit(TurnFrame.clear()); return; }
        int[] icons;
        if (farStraight) {
            icons = new int[]{TurnFrame.ICON_STRAIGHT};
        } else {
            icons = new int[Math.min(3, current.length)];
            for (int i = 0; i < icons.length; i++) icons[i] = ClusterIcon.of(maneuvers.get(key(component, current[i])));
        }
        emit(TurnFrame.encode(icons, first.afterRoad));
    }
    private void emit(byte[] frame) {
        desiredFrame = frame;
        if (outputAllowed && !Arrays.equals(lastFrame, frame) && sink.turns(frame.clone())) lastFrame = frame;
    }
    private void emitTbt(int icon, int secondIcon, long meters) {
        desiredTbt = true; desiredIcon = icon; desiredSecondIcon = secondIcon; desiredDistance = meters;
        if (outputAllowed && sink instanceof TbtSink && (icon != sentIcon || secondIcon != sentSecondIcon || meters != sentDistance)
                && ((TbtSink)sink).tbt(icon, secondIcon, meters)) {
            sentIcon = icon; sentSecondIcon = secondIcon; sentDistance = meters;
        }
    }
    private long desiredTime = Long.MIN_VALUE;
    private void emitTime(long seconds) {
        desiredTime = seconds;
        // The duration was received at timeLeftAtMs; a later send (retry, resume after stock) must not restart that countdown.
        long left = seconds < 0 ? -1 : Math.max(0L, seconds - Math.max(0L, System.currentTimeMillis() - timeLeftAtMs) / 1000L);
        // Only new source data (or ownership/failure invalidation) causes a write.
        // The cluster displays an arrival clock, not a countdown needing minute ticks.
        long minute = seconds < 0 ? -1 : seconds / 60;
        if (outputAllowed && sink instanceof TimeSink && minute != sentTimeMinute
                && ((TimeSink)sink).timeRemaining(left)) sentTimeMinute = minute;
    }
    private String desiredDestination;
    private void emitDestination(String name) {
        desiredDestination = name;
        if (outputAllowed && sink instanceof DestinationSink && !name.equals(sentDestination)
                && ((DestinationSink)sink).destination(name)) sentDestination = name;
    }
    private long desiredRemaining = Long.MIN_VALUE;
    private void emitRemaining(long meters) {
        desiredRemaining = meters;
        if (outputAllowed && sink instanceof RemainSink && meters != sentRemaining
                && ((RemainSink)sink).remaining(meters)) sentRemaining = meters;
    }
    private void emitTunnel(boolean active, long meters) {
        long bucket = !active ? -1L : (meters < 50L ? 0L : Math.min(TUNNEL_MAX_DISTANCE_M, (meters / 50L) * 50L));
        desiredTunnelActive = active;
        desiredTunnelBucket = bucket;
        // A failed activation still reached the sink, so its clear must be delivered as well.
        if (!active && !sentTunnelActive && !requestedTunnelActive) {
            sentTunnelBucket = -1L;
            return;
        }
        if (outputAllowed && sink instanceof TunnelSink && (active != sentTunnelActive || bucket != sentTunnelBucket
                || (!active && requestedTunnelActive))) {
            if (active) requestedTunnelActive = true;
            if (((TunnelSink) sink).tunnel(active, bucket)) {
                sentTunnelActive = active;
                sentTunnelBucket = bucket;
                if (!active) requestedTunnelActive = false;
            }
        }
    }
    private void clearLaneState() {
        laneSets.clear(); laneIndex = -1; laneTotal = -1; laneVisible = false;
    }
    private void renderLanes() {
        if (!isDisplayActive() || !laneVisible || laneIndex < 0 || laneTotal == 0) {
            emitLanes(LaneFrame.clear()); return;
        }
        Maneuver first = current.length == 0 ? null : maneuvers.get(key(component,current[0]));
        int laneIcon = TurnFrame.effectiveIcon(ClusterIcon.of(first), distance);
        emitLanes(LaneFrame.encode(laneSets.get(key(component,laneIndex)), laneIcon));
    }
    private void emitLanes(byte[] frame) {
        desiredLanes = frame;
        if (outputAllowed && sink instanceof LaneSink && !Arrays.equals(lastLanes,frame)
                && ((LaneSink)sink).lanes(frame.clone())) lastLanes = frame;
    }
    /** Retry the most recent desired outputs, including clears, without route input. */
    public void retryOutput() {
        if (desiredFrame != null) emit(desiredFrame);
        if (desiredLanes != null) emitLanes(desiredLanes);
        if (desiredTbt) emitTbt(desiredIcon, desiredSecondIcon, desiredDistance);
        if (desiredRemaining != Long.MIN_VALUE) emitRemaining(desiredRemaining);
        if (desiredDestination != null) emitDestination(desiredDestination);
        if (desiredTime != Long.MIN_VALUE) emitTime(desiredTime);
        if (desiredTunnelActive || sentTunnelActive || requestedTunnelActive) emitTunnel(desiredTunnelActive, desiredTunnelBucket);
    }
    public boolean hasActiveGuidance() {
        return desiredFrame != null && !Arrays.equals(desiredFrame, TurnFrame.clear());
    }
    /** A live phone route may have no displayable turn (rerouting, locating, or input ordering). */
    public boolean hasPhoneRoute() { return phoneRoute; }
    /** Next maneuver's road name if available, otherwise empty string. */
    public String currentRoad() {
        if (!isDisplayActive() || current.length == 0) return "";
        Maneuver first = maneuvers.get(key(component, current[0]));
        return first != null && first.afterRoad != null ? first.afterRoad : "";
    }
    /** A failed cluster binding may have lost all output channels. */
    public void invalidateOutput() {
        lastFrame = null; lastLanes = null;
        sentIcon = Integer.MIN_VALUE; sentSecondIcon = Integer.MIN_VALUE; sentDistance = Long.MIN_VALUE;
        sentRemaining = Long.MIN_VALUE; sentDestination = null; sentTimeMinute = Long.MIN_VALUE;
        sentTunnelBucket = Long.MIN_VALUE;
    }
    private static long key(int component, int index) { return ((long)component << 32) | (index & 0xffffffffL); }
}
