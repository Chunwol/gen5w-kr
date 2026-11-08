"""Verify the built core APK preserves its source manifest version (no CLI overrides)."""
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
sdk = Path(os.environ.get('ANDROID_SDK') or os.environ.get('ANDROID_HOME') or Path.home() / 'AppData/Local/Android/Sdk')
bt = sdk / 'build-tools' / os.environ.get('BUILD_TOOLS', '36.0.0')
aapt = bt / ('aapt2.exe' if os.name == 'nt' else 'aapt2')
manifest = ET.parse(root / 'app/AndroidManifest.xml').getroot()
android = '{http://schemas.android.com/apk/res/android}'
badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(root / 'app/build/gen5w-core.apk')], text=True, encoding='utf-8')
package = next(line for line in badging.splitlines() if line.startswith('package:'))
for attr in ('versionCode', 'versionName'):
    actual = re.search(r"\b" + attr + r"='([^']*)'", package)
    expected = manifest.attrib[android + attr]
    assert actual and actual.group(1) == expected, f'{attr}: built APK {actual.group(1) if actual else None!r} != source manifest {expected!r}'
print('PASS built APK version matches source manifest')
