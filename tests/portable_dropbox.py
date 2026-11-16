"""Exercise production Dropbox scanning with slow Android process creation."""
import os
import gzip
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class DropboxScan(unittest.TestCase):
    def test_readonly_scan_allows_backlog_without_extending_reset_budget(self):
        source = Path('tools/portable/boot.sh').read_text()
        bounded = source[source.index('scan_bounded() {'):source.index('reset_bounded() {')]
        functions = source[source.index('DROPBOX=$ROOT/data/system/dropbox'):source.index('reset_check() {')]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            db = root / 'data/system/dropbox'
            state = root / 'state'
            bins = root / 'bin'
            for directory in (db, state, bins):
                directory.mkdir(parents=True)
            (state / 'dropbox-baseline').write_text('')
            for n in range(20):
                (db / f'system_app_crash@{n}.txt').write_text('Process: com.example.radio\n')
            grep = shutil.which('grep')
            (bins / 'grep').write_text('#!/bin/sh\nsleep .1\nexec ' + grep + ' "$@"\n')
            (bins / 'grep').chmod(0o755)
            supervisor = root / 'supervisor.py'
            supervisor.write_text('''#!/usr/bin/env python3
import os,signal,subprocess,sys
p=subprocess.Popen(sys.argv[4:],start_new_session=True)
try: sys.exit(p.wait(timeout=int(sys.argv[2])/10))
except subprocess.TimeoutExpired:
 os.killpg(p.pid,signal.SIGKILL);p.wait();sys.exit(124)
''')
            supervisor.chmod(0o755)
            child = root / 'boot.sh'
            child.write_text('#!/bin/sh\nplain() { return 0; }\n' + functions + '\ncase "$1" in dropbox-scan) dropbox_scan;; *) sleep 2;; esac\n')
            wrapper = root / 'wrapper.sh'
            wrapper.write_text(bounded + '\nscan_bounded "$1"\n')
            env = dict(os.environ, ROOT=str(root), BASE=str(root), STATE=str(state), SUPERVISOR=str(supervisor), PATH=str(bins)+':'+os.environ['PATH'])
            result = subprocess.run(['mksh', str(wrapper), 'dropbox-scan'], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, 'clean'), result.stderr)
            # The unrelated reset reader must retain its shorter deadline.
            result = subprocess.run(['mksh', str(wrapper), 'reset-snapshot'], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 124)

    def test_historical_entries_are_bounded_and_new_failures_remain_visible(self):
        source = Path('tools/portable/boot.sh').read_text()
        functions = source[source.index('DROPBOX=$ROOT/data/system/dropbox'):source.index('reset_check() {')]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            db = root / 'data/system/dropbox'
            state = root / 'state'
            bins = root / 'bin'
            for directory in (db, state, bins):
                directory.mkdir(parents=True)
            old = [f'system_app_crash@{n}.txt' for n in range(168)]
            for name in old:
                (db / name).write_text('Process: com.daudio.app.dipo\n')
            (state / 'dropbox-baseline').write_text('\n'.join(old) + '\n')
            (db / 'system_app_anr@2000.txt').write_text('Process: com.example.radio\nCPU usage:\n  2% 1873/com.daudio.app.dipo: 0% user\n')
            real_grep = shutil.which('grep')
            (bins / 'grep').write_text('#!/bin/sh\nif [ "$1" = -qFx ]; then sleep .1; fi\nexec ' + real_grep + ' "$@"\n')
            (bins / 'grep').chmod(0o755)
            script = root / 'scan.sh'
            script.write_text('plain() { return 0; }\n' + functions + '\ndropbox_scan\n')
            env = dict(os.environ, ROOT=str(root), STATE=str(state), PATH=str(bins) + ':' + os.environ['PATH'])

            def scan():
                return subprocess.run(['mksh', str(script)], env=env, capture_output=True, text=True, timeout=4, check=True).stdout.strip()

            self.assertEqual(scan(), 'clean')
            # The old name contains the new one as a substring; membership must
            # compare complete lines, including the first and last baseline row.
            (db / 'system_app_crash@68.txt').unlink()
            (db / 'system_app_crash@8.txt').unlink()
            baseline = '\n'.join(n for n in old if n != 'system_app_crash@8.txt') + '\n'
            (state / 'dropbox-baseline').write_text(baseline)
            (db / 'system_app_crash@8.txt').write_text('Process: com.daudio.app.dipo\n')
            self.assertEqual(scan(), 'hit|system_app_crash@8.txt')
            (db / 'system_app_crash@8.txt').unlink()
            (db / 'system_server_watchdog@2001.txt').write_text('Blocked handler\n')
            self.assertEqual(scan(), 'hit|system_server_watchdog@2001.txt')
            (db / 'system_server_watchdog@2001.txt').unlink()
            (db / 'system_app_anr@2002.txt').write_text('Process: com.tcc.iap2server\n')
            self.assertEqual(scan(), 'hit|system_app_anr@2002.txt')
            (db / 'system_app_anr@2002.txt').unlink()
            (db / 'system_app_anr@2002.txt').write_text('Process: com.daudio.app.dipocopy\n')
            self.assertEqual(scan(), 'clean')
            native = db / 'SYSTEM_TOMBSTONE@2003.txt.gz'
            for header in ('pid: 9, name: projection >>> com.google.android.projection.sink <<<', 'Cmd line: com.daudio.app.dipo:worker'):
                native.write_bytes(gzip.compress((header + '\n').encode()))
                self.assertEqual(scan(), 'hit|SYSTEM_TOMBSTONE@2003.txt.gz')


if __name__ == '__main__':
    unittest.main()
