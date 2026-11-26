"""Build the authored core variant whose startup belongs solely to boot.sh."""
from pathlib import Path
import argparse
import hashlib
import os
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ANDROID = '{http://schemas.android.com/apk/res/android}'

SOURCE_ROOTS = (
    'app/src', 'app/stubs', 'shared/src', 'probe/stubs',
    'probe/src/kr/gen5w/probe/Item.java', 'probe/src/kr/gen5w/probe/Convert.java',
    'packages/wireless-bridge/src', 'packages/wireless-bridge/stubs',
    'app/AndroidManifest.xml', 'packages/wireless-bridge/host/AndroidManifest.xml',
    'tools/portable/build_apps.py',
)


def source_digest(root=ROOT):
    """Hash authored Java, manifests, and recipe; paths detect added/removed files."""
    root = Path(root)
    digest = hashlib.sha256()
    for relative in SOURCE_ROOTS:
        base = root / relative
        if base.is_file():
            files = [base]
        elif base.is_dir():
            files = sorted(base.rglob('*.java'))
        else:
            raise FileNotFoundError(base)
        for path in files:
            digest.update(path.relative_to(root).as_posix().encode('utf-8') + bytes(1))
            digest.update(path.read_bytes().replace(bytes([13,10]), bytes([10])) + bytes(1))
    return digest.hexdigest()


def build(output: Path, sdk: Path, java_home: Path, keystore: Path) -> None:
    output, sdk, java_home, keystore = map(Path, (output, sdk, java_home, keystore))
    if output.exists() or output.is_symlink():
        raise FileExistsError(output)
    resolved = output.absolute().resolve()
    if resolved == ROOT or (ROOT in resolved.parents and ROOT / '.build' not in resolved.parents):
        raise ValueError('output must not replace source or release files')
    suffix = '.exe' if os.name == 'nt' else ''
    tools = sdk / 'build-tools/36.0.0'
    java = java_home / ('bin/java' + suffix)
    javac = java_home / ('bin/javac' + suffix)
    d8 = tools / 'lib/d8.jar'
    aapt = tools / ('aapt2' + suffix)
    align = tools / ('zipalign' + suffix)
    signer = tools / 'lib/apksigner.jar'
    android_jar = sdk / 'platforms/android-36/android.jar'
    for path in (java, javac, d8, aapt, align, signer, android_jar, keystore, Path(str(keystore)+'.pass')):
        if not path.is_file():
            raise FileNotFoundError(path)
    for ancestor in (output.absolute(), *output.absolute().parents):
        if ancestor.is_symlink():
            raise ValueError('symlink output ancestor')
    built_source_digest = source_digest()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='portable-apk-', dir=output.parent) as temp:
        stage = Path(temp)
        manifest = ET.parse(ROOT / 'app/AndroidManifest.xml')
        receiver = next(element for element in manifest.findall('./application/receiver')
                        if element.get(ANDROID+'name') == '.StartReceiver')
        receiver.set(ANDROID+'enabled', 'false')
        ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
        manifest.write(stage / 'AndroidManifest.xml', encoding='utf-8', xml_declaration=True)
        subprocess.run([str(aapt), 'link', '--manifest', str(stage/'AndroidManifest.xml'), '-I', str(android_jar),
                        '--min-sdk-version', '18', '--target-sdk-version', '19', '-o', str(stage/'unsigned.apk')], check=True)
        # Compile the current authored core privately; its portable status flag
        # selects accurate restoration text while legacy installations keep theirs.
        stubs = stage/'core-stubs'; stubs.mkdir()
        core = stage/'core-classes'; core.mkdir()
        subprocess.run([str(javac), '--release', '8', '-encoding', 'UTF-8', '-Xlint:-options', '-cp', str(android_jar),
                        '-d', str(stubs), *[str(p) for root in (ROOT/'app/stubs', ROOT/'probe/stubs') for p in root.rglob('*.java')]], check=True)
        core_sources = [str(p) for root in (ROOT/'app/src', ROOT/'shared/src') for p in root.rglob('*.java')]
        core_sources += [str(ROOT/'probe/src/kr/gen5w/probe'/(name+'.java')) for name in ('Item', 'Convert')]
        subprocess.run([str(javac), '--release', '8', '-encoding', 'UTF-8', '-Xlint:-options', '-cp', str(android_jar)+os.pathsep+str(stubs),
                        '-d', str(core), *core_sources], check=True)
        core_jar = stage/'core-classes.jar'
        with zipfile.ZipFile(core_jar, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted((core/'kr').rglob('*.class')): archive.write(path, path.relative_to(core).as_posix())
        core_dex = stage/'core-dex'; core_dex.mkdir()
        subprocess.run([str(java), '-cp', str(d8), 'com.android.tools.r8.D8', '--min-api', '18', '--release',
                        '--lib', str(android_jar), '--classpath', str(stubs), '--output', str(core_dex), str(core_jar)], check=True)
        with zipfile.ZipFile(stage/'unsigned.apk', 'a', zipfile.ZIP_DEFLATED) as apk:
            apk.writestr('classes.dex', (core_dex/'classes.dex').read_bytes())
        subprocess.run([str(align), '-f', '-p', '4', str(stage/'unsigned.apk'), str(stage/'aligned.apk')], check=True)
        subprocess.run([str(java), '-jar', str(signer), 'sign', '--ks', str(keystore), '--ks-pass', 'file:'+str(keystore)+'.pass',
                        '--ks-key-alias', 'probe', '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'false',
                        '--v3-signing-enabled', 'false', '--min-sdk-version', '18', '--out', str(stage/'gen5w-core.apk'), str(stage/'aligned.apk')], check=True)
        subprocess.run([str(java), '-jar', str(signer), 'verify', '--min-sdk-version', '18', str(stage/'gen5w-core.apk')], check=True)
        # Build current authored radio/host code privately; do not overwrite the
        # standard package APK/DEX. Compile-only OEM declarations stay excluded.
        classes = stage / 'bridge-classes'; classes.mkdir()
        package = ROOT / 'packages/wireless-bridge'
        roots = [package/'src', ROOT/'probe/stubs', package/'stubs', ROOT/'shared/src']
        entries = ['wireless/BridgeHostService', 'wireless/WirelessBridge', 'wireless/V039RelayCoordinator',
                   'wireless/V039BtRelayAdapter', 'wireless/PhoneProjectionAccess', 'wireless/StockProjectionSession',
                   'wireless/BluetoothCandidateScan', 'wireless/ProjectionWifiAccess', 'wireless/DriveLog']
        subprocess.run([str(javac), '--release', '8', '-encoding', 'UTF-8', '-Xlint:-options', '-cp', str(android_jar),
                        '-sourcepath', os.pathsep.join(map(str, roots)), '-d', str(classes),
                        *[str(package/'src/kr/gen5w'/(name+'.java')) for name in entries]], check=True)
        compiled = stage/'bridge-classes.jar'
        with zipfile.ZipFile(compiled, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted((classes/'kr').rglob('*.class')):
                archive.write(path, path.relative_to(classes).as_posix())
        dex = stage/'bridge-dex'; dex.mkdir()
        subprocess.run([str(java), '-cp', str(d8), 'com.android.tools.r8.D8', '--min-api', '18', '--release',
                        '--lib', str(android_jar), '--classpath', str(classes), '--output', str(dex), str(compiled)], check=True)
        subprocess.run([str(aapt), 'link', '--manifest', str(package/'host/AndroidManifest.xml'), '-I', str(android_jar),
                        '--min-sdk-version', '18', '--target-sdk-version', '19', '-o', str(stage/'host-unsigned.apk')], check=True)
        with zipfile.ZipFile(stage/'host-unsigned.apk', 'a', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('classes.dex', (dex/'classes.dex').read_bytes())
        subprocess.run([str(align), '-f', '-p', '4', str(stage/'host-unsigned.apk'), str(stage/'host-aligned.apk')], check=True)
        subprocess.run([str(java), '-jar', str(signer), 'sign', '--ks', str(keystore), '--ks-pass', 'file:'+str(keystore)+'.pass',
                        '--ks-key-alias', 'probe', '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'false',
                        '--v3-signing-enabled', 'false', '--min-sdk-version', '18', '--out', str(stage/'wireless-host.apk'), str(stage/'host-aligned.apk')], check=True)
        subprocess.run([str(java), '-jar', str(signer), 'verify', '--min-sdk-version', '18', str(stage/'wireless-host.apk')], check=True)
        if source_digest() != built_source_digest:
            raise ValueError('app sources changed during build; rebuild with tools/portable/build_apps.py')
        output.mkdir(mode=0o755)
        for name in ('gen5w-core.apk', 'wireless-host.apk'):
            (stage/name).rename(output/name)
        (dex/'classes.dex').rename(output/'bridge.dex')
        (output/'source.sha256').write_text(built_source_digest + '\n', encoding='ascii')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, default=Path.home()/'AppData/Local/Android/Sdk')
    parser.add_argument('--java-home', type=Path, default=os.environ.get('JAVA_HOME'), required=not bool(os.environ.get('JAVA_HOME')))
    parser.add_argument('--keystore', type=Path, default=Path.home()/'gen5w-kr-private/probe.keystore')
    args = parser.parse_args()
    build(args.output, args.sdk, args.java_home, args.keystore)
