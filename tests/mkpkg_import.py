import subprocess
import sys
import tempfile
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    package = root / 'package'
    package.mkdir()
    (package / 'NEMESIS.data').write_bytes(b'[package]\nid=test\n')
    output = root / 'package.zip'
    subprocess.run(
        [sys.executable, '-I', str(ROOT / 'tools/mkpkg.py'), str(package), str(output)],
        cwd=ROOT,
        check=True,
    )
    with zipfile.ZipFile(output) as archive:
        assert 'BUILD-REVISION' in archive.namelist()
print('PASS mkpkg isolated import and revision')
