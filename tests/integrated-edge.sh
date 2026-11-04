#!/bin/bash
# Integrated installer edge cases: the boot-loop guard must have its runner,
# removal must survive an unrecognised stock file, a failed start must not leave
# reboot suppression behind, and rollback must accept an earlier package that
# no longer applies.
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
. tests/lib.sh

setup() {
    W=$(mktemp -d); mkdir -p "$W/usb/packages" "$W/data/nemesis/apps" "$W/bin"
    cp "$ROOT/tools/integrated/"*.sh "$W/usb/"
    cp "$ROOT/tools/integrated/bin/zipstore-host" "$W/usb/zipstore"
    cat > "$W/bin/nemesis" <<'PY'
#!/usr/bin/env python3
import sys,os,zipfile,shutil
root=os.environ['IT_DATA']+'/nemesis/apps'; args=sys.argv[1:]
if args[0]=='pkg-info':
    with zipfile.ZipFile(args[-1]) as z:
        print('id='+z.read('NEMESIS.data').decode().split('id=')[1].splitlines()[0])
elif args[0]=='install':
    with zipfile.ZipFile(args[-1]) as z:
        id=z.read('NEMESIS.data').decode().split('id=')[1].splitlines()[0]
        path=root+'/'+id; shutil.rmtree(path,ignore_errors=True); os.makedirs(path); z.extractall(path)
elif args[0]=='version' and os.environ.get('IT_NEM116'): print('1.16.3')
elif args[0]=='uninstall':
    # IT_NEM116: NEMESIS 1.16 runs preuninstall itself and keeps the package if it fails.
    force='--force' in args; pid=[a for a in args[1:] if not a.startswith('-')][0]
    if os.environ.get('IT_NEM116') and not force and os.path.exists(root+'/'+pid+'/scripts/preun.sh'):
        import subprocess
        if subprocess.call(['sh','scripts/preun.sh'],cwd=root+'/'+pid)!=0: sys.exit(5)
    elif force and not os.environ.get('IT_NEM116'): sys.exit(1)  # 1.15 reads --force as the package id
    shutil.rmtree(root+'/'+pid,ignore_errors=True)
else: sys.exit(1)
PY
    chmod +x "$W/bin/nemesis"
    printf '#!/bin/sh\nexit 0\n' > "$W/bin/sync"; chmod +x "$W/bin/sync"
    python3 - "$W/usb/packages" <<'PY'
import zipfile,sys,hashlib,pathlib
for m in ['dongle','wireless','audio','bridge','core','timer','bluelink','drivelog']:
    pid='gen5w.kr.'+m
    with zipfile.ZipFile(sys.argv[1]+'/'+pid+'.zip','w') as z:
        z.writestr('NEMESIS.data','[nemesis]\nid='+pid+'\nversion=new\npreinstall=scripts/pre.sh\npostinstall=scripts/post.sh\npreuninstall=scripts/preun.sh\n')
        # The installed copy refuses when IT_PREUN_REFUSE names it; this bundle's copy (checks/) agrees.
        z.writestr('scripts/preun.sh','case "$PWD" in */checks/*) exit 0;; esac\n[ "$IT_PREUN_REFUSE" != "'+pid+'" ] || exit 1\nexit 0\n')
        # Incoming build (bundle checks/) and earlier build (snapshot) answer separately.
        z.writestr('scripts/pre.sh','case "$PWD" in */checks/*) [ "$IT_SKIP" != "'+pid+'" ] || exit 77; exit 0;; esac\n[ "$IT_PRIOR_SKIP" != "'+pid+'" ] || exit 77\nexit 0\n')
        # Fails once, so the rollback reinstall of the earlier build succeeds.
        z.writestr('scripts/post.sh','[ "$IT_POST_FAIL" != "'+pid+'" ] || [ -e "$IT_DATA/post-failed" ] || { : > "$IT_DATA/post-failed"; exit 1; }\nexit 0\n')
        if m=='timer': z.writestr('bin/sha256-check','#!/bin/sh\ncase "$1:$3" in verify:63cf*|verify:97e7*) grep -q "^stock" "$2";; *) exit 1;; esac\n')
    package=pathlib.Path(sys.argv[1])/(pid+'.zip')
    stage=package.parent.parent/'checks'/pid; stage.mkdir(parents=True)
    sums=[]
    with zipfile.ZipFile(package) as z:
        z.extractall(stage)
        for name in z.namelist(): sums.append(hashlib.md5(z.read(name)).hexdigest()+'  '+name)
    (stage/'FILES.md5').write_text('\n'.join(sums)+'\n')
    (stage/'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest()+'\n')
PY
    mkdir -p "$W/sys/framework" "$W/sys/priv-app"
    echo stock > "$W/sys/framework/services.odex"; echo stock > "$W/sys/priv-app/SystemUI.odex"
}
run() { (cd "$W/usb" && IT_SYSFS="$W/sysfs" IT_DATA="$W/data" IT_SYSTEM="$W/sys" IT_NEM="$W/bin/nemesis" IT_SHELL=$(command -v mksh) IT_NO_REBOOT=1 CK_TEST_PATH="$W/bin:$PATH" PATH="$W/bin:$PATH" mksh "$1.sh" > "$W/out" 2>&1); }
state() { cat "$W/data/nemesis/gen5w-kr-integrated/state" 2>/dev/null; }
reg() { [ -f "$W/data/nemesis/apps/$1/NEMESIS.data" ]; }
NOREBOOT() { [ -e "$W/data/nemesis/gen5wkr.noreboot" ]; }

# A: the bridge skips itself, so nothing would run the guard: refuse to commit.
setup
IT_SKIP=gen5w.kr.bridge run install
check 'install without the bridge does not commit' test "$(state)" != committed
check 'install without the bridge leaves no /system module registered' eval '! reg gen5w.kr.wireless && ! reg gen5w.kr.audio'
grep -q 'bridge service that runs it is not installed' "$W/data/nemesis/gen5w-kr-integrated/report"
check 'install without the bridge says why' test $? = 0
check 'normal install still commits' eval 'run install && test "$(state)" = committed && reg gen5w.kr.bridge'
rm -rf "$W"

# F: the result screen points to the matching download.
setup
IT_SKIP=gen5w.kr.wireless run install
R=$W/usb/GEN5W-REPORT/RESULT.md
check 'no wireless code in stock apps: no dongle advice' eval '! grep -q "받을 버전 안내" "$R"'
mkdir -p "$W/sys/app"; printf 'x carplay_wireless x' > "$W/sys/app/HKMC_DiPO.odex"
IT_SKIP=gen5w.kr.wireless run install
check 'no built-in Wi-Fi: result points to the dongle edition' grep -q 'gen5w-kr-dongle.zip으로 업데이트' "$R"
check 'no built-in Wi-Fi: RESULT.html shows the notice' grep -q '받을 버전 안내' "$W/usb/GEN5W-REPORT/RESULT.html"
mkdir -p "$W/sysfs/class/net/wlan0"
IT_SKIP=gen5w.kr.wireless run install
check 'built-in Wi-Fi seen: no dongle advice' eval '! grep -q "받을 버전 안내" "$R"'
check 'wireless installed: no dongle advice' eval 'run install && ! grep -q "받을 버전 안내" "$R"'
echo standard > "$W/data/nemesis/gen5wkr.edition-hint"
run status
check 'dongle refusal hint points to the standard edition' grep -q '기본형 gen5w-kr-standard.zip을 설치하세요' "$R"
check 'the hint is shown once' test ! -e "$W/data/nemesis/gen5wkr.edition-hint"
run status
check 'later results carry no stale hint' eval '! grep -q "받을 버전 안내" "$R"'
check 'standard edition is named in the result' grep -q '기본형(내장 Wi-Fi)' "$R"
rm -rf "$W"

# G: NEMESIS 1.16 keeps a package whose installed preuninstall refuses.
setup
run install
check 'NEMESIS 1.16: normal remove still works' eval 'IT_NEM116=1 run remove && test "$(state)" = committed && ! reg gen5w.kr.bridge'
run install
IT_NEM116=1 IT_PREUN_REFUSE=gen5w.kr.bridge run remove
check 'NEMESIS 1.16: refusing installed hook, bundle check removes it' eval 'test "$(state)" = committed && ! reg gen5w.kr.bridge'
check 'NEMESIS 1.16: forced removal is reported' grep -q 'FORCED gen5w.kr.bridge' "$W/data/nemesis/gen5w-kr-integrated/report"
check 'NEMESIS 1.16: ISSUE.md records the NEMESIS version' grep -qx -- '- NEMESIS 버전: 1.16.3' "$W/usb/GEN5W-REPORT/ISSUE.md"
run status
check 'NEMESIS without a version command is reported as unknown' grep -q -- '- NEMESIS 버전: 확인 불가(1.15 이하일 수 있음)' "$W/usb/GEN5W-REPORT/ISSUE.md"
run install
check 'NEMESIS 1.15: no force needed' eval 'IT_PREUN_REFUSE=gen5w.kr.bridge run remove && ! grep -q "FORCED" "$W/out"'
rm -rf "$W"

# B: remove after an official firmware update (audio library not recognised).
setup
run install
mkdir -p "$W/usb/checks/gen5w.kr.audio/bin"
printf '#!/bin/sh\nexit 1\n' > "$W/usb/checks/gen5w.kr.audio/bin/audio-patch"
(cd "$W/usb/checks/gen5w.kr.audio" && md5sum bin/audio-patch | sed 's/ \*/  /' >> FILES.md5)
mkdir -p "$W/sys/lib"; echo newfw > "$W/sys/lib/libCarPlayAudio.so"
check 'remove succeeds with an unrecognised audio library' run remove
check 'remove commits instead of rolling back' test "$(state)" = committed
check 'remove leaves no module registered' eval '! ls "$W/data/nemesis/apps" | grep -q .'
check 'install that skips audio still refuses to arm over an unrecognised library' eval '! IT_SKIP=gen5w.kr.audio run install'
rm -rf "$W"

# C: a start that fails while capturing must not leave reboot suppression.
setup
run install
printf '#!/bin/sh\nexit 1\n' > "$W/usb/zipstore"
check 'update with a failing snapshot fails' eval '! run update'
check 'failed start leaves no reboot suppression' eval '! NOREBOOT'
rm -rf "$W"

# E: rollback where the earlier wireless build answers "does not apply" (77).
setup
run install
IT_POST_FAIL=gen5w.kr.bridge IT_PRIOR_SKIP=gen5w.kr.wireless run update
check 'rollback accepts an earlier package that no longer applies' test "$(state)" = rolled-back
check 'that package is left removed (stock)' eval '! reg gen5w.kr.wireless'
check 'wireless falls back to wired-only' test -f "$W/data/nemesis/gen5wkr.wireless-disabled"
check 'audio is not reinstalled in wired-only mode' eval '! reg gen5w.kr.audio'
check 'the rest is restored' eval 'reg gen5w.kr.bridge && reg gen5w.kr.core'
rm -rf "$W"

done_tests 'integrated edge cases'
