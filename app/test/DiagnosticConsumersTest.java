import kr.gen5w.ui.SwitchRequest;
import java.io.*;
public final class DiagnosticConsumersTest {
    public static void main(String[] args) throws Exception {
        File dir=java.nio.file.Files.createTempDirectory("gen5w-private-secret-").toFile();
        File blocked=new File(dir,"ui-request");blocked.mkdir();
        File keep=new File(blocked,"keep");new FileOutputStream(keep).close();
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();PrintStream original=System.err;
        boolean result;
        try {System.setErr(new PrintStream(bytes));result=SwitchRequest.write(dir,"on",null,null,null,null,null);}
        finally {System.setErr(original);}
        if(result||!keep.isFile())throw new AssertionError("failed rename must retain existing target");
        String log=bytes.toString("UTF-8");
        if(!log.contains("ui.request.rename"))throw new AssertionError("request failure cause not observable");
        if(log.contains("private-secret")||log.contains(dir.toString()))throw new AssertionError("private path leaked");
        keep.delete();blocked.delete();dir.delete();
        System.out.println("PASS actual request write failure diagnosed without altering result or leaking path");
    }
}
