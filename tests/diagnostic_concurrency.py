"""Real mksh attempts must not overwrite a live attempt's report or lock."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]

def until(path):
    deadline = time.monotonic() + 5
    while not path.exists():
        if time.monotonic() >= deadline:
            raise AssertionError(f"barrier not reached: {path.name}")
        time.sleep(.01)

with tempfile.TemporaryDirectory(prefix='gen5w-reclaim-') as folder:
    work = Path(folder)
    (work/'journal/write.lock').mkdir(parents=True)
    (work/'journal/write.lock/owner').write_text('oldboot 99999999\n')
    env = dict(os.environ, ROOT=str(root), W=str(work))
    a = subprocess.Popen(['mksh', '-c', '''
. "$ROOT/tools/diagnostics/errors.sh"
rm() {
  : > "$W/a-paused"
  while [ ! -e "$W/release-a" ];do sleep .01;done
  command rm "$@"
}
rc=0;err_lock "$W/journal" currentboot || rc=$?
echo "$rc"
'''], env=env, stdout=subprocess.PIPE, text=True)
    b = None
    try:
        until(work/'a-paused')
        b = subprocess.Popen(['mksh', '-c', '''
. "$ROOT/tools/diagnostics/errors.sh"
rc=0;err_lock "$W/journal" currentboot || rc=$?
echo "$rc"
[ "$rc" != 0 ] || : > "$W/b-holding"
: > "$W/b-finished"
while [ ! -e "$W/release-b" ];do sleep .01;done
'''], env=env, stdout=subprocess.PIPE, text=True)
        until(work/'b-finished')
        (work/'release-a').touch()
        a_rc = a.communicate(timeout=5)[0].strip()
        if (work/'b-holding').exists():
            assert a_rc != '0', 'stale reclaimer stole the new live writer lock'
    finally:
        (work/'release-a').touch()
        (work/'release-b').touch()
        a.wait(timeout=5)
        if b is not None:
            b.communicate(timeout=5)
print('PASS stale recovery cannot steal a replacement writer lock')

with tempfile.TemporaryDirectory(prefix='gen5w-writer-pid-') as folder:
    work = Path(folder)
    (work/'journal').mkdir()
    result = subprocess.run(['mksh', '-c', '''
. "$ROOT/tools/diagnostics/errors.sh"
(
  err_lock "$W/journal" sameboot || exit 2
  : > "$W/held"
  while :;do sleep .02;done
) & writer=$!
while [ ! -e "$W/held" ];do sleep .01;done
kill -9 "$writer";wait "$writer" 2>/dev/null || :
err_lock "$W/journal" sameboot || { echo 'FAIL dead background writer mistaken for live parent';exit 3; }
'''], env=dict(os.environ, ROOT=str(root), W=str(work)), capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stdout + result.stderr
print('PASS killed background writer recovered while supervisor remains alive')

with tempfile.TemporaryDirectory(prefix='gen5w-concurrent-') as folder:
    work = Path(folder)
    for name in ('errors.sh', 'history.sh', 'NEMESIS.sh'):
        shutil.copy(root/'tools/integrated'/name, work/name)
    (work/'bin').mkdir()
    getprop = work/'bin/getprop'
    getprop.write_text('#!/bin/sh\necho 1\n')
    getprop.chmod(0o755)
    (work/'install.sh').write_text('''#!/bin/sh
echo invocation >> invocations
echo 'FIRST operation output'
touch entered
while [ ! -e release ];do sleep .02;done
exit 17
''')
    env = dict(os.environ, PATH=str(work/'bin')+':'+os.environ['PATH'],
               ERR_DIR=str(work/'private'), IT_SHELL='mksh')
    first = subprocess.Popen(['mksh', 'NEMESIS.sh'], cwd=work, env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        until(work/'entered')
        # A real competing entry must refuse before archiving/truncating or running.
        (work/'release').touch()
        # Keep the original process alive at a second barrier in a fresh attempt.
        first.wait(timeout=5)
        (work/'release').unlink()
        (work/'entered').unlink()
        first = subprocess.Popen(['mksh', 'NEMESIS.sh'], cwd=work, env=env,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        until(work/'entered')
        second = subprocess.Popen(['mksh', 'NEMESIS.sh'], cwd=work, env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(.15)
            calls = (work/'invocations').read_text().splitlines()
            assert len(calls) == 2, 'competing entry ran and overwrote live report'
            assert second.wait(timeout=2) != 0, 'competing entry was accepted'
        finally:
            (work/'release').touch()
            second.wait(timeout=5)
    finally:
        (work/'release').touch()
        first.wait(timeout=5)
    assert first.returncode == 17, 'report lock changed original operation rc'
    assert 'FIRST operation output' in (work/'GEN5W-REPORT/EXEC_LOG.txt').read_text()
    # Clean exit releases ownership; later attempts must remain usable.
    later = subprocess.run(['mksh', 'NEMESIS.sh'], cwd=work, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    assert later.returncode == 17, 'completed attempt left an unusable report lock'
print('PASS live report attempt serialization, original rc and next attempt')
