package kr.gen5w.core;

import android.content.Context;
import android.database.Cursor;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.Uri;
import android.os.Binder;
import android.os.IBinder;
import android.os.Looper;
import android.os.Process;

/** System-uid NEMESIS service. Its sole operation reads one non-personal flag. */
public final class StockOwner {
    private static final Uri STATE = Uri.parse("content://com.mnsoft.navi/State_Table");
    private static final Observation observation = new Observation();
    private static final int GC_QUERY_INTERVAL = 60;
    private static final java.util.concurrent.atomic.AtomicBoolean gcRunning = new java.util.concurrent.atomic.AtomicBoolean();
    private static int queryCount;

    interface Source { Cursor query(Uri uri, String[] columns) throws Exception; }

    private static int read(final Source source) {
        return observation.read(new java.util.concurrent.Callable<Integer>() {
            public Integer call() { return readProvider(source); }
        });
    }

    /**
     * Reads a provider without an app record, as the stock `content` shell command does.
     * This process was not started by the activity manager, so an ordinary
     * ContentResolver query is refused ("Unable to find app for caller"). Checked
     * against the car build's ActivityManagerService (getContentProviderExternal
     * passes no caller; uid 1000 holds ACCESS_CONTENT_PROVIDERS_EXTERNALLY).
     */
    static final class ExternalSource implements Source {
        private final IBinder token = new Binder();
        private Object provider;
        private String authority;

        public synchronized Cursor query(Uri uri, String[] columns) throws Exception {
            if (provider == null) {
                authority = uri.getAuthority();
                Object manager = Class.forName("android.app.ActivityManagerNative").getMethod("getDefault").invoke(null);
                Object holder = Class.forName("android.app.IActivityManager")
                        .getMethod("getContentProviderExternal", String.class, int.class, IBinder.class)
                        .invoke(manager, authority, 0, token);
                if (holder == null) return null;
                provider = holder.getClass().getField("provider").get(holder);
                if (provider == null) { release(); return null; }
            }
            try {
                return (Cursor)Class.forName("android.content.IContentProvider")
                        .getMethod("query", String.class, Uri.class, String[].class, String.class,
                                String[].class, String.class, Class.forName("android.os.ICancellationSignal"))
                        .invoke(provider, "android", uri, columns, null, null, null, null);
            } catch (java.lang.reflect.InvocationTargetException e) {
                // The navigation process restarted: drop the reference and acquire afresh next time.
                release();
                Throwable cause = e.getCause();
                if (isWindowOrBinderExhaustion(cause)) reclaimNativeResources();
                if (cause instanceof Exception) throw (Exception)cause;
                if (cause instanceof Error) throw (Error)cause;
                throw new RuntimeException(cause);
            } catch (Throwable t) {
                release();
                if (isWindowOrBinderExhaustion(t)) reclaimNativeResources();
                if (t instanceof Exception) throw (Exception)t;
                if (t instanceof Error) throw (Error)t;
                throw new RuntimeException(t);
            }
        }

        private static boolean isWindowOrBinderExhaustion(Throwable t) {
            if (t == null) return false;
            String name = t.getClass().getName();
            return name.contains("CursorWindow") || name.contains("TransactionTooLarge");
        }

        private static void reclaimNativeResources() {
            System.gc();
            System.runFinalization();
        }

        private void release() {
            provider = null;
            try {
                Object manager = Class.forName("android.app.ActivityManagerNative").getMethod("getDefault").invoke(null);
                Class.forName("android.app.IActivityManager")
                        .getMethod("removeContentProviderExternal", String.class, IBinder.class)
                        .invoke(manager, authority, token);
            } catch (Exception ignored) { }
        }
    }

    /** One provider worker, one pending observation, and no cached ownership.
     * A stuck Binder call cannot be reliably interrupted on API 18. Keep it
     * isolated, fail closed, and discard its late answer before trying afresh. */
    static final class Observation {
        private final java.util.concurrent.ExecutorService worker =
                new java.util.concurrent.ThreadPoolExecutor(1, 1, 0L,
                        java.util.concurrent.TimeUnit.MILLISECONDS,
                        new java.util.concurrent.ArrayBlockingQueue<Runnable>(1),
                        new java.util.concurrent.ThreadFactory() {
                            public Thread newThread(Runnable runnable) {
                                Thread thread = new Thread(runnable, "gen5w-stock-query");
                                thread.setDaemon(true);
                                return thread;
                            }
                        });
        private java.util.concurrent.Future<Integer> pending;

        synchronized int read(java.util.concurrent.Callable<Integer> query) {
            if (pending != null) {
                if (!pending.isDone()) return '?';
                // A timed-out observation must never grant ownership later.
                pending = null;
            }
            pending = worker.submit(query);
            try {
                int value = pending.get(350, java.util.concurrent.TimeUnit.MILLISECONDS);
                pending = null;
                return value;
            } catch (java.util.concurrent.TimeoutException e) {
                kr.gen5w.diag.SafeDiagnostic.failure("core.owner.timeout",e);
                return '?';
            } catch (InterruptedException e) {
                kr.gen5w.diag.SafeDiagnostic.failure("core.owner.interrupted",e);
                Thread.currentThread().interrupt();
                return '?';
            } catch (java.util.concurrent.ExecutionException e) {
                kr.gen5w.diag.SafeDiagnostic.failure("core.owner.worker",e.getCause());
                pending = null;
                return '?';
            }
        }
    }

    private static int readProvider(Source source) {
        Cursor cursor = null;
        try {
            cursor = source.query(STATE, new String[]{"State_Destination"});
            if (cursor == null) return '?';
            final Cursor rows = cursor;
            int result = StockFlag.decode(new StockFlag.Rows() {
                public int columns() { return rows.getColumnCount(); }
                public boolean next() { return rows.moveToNext(); }
                public boolean isNull() { return rows.isNull(0); }
                public String text() { return rows.getString(0); }
            });
            kr.gen5w.diag.DebugTrace.event("hud.provider.result", result);
            return result;
        } catch (Exception e) { kr.gen5w.diag.SafeDiagnostic.failure("core.owner.query",e); return '?'; }
        finally {
            if (cursor != null) {
                try { cursor.close(); } catch (Throwable ignored) { }
            }
        }
    }

    /** Early in boot the package service is not up yet; wait for it instead of crashing. */
    private static int clientUid(Context context) throws Exception {
        for (int attempt = 0; ; attempt++) {
            try {
                android.content.pm.PackageManager packages = context.getPackageManager();
                if (packages != null) return packages.getApplicationInfo("kr.gen5w.core", 0).uid;
            } catch (RuntimeException e) {
                if (attempt >= 120) throw e;
            }
            if (attempt >= 120) throw new IllegalStateException("package service unavailable");
            Thread.sleep(1000);
        }
    }

    private static volatile Class<?> cachedSocketClass;
    private static volatile java.lang.reflect.Field cachedImplField;
    private static volatile java.lang.reflect.Field cachedFdInternalField;

    /**
     * Android 4.3 (API 18) LocalServerSocket.accept() leaves LocalSocketImpl.mFdCreatedInternally
     * false, causing LocalSocketImpl.close() to skip Libcore.os.close(fd) and leak one FD per accept.
     * Mark the accepted impl internally owned under its monitor before closing; safe no-op if absent.
     */
    static void closeAccepted(LocalSocket client) {
        if (client == null) return;
        try {
            Class<?> socketClass = client.getClass();
            java.lang.reflect.Field implField = cachedImplField;
            java.lang.reflect.Field fdInternalField = cachedFdInternalField;
            if (socketClass != cachedSocketClass) {
                implField = socketClass.getDeclaredField("impl");
                implField.setAccessible(true);
                Object probe = implField.get(client);
                if (probe != null) {
                    fdInternalField = probe.getClass().getDeclaredField("mFdCreatedInternally");
                    fdInternalField.setAccessible(true);
                    cachedImplField = implField;
                    cachedFdInternalField = fdInternalField;
                    cachedSocketClass = socketClass;
                } else {
                    fdInternalField = null;
                }
            }
            if (implField != null && fdInternalField != null) {
                Object impl = implField.get(client);
                if (impl != null) {
                    synchronized (impl) {
                        fdInternalField.setBoolean(impl, true);
                    }
                }
            }
        } catch (Throwable ignored) { }
        try { client.close(); } catch (java.io.IOException ignored) { } catch (RuntimeException ignored) { }
    }

    public static void main(String[] args) throws Exception {
        if (Process.myUid() != 1000 || args.length != 0) System.exit(1);
        Looper.prepareMainLooper();
        Class<?> type = Class.forName("android.app.ActivityThread");
        Object thread = type.getMethod("systemMain").invoke(null);
        final Context context = (Context)type.getMethod("getSystemContext").invoke(thread);
        final int clientUid = clientUid(context);
        final Source source = new ExternalSource();
        final LocalServerSocket server = new LocalServerSocket(StockGuidance.SOCKET);
        new Thread(new Runnable() {
            public void run() {
                int acceptErrors = 0;
                while (true) {
                    try {
                        LocalSocket client = server.accept();
                        acceptErrors = 0;
                        try {
                            client.setSoTimeout(350);
                            if (client.getPeerCredentials().getUid() == clientUid
                                    && client.getInputStream().read() == '?') {
                                client.getOutputStream().write(read(source));
                                if ((++queryCount % GC_QUERY_INTERVAL) == 0 && gcRunning.compareAndSet(false, true)) {
                                    Thread gcThread = new Thread(new Runnable() {
                                        public void run() {
                                            try {
                                                System.gc();
                                                System.runFinalization();
                                            } finally {
                                                gcRunning.set(false);
                                            }
                                        }
                                    }, "gen5w-stock-gc");
                                    gcThread.setDaemon(true);
                                    gcThread.start();
                                }
                            }
                        } catch (java.io.IOException ignored) { }
                        finally { closeAccepted(client); }
                    } catch (java.io.IOException e) {
                        kr.gen5w.diag.SafeDiagnostic.failure("core.owner.accept", e);
                        if (++acceptErrors >= 20) System.exit(1);
                        try { Thread.sleep(500); } catch (InterruptedException ignored) { }
                    }
                }
            }
        }, "gen5w-stock-owner").start();
        Looper.loop();
    }
}
