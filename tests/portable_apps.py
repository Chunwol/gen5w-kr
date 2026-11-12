"""Build a real portable APK and inspect its manifest, payload and signature."""
from pathlib import Path
import importlib.util,subprocess,tempfile,zipfile,os,hashlib
ROOT=Path(__file__).resolve().parents[1]
def main():
 spec=importlib.util.spec_from_file_location('portable_apps',ROOT/'tools/portable/build_apps.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 sdk=Path(os.environ.get('ANDROID_HOME',str(Path.home()/'AppData/Local/Android/Sdk')))
 java=Path(os.environ.get('JAVA_HOME','C:/Program Files/Eclipse Adoptium/jdk-25.0.2.10-hotspot'))
 key=Path.home()/'gen5w-kr-private/probe.keystore'
 with tempfile.TemporaryDirectory(dir=ROOT/'.build',prefix='portable-apps-test-') as temp:
  old_digest=hashlib.sha256((ROOT/'packages/core/app/gen5w-core.apk').read_bytes()).digest()
  out=Path(temp)/'apps';m.build(out,sdk,java,key)
  with zipfile.ZipFile(out/'gen5w-core.apk') as new,zipfile.ZipFile(ROOT/'packages/core/app/gen5w-core.apk') as old:
   assert b'portableRemovalDone' in new.read('classes.dex') and b'portable_enabled' in new.read('classes.dex'),'stale core status behavior'
  assert hashlib.sha256((ROOT/'packages/core/app/gen5w-core.apk').read_bytes()).digest()==old_digest,'standard APK changed'
  with zipfile.ZipFile(out/'wireless-host.apk') as host:
   assert host.read('classes.dex')==(out/'bridge.dex').read_bytes(),'broker and host differ'
  assert b'HostReadyMarker' in (out/'bridge.dex').read_bytes() and b'ApAttemptGuard' in (out/'bridge.dex').read_bytes(),'stale portable host build'
  aapt=sdk/'build-tools/36.0.0'/('aapt.exe' if os.name=='nt' else 'aapt')
  manifest=subprocess.check_output([str(aapt),'dump','xmltree','gen5w-core.apk','AndroidManifest.xml'],cwd=out,text=True)
  receiver=manifest.split('E: receiver',1)[1].split('E: intent-filter',1)[0]
  assert 'StartReceiver' in receiver
  assert 'android:enabled' in receiver and '=(type 0x12)0x0' in receiver,'core can independently start at boot'
  try:m.build(out,sdk,java,key)
  except FileExistsError:pass
  else:raise AssertionError('overwrote existing output')
 print('PASS portable APK: independently disabled boot receiver, current authored core and host, signing and overwrite refusal')
if __name__=='__main__':main()
