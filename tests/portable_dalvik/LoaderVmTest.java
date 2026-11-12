import kr.gen5w.portable.AppLocalLoader;
public final class LoaderVmTest {
    public static void main(String[] args) throws Throwable {
        ClassLoader parent = LoaderVmTest.class.getClassLoader();
        ClassLoader child = AppLocalLoader.create(args[0], args[1], parent);
        Class<?> loaded = AppLocalLoader.loadWith(child, "AdapterFixture");
        if (loaded.getClassLoader() != child) throw new AssertionError("wrong app-local loader");
        if (loaded.getMethod("identity", Object.class).getParameterTypes()[0] != Object.class)
            throw new AssertionError("parent class identity");
        Object token = new Object();
        if (AppLocalLoader.invoke(loaded.getMethod("identity", Object.class), null, new Object[]{token}) != token)
            throw new AssertionError("argument/return identity");
        System.out.println("PASS V039 app-local DexClassLoader dispatch identity");
    }
}
