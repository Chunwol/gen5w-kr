package kr.gen5w.portable;

import java.io.File;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** Standard Android loader API only; never relies on a ClassObject field offset. */
public final class AppLocalLoader {
    private AppLocalLoader() {}
    public static ClassLoader create(String jar, String cache, ClassLoader parent) throws Exception {
        if (parent == null || jar == null || cache == null || !new File(jar).isAbsolute() || !new File(cache).isAbsolute())
            throw new IllegalArgumentException("absolute jar/cache and app class loader required");
        Constructor<?> constructor = Class.forName("dalvik.system.DexClassLoader").getConstructor(
            String.class, String.class, String.class, ClassLoader.class);
        return (ClassLoader)constructor.newInstance(jar, cache, null, parent);
    }
    public static Class<?> loadWith(ClassLoader loader, String name) throws ClassNotFoundException {
        if (loader == null) throw new NullPointerException("app class loader");
        return Class.forName(name, true, loader);
    }
    public static Object invoke(Method method, Object receiver, Object[] args) throws Throwable {
        try { return method.invoke(receiver, args); }
        catch (InvocationTargetException wrapped) { throw wrapped.getCause(); }
    }
}
