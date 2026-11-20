import java.lang.reflect.Method;

/** Hooked-VM regression (2026-11-19 vehicle): the live bootclasspath must keep
 * exactly the inherited BOOTCLASSPATH entries, before and after opening a
 * shared framework jar. One extra entry makes every shared odex "stale" and
 * the VM rebuilds shared dalvik-cache files under other running apps. */
public final class BootPathVmTest {
    private BootPathVmTest() {}
    public static void main(String[] args) throws Exception {
        Method size = Class.forName("java.lang.VMClassLoader").getDeclaredMethod("getBootClassPathSize");
        size.setAccessible(true);
        int expected = 0;
        for (String entry : System.getenv("BOOTCLASSPATH").split(":")) if (!entry.isEmpty()) expected++;
        int live = (Integer)size.invoke(null);
        if (live != expected) throw new AssertionError("bootclasspath changed: live=" + live + " expected=" + expected);
        ClassLoader loader = (ClassLoader)Class.forName("dalvik.system.PathClassLoader")
            .getConstructor(String.class, ClassLoader.class).newInstance(args[0], ClassLoader.getSystemClassLoader());
        loader.loadClass(args[1]);
        live = (Integer)size.invoke(null);
        if (live != expected) throw new AssertionError("bootclasspath changed after shared jar: live=" + live);
        System.out.println("PASS bootclasspath unchanged entries=" + live + " loaded=" + args[1]);
    }
}
