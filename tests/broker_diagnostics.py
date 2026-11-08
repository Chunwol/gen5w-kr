"""Execute the production broker launch/exit blocks; fake only the native child."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root/'packages/wireless-bridge/scripts/service.sh').read_text(encoding='utf-8')
start = source.index('            ERR_DIR=${ERR_DIR:-$DATA/nemesis/gen5wkr.errors}')
end = source.index('            broker_pid=$!', start) + len('            broker_pid=$!')
launch = source[start:end]
start = source.index('        if [ -n "$broker_pid" ] && ! kill -0')
end = source.index('        RETRY_COUNT=$broker_count', start)
observe = source[start:end]
with tempfile.TemporaryDirectory(prefix='gen5w-broker-diag-') as folder:
    work = Path(folder)
    child = work/'nemesis'
    child.write_text('''#!/bin/sh
echo "$$" > "$TEST_PID_FILE"
echo 'java.lang.NoClassDefFoundError SSID=secret-broker password=private' >&2
trap 'exit 23' TERM
while :;do sleep 0.05;done
''',encoding='utf-8')
    child.chmod(0o755)
    script = '''set -u
. "$ERROR_HELPER"
DATA=$TEST_WORK
NEM=$TEST_WORK/nemesis
DEX=unused
broker_count=1
''' + launch + '''
n=0
while [ ! -s "$TEST_PID_FILE" ];do n=$((n+1));[ "$n" -lt 100 ] || exit 10;sleep 0.02;done
IFS= read -r actual < "$TEST_PID_FILE"
[ "$broker_pid" = "$actual" ] || { echo 'FAIL child PID replaced by diagnostic wrapper';exit 11; }
kill "$broker_pid"
n=0
while kill -0 "$broker_pid" 2>/dev/null;do n=$((n+1));[ "$n" -lt 100 ] || exit 12;sleep 0.02;done
''' + observe + '''
wait "$broker_reader"
grep -q 'operation=ap-broker.*reason=missing-class' "$ERR_DIR/errors.0" || exit 13
grep -q 'operation=ap-broker-exit.*rc=23' "$ERR_DIR/errors.0" || exit 14
if grep -R -E 'secret-broker|password=private' "$ERR_DIR";then exit 15;fi
echo 'PASS broker PID identity/stderr classification/native exit/cleanup/privacy'
'''
    env=dict(os.environ,TEST_WORK=str(work),TEST_PID_FILE=str(work/'pid'),
             ERROR_HELPER=str(root/'tools/diagnostics/errors.sh'),ERR_DIR=str(work/'errors'))
    subprocess.run(['mksh','-c',script],env=env,check=True,timeout=10)
