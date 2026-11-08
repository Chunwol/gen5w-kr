import kr.gen5w.diag.SafeDiagnostic;
import java.util.ArrayList;
public final class SafeDiagnosticTest {
    static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
    public static void main(String[] args) throws Exception {
        final ArrayList<String> lines=new ArrayList<String>();
        SafeDiagnostic.Sink sink=new SafeDiagnostic.Sink(){public void write(String line){lines.add(line);}};
        SafeDiagnostic d=new SafeDiagnostic();
        Throwable secret=new IllegalStateException("SSID=secret-network password=secret-key 00:11:22:33:44:55");
        check(d.emit(sink,"core.owner.query",secret,7,100),"first error emitted");
        for(int i=0;i<1000;i++)check(!d.emit(sink,"core.owner.query",secret,7,101+i),"repeat rate gated");
        check(lines.size()==1&&!lines.get(0).contains("secret")&&!lines.get(0).contains("00:11"),"exception message never logged");
        check(lines.get(0).contains("IllegalStateException")&&lines.get(0).contains("generation=7"),"class and generation retained");
        check(d.emit(sink,"core.storage.write",new java.io.IOException("/private/secret-key: No space left on device"),0,2000),"storage failure emitted");
        check(lines.get(lines.size()-1).contains("reason=no-space")&&!lines.get(lines.size()-1).contains("secret-key"),"classify storage cause without path");
        check(d.emit(sink,"core.owner.query",secret,7,30100),"thirty second retry observable");
        check(d.emit(sink,"core.owner.query",secret,8,30101),"new generation observable");
        check(d.emit(sink,"core.owner.query",secret,8,1),"clock rollback observable");
        check(!d.emit(sink,"SSID=secret",secret,0,0),"invalid code not logged");
        for(int i=0;i<100;i++)d.emit(sink,"core.test."+i,secret,0,100000+i);
        java.lang.reflect.Field state=SafeDiagnostic.class.getDeclaredField("stamps");state.setAccessible(true);
        check(((java.util.Map<?,?>)state.get(d)).size()<=64,"rate state bounded");
        check(!d.emit(new SafeDiagnostic.Sink(){public void write(String line){throw new IllegalStateException();}},"core.sink.failure",secret,0,200000),"observer cannot interrupt cleanup");
        System.out.println("PASS safe diagnostics privacy/rate/generation/clock/capacity/observer");
    }
}
