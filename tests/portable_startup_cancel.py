"""Stopping a session waits for its in-flight startup and cleanup worker."""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path('tools/portable/boot.sh').read_text()
stop = re.search(r'^stop_session\(\) \{.*?^\}', source, re.M | re.S).group()
with tempfile.TemporaryDirectory(prefix='gen5w-stop-') as temp:
    script = r'''
clock() { date +%s; }
deadline() { limit=$(( $(clock) + 3 )); }
within() { [ "$(clock)" -lt "$limit" ]; }
op() { case "$1" in session-stop) :;; busy) return 1;; pause) sleep .02;; *) return 1;; esac; }
''' + stop + r'''
(sleep .3; touch "$1/cleanup-finished") & child=$!
trap 'kill "$child" 2>/dev/null; wait "$child" 2>/dev/null' EXIT
stop_session || exit 2
[ -f "$1/cleanup-finished" ] || { echo 'FAIL restoration raced an in-flight session worker'; exit 3; }
'''
    subprocess.run(['mksh', '-c', script, 'fixture', temp], check=True)
print('PASS restoration waits for the owned startup/cleanup worker')
