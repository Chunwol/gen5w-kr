#!/usr/bin/env python3
"""Exercise durable radio admission and boot/process identity without Android."""
import os, pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
JDK = pathlib.Path(os.environ.get('JAVA_HOME', '')) / 'bin'
def tool(name):
    candidate = JDK / (name + ('.exe' if os.name == 'nt' else ''))
    return str(candidate) if candidate.is_file() else name
with tempfile.TemporaryDirectory(prefix='g5p-guard-') as directory:
    work = pathlib.Path(directory)
    cases = {
      'kr/gen5w/hotspot/GuardTest.java': r'''package kr.gen5w.hotspot;
import java.io.*;
public final class GuardTest {
 interface Action { void run() throws Exception; }
 static void reject(Action action) throws Exception {
   try { action.run(); } catch (IOException expected) { return; }
   throw new AssertionError("unsafe admission");
 }
 static final ApAttemptGuard.Flush FLUSH = new ApAttemptGuard.Flush() {public void run() {}};
 static void record(File root,String boot) throws IOException {ApAttemptGuard.record(root,boot,FLUSH);}
 public static void main(String[] args) throws Exception {
   final File root = new File(args[0]);
   final String boot = "12345678-abcd-1234-abcd-123456789abc";
   reject(new Action(){public void run() throws Exception {record(new File(root,"absent"),boot);}});
   final File good = new File(root,"good"); good.mkdir();
   record(good,boot);
   if (File.separatorChar == '\\') {
     // Windows renameTo refuses replacing a target; Android/Linux permits it.
     reject(new Action(){public void run() throws Exception {record(good,boot);}});
   } else { record(good,boot); }
   BufferedReader input = new BufferedReader(new FileReader(new File(good,"attempt")));
   if (!boot.equals(input.readLine()) || input.readLine()!=null) throw new AssertionError("journal"); input.close();
   reject(new Action(){public void run() throws Exception {record(good,"bad");}});
   final File syncFail = new File(root,"syncFail"); syncFail.mkdir();
   reject(new Action(){public void run() throws Exception {
     ApAttemptGuard.record(syncFail,boot,new ApAttemptGuard.Flush(){public void run() throws IOException {
       if(!new File(syncFail,"attempt").isFile())throw new AssertionError("sync before seal");
       throw new IOException("sync failed");
     }});
   }});
   if(!new File(syncFail,"attempt").isFile())throw new AssertionError("sync failure lost evidence");
   new File(good,"attempt.tmp").mkdir();
   reject(new Action(){public void run() throws Exception {record(good,boot);}});
   if (!new File(good,"attempt").isFile()) throw new AssertionError("lost previous evidence");
 }
}''',
      'kr/gen5w/wireless/MarkerTest.java': r'''package kr.gen5w.wireless;
import java.io.*;
public final class MarkerTest {
 static String stat(String state) {String s="42 (odd ) name) "+state; for(int i=1;i<19;i++)s+=" 0";return s+" 9876";}
 static void reject(int pid,String boot,String stat) throws Exception {
   try {HostReadyMarker.content(pid,boot,stat);}catch(IOException expected){return;}
   throw new AssertionError("unsafe marker");
 }
 public static void main(String[] args) throws Exception {
   String boot="12345678-abcd-1234-abcd-123456789abc";
   if(!HostReadyMarker.content(42,boot,stat("S")).equals("42\nboot_id="+boot+"\nstarttime=9876\n"))throw new AssertionError("identity");
   reject(43,boot,stat("S")); reject(42,boot,stat("Z")); reject(42,boot,"42 (short) S"); reject(42,"bad",stat("S"));
 }
}'''}
    sources = []
    for name, content in cases.items():
        file = work / name; file.parent.mkdir(parents=True, exist_ok=True); file.write_text(content); sources.append(str(file))
    for name in ('hotspot/ApAttemptGuard.java', 'wireless/HostReadyMarker.java'):
        sources.append(str(ROOT/'packages/wireless-bridge/src/kr/gen5w'/name))
    subprocess.run([tool('javac'),'--release','8','-d',str(work),*sources],check=True)
    for name in ('hotspot.GuardTest','wireless.MarkerTest'):
        subprocess.run([tool('java'),'-Xms16m','-Xmx128m','-cp',str(work),'kr.gen5w.'+name,str(work)],check=True)
print('PASS durable AP admission, preserved failure evidence, boot/PID/starttime markers')
