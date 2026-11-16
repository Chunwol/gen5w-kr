#!/bin/bash
# Portable USB installer: NEMESIS and the installed package are mocked; the
# installer script itself is production and runs under mksh.
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5p-usb.XXXXXX)
trap 'rm -rf "$t"' EXIT
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
 app=$PORTABLE_TEST_ROOT/data/nemesis/apps/gen5w.kr.portable
 mkdir -p "$app"
 echo 'new package hook' > "$app/package-preun.sh.new"
 mv "$app/package-preun.sh.new" "$app/package-preun.sh"
 printf '#!/bin/sh\necho enabled\\|1\necho mode\\|auto\n' > "$app/boot.sh"
 printf '#!/bin/sh\necho "snapshot $2" >> "$ACTIONS/log"\n' > "$app/check.sh"
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
chmod +x "$t/bin/md5" "$t/nemesis" "$t/am" "$t/settings"
export PATH=$t/bin:$PATH ACTIONS=$t/actions PORTABLE_TEST_NEM=$t/nemesis PORTABLE_TEST_SH=/bin/sh
export PORTABLE_TEST_AM=$t/am PORTABLE_TEST_SETTINGS=$t/settings
new_case() {
    rm -rf "$t/usb" "$t/root"; mkdir -p "$t/usb" "$t/root/data"
    cp tools/portable/usb/NEMESIS.sh tools/portable/usb/NEMESIS.data "$t/usb/"
    head -c 4096 /dev/urandom > "$t/usb/gen5w.kr.portable.zip"
    cp "$t/usb/gen5w.kr.portable.zip" "$ACTIONS/expected.zip"
    printf '%s\r\n' "$(md5sum "$t/usb/gen5w.kr.portable.zip" | cut -d' ' -f1)" > "$t/usb/gen5w.kr.portable.zip.md5"
    rm -f "$ACTIONS/log" "$ACTIONS/refuse" "$ACTIONS/pkg-list" "$ACTIONS/ap" "$ACTIONS/toast" "$ACTIONS/ap-fail" "$ACTIONS/new-hook-fail" "$ACTIONS/inplace-hook-fail"
    export PORTABLE_TEST_ROOT=$t/root
}
run() { mksh "$t/usb/NEMESIS.sh"; }
result() { head -n 1 "$t/usb/GEN5W-PORTABLE-REPORT/RESULT.txt"; }

new_case
run
[ "$(result)" = '결과: ok' ]
grep -qx "install $t/root/data/gen5w.kr.portable.zip" "$ACTIONS/log"
grep -qx 'snapshot /data/g5p-before' "$ACTIONS/log"
[ ! -e "$t/root/data/gen5w.kr.portable.zip" ]
grep -q 'enabled|1' "$t/usb/GEN5W-PORTABLE-REPORT/status.txt"
grep -q TOAST "$ACTIONS/toast"
echo 'PASS verified ZIP staged, NEMESIS install, staged copy removed, status/baseline recorded'

for pkg in gen5w.kr.core gen5w.kr.bluelink wireless.projection gen5w.kr.portable; do
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
echo 'PASS existing integrated/portable packages refuse before staging'

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
