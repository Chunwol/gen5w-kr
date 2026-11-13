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
 // Fake /system/bin/sync: waitFor() is forbidden (it is unbounded on API 19).
 static class FakeProcess extends Process {
   final int code; final boolean hang; boolean destroyed;
   FakeProcess(int code,boolean hang){this.code=code;this.hang=hang;}
   public OutputStream getOutputStream(){return new ByteArrayOutputStream();}
   public InputStream getInputStream(){return new ByteArrayInputStream(new byte[0]);}
   public InputStream getErrorStream(){return new ByteArrayInputStream(new byte[0]);}
   public int waitFor(){throw new AssertionError("unbounded Process.waitFor");}
   public int exitValue(){if(hang&&!destroyed)throw new IllegalThreadStateException();return destroyed?137:code;}
   public void destroy(){destroyed=true;}
 }
 static ApAttemptGuard.Flush sync(final Process process,long ms){
   return ApAttemptGuard.syncFlush(new ApAttemptGuard.Starter(){public Process start(){return process;}},ms);
 }
 static int radio;
 // Mirrors AndroidWifiAp.markAttempt(): the radio call only follows a returned record.
 static void admitThenRadio(File dir,String boot,ApAttemptGuard.Flush flush) throws IOException {ApAttemptGuard.record(dir,boot,flush);radio++;}
 static void preserved(File dir,String boot) throws IOException {
   BufferedReader in=new BufferedReader(new FileReader(new File(dir,"attempt")));
   try{if(!boot.equals(in.readLine()))throw new AssertionError("failure lost the attempt record");}finally{in.close();}
 }
 static void boundedSync(File root,final String boot) throws Exception {
   if(ApAttemptGuard.SYNC_TIMEOUT_MS<=0||ApAttemptGuard.SYNC_TIMEOUT_MS>30000)throw new AssertionError("sync bound");
   final File hung=new File(root,"hung");hung.mkdir();
   final FakeProcess stuck=new FakeProcess(0,true);
   long start=System.nanoTime();
   reject(new Action(){public void run() throws Exception {admitThenRadio(hung,boot,sync(stuck,200));}});
   long ms=(System.nanoTime()-start)/1000000L;
   if(!stuck.destroyed)throw new AssertionError("hung sync not destroyed");
   if(ms<150||ms>5000)throw new AssertionError("sync wait not bounded: "+ms+" ms");
   preserved(hung,boot);
   final File failing=new File(root,"failing");failing.mkdir();
   reject(new Action(){public void run() throws Exception {admitThenRadio(failing,boot,sync(new FakeProcess(1,false),1000));}});
   preserved(failing,boot);
   final File unstartable=new File(root,"unstartable");unstartable.mkdir();
   reject(new Action(){public void run() throws Exception {admitThenRadio(unstartable,boot,ApAttemptGuard.syncFlush(
     new ApAttemptGuard.Starter(){public Process start() throws IOException {throw new IOException("no sync binary");}},1000));}});
   preserved(unstartable,boot);
   final File interrupted=new File(root,"interrupted");interrupted.mkdir();
   final FakeProcess pending=new FakeProcess(0,true);
   Thread.currentThread().interrupt();
   reject(new Action(){public void run() throws Exception {admitThenRadio(interrupted,boot,sync(pending,5000));}});
   if(!Thread.interrupted())throw new AssertionError("interrupt status lost");
   if(!pending.destroyed)throw new AssertionError("interrupted sync not destroyed");
   preserved(interrupted,boot);
   if(radio!=0)throw new AssertionError("radio call after a failed or timed-out sync");
   File ok=new File(root,"exit0");ok.mkdir();
   admitThenRadio(ok,boot,sync(new FakeProcess(0,false),1000));
   if(radio!=1)throw new AssertionError("exit 0 sync must admit exactly one radio call");
   preserved(ok,boot);
 }
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
   boundedSync(root,boot);
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
print('PASS durable AP admission, bounded sync (hang/fail/exit0/interrupt), preserved failure evidence, boot/PID/starttime markers')
