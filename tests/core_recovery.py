"""Execute production recovery methods against host IPC/provider boundaries."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

def block(source, signature):
    start = source.index(signature)
    begin = source.index('{', start)
    end, depth = begin + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

owner = (root/'app/src/kr/gen5w/core/StockOwner.java').read_text(encoding='utf-8')
methods = block(owner, 'private static int read(')
for signature in ['private static int readProvider(', 'static final class Observation']:
    if signature in owner:
        methods += '\n' + block(owner, signature)
flag = (root/'app/src/kr/gen5w/core/StockFlag.java').read_text(encoding='utf-8')
flag = flag[flag.index('public final class StockFlag'):].replace('public final class', 'static final class', 1)
harness = r'''
import java.util.concurrent.*;
public class OwnerRecoveryTest {
    static final Object STATE = new Object();
    static final Observation observation = new Observation();
    static class Context {
        final CountDownLatch release = new CountDownLatch(1);
        volatile boolean stalled = true;
        int calls;
        Context getContentResolver() { return this; }
        Cursor query(Object u, String[] columns, Object a, Object b, Object c) {
            calls++;
            if (stalled) try { release.await(); } catch (InterruptedException e) { throw new RuntimeException(e); }
            return new Cursor();
        }
    }
    static class Cursor {
        boolean moved;
        int getColumnCount() { return 1; }
        boolean moveToNext() { boolean result = !moved; moved = true; return result; }
        boolean isNull(int column) { return false; }
        String getString(int column) { return "0"; }
        void close() {}
    }
    static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        final Context context = new Context();
        ExecutorService caller = Executors.newSingleThreadExecutor();
        try {
            Future<Integer> first = caller.submit(new Callable<Integer>() {
                public Integer call() { return read(context); }
            });
            int result;
            try { result = first.get(700, TimeUnit.MILLISECONDS); }
            catch (TimeoutException e) { throw new AssertionError("provider stall blocks ownership clients", e); }
            check(result == '?', "timeout must be UNKNOWN");
            for (int i=0; i<30; i++) check(read(context)=='?', "busy provider must remain UNKNOWN");
            check(context.calls == 1, "stalled provider must not spawn more observations");
            context.stalled = false; context.release.countDown();
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
            do { result = read(context); Thread.yield(); } while (result=='?' && System.nanoTime()<deadline);
            check(result == '0' && context.calls >= 2, "recovery requires fresh provider observation");
            System.out.println("PASS owner timeout, bounded pending query, fresh recovery");
        } finally { context.release.countDown(); caller.shutdownNow(); }
    }
'''
# Before bounded observation exists, omit its field so the regression fails at runtime.
if 'static final class Observation' not in owner:
    harness = harness.replace('    static final Observation observation = new Observation();\n', '')
with tempfile.TemporaryDirectory(prefix='gen5w-recovery-') as tmp:
    path = Path(tmp)/'OwnerRecoveryTest.java'
    path.write_text(harness + methods + '\n' + flag + '\n}', encoding='utf-8')
    subprocess.run(['javac', '--release', '8', '-d', tmp, str(path)], check=True)
    subprocess.run(['java', '-cp', tmp, 'OwnerRecoveryTest'], check=True, timeout=10)

core = (root/'app/src/kr/gen5w/core/CoreService.java').read_text(encoding='utf-8')
methods = block(core, 'private void startAaSocketServer()')
if 'private void stopAaSocketServer()' in core:
    methods += '\n' + block(core, 'private void stopAaSocketServer()')
harness = r'''
public class SocketRecoveryTest {
    static final String TAG="test";
    static final long RETRY_MS=5;
    volatile boolean stopping;
    final Object aaSocketLock = new Object();
    volatile LocalServerSocket aaServer;
    volatile LocalSocket aaClient;
    Thread aaThread;
    volatile int handled;
    boolean blockClient;
    static class Log { static void w(String tag, String value) {} static void i(String tag, String value) {} }
    static class LocalSocket { volatile boolean closed; void close() throws java.io.IOException { closed=true; } }
    static class LocalServerSocket {
        static volatile int binds, closed;
        int accepts;
        boolean ended;
        LocalServerSocket(String name) throws java.io.IOException {
            if (++binds==1) throw new java.io.IOException("transient bind");
        }
        synchronized LocalSocket accept() throws java.io.IOException {
            if (binds==2) throw new java.io.IOException("transient accept");
            if (accepts++==0) return new LocalSocket();
            while (!ended) try { wait(); } catch (InterruptedException e) { throw new java.io.IOException(); }
            throw new java.io.IOException("closed");
        }
        synchronized void close() throws java.io.IOException { ended=true; closed++; notifyAll(); }
    }
    void handleAaClient(LocalSocket client) {
        handled++;
        if(blockClient) while(!client.closed) Thread.yield();
        try { client.close(); } catch (Exception e) {}
    }
    static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        SocketRecoveryTest service=new SocketRecoveryTest();
        service.startAaSocketServer();
        long deadline=System.nanoTime()+2000000000L;
        while(service.handled==0 && System.nanoTime()<deadline) Thread.yield();
        try { check(service.handled==1, "listener must recover after bind and accept failure"); }
        finally {
            service.stopping=true;
            STOP
        }
        if(service.aaThread!=null) service.aaThread.join(500);
        check(service.aaServer==null, "shutdown releases listener reference");
        check(service.aaThread==null || !service.aaThread.isAlive(), "shutdown terminates listener");
        check(LocalServerSocket.closed>=2, "failed and stopped listeners close");
        SocketRecoveryTest blocked=new SocketRecoveryTest(); blocked.blockClient=true;
        blocked.startAaSocketServer();
        deadline=System.nanoTime()+2000000000L;
        while(blocked.handled==0 && System.nanoTime()<deadline) Thread.yield();
        check(blocked.handled==1, "client entered handler");
        blocked.stopping=true;
        STOP_BLOCKED
        blocked.aaThread.join(500);
        check(!blocked.aaThread.isAlive() && blocked.aaClient==null, "shutdown closes active client");
        System.out.println("PASS AA bind/accept recovery and shutdown");
    }
'''
harness = harness.replace('STOP_BLOCKED', 'blocked.stopAaSocketServer();' if 'private void stopAaSocketServer()' in core
                          else 'if(blocked.aaServer!=null) blocked.aaServer.close();')
harness = harness.replace('STOP', 'service.stopAaSocketServer();' if 'private void stopAaSocketServer()' in core
                          else 'if(service.aaServer!=null) service.aaServer.close();')
with tempfile.TemporaryDirectory(prefix='gen5w-socket-recovery-') as tmp:
    path=Path(tmp)/'SocketRecoveryTest.java'
    path.write_text(harness+methods+'\n}', encoding='utf-8')
    subprocess.run(['javac', '--release', '8', '-d', tmp, str(path)], check=True)
    subprocess.run(['java', '-cp', tmp, 'SocketRecoveryTest'], check=True, timeout=10)

methods = block(core, 'private final Runnable outputRetry') + ';'
if 'private void recordHudHealth()' in core:
    methods += '\n' + block(core, 'private void recordHudHealth()')
harness = r'''
public class HudHealthTest {
    static final String TAG="test";
    static class Log { static void w(String a,String b) {} }
    static class Handler { void postDelayed(Runnable r,long delay) {} }
    static class Session { void retryOutput() {} }
    Handler io=new Handler(); Session session=new Session();
    boolean stopping; String ownerState="UNKNOWN";
    java.io.File folder;
    java.io.File getFilesDir() { return folder; }
    void refreshOwnership() {}
    void flushAaClear() {}
    public static void main(String[] args) throws Exception {
        HudHealthTest service=new HudHealthTest();
        service.folder=new java.io.File(args[0]);
        service.outputRetry.run();
        java.io.File status=new java.io.File(service.folder,"hud-health.status");
        if(!status.isFile()) throw new AssertionError("retry must publish fresh ownership heartbeat");
        String result=new String(java.nio.file.Files.readAllBytes(status.toPath()),"US-ASCII");
        if(!result.equals("123 UNKNOWN\n")) throw new AssertionError("heartbeat must describe UNKNOWN with monotonic observation time");
        service.ownerState="STOCK"; service.outputRetry.run();
        result=new String(java.nio.file.Files.readAllBytes(status.toPath()),"US-ASCII");
        if(!result.equals("123 STOCK\n")) throw new AssertionError("heartbeat must replace ownership atomically");
        System.out.println("PASS periodic HUD ownership heartbeat");
    }
'''
with tempfile.TemporaryDirectory(prefix='gen5w-health-') as tmp:
    path=Path(tmp)/'HudHealthTest.java'
    path.write_text(harness+methods+'\n}', encoding='utf-8')
    clock=Path(tmp)/'android/os/SystemClock.java'
    clock.parent.mkdir(parents=True)
    clock.write_text('package android.os; public class SystemClock { public static long elapsedRealtime() { return 123000; } }',encoding='utf-8')
    atomic=Path(tmp)/'android/util/AtomicFile.java'
    atomic.parent.mkdir(parents=True)
    atomic.write_text('''package android.util;
public class AtomicFile {
    final java.io.File target, temporary;
    public AtomicFile(java.io.File file) { target=file; temporary=new java.io.File(file+".tmp"); }
    public java.io.FileOutputStream startWrite() throws java.io.IOException { return new java.io.FileOutputStream(temporary); }
    public void finishWrite(java.io.FileOutputStream out) {
        try { out.close(); java.nio.file.Files.move(temporary.toPath(),target.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING); }
        catch(java.io.IOException e) { throw new AssertionError(e); }
    }
    public void failWrite(java.io.FileOutputStream out) { try { out.close(); } catch(java.io.IOException e) {} }
}''', encoding='utf-8')
    subprocess.run(['javac','--release','8','-d',tmp,str(path),str(clock),str(atomic)],check=True)
    subprocess.run(['java','-cp',tmp,'HudHealthTest',tmp],check=True,timeout=10)
