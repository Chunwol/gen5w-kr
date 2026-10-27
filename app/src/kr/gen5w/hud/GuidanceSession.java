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
    public interface TbtSink extends LaneSink { boolean tbt(int icon, long distanceMeters); }
    private final Sink sink;
    private boolean outputAllowed = true;
    private final Map<Long, Maneuver> maneuvers = new LinkedHashMap<Long, Maneuver>();
    private int component = -1, state = -1;
    private String source;
    private int[] current = new int[0];
    private byte[] lastFrame;
    private byte[] lastLanes;
    private byte[] desiredFrame, desiredLanes;
    private boolean desiredTbt;
    private int desiredIcon;
    private long desiredDistance;
    private final Map<Long, GuidanceParser.Lanes> laneSets = new LinkedHashMap<Long, GuidanceParser.Lanes>();
    private int laneIndex = -1, laneTotal = -1;
    private boolean laneVisible;
    private long distance = -1, sentDistance = Long.MIN_VALUE;
    private int sentIcon = Integer.MIN_VALUE;

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
        boolean changed = component >= 0 && component != update.component;
        if (changed) { maneuvers.clear(); clearLaneState(); current = new int[0]; state = -1; source = null; distance = -1; }
        component = update.component;
        if (update.hasSource) {
            if (source != null && !source.equals(update.source)) {
                maneuvers.clear(); current = new int[0];
                clearLaneState();
                distance = -1;
            }
            source = update.source;
        }
        if (update.hasState) state = update.state;
        if (update.hasCurrent && !Arrays.equals(current,update.current) && !update.hasLaneIndex) {
            clearLaneState();
        }
        if (update.hasCurrent && !Arrays.equals(current,update.current)) distance = -1;
        if (update.hasCurrent) current = update.current.clone();
        if (update.hasDistance) distance = update.distanceToNext;
        if (update.hasLaneIndex) laneIndex = update.laneIndex;
        if (update.hasLaneTotal) laneTotal = update.laneTotal;
        if (update.hasLaneVisible) laneVisible = update.laneVisible;
        if (!isNavigating(state)) {
            maneuvers.clear(); current = new int[0];
            clearLaneState();
            distance = -1;
        }
        render();
    }
    public static boolean isNavigating(int s) { return s == 1 || s == 6; }
    public void disconnect() {
        component = -1; state = -1; source = null;
        current = new int[0]; maneuvers.clear();
        clearLaneState();
        distance = -1;
        emit(TurnFrame.clear());
        emitLanes(LaneFrame.clear());
        emitTbt(0, -1);
    }
    private void render() {
        renderLanes();
        Maneuver selected = current.length == 0 ? null : maneuvers.get(key(component,current[0]));
        int selectedIcon = isNavigating(state) ? ClusterIcon.of(selected) : ClusterIcon.NONE;
        emitTbt(selectedIcon < 0 ? 0 : selectedIcon, selectedIcon < 0 ? -1 : distance);
        if (!isNavigating(state) || current.length == 0) { emit(TurnFrame.clear()); return; }
        Maneuver first = maneuvers.get(key(component, current[0]));
        if (first == null) { emit(TurnFrame.clear()); return; }
        int[] icons = new int[Math.min(3, current.length)];
        for (int i = 0; i < icons.length; i++) icons[i] = ClusterIcon.of(maneuvers.get(key(component, current[i])));
        emit(TurnFrame.encode(icons, first.afterRoad));
    }
    private void emit(byte[] frame) {
        desiredFrame = frame;
        if (outputAllowed && !Arrays.equals(lastFrame, frame) && sink.turns(frame.clone())) lastFrame = frame;
    }
    private void emitTbt(int icon, long meters) {
        desiredTbt = true; desiredIcon = icon; desiredDistance = meters;
        if (outputAllowed && sink instanceof TbtSink && (icon != sentIcon || meters != sentDistance)
                && ((TbtSink)sink).tbt(icon, meters)) { sentIcon = icon; sentDistance = meters; }
    }
    private void clearLaneState() {
        laneSets.clear(); laneIndex = -1; laneTotal = -1; laneVisible = false;
    }
    private void renderLanes() {
        if (!isNavigating(state) || !laneVisible || laneIndex < 0 || laneTotal == 0) {
            emitLanes(LaneFrame.clear()); return;
        }
        Maneuver first = current.length == 0 ? null : maneuvers.get(key(component,current[0]));
        emitLanes(LaneFrame.encode(laneSets.get(key(component,laneIndex)),ClusterIcon.of(first)));
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
        if (desiredTbt) emitTbt(desiredIcon, desiredDistance);
    }
    /** A failed cluster binding may have lost all three output channels. */
    public void invalidateOutput() {
        lastFrame = null; lastLanes = null;
        sentIcon = Integer.MIN_VALUE; sentDistance = Long.MIN_VALUE;
    }
    private static long key(int component, int index) { return ((long)component << 32) | (index & 0xffffffffL); }
}
