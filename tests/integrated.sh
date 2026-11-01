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
for m in ['dongle','wireless','audio','hotspot','bridge','core','notice']:
 with zipfile.ZipFile(sys.argv[1]+'/gen5w.kr.'+m+'.zip','w') as z:
  z.writestr('NEMESIS.data','[nemesis]\nid=gen5w.kr.'+m+'\nversion=new\npreinstall=scripts/pre.sh\npostinstall=scripts/post.sh\n')
  z.writestr('scripts/pre.sh','[ "$IT_PRE_FAIL" != "gen5w.kr.'+m+'" ] || exit 1\n[ "$IT_SKIP" != "gen5w.kr.'+m+'" ] || exit 77\nexit 0\n')
  z.writestr('scripts/post.sh','[ "$IT_POST_FAIL" != "gen5w.kr.'+m+'" ] || exit 1\nexit 0\n')
  if m=='hotspot':
   z.writestr('app/match.dex',b'own-test-helper')
   z.writestr('bin/hotspot-patch-v039','#!/bin/sh\ncase "$1" in original) grep -q "^stock" "$2";; patched) grep -q "^patched" "$2";; *) exit 1;; esac\n')
  if m=='bridge':
   for t in ('iap2','dipo','gpm'): z.writestr('bin/'+t+'-patch-v039','#!/bin/sh\ncase "$1" in original) grep -q "^stock" "$2";; patched) grep -q "^patched" "$2";; *) exit 1;; esac\n')
  if m=='notice': z.writestr('bin/notice-patch-v039','#!/bin/sh\ncase "$1" in original) grep -q "^stock" "$2";; *) exit 1;; esac\n')
 package=pathlib.Path(sys.argv[1])/('gen5w.kr.'+m+'.zip')
 stage=package.parent.parent/'checks'/('gen5w.kr.'+m);stage.mkdir(parents=True)
 sums=[]
 with zipfile.ZipFile(package) as z:
  z.extractall(stage)
  for name in z.namelist(): sums.append(hashlib.md5(z.read(name)).hexdigest()+'  '+name)
 (stage/'FILES.md5').write_text('\n'.join(sums)+'\n')
 (stage/'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest()+'\n')
PY
mkdir -p "$W/sys/framework"; echo stock > "$W/sys/framework/services.odex"
run() { (cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/sys" IT_NEM="$W/bin/nemesis" IT_SHELL=$(command -v mksh) IT_NO_REBOOT=1 CK_TEST_PATH="$W/bin:$PATH" PATH="$W/bin:$PATH" mksh "$1.sh" > "$W/out" 2>&1); }
check 'integrated install all modules' run install
check 'five registered module trees (no services.odex hotspot module)' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
check 'standard never installs the services.odex hotspot patch' test ! -e "$W/data/nemesis/apps/gen5w.kr.hotspot"
check 'standard leaves services.odex stock' grep -qx stock "$W/sys/framework/services.odex"
check 'standard uses match mode' grep -qx match "$W/data/nemesis/gen5wkr.ap-match"
check 'standard keeps the stock hotspot feature' grep -qx feature "$W/data/nemesis/gen5wkr.ap-hotspot-feature"
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
check 'rollback restores all five modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
check 'rollback restores prior wireless mode' test ! -e "$W/data/nemesis/gen5wkr.wireless-disabled"
# An earlier services.odex hotspot module is removed through its own uninstall.
mkdir -p "$W/data/nemesis/apps/gen5w.kr.hotspot"
printf '[nemesis]
id=gen5w.kr.hotspot
' > "$W/data/nemesis/apps/gen5w.kr.hotspot/NEMESIS.data"
echo hotspot_old > "$W/data/nemesis/apps/gen5w.kr.hotspot/old.txt"
check 'update removes an earlier services.odex hotspot module' run update
check 'earlier hotspot module unregistered' test ! -e "$W/data/nemesis/apps/gen5w.kr.hotspot"
check 'hotspot restore is reported' grep -q 'RESTORED gen5w.kr.hotspot: services.odex back to stock' "$W/data/nemesis/gen5w-kr-integrated/report"
check 'wireless stays enabled after the hotspot module is removed' test ! -e "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'rollback brings the earlier hotspot module back' eval 'run rollback && grep -qx hotspot_old "$W/data/nemesis/apps/gen5w.kr.hotspot/old.txt"'
check 'rollback restores the earlier markers' eval 'grep -qx match "$W/data/nemesis/gen5wkr.ap-match" && grep -qx feature "$W/data/nemesis/gen5wkr.ap-hotspot-feature"'
check 'update after rollback removes it again' eval 'run update && test ! -e "$W/data/nemesis/apps/gen5w.kr.hotspot"'
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
echo 'exit 0' > "$W/data/nemesis/apps/gen5w.kr.consent/scripts/preun.sh"
check 'rollback after consent removal failure' run rollback
echo 'exit 0' > "$W/data/nemesis/apps/gen5w.kr.consent/scripts/preun.sh"
check 'clean update after fixing consent preuninstall removes consent' run update
check 'five modules remain after consent cleanup' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
echo usb > "$W/usb/GEN5W-BACKEND"
check 'unavailable USB backend is refused before transaction mutation' eval '! run update'
check 'backend refusal preserves installed modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
rm "$W/usb/GEN5W-BACKEND"
check 'isolated hotspot repair' run repair-hotspot
check 'hotspot repair leaves other modules registered' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
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
check 'standard never registers the hotspot module after rollback and update' eval 'run update && test ! -e "$W/data/nemesis/apps/gen5w.kr.hotspot"'
echo dongle > "$W/usb/GEN5W-VARIANT"
check 'dongle variant installs seven modules' run update
check 'dongle variant registers dongle module' test -f "$W/data/nemesis/apps/gen5w.kr.dongle/NEMESIS.data"
check 'dongle variant reports dongle feature' grep -q 'USB Wi-Fi 동글 드라이버·HAL' "$W/usb/GEN5W-REPORT/RESULT.md"
echo dongle_old > "$W/data/nemesis/apps/gen5w.kr.dongle/old.txt"
export IT_FAIL=gen5w.kr.core
check 'dongle variant update failure rolls back dongle' eval '! run update'
unset IT_FAIL
check 'prior dongle retained after rollback' grep -qx dongle_old "$W/data/nemesis/apps/gen5w.kr.dongle/old.txt"
rm -f "$W/usb/GEN5W-VARIANT"
check 'return to standard variant removes dongle and keeps five modules' run update
check 'standard variant removes dongle registration' test ! -e "$W/data/nemesis/apps/gen5w.kr.dongle"
check 'standard variant retains five modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
check 'rollback after dongle to standard transition restores dongle' run rollback
check 'dongle registration restored after rollback' test -f "$W/data/nemesis/apps/gen5w.kr.dongle/NEMESIS.data"
check 'return to standard variant again' run update
# Safe edition: wired HUD only. Wi-Fi/hotspot/audio and the SystemUI notice timer
# are restored to stock, and the boot guard recovers after 2 failed boots.
mkdir -p "$W/sys/priv-app" "$W/sys/app"; echo stock > "$W/sys/priv-app/SystemUI.odex"
for f in Iap2ServerApp HKMC_DiPO HKMC_GPM; do echo stock > "$W/sys/app/$f.odex"; done
echo safe > "$W/usb/GEN5W-VARIANT"
rm -rf "$W/usb/GEN5W-REPORT"
check 'safe edition refuses without a pre-install check report' eval '! run update'
check 'missing report reason' grep -q 'no pre-install check report' "$W/data/nemesis/gen5w-kr-integrated/report"
check 'refusal without report changes no modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
check 'pre-install check passes on stock' run check
check 'check report says install' grep -qx 'verdict=install' "$W/usb/GEN5W-REPORT/CHECK.txt"
cp "$W/usb/GEN5W-REPORT/CHECK.txt" "$W/check.saved"
echo other-build > "$W/usb/BUILD-REVISION"
check 'report from a different build is refused' eval '! run update'
rm -f "$W/usb/BUILD-REVISION"
echo patched > "$W/sys/app/HKMC_GPM.odex"
check 'changed file after the check is refused' eval '! run update'
check 'mismatch is reported' grep -q 'MISMATCH' "$W/data/nemesis/gen5w-kr-integrated/report"
echo stock > "$W/sys/app/HKMC_GPM.odex"
sed -i 's/^verdict=install$/verdict=block/' "$W/usb/GEN5W-REPORT/CHECK.txt"
check 'report that did not say install is refused' eval '! run update'
cp "$W/check.saved" "$W/usb/GEN5W-REPORT/CHECK.txt"
check 'unchanged unit matching the report counts as verified' eval 'run update || true; grep -q "CHECK verified" "$W/data/nemesis/gen5w-kr-integrated/report"'
check 'rollback after verified safe install' run rollback
run check
check 'safe edition installs' run update
check 'safe edition keeps only bridge and core' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 2
check 'safe edition registers bridge' test -f "$W/data/nemesis/apps/gen5w.kr.bridge/NEMESIS.data"
check 'safe edition registers core' test -f "$W/data/nemesis/apps/gen5w.kr.core/NEMESIS.data"
for m in wireless audio hotspot notice; do
    check "safe edition removes $m" test ! -e "$W/data/nemesis/apps/gen5w.kr.$m"
done
check 'safe edition marks wireless disabled' test -f "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'safe edition plans wired-only without the wireless preflight' eval 'grep "^PLAN " "$W/data/nemesis/gen5w-kr-integrated/report" | tail -n 1 | grep -q "PLAN wired-only"'
check 'safe edition arms boot guard at 2 failures' grep -qx 2 "$W/data/nemesis/gen5wkr.bootguard/max"
check 'safe edition commits' grep -qx committed "$W/data/nemesis/gen5w-kr-integrated/state"
check 'safe edition retains the SystemUI verifier' test -x "$W/data/nemesis/gen5wkr.bootguard/verifiers/notice-v039"
check 'rollback from safe edition restores five modules' run rollback
check 'five modules back after safe rollback' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
echo patched > "$W/sys/priv-app/SystemUI.odex"
check 'check blocks a SystemUI that is not recognised stock' eval '! run check'
check 'check report says block' grep -qx 'verdict=block' "$W/usb/GEN5W-REPORT/CHECK.txt"
check 'safe edition refuses when SystemUI is not recognised stock' eval '! run update'
check 'refused safe edition keeps five modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
check 'refused safe edition reports the reason' grep -q 'REFUSED pre-install check guard' "$W/data/nemesis/gen5w-kr-integrated/report"
echo stock > "$W/sys/priv-app/SystemUI.odex"
# Safe-wireless edition: wireless CarPlay/AA kept, SystemUI and services.odex stock, guard at 2.
echo safe-wireless > "$W/usb/GEN5W-VARIANT"
mkdir -p "$W/data/nemesis/apps/gen5w.kr.hotspot"
printf '[nemesis]
id=gen5w.kr.hotspot
' > "$W/data/nemesis/apps/gen5w.kr.hotspot/NEMESIS.data"
run check
check 'safe-wireless refuses while a services.odex hotspot package is present' eval '! run update'
check 'hotspot refusal reason' grep -q 'services.odex hotspot patch is present' "$W/data/nemesis/gen5w-kr-integrated/report"
check 'hotspot refusal keeps six modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 6
check 'clean unit for safe-wireless' run remove
run check
: > "$W/usb/GEN5W-WIFI-CLIENT"
check 'safe-wireless refuses the Wi-Fi client opt-in' eval '! run update'
check 'safe-wireless refusal reports the reason' grep -q 'does not enable the Wi-Fi client' "$W/data/nemesis/gen5w-kr-integrated/report"
check 'safe-wireless refusal installs nothing' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 0
rm -f "$W/usb/GEN5W-WIFI-CLIENT"
check 'safe-wireless edition installs' run update
check 'safe-wireless keeps four modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 4
for m in wireless audio bridge core; do
    check "safe-wireless registers $m" test -f "$W/data/nemesis/apps/gen5w.kr.$m/NEMESIS.data"
done
check 'safe-wireless never installs the services.odex hotspot patch' test ! -e "$W/data/nemesis/apps/gen5w.kr.hotspot"
check 'safe-wireless reports the hotspot skip' grep -q 'SKIPPED gen5w.kr.hotspot: safe-wireless keeps services.odex stock' "$W/data/nemesis/gen5w-kr-integrated/report"
check 'safe-wireless leaves services.odex stock' grep -qx stock "$W/sys/framework/services.odex"
check 'safe-wireless writes the match marker' grep -qx match "$W/data/nemesis/gen5wkr.ap-match"
check 'safe-wireless leaves out the hotspot feature' test ! -e "$W/data/nemesis/gen5wkr.ap-hotspot-feature"
check 'safe-wireless removes the notice timer' test ! -e "$W/data/nemesis/apps/gen5w.kr.notice"
check 'safe-wireless keeps wireless enabled' test ! -e "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'safe-wireless plans wireless' eval 'grep "^PLAN " "$W/data/nemesis/gen5w-kr-integrated/report" | tail -n 1 | grep -q "PLAN wireless: supported"'
check 'safe-wireless arms boot guard at 2 failures' grep -qx 2 "$W/data/nemesis/gen5wkr.bootguard/max"
check 'safe-wireless retains the services.odex verifier' test -x "$W/data/nemesis/gen5wkr.bootguard/verifiers/hotspot-v039"
check 'safe-wireless commits' grep -qx committed "$W/data/nemesis/gen5w-kr-integrated/state"
check 'rollback from safe-wireless returns to the clean unit' run rollback
check 'no modules after safe-wireless rollback' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 0
echo patched > "$W/sys/priv-app/SystemUI.odex"
run check
check 'safe-wireless refuses when SystemUI is not recognised stock' eval '! run update'
check 'refused safe-wireless installs nothing' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 0
echo stock > "$W/sys/priv-app/SystemUI.odex"
echo junk > "$W/sys/framework/services.odex"
check 'check blocks an unrecognised services.odex' eval '! run check'
check 'safe-wireless refuses an unrecognised services.odex' eval '! run update'
echo stock > "$W/sys/framework/services.odex"
check 'remove clears the match marker' eval 'run check; run update; run remove; test ! -e "$W/data/nemesis/gen5wkr.ap-match"'
rm -f "$W/usb/GEN5W-VARIANT"
check 'standard boot guard limit stays 3' eval 'rm -f "$W/usb/GEN5W-VARIANT"; run update && grep -qx 3 "$W/data/nemesis/gen5wkr.bootguard/max"'
export IT_PRE_FAIL=gen5w.kr.audio
check 'explicit preinstall refusal reported' eval '! run update'
unset IT_PRE_FAIL
check 'preinstall refusal preserves prior modules' test "$(find "$W/data/nemesis/apps" -name NEMESIS.data | wc -l)" = 5
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
echo "PRIVATE_ROUTE_NAME" > "$W/data/data/kr.gen5w.core/files/navi-debug.log"
echo APIS_PRESENT_SOURCE_UNOBSERVED > "$W/data/data/kr.gen5w.core/files/hud-native-warning.status"
check 'status includes honest native warning capability' run status
check 'navi-debug.log is never copied to public USB report' test ! -e "$W/usb/GEN5W-REPORT/navi-debug.log"
check 'native warning is never reported as proven live output' grep -q '순정 경고 API 확인 · CarPlay 중 표시 미확인' "$W/usb/GEN5W-REPORT/RESULT.html"
echo DO_NOT_COLLECT_PRIVATE_WARNING > "$W/data/data/kr.gen5w.core/files/hud-native-warning.status"
check 'unrecognized private warning file is ignored' run status
check 'unrecognized warning content does not leave vehicle' eval '! grep -q DO_NOT_COLLECT_PRIVATE_WARNING "$W/usb/GEN5W-REPORT/ISSUE.md"'
echo recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
touch "$W/data/nemesis/gen5wkr.noreboot"
check 'isolated repair refuses unresolved system recovery' eval '! run repair-hotspot'
check 'repair refusal preserves recovery state' grep -qx recovery-required "$W/data/nemesis/gen5w-kr-integrated/state"
done_tests integrated
