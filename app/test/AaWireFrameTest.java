import kr.gen5w.hud.AaWireFrame;
import java.io.*;
public class AaWireFrameTest {
 static void bad(byte[] b)throws Exception{try{AaWireFrame.read(new ByteArrayInputStream(b));throw new AssertionError("accepted bad frame");}catch(IOException expected){}}
 public static void main(String[] args)throws Exception{
  byte[] b={'G','A','N','1',0,0,(byte)128,6,0,0,0,2,10,0};
  AaWireFrame f=AaWireFrame.read(new ByteArrayInputStream(b));if(f.type!=0x8006||f.payload.length!=2)throw new AssertionError();
  for(int n=0;n<b.length;n++)bad(java.util.Arrays.copyOf(b,n));
  byte[] x=b.clone();x[0]='X';bad(x);x=b.clone();x[7]=8;bad(x);x=b.clone();x[8]=1;bad(x);
  System.out.println("PASS AA binary framing, length bound, unknown types and every truncation");
 }
}