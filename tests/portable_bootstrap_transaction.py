"""Production Bootstrap/adapters; Android and native Hook are host boundaries.

Run on Linux (real /proc), or set PORTABLE_BOOTSTRAP_LINUX_JAVA to a WSL Java
executable when compiling with a Windows JDK. Marker failures use actual files.
"""
import os
from pathlib import Path
import subprocess
import tempfile

from portable_adapters import ROOT, STUBS

BOUNDARIES = dict(STUBS)
BOUNDARIES['android/content/Context.java'] = '''package android.content;
import java.io.File;public class Context {
 public String pkg="com.daudio.app.dipo";public File root;
 public String getPackageName(){return pkg;}
 public String getPackageCodePath(){return "fake.dex";}
 public ClassLoader getClassLoader(){return getClass().getClassLoader();}
 public File getFilesDir(){File f=new File(root,"files");f.mkdirs();return f;}
 public File getDir(String name,int mode){File f=new File(root,"app_"+name);f.mkdirs();return f;}
 public ComponentName startService(Intent i){return null;}
}'''
BOUNDARIES['dalvik/system/DexClassLoader.java'] = '''package dalvik.system;
public class DexClassLoader extends ClassLoader {public static int created;
 public DexClassLoader(String jar,String cache,String lib,ClassLoader parent){super(parent);created++;}
}'''
BOUNDARIES['kr/gen5w/portable/Hook.java'] = BOUNDARIES['kr/gen5w/portable/Hook.java'].replace(
 'public static int fail=-1;', 'public static int fail=-1,failRemove=-1;public static java.util.HashSet<Integer> live=new java.util.HashSet<Integer>();') .replace(
 'targets.add(t);', 'for(Integer i:live)if(targets.get(i).equals(t))throw new IllegalStateException("duplicate target");live.add(targets.size());targets.add(t);').replace(
 'removed.add(i);', 'if(i==failRemove)throw new IllegalStateException("rollback failure");removed.add(i);live.remove(i);').replace(
 'try{Method m=targets.get(i);', 'if(i<0)return null;try{Method m=targets.get(i);')

HARNESS = r'''import kr.gen5w.portable.*;import android.content.Context;
import java.io.*;import java.lang.reflect.*;
public class BootstrapTransactionTest {
 static void check(boolean b,String m){if(!b)throw new AssertionError(m);}
 static void field(String name,Object value)throws Exception{Field f=Bootstrap.class.getDeclaredField(name);f.setAccessible(true);f.set(null,value);}
 static Object call(Object receiver,String name)throws Throwable{try{return receiver.getClass().getMethod(name).invoke(receiver);}catch(InvocationTargetException e){throw e.getCause();}}
 static Object begin(Context c)throws Throwable{try{return ProjectionAdapters.class.getMethod("beginInstall",Context.class).invoke(null,c);}catch(NoSuchMethodException e){throw new AssertionError("transactional adapter beginInstall required",e);}catch(InvocationTargetException e){throw e.getCause();}}
 public static void main(String[] args)throws Throwable {
  String mode=args[0];Context c=new Context();c.root=new File(args[1]);c.getFilesDir();
  dalvik.system.DexFile.names=new String[]{"com.daudio.app.dipo.renamed.Owner","com.daudio.app.dipo.renamed.Owner$Local","com.daudio.app.dipo.renamed.Owner$Local$BinderListener","com.daudio.app.dipo.renamed.Owner$Connection","com.daudio.app.dipo.renamed.Owner$OtherConnection","com.daudio.app.dipo.renamed.Wireless","com.daudio.app.dipo.renamed.BluetoothManager","com.daudio.app.dipo.service.DipoService$Details"};
  if(mode.startsWith("gpm"))c.pkg="com.google.android.projection.sink";
  field("ownerPackage",c.pkg);field("adapterJar",new File(c.root,"adapter.jar").getAbsolutePath());
  if(mode.endsWith("existing"))ProjectionAdapters.install(c);
  if(mode.equals("transaction")){
   Object attempt=begin(c);check(Hook.live.size()==15,"provisional group installed");call(attempt,"rollback");check(Hook.live.isEmpty(),"rollback all provisional hooks");
   attempt=begin(c);check(Hook.live.size()==15,"retry installs complete group");call(attempt,"commit");call(attempt,"rollback");check(Hook.live.size()==15,"committed group preserved");
   Object existing=begin(c);call(existing,"rollback");check(Hook.live.size()==15,"preexisting group preserved");return;
  }
  if(mode.equals("partial-rollback-failure")){
   Hook.fail=5;Hook.failRemove=3;
   try{begin(c);throw new AssertionError("accepted partial installation");}catch(IllegalStateException expected){check(expected.getSuppressed().length>0,"rollback failure retained");}
   check(Hook.live.size()==1&&Hook.live.contains(3),"other provisional hooks still rolled back");Hook.fail=-1;
   try{begin(c);throw new AssertionError("retried unresolved group");}catch(IllegalStateException expected){}
   return;
  }
  File ready=new File(c.getFilesDir(),"gen5w-portable-ready"),temporary=new File(c.getFilesDir(),"gen5w-portable-ready.tmp");
  if(mode.contains("rename")){
   c=new Context(){public File getFilesDir(){return new File(root,"files");}public File getDir(String n,int m){File f=super.getDir(n,m);try{File blocker=new File(root,"files/gen5w-portable-ready");blocker.mkdirs();new File(blocker,"child").createNewFile();}catch(IOException e){throw new RuntimeException(e);}return f;}};
   c.root=new File(args[1]);field("ownerPackage",c.pkg);
  }else if(!mode.equals("success")){check(temporary.mkdir(),"create actual marker-open failure");}
  if(mode.endsWith("rollback-failure")){Hook.failRemove=3;if(mode.startsWith("partial-bootstrap"))Hook.fail=5;}
  boolean threw=false;try{Bootstrap.attach(null,c,-1);}catch(Throwable failure){threw=true;check(mode.endsWith("rollback-failure"),"unexpected attach failure: "+failure);}
  int count=mode.startsWith("gpm")?1:15;
  if(mode.equals("success")){check(ready.isFile(),"ready marker published");check(Hook.live.size()==15,"successful group retained");Bootstrap.attach(null,c,-1);check(Hook.targets.size()==15,"successful attach cannot duplicate install");return;}
  if(mode.endsWith("rollback-failure")){check(threw,"rollback failure cannot be reported as unavailable/stock");check(Hook.live.size()==1,"remaining hook accounted for");int installed=Hook.targets.size();try{Bootstrap.attach(null,c,-1);throw new AssertionError("retry hid unresolved hooks");}catch(IllegalStateException expected){}check(Hook.targets.size()==installed,"unresolved rollback cannot install duplicate hooks");return;}
  if(mode.endsWith("existing")){check(Hook.live.size()==count,"readiness failure preserves preexisting group");return;}
  check(Hook.live.isEmpty(),"readiness failure must roll back this attempt's hooks");
  check(!ready.isFile(),"failed publication must not leave ready marker");
  if(!mode.contains("rename")){check(temporary.delete(),"remove marker-open blocker");Bootstrap.attach(null,c,-1);check(ready.isFile(),"retry publishes readiness");check(Hook.live.size()==count,"retry installs one complete group");check(dalvik.system.DexClassLoader.created==1,"retry must retain adapter loader transaction state");}
 }
}'''


def main():
    linux_java = os.environ.get('PORTABLE_BOOTSTRAP_LINUX_JAVA')
    if os.name == 'nt' and not linux_java:
        raise SystemExit('Real /proc required: set PORTABLE_BOOTSTRAP_LINUX_JAVA to WSL java')
    with tempfile.TemporaryDirectory(prefix='bootstrap-transaction-', dir=ROOT / '.build') as temporary:
        tmp = Path(temporary)
        sources = []
        for name, content in dict(BOUNDARIES, **{'BootstrapTransactionTest.java': HARNESS}).items():
            path = tmp / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            sources.append(path)
        sources += list((ROOT / 'tools/portable/adapters/src').rglob('*.java'))
        sources += [ROOT / 'tools/portable/dalvik/src/kr/gen5w/portable' / name for name in ('Bootstrap.java', 'AppLocalLoader.java')]
        sources += [ROOT / 'tools/v039-relay/dipo-src/kr/gen5w/dipo/RelayBridge.java', ROOT / 'tools/v039-relay/gpm-src/kr/gen5w/gpm/GpmUsbGuard.java']
        subprocess.run(['javac', '--release', '8', '-Xlint:-options', '-d', str(tmp / 'classes'), *map(str, sources)], check=True)
        def guest(path):
            if os.name != 'nt':
                return str(path)
            return '/mnt/' + path.drive[0].lower() + path.as_posix()[2:]
        command = ['wsl', '-e', linux_java] if os.name == 'nt' else ['java']
        for case in ('open', 'rename', 'success', 'existing', 'gpm-open', 'gpm-existing', 'transaction', 'rollback-failure', 'partial-rollback-failure', 'partial-bootstrap-rollback-failure'):
            home = tmp / case
            home.mkdir()
            subprocess.run([*command, '-cp', guest(tmp / 'classes'), 'BootstrapTransactionTest', case, guest(home)], check=True)
            print('PASS bootstrap transaction', case, flush=True)


if __name__ == '__main__':
    main()
