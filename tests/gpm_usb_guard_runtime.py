"""Execute the real guard; doubles replace Android boundaries only."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tools/v039-relay/gpm-src/kr/gen5w/gpm/GpmUsbGuard.java'
STUBS = {
 'android/content/ComponentName.java': '''package android.content; public class ComponentName {String p,c;public ComponentName(String p,String c){this.p=p;this.c=c;}public String getPackageName(){return p;}public String getClassName(){return c;}}''',
 'android/content/Context.java': '''package android.content;public class Context{public int starts;public RuntimeException error;public ComponentName result=new ComponentName("result","result");public ComponentName startService(Intent i){starts++;if(error!=null)throw error;return result;}}''',
 'android/content/Intent.java': '''package android.content;public class Intent{public ComponentName component=new ComponentName("com.google.android.projection.sink","com.google.android.projection.service.GalReceiverService");public int mode=1;public Object device;public boolean broken;public ComponentName getComponent(){if(broken)throw new IllegalStateException();return component;}public int getIntExtra(String k,int d){return mode;}public Object getParcelableExtra(String k){return device;}}''',
 'android/hardware/usb/UsbInterface.java': '''package android.hardware.usb;public class UsbInterface{int c;public UsbInterface(int c){this.c=c;}public int getInterfaceClass(){if(c==-2)throw new IllegalStateException();return c;}}''',
 'android/hardware/usb/UsbDevice.java': '''package android.hardware.usb;public class UsbDevice{public UsbInterface[] items;public UsbDevice(int... cs){items=new UsbInterface[cs.length];for(int i=0;i<cs.length;i++)items[i]=cs[i]==-1?null:new UsbInterface(cs[i]);}public int getInterfaceCount(){return items.length;}public UsbInterface getInterface(int i){return items[i];}}''',
}
HARNESS = '''import android.content.*;import android.hardware.usb.*;import kr.gen5w.gpm.GpmUsbGuard;
public class GuardTest{
 static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
 static void test(String name,Intent i,boolean blocked){Context c=new Context();ComponentName r=GpmUsbGuard.startService(c,i);check(c.starts==(blocked?0:1),name+" starts");check(r==(blocked?null:c.result),name+" result");System.out.println("PASS "+name);}
 public static void main(String[] args){
  int[][] cases={{8},{9},{8,9},{255},{8,255},{},{-1},{8,-2},{0}};
  for(int n=0;n<cases.length;n++){Intent i=new Intent();i.device=new UsbDevice(cases[n]);test("interfaces-"+n,i,n<3);}
  Intent i=new Intent();test("missing-device",i,false);i.device="wrong-type";test("wrong-device",i,false);
  i.device=new UsbDevice(8);i.mode=2;test("wireless-mode",i,false);i.mode=-1;test("missing-mode",i,false);i.mode=1;
  i.component=new ComponentName("other","com.google.android.projection.service.GalReceiverService");test("foreign-package",i,false);
  i.component=new ComponentName("com.google.android.projection.sink","other");test("other-service",i,false);
  i.component=null;test("implicit",i,false);i.broken=true;test("metadata-exception",i,false);test("null-intent",null,false);
  Context c=new Context();c.error=new SecurityException("original");Intent phone=new Intent();phone.device=new UsbDevice(255);
  try{GpmUsbGuard.startService(c,phone);throw new AssertionError("exception swallowed");}catch(SecurityException e){check(e==c.error&&c.starts==1,"delegated failure cannot retry");}
  System.out.println("PASS delegated-exception-once");
 }
}'''

assert SOURCE.is_file(), 'missing production USB guard'
with tempfile.TemporaryDirectory(prefix='gen5w-gpm-guard-') as folder:
    work = Path(folder); sources = []
    for name, body in {**STUBS, 'GuardTest.java': HARNESS}.items():
        path = work/name; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding='utf-8'); sources.append(str(path))
    sources += [str(SOURCE), str(ROOT/'shared/src/kr/gen5w/diag/SafeDiagnostic.java')]
    subprocess.run(['javac','-encoding','UTF-8','-Xlint:-options','--release','8','-d',str(work),*sources],check=True)
    subprocess.run(['java','-cp',str(work),'GuardTest'],check=True,timeout=15)
