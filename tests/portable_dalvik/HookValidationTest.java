import kr.gen5w.portable.Hook;
import java.lang.reflect.Method;
public final class HookValidationTest {
    public int target(String value) { return value.length(); }
    public static int wrong(Object self, String value) { return 0; }
    public static int widened(Object self, Object value, int handle) { return 0; }
    public static void main(String[] args) throws Exception {
        Method target = HookValidationTest.class.getMethod("target", String.class);
        try { Hook.install(target, HookValidationTest.class.getMethod("wrong", Object.class, String.class));
            throw new AssertionError("missing handle accepted"); }
        catch (IllegalArgumentException expected) { }
        try { Hook.install(target, HookValidationTest.class.getMethod("widened", Object.class, Object.class, Integer.TYPE));
            throw new AssertionError("native backend unexpectedly available on host"); }
        catch (UnsatisfiedLinkError expected) { }
        try { Hook.original(-1, null, null); throw new AssertionError("invalid original handle accepted"); }
        catch (IllegalArgumentException expected) { }
        catch (Throwable other) { throw new AssertionError(other); }
        System.out.println("PASS host signature validation widening invalid handle");
    }
}
