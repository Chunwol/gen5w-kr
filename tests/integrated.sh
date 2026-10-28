#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); mkdir -p "$W/usb/packages" "$W/data/nemesis/apps" "$W/bin"
cp "$ROOT/tools/integrated/"*.sh "$W/usb/" 2>/dev/null || true
cp "$ROOT/tools/integrated/bin/zipstore-host" "$W/usb/zipstore"
cat > "$W/bin/nemesis" <<'PY'
#!/usr/bin/env python3
import sys,os,zipfile,shutil,subprocess
root=os.environ['IT_DATA']+'/nemesis/apps'; args=sys.argv[1:]
with open(os.environ['IT_DATA']+'/calls','a') as f: f.write(' '.join(args)+'\n')
if args[0]=='pkg-info':
 with zipfile.ZipFile(args[-1]) as z:
  print(z.read('NEMESIS.data').decode().split('id=')[1].splitlines()[0].join(['id=','']))
elif args[0]=='install':
 with zipfile.ZipFile(args[-1]) as z:
  id=z.read('NEMESIS.data').decode().split('id=')[1].splitlines()[0]
  path=root+'/'+id; shutil.rmtree(path,ignore_errors=True); os.makedirs(path); z.extractall(path)
  if os.environ.get('IT_FAIL')==id and '/packages/' in args[-1]: sys.exit(1)
elif args[0]=='uninstall': shutil.rmtree(root+'/'+args[1],ignore_errors=True)
elif args[0]=='root':
 print('RESULT error carplay-settings-missing' if os.environ.get('IT_REPAIR_FAIL') else 'RESULT applied')
 if os.environ.get('IT_REPAIR_FAIL'): sys.exit(3)
else: sys.exit(1)
PY
chmod +x "$W/bin/nemesis"
echo '#!/bin/sh' > "$W/bin/sync"
echo 'exit 0' >> "$W/bin/sync"
chmod +x "$W/bin/sync"
python3 - "$W/usb/packages" <<'PY'
import zipfile,sys,hashlib,pathlib
for m in ['wireless','audio','hotspot','bridge','core','notice']:
 with zipfile.ZipFile(sys.argv[1]+'/gen5w.kr.'+m+'.zip','w') as z:
  z.writestr('NEMESIS.data','[nemesis]\nid=gen5w.kr.'+m+'\nversion=new\npreinstall=scripts/pre.sh\npostinstall=scripts/post.sh\n')
  z.writestr('scripts/pre.sh','[ "$IT_PRE_FAIL" != "gen5w.kr.'+m+'" ] || exit 1\n[ "$IT_SKIP" != "gen5w.kr.'+m+'" ] || exit 77\nexit 0\n')
  z.writestr('scripts/post.sh','[ "$IT_POST_FAIL" != "gen5w.kr.'+m+'" ] || exit 1\nexit 0\n')
  if m=='hotspot': z.writestr('app/match.dex',b'own-test-helper')
 package=pathlib.Path(sys.argv[1])/('gen5w.kr.'+m+'.zip')
 stage=package.parent.parent/'checks'/('gen5w.kr.'+m);stage.mkdir(parents=True)
 sums=[]
 with zipfile.ZipFile(package) as z:
  z.extractall(stage)
  for name in z.namelist(): sums.append(hashlib.md5(z.read(name)).hexdigest()+'  '+name)
 (stage/'FILES.md5').write_text('\n'.join(sums)+'\n')
 (stage/'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest()+'\n')
PY
run() { (cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/sys" IT_NEM="$W/bin/nemesis" IT_SHELL=$(command -v mksh) IT_NO_REBOOT=1 PATH="$W/bin:$PATH" mksh "$1.sh" > "$W/out" 2>&1); }
check 'integrated install all modules' run install
check 'six registered module trees' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 6
check 'transaction committed' grep -qx committed "$W/data/nemesis/gen5w-kr-integrated/state"
check 'reboot suppression removed' test ! -e "$W/data/nemesis/gen5wkr.noreboot"
check 'feature result dashboard generated' grep -q '적용 완료' "$W/usb/GEN5W-REPORT/RESULT.html"
check 'issue attachment generated' test -f "$W/usb/GEN5W-REPORT/ISSUE.md"
export IT_SKIP=gen5w.kr.wireless
check 'unavailable wireless continues installing independent features' run update
unset IT_SKIP
check 'wired fallback retains bridge core and notice timer only' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 3
check 'wired fallback disables Bluetooth transport' test -f "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'wired fallback reports bridge route support' grep -q '유선 HUD 기반' "$W/usb/GEN5W-REPORT/RESULT.md"
check 'rollback wired fallback' run rollback
check 'rollback restores all six modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 6
check 'rollback restores prior wireless mode' test ! -e "$W/data/nemesis/gen5wkr.wireless-disabled"
export IT_SKIP=gen5w.kr.hotspot
check 'unsupported native AP profile falls back to wired features' run update
unset IT_SKIP
check 'native AP fallback restores wireless settings' test -f "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'native AP fallback retains three independent modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 3
check 'rollback native AP fallback' run rollback
check 'explicit wired-only mode' run wired-only
check 'explicit wired-only preserves HUD and notice timer' test -f "$W/data/nemesis/apps/gen5w.kr.notice/NEMESIS.data"
check 'normal update enables wireless again' run update
check 'wireless mode restored after normal update' test ! -e "$W/data/nemesis/gen5wkr.wireless-disabled"

mkdir -p "$W/data/nemesis/apps/gen5w.kr.consent"
printf '[nemesis]\nid=gen5w.kr.consent\n' > "$W/data/nemesis/apps/gen5w.kr.consent/NEMESIS.data"
check 'public update removes registered previous local notice package' run update
check 'standard has no consent registration' test ! -e "$W/data/nemesis/apps/gen5w.kr.consent"
check 'failed switch can restore registered previous package' run rollback
check 'prior consent registered after rollback' test -f "$W/data/nemesis/apps/gen5w.kr.consent/NEMESIS.data"
check 'successful public update retains only public modules' run update

mkdir -p "$W/data/nemesis/apps/gen5w.kr.consent/scripts"
printf '[nemesis]\nid=gen5w.kr.consent\npreuninstall=scripts/preun.sh\n' > "$W/data/nemesis/apps/gen5w.kr.consent/NEMESIS.data"
echo 'exit 1' > "$W/data/nemesis/apps/gen5w.kr.consent/scripts/preun.sh"
check 'consent skip removal failure refuses transaction' eval '! run update'
check 'consent skip removal failure reported' grep -q 'FAILED restoring previous notice-disabling package gen5w.kr.consent' "$W/out"
rm -rf "$W/data/nemesis/apps/gen5w.kr.consent"
check 'rollback after consent removal failure' run rollback
echo usb > "$W/usb/GEN5W-BACKEND"
check 'unavailable USB backend is refused before transaction mutation' eval '! run update'
check 'backend refusal preserves installed modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 6
rm "$W/usb/GEN5W-BACKEND"
check 'isolated hotspot repair' run repair-hotspot
check 'hotspot repair leaves other modules registered' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 6
export IT_REPAIR_FAIL=1
check 'missing CarPlay settings reported' eval '! run repair-hotspot'
unset IT_REPAIR_FAIL
check 'repair failure attachment gives reason' grep -q 'CarPlay settings unavailable' "$W/usb/GEN5W-REPORT/ISSUE.md"
export IT_SKIP=gen5w.kr.audio
check 'unsupported audio continues with supported modules' run update
unset IT_SKIP
check 'supported modules commit despite unsupported audio' grep -qx committed "$W/data/nemesis/gen5w-kr-integrated/state"
check 'unsupported audio is explicit in dashboard' grep -q '이번 설치에서 제외' "$W/usb/GEN5W-REPORT/RESULT.html"
mkdir -p "$W/data/nemesis/apps/wireless.carplay.aa"
check 'unfinished registration can pass normal original gates' run update
check 'unfinished prior tree stays untouched' test -d "$W/data/nemesis/apps/wireless.carplay.aa"
rmdir "$W/data/nemesis/apps/wireless.carplay.aa"
# Update must snapshot old package trees and restore them on a failed new module.
echo original > "$W/data/nemesis/apps/gen5w.kr.core/old.txt"
export IT_FAIL=gen5w.kr.audio
check 'update failure reported' eval '! run update'
unset IT_FAIL
check 'prior core retained after failure' grep -qx original "$W/data/nemesis/apps/gen5w.kr.core/old.txt"
check 'failed update shown as restored' grep -q '실패 후 이전 상태로 원복' "$W/usb/GEN5W-REPORT/RESULT.md"
check 'explicit rollback' run rollback
export IT_PRE_FAIL=gen5w.kr.audio
check 'explicit preinstall refusal reported' eval '! run update'
unset IT_PRE_FAIL
check 'preinstall refusal preserves prior modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 6
# Failure happens only in incoming payload; old snapshot hooks remain valid.
cp "$W/usb/checks/gen5w.kr.audio/scripts/post.sh" "$W/post.saved"
echo 'exit 1' > "$W/usb/checks/gen5w.kr.audio/scripts/post.sh"
python3 - "$W/usb/checks/gen5w.kr.audio" <<'PYFIX'
import sys,pathlib,hashlib,zipfile
p=pathlib.Path(sys.argv[1]); f=p/'FILES.md5'
f.write_text('\n'.join(hashlib.md5((p/line.split('  ',1)[1]).read_bytes()).hexdigest()+'  '+line.split('  ',1)[1] for line in f.read_text().splitlines())+'\n')
package=p.parent.parent/'packages'/(p.name+'.zip')
with zipfile.ZipFile(package,'w') as z:
 for line in f.read_text().splitlines():
  name=line.split('  ',1)[1];z.writestr(name,(p/name).read_bytes())
(p/'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest()+'\n')
PYFIX
check 'explicit postinstall failure reported' eval '! run update'
check 'postinstall failure recovers all previous modules' grep -qx rolled-back "$W/data/nemesis/gen5w-kr-integrated/state"
cp "$W/post.saved" "$W/usb/checks/gen5w.kr.audio/scripts/post.sh"
# Restore original checksum too.
md5sum "$W/post.saved" | cut -d' ' -f1 > "$W/post.hash"
python3 - "$W/usb/checks/gen5w.kr.audio" <<'PYFIX'
import sys,pathlib,hashlib,zipfile
p=pathlib.Path(sys.argv[1]); f=p/'FILES.md5'
f.write_text('\n'.join(hashlib.md5((p/line.split('  ',1)[1]).read_bytes()).hexdigest()+'  '+line.split('  ',1)[1] for line in f.read_text().splitlines())+'\n')
package=p.parent.parent/'packages'/(p.name+'.zip')
with zipfile.ZipFile(package,'w') as z:
 for line in f.read_text().splitlines():
  name=line.split('  ',1)[1];z.writestr(name,(p/name).read_bytes())
(p/'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest()+'\n')
PYFIX
export IT_SKIP=gen5w.kr.audio
touch "$W/usb/GEN5W-ALLOW-SKIPS"
check 'opt-in unsupported module skips' run update
unset IT_SKIP
rm "$W/usb/GEN5W-ALLOW-SKIPS"
check 'skip preserves previous installed audio' test -f "$W/data/nemesis/apps/gen5w.kr.audio/NEMESIS.data"
echo applying > "$W/data/nemesis/gen5w-kr-integrated/state"
touch "$W/data/nemesis/gen5wkr.noreboot"
check 'power interruption recovers before retry' run update
echo removing > "$W/data/nemesis/gen5w-kr-integrated/state"
touch "$W/data/nemesis/gen5wkr.noreboot"
check 'interrupted removal recovers before retry' run update
# Migration uses only package metadata and its declared hooks.
mkdir -p "$W/data/nemesis/apps/wireless.carplay.aa"
printf '[nemesis]\nid=wireless.carplay.aa\npreuninstall=restore.sh\n' > "$W/data/nemesis/apps/wireless.carplay.aa/NEMESIS.data"
echo 'echo restored > "$IT_DATA/legacy-restored"' > "$W/data/nemesis/apps/wireless.carplay.aa/restore.sh"
check 'legacy metadata migration' run update
check 'legacy declared restore hook called' test -f "$W/data/legacy-restored"
check 'legacy registration removed' test ! -d "$W/data/nemesis/apps/wireless.carplay.aa"
check 'legacy rollback restored package' run rollback
check 'legacy prior registration restored' test -f "$W/data/nemesis/apps/wireless.carplay.aa/NEMESIS.data"
check 'remove all modules' run remove
check 'no module trees after remove' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 0
# A reset removes registrations; the bundle's declared recovery hook restores owned system state.
mkdir -p "$W/sys/etc/gen5w-kr-backup/wireless"
echo 'preuninstall=scripts/preun.sh' >> "$W/usb/checks/gen5w.kr.wireless/NEMESIS.data"
echo 'rmdir "$IT_SYSTEM/etc/gen5w-kr-backup/wireless"' > "$W/usb/checks/gen5w.kr.wireless/scripts/preun.sh"
python3 - "$W/usb/checks/gen5w.kr.wireless" <<'PYRESET'
import pathlib,sys,hashlib,zipfile
p=pathlib.Path(sys.argv[1]); names=['NEMESIS.data','scripts/pre.sh','scripts/post.sh','scripts/preun.sh']
(p/'FILES.md5').write_text('\n'.join(hashlib.md5((p/n).read_bytes()).hexdigest()+'  '+n for n in names)+'\n')
package=p.parent.parent/'packages'/(p.name+'.zip')
with zipfile.ZipFile(package,'w') as z:
 for n in names:z.writestr(n,(p/n).read_bytes())
(p/'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest()+'\n')
PYRESET
check 'removal after data reset uses declared durable hook' run remove
check 'durable state restored after registration loss' test ! -d "$W/sys/etc/gen5w-kr-backup/wireless"
# A corrupt new package is refused before touching installed state.
echo corrupt >> "$W/usb/packages/gen5w.kr.wireless.zip"
check 'rejects bundle package corruption' eval '! run install'
echo DO_NOT_COLLECT_PRIVATE_LOG > "$W/data/nemesis/gen5w.kr.hotspot.log"
check 'status creates current support document' run status
check 'support document excludes raw logs' eval '! grep -q DO_NOT_COLLECT_PRIVATE_LOG "$W/usb/GEN5W-REPORT/ISSUE.md"'
mkdir -p "$W/data/data/kr.gen5w.core/files"
echo APIS_PRESENT_SOURCE_UNOBSERVED > "$W/data/data/kr.gen5w.core/files/hud-native-warning.status"
check 'status includes honest native warning capability' run status
check 'native warning is never reported as proven live output' grep -q '순정 경고 API 확인 · CarPlay 중 표시 미확인' "$W/usb/GEN5W-REPORT/RESULT.html"
echo DO_NOT_COLLECT_PRIVATE_WARNING > "$W/data/data/kr.gen5w.core/files/hud-native-warning.status"
check 'unrecognized private warning file is ignored' run status
check 'unrecognized warning content does not leave vehicle' eval '! grep -q DO_NOT_COLLECT_PRIVATE_WARNING "$W/usb/GEN5W-REPORT/ISSUE.md"'
echo recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
touch "$W/data/nemesis/gen5wkr.noreboot"
check 'isolated repair refuses unresolved system recovery' eval '! run repair-hotspot'
check 'repair refusal preserves recovery state' grep -qx recovery-required "$W/data/nemesis/gen5w-kr-integrated/state"
done_tests integrated
