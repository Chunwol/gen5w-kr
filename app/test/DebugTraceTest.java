import java.util.ArrayList;
import kr.gen5w.diag.DebugTrace;

public final class DebugTraceTest {
    public static void main(String[] args) {
        final ArrayList<String> lines = new ArrayList<String>();
        DebugTrace trace = new DebugTrace();
        DebugTrace.Sink sink = new DebugTrace.Sink() { public void write(String s) { lines.add(s); } };
        check(!trace.emit(sink, false, "route.receive", new long[]{102, 5}, 10), "off must be silent");
        check(trace.emit(sink, true, "route.receive", new long[]{102, 5}, 10), "enabled event");
        check(!trace.emit(sink, true, "route.receive", new long[]{102, 5}, 11), "repeat rate limited");
        check(trace.emit(sink, true, "route.receive", new long[]{103, 5}, 12), "changed boundary recorded");
        check(!trace.emit(sink, true, "phone name", new long[]{1}, 13), "reject free text code");
        check(!trace.emit(sink, true, "large", new long[9], 13), "bounded numeric fields");
        check(trace.emit(sink, true, "route.receive", new long[]{103, 5}, 1012), "heartbeat recorded");
        check(lines.get(0).contains("code=route.receive") && lines.get(0).contains("values=102,5"), "fixed fields");
        check(!trace.emit(sink, false, "off", new long[]{1}, 2000), "can disable immediately");
        System.out.println("PASS debug traces: opt-in, numeric fields, rate and size bounds");
    }
    static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
}
