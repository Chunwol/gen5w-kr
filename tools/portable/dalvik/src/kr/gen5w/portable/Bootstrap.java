package kr.gen5w.portable;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.BufferedReader;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/** Invoked explicitly by the opt-in VM interposer, before application startup. */
public final class Bootstrap {
    private static boolean installed;
    private static boolean adaptersInstalled;
    /* Wrapper inputs, kept here because the native interposer removes them from
     * the process environment before startup so that children do not inherit
     * the engine. Written once in start(), read under the same class lock. */
    private static String adapterJar, ownerPackage;
    // A retry must see the same adapter transaction, including failed rollback.
    private static Class<?> adapterType;
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
        // WrapperInit repeats the full (OEM: three-thread) ZygoteInit.preload() in
        // this process instead of sharing zygote's. On a busy unit a preloader thread
        // missed Dalvik's GC suspend deadline and the app was killed (SIGSTKFLT);
        // restarting it, AMS held its lock waiting on zygote until the watchdog reset
        // Android (VM 2026-11-21). Skip only that warm-up: classes and resources load
        // on first use as in any non-zygote VM. Optional: if absent, stock is kept.
        try {
            Method preload = Class.forName("com.android.internal.os.ZygoteInit").getDeclaredMethod("preload");
            if (Modifier.isStatic(preload.getModifiers()) && preload.getReturnType() == Void.TYPE)
                Hook.install(preload, Bootstrap.class.getMethod("skipPreload", Integer.TYPE));
        } catch (Throwable keep) {
            System.err.println("Gen5wPortable: wrapper preload kept: " + keep);
        }
    }
    /** Replacement for ZygoteInit.preload() in the wrapped app only. */
    public static void skipPreload(int handle) {
        System.err.println("Gen5wPortable: wrapper preload skipped");
    }
    public static void attach(Object application, Object context, int handle) throws Throwable {
        Hook.original(handle, application, new Object[]{context});
        synchronized (Bootstrap.class) {
            if (adaptersInstalled) return;
            Object transaction = null;
            File ready = null, temporary = null;
            boolean published = false;
            try {
                Class<?> type = Class.forName("android.content.Context");
                String owner = (String)type.getMethod("getPackageName").invoke(context);
                if (!owner.equals(ownerPackage)) return;
                File files = (File)type.getMethod("getFilesDir").invoke(context);
                ready = new File(files, "gen5w-portable-ready");
                if (ready.exists() && !ready.delete()) throw new IllegalStateException("stale readiness marker cannot be removed");
                if (adapterType == null) {
                    ClassLoader parent = (ClassLoader)type.getMethod("getClassLoader").invoke(context);
                    File cache = (File)type.getMethod("getDir", String.class, Integer.TYPE).invoke(context, "gen5w-adapters", 0);
                    ClassLoader loader = AppLocalLoader.create(adapterJar, cache.getAbsolutePath(), AppLocalLoader.engineFirst(parent));
                    adapterType = AppLocalLoader.loadWith(loader, "kr.gen5w.portable.ProjectionAdapters");
                }
                transaction = AppLocalLoader.invoke(adapterType.getMethod("beginInstall", type), null, new Object[]{context});
                if (transaction == null) throw new IllegalStateException("adapter discovery declined");
                BufferedReader bootReader = new BufferedReader(new FileReader("/proc/sys/kernel/random/boot_id"));
                String boot;
                try { boot = bootReader.readLine(); } finally { bootReader.close(); }
                BufferedReader processReader = new BufferedReader(new FileReader("/proc/self/stat"));
                String process;
                try { process = processReader.readLine(); } finally { processReader.close(); }
                int pid = Integer.parseInt(process.substring(0, process.indexOf(' ')));
                temporary = new File(files, "gen5w-portable-ready.tmp");
                FileOutputStream output = new FileOutputStream(temporary);
                try {
                    output.write(("boot_id=" + boot + "\npid=" + pid + "\npackage=" + owner + "\n").getBytes("UTF-8"));
                    output.getFD().sync();
                } finally { output.close(); }
                if (!temporary.renameTo(ready)) throw new IllegalStateException("readiness marker publication failed");
                published = true;
                AppLocalLoader.invoke(transaction.getClass().getMethod("commit"), transaction, new Object[0]);
                adaptersInstalled = true;
                System.err.println("Gen5wPortable: app-local adapters installed for " + owner);
            } catch (Throwable failure) {
                // No compile-time dependency on adapter.jar is permitted here.
                if (failure.getClass().getName().equals("kr.gen5w.portable.ProjectionAdapters$RollbackFailure")) {
                    System.err.println("Gen5wPortable: adapter rollback incomplete; process restart required: " + failure);
                    throw failure;
                }
                if (published && ready != null && !ready.delete())
                    failure.addSuppressed(new IllegalStateException("failed readiness marker cleanup"));
                if (temporary != null && temporary.isFile() && !temporary.delete())
                    failure.addSuppressed(new IllegalStateException("failed temporary marker cleanup"));
                if (transaction != null) {
                    try {
                        AppLocalLoader.invoke(transaction.getClass().getMethod("rollback"), transaction, new Object[0]);
                    } catch (Throwable rollback) {
                        IllegalStateException unresolved = new IllegalStateException("adapter rollback incomplete; process restart required", rollback);
                        unresolved.addSuppressed(failure);
                        System.err.println("Gen5wPortable: " + unresolved);
                        throw unresolved;
                    }
                }
                System.err.println("Gen5wPortable: adapters unavailable: " + failure);
            }
        }
    }
}
