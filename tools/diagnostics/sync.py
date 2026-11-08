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
    print('PASS standalone diagnostic helper copies match canonical source')

if __name__ == '__main__':
    check()
