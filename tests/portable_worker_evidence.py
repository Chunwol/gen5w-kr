"""A dead owned worker must identify its role and preserve its wait status."""
from pathlib import Path
import subprocess,re
s=Path('tools/portable/session.sh').read_text()
m=re.search(r'^check_worker\(\) \{.*?^\}',s,re.M|re.S)
assert m, 'worker failure is still anonymous: missing check_worker'
for rc in (0,23,143):
    harness = """
process_key() { return 1; }
fail() { echo "FAIL:$*"; exit 1; }
"""+m.group()+f'\n(exit {rc}) & pid=$!; sleep .05; check_worker owner "$pid"\n'
    out=subprocess.run(['mksh','-c',harness],capture_output=True,text=True,timeout=3)
    assert out.returncode!=0 and f'worker=owner pid=' in out.stdout and f'exit={rc}' in out.stdout,out
assert 'worker-broker.log' in s and 'worker-owner.log' in s
assert 'diagnostics.sh' in s, 'no failure-time snapshot'
print('PASS worker role/PID and exact wait status (0/23/143), durable logs and failure capture')
