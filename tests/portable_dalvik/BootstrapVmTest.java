import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public final class BootstrapVmTest {
    static Object allocate(Class<?> type) throws Exception {
        Class<?> unsafeType = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeType.getDeclaredField("THE_ONE");
        singleton.setAccessible(true);
        Object unsafe = singleton.get(null);
        return unsafeType.getMethod("allocateInstance", Class.class).invoke(unsafe, type);
    }
    static void put(Object receiver, String name, Object value) throws Exception {
        Field field = receiver.getClass().getDeclaredField(name);
        field.setAccessible(true); field.set(receiver, value);
    }
    public static void main(String[] args) throws Exception {
        Object context = allocate(Class.forName("android.app.ContextImpl"));
        Object apk = allocate(Class.forName("android.app.LoadedApk"));
        put(apk, "mPackageName", "fixture");
        put(apk, "mClassLoader", BootstrapVmTest.class.getClassLoader());
        put(apk, "mDataDirFile", new File(args[0]));
        put(context, "mPackageInfo", apk);
        put(context, "mSync", new Object());
        Class<?> applicationType = Class.forName("android.app.Application");
        Object application = applicationType.newInstance();
        Method attach = applicationType.getDeclaredMethod("attach", Class.forName("android.content.Context"));
        attach.setAccessible(true);
        attach.invoke(application, context);
        if (!new File(args[0], "app_gen5w-adapters/fixture-installed").isFile())
            throw new AssertionError("app-local bootstrap adapter not called");
        File ready = new File(args[0], "files/gen5w-portable-ready");
        if (!ready.isFile()) throw new AssertionError("private readiness marker not published");
        System.out.println("PASS V039 JNI interposer app-local engine Application.attach app-local adapter");
    }
}
