import android.content.ContextWrapper;
import kr.gen5w.portable.AppLocalLoader;
public final class AdapterDiscoveryVmTest {
    public static final class AppContext extends ContextWrapper {
        private final ClassLoader loader;
        private final String name, apk;
        AppContext(ClassLoader loader, String name, String apk) { super(null); this.loader=loader;this.name=name;this.apk=apk; }
        public ClassLoader getClassLoader() { return loader; }
        public String getPackageName() { return name; }
        public String getPackageCodePath() { return apk; }
    }
    public static void main(String[] args) throws Throwable {
        ClassLoader owner = AppLocalLoader.create(args[0], args[2], AdapterDiscoveryVmTest.class.getClassLoader());
        ClassLoader adapters = AppLocalLoader.create(args[1], args[2], owner);
        Class<?> plan = AppLocalLoader.loadWith(adapters, "kr.gen5w.portable.DipoAdapters");
        Object count = AppLocalLoader.invoke(plan.getMethod("validate", android.content.Context.class), null,
            new Object[]{new AppContext(owner, "com.daudio.app.dipo", "/system/app/HKMC_DiPO.apk")});
        if (!Integer.valueOf(19).equals(count)) throw new AssertionError("DiPO discovery count=" + count);
        System.out.println("PASS V039 actual stock DiPO adapter discovery hooks=" + count);
    }
}
