import kr.gen5w.portable.Hook;
import java.lang.reflect.Method;

public final class HookVmTest {
    static int calls;
    static final RuntimeException FAILURE = new RuntimeException("identity");
    public int sum(int a, long b, Object marker) { calls++; if (marker == null) throw FAILURE; return a + (int)b; }
    public static int replacement(HookVmTest self, int a, long b, Object marker, int handle) throws Throwable {
        Object result = Hook.original(handle, self, new Object[]{a, b, marker});
        return ((Integer)result).intValue() * 2;
    }
    public static long wide(long value) { return value + 1; }
    public static long wideReplacement(long value, int handle) throws Throwable {
        return ((Long)Hook.original(handle, null, new Object[]{value})).longValue() + 5;
    }
    public static Object object(Object value) { return value; }
    public static Object objectReplacement(Object value, int handle) throws Throwable {
        System.gc();
        Object result = Hook.original(handle, null, new Object[]{value});
        System.gc();
        return result;
    }
    public synchronized double floating(float a, double b, boolean yes) { return yes ? a + b : 0; }
    public static double floatingReplacement(Object self, float a, double b, boolean yes, int handle) throws Throwable {
        if (!Thread.holdsLock(self)) throw new AssertionError("synchronized target lost monitor");
        return ((Double)Hook.original(handle, self, new Object[]{a,b,yes})).doubleValue() * 2;
    }
    static final Object LOCK = new Object();
    static boolean entered, released;
    static Throwable threadFailure;
    public static int inFlight(int value) { return value + 3; }
    public static int inFlightReplacement(int value, int handle) throws Throwable {
        synchronized (LOCK) { entered = true; LOCK.notifyAll(); while (!released) LOCK.wait(); }
        return ((Integer)Hook.original(handle, null, new Object[]{value})).intValue() * 2;
    }
    public static void main(String[] args) throws Throwable {
        if (System.getenv("GEN5W_ENGINE_JAR") == null) System.load(args[0]);
        System.err.println("VM stage: load");
        HookVmTest self = new HookVmTest();
        Method target = HookVmTest.class.getMethod("sum", Integer.TYPE, Long.TYPE, Object.class);
        Method replacement = HookVmTest.class.getMethod("replacement", HookVmTest.class, Integer.TYPE, Long.TYPE, Object.class, Integer.TYPE);
        int handle = Hook.install(target, replacement);
        System.err.println("VM stage: first-dispatch");
        int result = self.sum(2, 3L, self);
        if (result != 10 || calls != 1) throw new AssertionError("dispatch/original result=" + result + " calls=" + calls);
        try { self.sum(2, 3L, null); throw new AssertionError("missing exception"); }
        catch (RuntimeException actual) { if (actual != FAILURE) throw new AssertionError("exception identity"); }
        System.err.println("VM stage: wide");
        Hook.install(HookVmTest.class.getMethod("wide", Long.TYPE), HookVmTest.class.getMethod("wideReplacement", Long.TYPE, Integer.TYPE));
        if (wide(0x1234567812345678L) != 0x123456781234567eL) throw new AssertionError("wide");
        System.err.println("VM stage: object-GC");
        Hook.install(HookVmTest.class.getMethod("object", Object.class), HookVmTest.class.getMethod("objectReplacement", Object.class, Integer.TYPE));
        if (object(self) != self) throw new AssertionError("object identity");
        try { Hook.install(target, replacement); throw new AssertionError("duplicate hook accepted"); }
        catch (IllegalStateException expected) { }
        System.err.println("VM stage: uninstall");
        Hook.uninstall(handle);
        if (self.sum(2, 3L, self) != 5) throw new AssertionError("uninstall restore");
        Hook.install(target, replacement);
        if (self.sum(2, 3L, self) != 10) throw new AssertionError("reinstall");
        System.err.println("VM stage: synchronized");
        Hook.install(HookVmTest.class.getMethod("floating", Float.TYPE, Double.TYPE, Boolean.TYPE),
            HookVmTest.class.getMethod("floatingReplacement", Object.class, Float.TYPE, Double.TYPE, Boolean.TYPE, Integer.TYPE));
        if (self.floating(1.5f, 2.25, true) != 7.5) throw new AssertionError("float/double/boolean synchronized");
        System.err.println("VM stage: inflight-install");
        int inFlightHandle = Hook.install(HookVmTest.class.getMethod("inFlight", Integer.TYPE),
            HookVmTest.class.getMethod("inFlightReplacement", Integer.TYPE, Integer.TYPE));
        Thread worker = new Thread(new Runnable() { public void run() {
            try { if (inFlight(4) != 14) throw new AssertionError("inflight result"); }
            catch (Throwable failure) { threadFailure = failure; }
        }});
        System.err.println("VM stage: inflight-start");
        worker.start();
        synchronized (LOCK) { while (!entered) LOCK.wait(); }
        System.err.println("VM stage: inflight-uninstall");
        Hook.uninstall(inFlightHandle);
        synchronized (LOCK) { released = true; LOCK.notifyAll(); }
        System.err.println("VM stage: inflight-join");
        worker.join();
        if (threadFailure != null) throw threadFailure;
        if (inFlight(4) != 7) throw new AssertionError("inflight uninstall restore");
        System.out.println("PASS V039 dispatch original exception wide object GC synchronized uninstall-inflight");
    }
}
