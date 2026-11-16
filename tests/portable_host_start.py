"""Service admission must use the session budget, not an inner ten-poll race."""
from pathlib import Path
import re
import subprocess

source = Path('tools/portable/session.sh').read_text()
function = re.search(r'^    start_host\(\) \{.*?^    \}', source, re.M | re.S).group()
for scenario in ('delayed', 'missing', 'cancelled'):
    script = r'''
wireless_denied=0; host=0; polls=0; ticks=0
fail() { echo "$*"; exit 1; }
startup_allowed() { [ "$scenario" != cancelled ] || [ "$ticks" -lt 3 ] || fail cancelled; }
op() {
 case "$1" in
 wireless-admit|start-host) return 0;;
 host-ready) polls=$((polls+1)); [ "$scenario" = delayed ] && [ "$polls" -ge 12 ];;
 pause) ticks=$((ticks+1));;
 *) exit 3;;
 esac
}
''' + function + '\nscenario=$1; start_host; echo "READY polls=$polls"\n'
    result = subprocess.run(['mksh', '-c', script, 'fixture', scenario], capture_output=True, text=True, timeout=5)
    if scenario == 'delayed':
        assert result.returncode == 0 and 'READY polls=12' in result.stdout, result.stdout
    else:
        assert result.returncode != 0, (scenario, result.stdout)
        assert ('timeout' if scenario == 'missing' else 'cancelled') in result.stdout
print('PASS delayed host admission, bounded missing host, cancellation; no radio success implied')
