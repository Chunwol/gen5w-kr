"""Real fork/exec/process-group recovery tests; no mocked kernel behavior."""
from pathlib import Path
import os, subprocess, tempfile, time, sys, signal
ROOT=Path(__file__).resolve().parents[1]
RUN=['qemu-arm',str(ROOT/'.build/portable/dex-patch')] if '--arm' in sys.argv else [str(ROOT/'.build/portable/dex-patch-host')]
def main():
 with tempfile.TemporaryDirectory(prefix='g5p-supervision-') as name:
  base=Path(name)
  def script(name,body):
   path=base/name;path.write_text('#!/bin/sh\n'+body+'\n');path.chmod(0o755);return str(path)
  rescue=script('rescue','echo rescued >> "$TEST_STATE/rescues"')
  env=dict(os.environ,TEST_STATE=str(base))
  good=script('good','printf "%s|%s" "$1" "$2" > "$TEST_STATE/args"; exit 0')
  command=[*RUN,'supervise','2',rescue,good,'one word','literal;$value']
  assert subprocess.run(command,env=env).returncode==0,'successful worker rejected'
  assert (base/'args').read_text()=='one word|literal;$value'
  assert not (base/'rescues').exists(),'rescue ran after success'
  bad=script('bad','exit 7')
  assert subprocess.run([*RUN,'supervise','2',rescue,bad],env=env).returncode!=0
  assert (base/'rescues').read_text().splitlines()==['rescued']
  hang=script('hang','(sleep 2; echo leaked > "$TEST_STATE/leaked") &\nwait')
  start=time.monotonic()
  assert subprocess.run([*RUN,'supervise','1',rescue,hang],env=env).returncode!=0
  assert time.monotonic()-start < 4
  time.sleep(2.1)
  assert not (base/'leaked').exists(),'worker descendant survived timeout'
  assert len((base/'rescues').read_text().splitlines())==2
  running=subprocess.Popen([*RUN,'supervise','10',rescue,hang],env=env)
  time.sleep(.2);running.kill();running.wait()
  deadline=time.monotonic()+3
  while len((base/'rescues').read_text().splitlines())<3 and time.monotonic()<deadline: time.sleep(.05)
  assert len((base/'rescues').read_text().splitlines())==3,'parent death did not rescue'
  time.sleep(2.1)
  assert not (base/'leaked').exists(),'descendant survived supervisor death'
  # A descheduled supervisor resumes after the guardian closed its pipe.
  # SIGPIPE must not bypass waiting for the rescue operation to finish.
  slow_rescue=script('slow-rescue','sleep 2; echo done > "$TEST_STATE/slow-done"')
  stopped=subprocess.Popen([*RUN,'supervise','1',slow_rescue,hang],env=env)
  time.sleep(.2);os.kill(stopped.pid,signal.SIGSTOP)
  time.sleep(1.5);os.kill(stopped.pid,signal.SIGCONT)
  assert stopped.wait(timeout=5)==1,'SIGPIPE interrupted guardian wait'
  assert (base/'slow-done').exists(),'returned before rescue completed'
  for limit in ('0','-1','9999','2x'):
   assert subprocess.run([*RUN,'supervise',limit,rescue,good],env=env).returncode!=0
  print('PASS real supervision: exec arguments, success, failure, timeout, descendant kill, supervisor SIGKILL and rescue')
if __name__=='__main__':main()
