#!/bin/bash
# Portable USB installer: NEMESIS and the installed package are mocked; the
# installer script itself is production and runs under mksh.
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-usb.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
mkdir -p "$t/bin" "$t/actions"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/sync"
chmod +x "$t/bin/sync"
# Bound the watchdog fixture without waiting 30 seconds for orphaned Linux
# sleep children; the fixture settings reader itself completes immediately.
printf '#!/bin/sh\nexec /bin/sleep 0.25\n' > "$t/bin/sleep"
chmod +x "$t/bin/sleep"
cat > "$t/bin/md5" <<'SH'
#!/bin/sh
md5sum "$1"
SH
cat > "$t/nemesis" <<'SH'
#!/bin/bash
case "$1" in
pkg-list) cat "$ACTIONS/pkg-list" 2>/dev/null || :;;
install)
 [ "$3" != --update ] || echo update >> "$ACTIONS/log"
 echo "install $2" >> "$ACTIONS/log"
 # NEMESIS extracts with the caller umask; pm (uid system) must read the APKs.
 [ "$(umask)" = 0022 ] || { echo "pkg: $2"; exit 1; }
 cmp -s "$2" "$ACTIONS/expected.zip" || { echo 'staged copy differs'; exit 3; }
 app=$PORTABLE_TEST_ROOT/data/nemesis/apps/gen5w.kr.portable
 if [ -f "$ACTIONS/expect-retirement" ] && [ "$3" = --update ]; then
   "$PORTABLE_TEST_SH" "$app/boot.sh" update-retire || exit 1
   "$PORTABLE_TEST_SH" "$app/boot.sh" status > "$ACTIONS/retirement-status" || exit 1
   grep -qx 'retirement|held' "$ACTIONS/retirement-status" || exit 1
   echo update-retired-and-verified >> "$ACTIONS/log"
 fi
 if [ -f "$ACTIONS/inplace-hook-fail" ]; then
   echo 'new package hook' > "$app/package-preun.sh"
   exit 1
 fi
 if [ -f "$ACTIONS/new-hook-fail" ]; then
   echo 'new package hook' > "$app/package-preun.sh.new"
   mv "$app/package-preun.sh.new" "$app/package-preun.sh"
   exit 1
 fi
 [ ! -f "$ACTIONS/refuse" ] || { echo 'portable install: conflicting installation retained'; exit 1; }
 [ ! -f "$ACTIONS/expect-retirement" ] || echo package-replace >> "$ACTIONS/log"
 : > "$ACTIONS/new-package"
  if [ -f "$ACTIONS/migration-fail" ]; then
    echo migration-rollback >> "$ACTIONS/log"
    rm -f "$ACTIONS/retirement-held"
    exit 1
  else
   echo retirement-finalize >> "$ACTIONS/log"
   rm -f "$ACTIONS/retirement-held"
   : > "$ACTIONS/migration-ready"
 fi
 app=$PORTABLE_TEST_ROOT/data/nemesis/apps/gen5w.kr.portable
 mkdir -p "$app"
 echo 'new package hook' > "$app/package-preun.sh.new"
 mv "$app/package-preun.sh.new" "$app/package-preun.sh"
 printf '#!/bin/sh\necho enabled\\|1\necho mode\\|auto\n' > "$app/boot.sh"
  printf '#!/bin/sh\necho "snapshot $2" >> "$ACTIONS/log"\n' > "$app/check.sh"
  printf '#!/bin/sh\necho persistent-verify >> "$ACTIONS/log"\necho persistent-payload-and-recovery-verified\n' > "$app/persistent-start.sh"
 echo 'portable install: guarded automatic wireless operation starts on next boot';;
*) exit 2;;
esac
SH
printf '#!/bin/sh
echo "$@" >> "$ACTIONS/toast"
' > "$t/am"
printf '#!/bin/sh
[ ! -f "$ACTIONS/ap-fail" ] || exit 1
cat "$ACTIONS/ap" 2>/dev/null || echo 0
' > "$t/settings"
printf '#!/bin/sh
echo reboot >> "$ACTIONS/log"
[ ! -f "$ACTIONS/reboot-fail" ] || exit 1
' > "$t/bin/reboot"
chmod +x "$t/bin/md5" "$t/nemesis" "$t/am" "$t/settings" "$t/bin/reboot"
cat > "$t/test-shell" <<'SH'
#!/bin/sh
case "$1" in
  */boot.sh)
    case "$2" in
      status)
        if [ -f "$ACTIONS/new-package" ]; then
          printf 'enabled|1\nmode|persistent\n'
          [ ! -f "$ACTIONS/migration-ready" ] || printf 'persistent-migration|ready\n'
        elif [ -f "$ACTIONS/legacy-disabled" ]; then
          printf 'enabled|0\nreason|disabled-restored\n'
        elif [ -f "$ACTIONS/retirement-held" ]; then
          printf 'enabled|0\nreason|update-held\nretirement|held\n'
        else
          printf 'enabled|1\n'
          [ ! -f "$ACTIONS/retirement-held" ] || printf 'retirement|held\n'
        fi;;
      update-retire)
        echo update-retire >> "$ACTIONS/log"
        [ ! -f "$ACTIONS/legacy-no-handoff" ] || { echo 'boot: usage: boot.sh status' >&2; exit 2; }
        [ ! -f "$ACTIONS/retire-fail" ] || exit 1
        : > "$ACTIONS/retirement-held";;
      disable)
        echo legacy-disable >> "$ACTIONS/log"
        : > "$ACTIONS/legacy-disabled";;
      update-restore)
        echo update-restore >> "$ACTIONS/log"
        [ ! -f "$ACTIONS/retirement-held" ] || rm "$ACTIONS/retirement-held";;
      *) exit 2;;
    esac;;
  *) exec /bin/sh "$@";;
esac
SH
chmod +x "$t/test-shell"
export PATH=$t/bin:$PATH ACTIONS=$t/actions PORTABLE_TEST_NEM=$t/nemesis PORTABLE_TEST_SH=/bin/sh
export PORTABLE_TEST_AM=$t/am PORTABLE_TEST_SETTINGS=$t/settings PORTABLE_TEST_REBOOT=$t/bin/reboot
new_case() {
    rm -rf "$t/usb" "$t/root"; mkdir -p "$t/usb" "$t/root/data"
    cp tools/portable/usb/NEMESIS.sh tools/portable/usb/NEMESIS.data "$t/usb/"
    head -c 4096 /dev/urandom > "$t/usb/gen5w.kr.portable.zip"
    cp "$t/usb/gen5w.kr.portable.zip" "$ACTIONS/expected.zip"
    printf '%s\r\n' "$(md5sum "$t/usb/gen5w.kr.portable.zip" | cut -d' ' -f1)" > "$t/usb/gen5w.kr.portable.zip.md5"
    rm -f "$ACTIONS/log" "$ACTIONS/refuse" "$ACTIONS/pkg-list" "$ACTIONS/ap" "$ACTIONS/toast" "$ACTIONS/ap-fail" "$ACTIONS/new-hook-fail" "$ACTIONS/inplace-hook-fail" "$ACTIONS/retirement-held" "$ACTIONS/retire-fail" "$ACTIONS/new-package" "$ACTIONS/migration-ready" "$ACTIONS/migration-fail" "$ACTIONS/expect-retirement" "$ACTIONS/retirement-status" "$ACTIONS/legacy-no-handoff" "$ACTIONS/legacy-disabled"
export PORTABLE_TEST_ROOT=$t/root
}
run() { mksh "$t/usb/NEMESIS.sh"; }
result() { head -n 1 "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt"; }

new_case
run
[ "$(result)" = '결과: ok' ]
grep -q '자동 재부팅' "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt"
grep -q '화면이 한 번 꺼졌다가 다시 켜질 수 있습니다' "$ACTIONS/toast"
if grep -Eq '시동을 완전히 끈 뒤|콜드 재시작|수동으로 재부팅' "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt" "$ACTIONS/toast"; then
    echo 'FAIL successful install instructs manual cold restart'; exit 1
fi
grep -qx "install $t/root/data/gen5w.kr.portable.zip" "$ACTIONS/log"
grep -qx 'persistent-verify' "$ACTIONS/log"
grep -qx reboot "$ACTIONS/log"
[ ! -e "$t/root/data/gen5w.kr.portable.zip" ]
grep -q 'persistent-payload-and-recovery-verified' "$t/usb/GEN5W-PORTABLE-REPORT/status.txt"
grep -q TOAST "$ACTIONS/toast"
echo 'PASS verified ZIP staged, NEMESIS install, staged copy removed, status/baseline recorded'

# A hung system_server (am never returns) must not stall the installer.
new_case
printf '#!/bin/sh\nexec sleep 600\n' > "$t/am-hang"; chmod +x "$t/am-hang"
start=$(date +%s)
PORTABLE_TEST_AM=$t/am-hang run
[ "$(result)" = '결과: ok' ]
[ $(( $(date +%s) - start )) -lt 200 ] || { echo 'FAIL installer waited on a hung toast'; exit 1; }
echo 'PASS hung toast broadcast is bounded; install still completes'

for pkg in gen5w.kr.core gen5w.kr.bluelink wireless.projection; do
    new_case; echo "$pkg|1.0|installed" > "$ACTIONS/pkg-list"
    if run; then echo "FAIL installed alongside $pkg"; exit 1; fi
    [ "$(result)" = '결과: refused' ]
    [ ! -f "$ACTIONS/log" ] && [ ! -e "$t/root/data/gen5w.kr.portable.zip" ]
done
# pkg-list format is unverified on the car: on-disk app dirs refuse too.
new_case; mkdir -p "$t/root/data/nemesis/apps/gen5w.kr.timer"; : > "$t/root/data/nemesis/apps/gen5w.kr.timer/NEMESIS.data"
if run; then echo 'FAIL installed alongside on-disk gen5w.kr.timer'; exit 1; fi
[ "$(result)" = '결과: refused' ] && [ ! -f "$ACTIONS/log" ]
new_case; mkdir -p "$t/root/data/nemesis/apps/other.vendor"; : > "$t/root/data/nemesis/apps/other.vendor/NEMESIS.data"
run; [ "$(result)" = '결과: ok' ]
echo 'PASS existing integrated packages refuse before staging'
# Vehicle 2026-11-19: a failed NEMESIS --update preinstall leaves the portable
# registration without its folder. Disabled state reinstalls with --update.
new_case; echo 'gen5w.kr.portable|0.3.72|installed' > "$ACTIONS/pkg-list"
mkdir -p "$t/root/data/local/gen5w-portable/boot"; echo 0 > "$t/root/data/local/gen5w-portable/boot/enabled"
run; [ "$(result)" = '결과: ok' ]; grep -qx update "$ACTIONS/log"
grep -qx 'registered-without-folder|1' "$t/usb/GEN5W-PORTABLE-REPORT/status-before.txt"
[ -z "$(find "$t/root/data" -maxdepth 1 -name 'gen5w-portable-usb-preun.*' -print)" ]
new_case; echo 'gen5w.kr.portable|0.3.72|installed' > "$ACTIONS/pkg-list"
mkdir -p "$t/root/data/local/gen5w-portable/boot"; echo 1 > "$t/root/data/local/gen5w-portable/boot/enabled"
if run; then echo 'FAIL reinstalled a stale registration recorded as enabled'; exit 1; fi
[ "$(result)" = '결과: refused' ] && [ ! -f "$ACTIONS/log" ]
echo 'PASS stale portable registration without folder: disabled reinstalls with --update, enabled refuses'


new_case; printf x >> "$t/usb/gen5w.kr.portable.zip"
if run; then echo 'FAIL corrupted ZIP accepted'; exit 1; fi
[ "$(result)" = '결과: refused' ] && [ ! -f "$ACTIONS/log" ]
new_case; : > "$t/usb/GEN5W-PORTABLE-RESCUE"
if run; then echo 'FAIL installed from a rescue-token USB'; exit 1; fi
[ "$(result)" = '결과: refused' ] && [ ! -f "$ACTIONS/log" ]
echo 'PASS corrupted ZIP and rescue-token USB refuse before staging'

new_case; touch "$ACTIONS/refuse"
if run; then echo 'FAIL hid NEMESIS refusal'; exit 1; fi
[ "$(result)" = '결과: failed' ]
grep -q 'conflicting installation' "$t/usb/GEN5W-PORTABLE-REPORT/nemesis-install.txt"
[ ! -e "$t/root/data/gen5w.kr.portable.zip" ]
if grep -q snapshot "$ACTIONS/log"; then echo 'FAIL continued after refusal'; exit 1; fi
echo 'PASS NEMESIS refusal is reported and leaves no staged copy'

for value in 1 null ''; do
    new_case; printf '%s
' "$value" > "$ACTIONS/ap"
    if run; then echo "FAIL installed with wifi_ap_on=$value"; exit 1; fi
    [ "$(result)" = '결과: refused' ] && [ ! -f "$ACTIONS/log" ]
done
new_case; printf '0
' > "$ACTIONS/ap"; run; [ "$(result)" = '결과: ok' ]
echo 'PASS wifi_ap_on other than 0 refuses before any change; CRLF 0 accepted'

# Car state 2026-11-13: package registered, postinstall failed, never armed.
new_case; app=$t/root/data/nemesis/apps/gen5w.kr.portable; mkdir -p "$app"; : > "$app/NEMESIS.data"
printf '#!/bin/sh
echo enabled\|
echo attempt\|
' > "$app/boot.sh"
echo 'gen5w.kr.portable|0.3.65|installed' > "$ACTIONS/pkg-list"
run; [ "$(result)" = '결과: ok' ]; grep -qx update "$ACTIONS/log"
new_case; mkdir -p "$app"; : > "$app/NEMESIS.data"; printf '#!/bin/sh
echo enabled\|1
' > "$app/boot.sh"
if run; then echo 'FAIL reinstalled over an armed package'; exit 1; fi
[ "$(result)" = '결과: refused' ] && [ ! -f "$ACTIONS/log" ]
echo 'PASS unarmed leftover is replaced with --update; armed install is refused'

new_case; touch "$ACTIONS/refuse"; mkdir -p "$app"; : > "$app/NEMESIS.data"; printf '#!/bin/sh
echo enabled\|
' > "$app/boot.sh"
echo 'gen5w.kr.portable|0.3.65|installed' > "$ACTIONS/pkg-list"
if run; then echo 'FAIL hid postinstall failure'; exit 1; fi
grep -q '자동 적용은 켜지지 않았습니다' "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt"
echo 'PASS registered-but-unarmed failure is reported as such'

# Refusal must preserve the original inode and avoid stopping existing apps.
old_package() {
    app=$t/root/data/nemesis/apps/gen5w.kr.portable
    mkdir -p "$app"
    : > "$app/NEMESIS.data"
    printf '#!/bin/sh\necho enabled\\|\necho attempt\\|\n' > "$app/boot.sh"
    printf '#!/bin/sh\necho old-hook\n' > "$app/package-preun.sh"
    chmod 750 "$app/package-preun.sh"
    ln "$app/package-preun.sh" "$t/root/old-hook"
    echo 'gen5w.kr.portable|old|installed' > "$ACTIONS/pkg-list"
}
for failure in ap-on ap-read; do
    new_case; old_package
    if [ "$failure" = ap-on ]; then echo 1 > "$ACTIONS/ap"; else touch "$ACTIONS/ap-fail"; fi
    if run; then echo "FAIL accepted $failure"; exit 1; fi
    [ "$(result)" = '결과: refused' ]
    [ "$app/package-preun.sh" -ef "$t/root/old-hook" ] || { echo "FAIL $failure changed old hook"; exit 1; }
    ! grep -q force-stop "$ACTIONS/toast"
done
echo 'PASS update AP refusal and read failure preserve old hook identity before app stop'
new_case; old_package; touch "$ACTIONS/refuse"
if run; then echo 'FAIL hid update refusal'; exit 1; fi
[ "$app/package-preun.sh" -ef "$t/root/old-hook" ] || { echo 'FAIL refused update lost old hook'; exit 1; }
[ "$(stat -c %a "$app/package-preun.sh")" = 750 ]
echo 'PASS failed update restores original hook inode and mode'
for outcome in success postinstall-failure inplace-failure; do
    new_case; old_package
    if [ "$outcome" != success ]; then
        if [ "$outcome" = inplace-failure ]; then touch "$ACTIONS/inplace-hook-fail"; else touch "$ACTIONS/new-hook-fail"; fi
        if run; then echo 'FAIL hid new package failure'; exit 1; fi
    else run; fi
    grep -qx 'new package hook' "$app/package-preun.sh"
    [ ! "$app/package-preun.sh" -ef "$t/root/old-hook" ]
    [ -z "$(find "$t/root/data" -maxdepth 1 -name 'gen5w-portable-usb-preun.*' -print)" ]
done
echo 'PASS successful update and failed new-package postinstall retain the new hook'

# Active update retires the currently enabled package overlay before NEMESIS
# can replace APKs/hooks. On NEMESIS failure the held overlay is restored; on
# success package migration owns finalization and USB requests one reboot.
new_case; old_package; touch "$ACTIONS/refuse" "$ACTIONS/expect-retirement"; export PORTABLE_TEST_SH=$t/test-shell
if run; then echo 'FAIL hid active update refusal'; exit 1; fi
[ "$(result)" = '결과: failed' ]
grep -qx update-retire "$ACTIONS/log"
grep -qx update-restore "$ACTIONS/log"
retire_line=$(grep -n '^update-retire$' "$ACTIONS/log" | head -n 1 | cut -d: -f1)
[ "$retire_line" -lt "$(grep -n '^update-retired-and-verified$' "$ACTIONS/log" | head -n 1 | cut -d: -f1)" ]
! grep -q 'install ' "$ACTIONS/log"
! grep -q '^package-replace$' "$ACTIONS/log"
[ ! -e "$ACTIONS/retirement-held" ]
[ "$(grep -c '^reboot$' "$ACTIONS/log" || : )" = 0 ]
! grep -q 'zygote' "$ACTIONS/log"
! grep -q 'zygote' "$ACTIONS/toast"

new_case; old_package; touch "$ACTIONS/expect-retirement"; export PORTABLE_TEST_SH=$t/test-shell
touch "$ACTIONS/retire-fail"
if run; then echo 'FAIL continued after owned overlay retirement failed'; exit 1; fi
[ "$(result)" = '결과: refused' ]
! grep -q 'install ' "$ACTIONS/log"
! grep -q update-restore "$ACTIONS/log"

new_case; old_package; touch "$ACTIONS/expect-retirement"; export PORTABLE_TEST_SH=$t/test-shell
run
[ "$(result)" = '결과: ok' ]
grep -qx update-retire "$ACTIONS/log"
! grep -q update-restore "$ACTIONS/log"
grep -q '^install .*gen5w.kr.portable.zip$' "$ACTIONS/log"
[ "$(grep -n '^update-retire$' "$ACTIONS/log" | head -n 1 | cut -d: -f1)" -lt "$(grep -n '^package-replace$' "$ACTIONS/log" | cut -d: -f1)" ]
[ "$(grep -c '^retirement-finalize$' "$ACTIONS/log")" = 1 ]
[ -f "$ACTIONS/migration-ready" ]
[ ! -f "$ACTIONS/retirement-held" ]
[ "$(grep -c '^reboot$' "$ACTIONS/log")" = 1 ]
! grep -q 'zygote' "$ACTIONS/log"
! grep -q 'zygote' "$ACTIONS/toast"
echo 'PASS enabled update holds owned retirement before replacement, restores on failure, and reboots once on success'

# The deployed 0.3.70 package has no no-zygote update handoff. Its own disable
# path is used only after read-only admission and the staged ZIP have passed.
new_case; old_package; touch "$ACTIONS/legacy-no-handoff"; export PORTABLE_TEST_SH=$t/test-shell
run
[ "$(result)" = '결과: ok' ]
grep -qx legacy-disable "$ACTIONS/log"
grep -q '구버전 적용을 먼저 안전하게 해제합니다.' "$ACTIONS/toast"
grep -q '정상 설치 후 자동 재부팅됩니다. 이때 화면이 한 번 꺼졌다가 다시 켜질 수 있습니다.' "$ACTIONS/toast"
[ "$(grep -c '^reboot$' "$ACTIONS/log")" = 1 ]
echo 'PASS legacy update warns about the transition, disables through its owning path, then reboots after install'

new_case; old_package; touch "$ACTIONS/expect-retirement" "$ACTIONS/migration-fail"; export PORTABLE_TEST_SH=$t/test-shell
if run; then echo 'FAIL accepted update without persistent migration readiness'; exit 1; fi
[ "$(result)" = '결과: failed' ]
[ ! -f "$ACTIONS/migration-ready" ]
[ "$(grep -c '^reboot$' "$ACTIONS/log" || : )" = 0 ]
grep -qx migration-rollback "$ACTIONS/log"
echo 'PASS update without persistent migration readiness does not request reboot'

new_case; touch "$ACTIONS/reboot-fail"
if run; then echo 'FAIL hid automatic reboot request failure'; exit 1; fi
[ "$(result)" = '결과: failed' ]
grep -q '자동 재부팅 요청에 실패' "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt"
grep -qx reboot "$ACTIONS/log"
echo 'PASS successful install reports automatic reboot command failure for manual recovery'

# Leftover persistent install whose package was deleted (2026-11-20 car: the
# 0.3.79 install was refused because build.prop still set the DiPO wrapper).
printf '#!/bin/sh\n[ "$1" = wrap.com.daudio.app.dipo ] && [ -f "$ACTIONS/wrap" ] && cat "$ACTIONS/wrap"\nexit 0\n' > "$t/getprop"
chmod +x "$t/getprop"; export PORTABLE_TEST_GETPROP=$t/getprop
leftover() {
    g=$t/root/data/local/gen5w-portable/persistent
    mkdir -p "$g/bootguard/bin" "$g/recovery" "$t/root/data/local/gen5w-portable/boot"
    rm -f "$ACTIONS/reboot-fail"; echo manifest > "$g/recovery/manifest"; echo 1 > "$t/root/data/local/gen5w-portable/boot/enabled"
    printf '#!/bin/sh\nexit 0\n' > "$g/bootguard/bin/dex-patch"; chmod +x "$g/bootguard/bin/dex-patch"
    printf '#!/bin/sh\necho guard-restore >> "$ACTIONS/log"\nprintf "%%s\n" "$(cat "$ACTIONS/restore-result")" > "$GEN5W_RECOVERY_USB_ROOT/GEN5W-RECOVERY-RESULT.txt"\n' > "$g/bootguard/restore.sh"
    echo '/system/bin/sh /data/nemesis/apps/gen5w.kr.portable/wrap-dipo.sh' > "$ACTIONS/wrap"
}
new_case; leftover
if run; then echo 'FAIL installed over a leftover /system install'; exit 1; fi
[ "$(result)" = '결과: refused' ] || { echo 'FAIL leftover not refused'; cat "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt"; exit 1; }
grep -q '업데이트하거나 삭제' "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt" || { echo 'FAIL refusal does not say what to do'; exit 1; }
if grep -sEq '^guard-restore$|^reboot$|^install ' "$ACTIONS/log"; then echo 'FAIL leftover refusal changed something'; cat "$ACTIONS/log"; exit 1; fi
[ "$(cat "$t/root/data/local/gen5w-portable/boot/enabled")" = 1 ] || { echo 'FAIL leftover refusal changed boot state'; exit 1; }
echo 'PASS leftover /system install without package: refused with update/remove guidance, nothing changed'
