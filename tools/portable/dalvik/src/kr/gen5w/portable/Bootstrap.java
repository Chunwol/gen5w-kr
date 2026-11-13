package kr.gen5w.portable;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.BufferedReader;
import java.lang.reflect.Method;

/** Invoked explicitly by the opt-in VM interposer, before application startup. */
public final class Bootstrap {
    private static boolean installed;
    private static boolean adaptersInstalled;
    /* Wrapper inputs, kept here because the native interposer removes them from
     * the process environment before startup so that children do not inherit
     * the engine. Written once in start(), read under the same class lock. */
    private static String adapterJar, ownerPackage;
    private Bootstrap() {}
    /** Called by the native VM interposer with its preserved wrapper inputs. */
    public static synchronized void start(String library, String jar, String owner) throws Exception {
        if (installed) return;
        if (library == null || jar == null || owner == null || !new File(library).isAbsolute() || !new File(jar).isAbsolute())
            throw new IllegalArgumentException("explicit absolute library/adapter and package required");
        adapterJar = jar;
        ownerPackage = owner;
        System.load(library);
        Class<?> application = Class.forName("android.app.Application");
        Class<?> context = Class.forName("android.content.Context");
        Method attach = application.getDeclaredMethod("attach", context);
        Hook.install(attach, Bootstrap.class.getMethod("attach", Object.class, Object.class, Integer.TYPE));
        installed = true;
    }
    public static void attach(Object application, Object context, int handle) throws Throwable {
        Hook.original(handle, application, new Object[]{context});
        synchronized (Bootstrap.class) {
            if (adaptersInstalled) return;
            try {
                Class<?> type = Class.forName("android.content.Context");
                String owner = (String)type.getMethod("getPackageName").invoke(context);
                if (!owner.equals(ownerPackage)) return;
                File files = (File)type.getMethod("getFilesDir").invoke(context);
                File ready = new File(files, "gen5w-portable-ready");
                if (ready.exists() && !ready.delete()) throw new IllegalStateException("stale readiness marker cannot be removed");
                ClassLoader parent = (ClassLoader)type.getMethod("getClassLoader").invoke(context);
                File cache = (File)type.getMethod("getDir", String.class, Integer.TYPE).invoke(context, "gen5w-adapters", 0);
                ClassLoader loader = AppLocalLoader.create(adapterJar, cache.getAbsolutePath(), parent);
                Class<?> adapter = AppLocalLoader.loadWith(loader, "kr.gen5w.portable.ProjectionAdapters");
                Object result = AppLocalLoader.invoke(adapter.getMethod("install", type), null, new Object[]{context});
                if (!Boolean.TRUE.equals(result)) throw new IllegalStateException("adapter discovery declined");
                BufferedReader bootReader = new BufferedReader(new FileReader("/proc/sys/kernel/random/boot_id"));
                String boot;
                try { boot = bootReader.readLine(); } finally { bootReader.close(); }
                BufferedReader processReader = new BufferedReader(new FileReader("/proc/self/stat"));
                String process;
                try { process = processReader.readLine(); } finally { processReader.close(); }
                int pid = Integer.parseInt(process.substring(0, process.indexOf(' ')));
                File temporary = new File(files, "gen5w-portable-ready.tmp");
                FileOutputStream output = new FileOutputStream(temporary);
                try {
                    output.write(("boot_id=" + boot + "\npid=" + pid + "\npackage=" + owner + "\n").getBytes("UTF-8"));
                    output.getFD().sync();
                } finally { output.close(); }
                if (!temporary.renameTo(ready)) throw new IllegalStateException("readiness marker publication failed");
                adaptersInstalled = true;
                System.err.println("Gen5wPortable: app-local adapters installed for " + owner);
            } catch (Throwable failure) {
                // ProjectionAdapters rolls back its group before reporting failure.
                System.err.println("Gen5wPortable: adapters unavailable: " + failure);
            }
        }
    }
}
