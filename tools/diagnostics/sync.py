"""Verify standalone generated helper copies; no runtime cross-module dependency."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
DIRECTORIES = [
    'packages/wireless-enable/scripts', 'packages/audio-format/scripts',
    'packages/wireless-bridge/scripts', 'packages/core/scripts',
    'packages/consent-timer/scripts', 'packages/bluelink-quiet/scripts',
    'packages/drive-log/scripts', 'tools/local-hotspot/package/scripts',
    'tools/usb-wifi/package/scripts', 'tools/integrated',
]

def check():
    expected = (ROOT / 'tools/diagnostics/errors.sh').read_bytes()
    bad = [str(Path(d) / 'errors.sh') for d in DIRECTORIES
           if not (ROOT / d / 'errors.sh').is_file()
           or (ROOT / d / 'errors.sh').read_bytes() != expected]
    if bad:
        raise SystemExit('Diagnostic helper copies differ: ' + ', '.join(bad))
    hold = (ROOT / 'tools/diagnostics/install-hold.sh').read_bytes()
    hold_dirs = [d for d in DIRECTORIES if d in (
        'packages/core/scripts', 'packages/drive-log/scripts',
        'packages/wireless-bridge/scripts', 'packages/consent-timer/scripts',
        'packages/bluelink-quiet/scripts', 'tools/usb-wifi/package/scripts')]
    bad = [d for d in hold_dirs if (ROOT / d / 'install-hold.sh').read_bytes() != hold]
    if bad:
        raise SystemExit('Install hold copies differ: ' + ', '.join(bad))
    print('PASS standalone diagnostic helper copies match canonical source')

if __name__ == '__main__':
    check()
