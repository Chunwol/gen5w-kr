"""Build/run the actual Android UI on an explicitly named emulator, never a car.

Generated APKs/screens stay in .build. An optional private OEM resource-only APK
allows pixel comparisons without copying any manufacturer artwork into our app.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--stock-dir', type=Path)
    parser.add_argument('--scenario', default='normal', choices=['normal', 'locked', 'unknown', 'stale',
        'recovery', 'recovery-unavailable', 'recovery-working', 'recovery-failed', 'recovery-restored'])
    parser.add_argument('--revision', help='Capture a committed UI for before/after comparison')
    parser.add_argument('--capture-only', action='store_true', help='Do not claim assertions passed for a historical UI')
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        raise SystemExit('UI tests only run on an explicitly named emulator')
    sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'AppData/Local/Android/Sdk'))
    bt = sdk / 'build-tools/36.0.0'
    jar = sdk / 'platforms/android-36/android.jar'
    key = Path.home() / 'gen5w-kr-private/probe.keystore'
    workroot = ROOT / '.build'
    workroot.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='ui-preview-', dir=workroot))

    def run(command, **kwargs):
        return subprocess.run([str(x) for x in command], check=True, **kwargs)

    def tool(name):
        return next(bt / (name + ext) for ext in ('.exe', '.bat', '') if (bt / (name + ext)).is_file())

    def sign(apk, name):
        aligned, signed = work / (name + '-aligned.apk'), work / (name + '.apk')
        run([tool('zipalign'), '-f', '-p', '4', apk, aligned])
        run([tool('apksigner'), 'sign', '--ks', key, '--ks-pass', 'file:' + str(key) + '.pass',
             '--ks-key-alias', 'probe', '--out', signed, aligned])
        return signed

    adb = sdk / 'platform-tools' / ('adb.exe' if os.name == 'nt' else 'adb')
    def device(*words, **kwargs):
        return run([adb, '-s', args.serial, *words], **kwargs)

    if args.stock_dir:
        # Resource table and PNGs only, installed separately and never in a public artifact.
        manifest = work / 'resources.xml'
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.android.generalsettings"><uses-sdk android:minSdkVersion="21" android:targetSdkVersion="28"/><application android:hasCode="false" android:label="Private OEM reference"/></manifest>')
        pack = work / 'resources-unsigned.apk'
        run([tool('aapt2'), 'link', '--manifest', manifest, '-I', jar, '-o', pack])
        with zipfile.ZipFile(pack) as compiled:
            compiled_manifest = compiled.read('AndroidManifest.xml')
        with zipfile.ZipFile(args.stock_dir / 'GeneralSettings.apk') as stock, zipfile.ZipFile(pack, 'w') as out:
            out.writestr('AndroidManifest.xml', compiled_manifest)
            for name in stock.namelist():
                if name == 'resources.arsc' or name.startswith('res/'):
                    out.writestr(name, stock.read(name))
        device('install', '--no-incremental', '-r', str(sign(pack, 'private-resources')))

    source = work / 'src'
    source.mkdir()
    if args.revision:
        names = run(['git', 'ls-tree', '-r', '--name-only', args.revision, '--', 'app/src/kr/gen5w/ui'], cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
        files = [ROOT / name for name in names if name.endswith('.java')]
    else:
        files = list((ROOT / 'app/src/kr/gen5w/ui').glob('*.java'))
    for file in files:
        text = (run(['git', 'show', args.revision + ':' + file.relative_to(ROOT).as_posix()], cwd=ROOT, capture_output=True, text=True, encoding='utf-8').stdout
                if args.revision else file.read_text(encoding='utf-8'))
        text = text.replace('"/data/nemesis/gen5wkr.ui"', '"/data/data/kr.gen5w.uipreview/files/fixture"')
        (source / file.name).write_text(text, encoding='utf-8')
    shutil.copyfile(ROOT / 'app/src/kr/gen5w/core/HudSwitch.java', source / 'HudSwitch.java')
    for name in ['CoreService.java', 'UiProbe.java']:
        shutil.copyfile(ROOT / 'tests/ui-preview' / name, source / name)
    classes, dex = work / 'classes', work / 'dex'
    classes.mkdir(); dex.mkdir()
    run(['javac', '-encoding', 'UTF-8', '--release', '8', '-cp', jar, '-d', classes, ROOT/'shared/src/kr/gen5w/diag/SafeDiagnostic.java', *source.glob('*.java')])
    run([tool('d8'), '--min-api', '21', '--lib', jar, '--output', dex, *classes.rglob('*.class')])
    unsigned = work / 'unsigned.apk'
    run([tool('aapt2'), 'link', '--manifest', ROOT / 'tests/ui-preview/AndroidManifest.xml', '-I', jar, '-o', unsigned])
    with zipfile.ZipFile(unsigned, 'a', zipfile.ZIP_DEFLATED) as out:
        out.write(dex / 'classes.dex', 'classes.dex')
    device('install', '--no-incremental', '-r', str(sign(unsigned, 'preview')))
    device('shell', 'pm', 'clear', 'kr.gen5w.uipreview')
    result = device('shell', 'am', 'instrument', '-w', '-r', '-e', 'scenario', args.scenario,
                    '-e', 'native', 'yes' if args.stock_dir else 'no',
                    '-e', 'capture-only', 'yes' if args.capture_only else 'no',
                    'kr.gen5w.uipreview/kr.gen5w.ui.UiProbe', capture_output=True, text=True, encoding='utf-8')
    print(result.stdout)
    (work / 'screens').mkdir()
    device('pull', '/sdcard/Android/data/kr.gen5w.uipreview/files/.', 'screens', cwd=work)
    print('Screens and build: ' + str(work))
    if 'INSTRUMENTATION_CODE: -1' not in result.stdout:
        raise SystemExit('UI assertions failed')


if __name__ == '__main__':
    main()
