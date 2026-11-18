"""Exercise the actual kernel lock/exec boundary, including abrupt death."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import sys

root = Path(__file__).resolve().parents[1]
helper = root / '.build/portable/dex-patch-host'
prefix = [str(helper)]
if sys.argv[1:] == ['--arm']:
    prefix = ['qemu-arm', str(root / '.build/portable/vehicle-067-inputs/dex-patch')]
with tempfile.TemporaryDirectory(prefix='g5lock-') as tmp:
    lock = str(Path(tmp) / 'lock')
    ready = Path(tmp) / 'ready'
    command = prefix + ['lock-run', lock, '/bin/sh', '-c', 'echo ready > "$1"; exec sleep 60', 'sh', str(ready)]
    worker = subprocess.Popen(command)
    try:
        for _ in range(100):
            if ready.exists():
                break
            assert worker.poll() is None
            time.sleep(.02)
        assert ready.exists()
        assert subprocess.run(prefix + ['lock-run', lock, '/bin/true', 'unused']).returncode == 75
        worker.kill()
        worker.wait(timeout=5)
        assert subprocess.run(prefix + ['lock-run', lock, '/bin/true', 'unused']).returncode == 0
        link = Path(tmp) / 'link'
        link.symlink_to(lock)
        assert subprocess.run(prefix + ['lock-run', str(link), '/bin/true', 'unused']).returncode != 0
    finally:
        if worker.poll() is None:
            worker.kill()
            worker.wait(timeout=5)
print('PASS kernel lock: exclusive exec ownership, SIGKILL recovery, symlink refusal')
