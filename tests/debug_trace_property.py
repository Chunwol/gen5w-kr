"""Exercise production tracing as an app without access to the root-owned flag."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as folder:
    work = Path(folder)
    stub = work / 'android/os/SystemProperties.java'
    stub.parent.mkdir(parents=True)
    stub.write_text('''package android.os;
public final class SystemProperties {
 public static String value="";
 public static String get(String name,String fallback) {
  if(!"debug.gen5wkr.trace".equals(name)) throw new AssertionError("unexpected property");
  return value;
 }
}''')
    harness = work / 'TracePropertyTest.java'
    harness.write_text('''import kr.gen5w.diag.DebugTrace;
public final class TracePropertyTest {
 static void check(boolean value,String why){if(!value)throw new AssertionError(why);}
 static boolean read(String value)throws Exception {
  android.os.SystemProperties.value=value;
  java.lang.reflect.Field checked=DebugTrace.class.getDeclaredField("checked");
  checked.setAccessible(true);checked.setLong(null,0);
  return DebugTrace.enabled();
 }
 public static void main(String[] args)throws Exception {
  check(!read(""),"trace must remain off by default");
  check(read("1"),"app must observe the enabled property without root flag access");
  check(!read("0"),"turning tracing off must stop app traces");
  check(!read("foreign"),"unknown property value must not enable tracing");
  System.out.println("PASS production app trace property enable/off/default/unknown");
 }
}''')
    subprocess.run(['javac', '--release', '8', '-Xlint:-options', '-d', str(work), str(stub), str(harness),
                    str(ROOT/'shared/src/kr/gen5w/diag/DebugTrace.java')], check=True)
    subprocess.run(['java', '-cp', str(work), 'TracePropertyTest'], check=True)
