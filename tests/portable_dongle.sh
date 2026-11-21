#!/bin/bash
# USB Wi-Fi dongle driver service of the portable install.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v mksh >/dev/null 2>&1 || { echo 'mksh not found'; exit 78; }
t=$(mktemp -d /tmp/g5p-dongle.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
R=$t/root; B=$R/data/bundle; A=$t/act; S=$R/data/local/gen5w-portable
fail() { echo "FAIL $*" >&2; exit 1; }
mkdir -p "$B/dongle/modules" "$B/dongle/firmware" "$A"
cp tools/portable/dongle.sh "$B/"
mkdir -p "$B/bin"; cp .build/portable/dex-patch-host "$B/bin/dex-patch"
cp tools/usb-wifi/package/files/modules/modules.alias tools/usb-wifi/package/files/modules/modules.profile "$B/dongle/modules/"
for m in tools/usb-wifi/package/files/modules/*.ko; do : > "$B/dongle/modules/${m##*/}"; done
( cd tools/usb-wifi/package/files/firmware && find . -type f ) | while read -r f; do
    mkdir -p "$B/dongle/firmware/${f%/*}"; : > "$B/dongle/firmware/$f"
done
# Kernel/Android boundaries. insmod of the last 88x2bu module creates wlan0
# unless the fixture makes the interface never appear.
cat > "$t/adapter" <<SH
#!/bin/bash
case "\$1" in
boot-completed) echo 1;;
modules) [ ! -f "$A/modules" ] || cat "$A/modules";;
insmod) echo "\${2##*/}" >> "$A/insmod"
        [ ! -f "$A/insmod-fail" ] || exit 1
        name=\${2##*/}; name=\${name%.ko}; echo "\${name//-/_} 1000 0 - Live 0x0" >> "$A/modules"
        if [ "\$name" = 88x2bu ] && [ ! -f "$A/no-wlan" ]; then mkdir -p "$R/sys/class/net/wlan0"; fi;;
sleep) echo sleep >> "$A/sleeps"
       [ ! -f "$A/unplug-after-first" ] || { rm -rf "$R/sys/bus/usb/devices/1-1" "$R/sys/bus/usb/devices/1-1:1.0"; rm -f "$A/unplug-after-first"; };;
sync) :;;
toast) echo "\$2" >> "$A/toast";;
*) echo "unexpected op \$1" >> "$A/errors"; exit 1;;
esac
SH
chmod 755 "$t/adapter"
export PORTABLE_TEST_ROOT=$R PORTABLE_TEST_DONGLE_ADAPTER=$t/adapter PORTABLE_TEST_DONGLE_STABLE=4
reset() { # backend enabled
    rm -rf "$R/sys" "$S" "$R/data/nemesis" "$A"; mkdir -p "$A" "$S/boot" "$R/sys/class/net" "$R/sys/module/firmware_class/parameters"
    : > "$R/sys/module/firmware_class/parameters/path"
    echo "$1" > "$S/wifi-backend"; echo "$2" > "$S/boot/enabled"
}
ar9271() { mkdir -p "$R/sys/bus/usb/devices/1-1"; echo 0cf3 > "$R/sys/bus/usb/devices/1-1/idVendor"; echo 9271 > "$R/sys/bus/usb/devices/1-1/idProduct"; }
rtl88x2bu() { mkdir -p "$R/sys/bus/usb/devices/1-1" "$R/sys/bus/usb/devices/1-1:1.0"; echo 0bda > "$R/sys/bus/usb/devices/1-1/idVendor"; echo b812 > "$R/sys/bus/usb/devices/1-1/idProduct"; echo 'usb:v0BDApB812d0210dc00dsc00dp00icFFiscFFipFFin00' > "$R/sys/bus/usb/devices/1-1:1.0/modalias"; }
run() { PORTABLE_TEST_DONGLE_ROUNDS=$1 mksh "$B/dongle.sh" > "$A/out" 2>&1 || { cat "$A/out" >&2; fail "service failed"; }
        [ ! -s "$A/errors" ] || { cat "$A/errors" >&2; fail 'unexpected Android call'; }; }
fwpath() { cat "$R/sys/module/firmware_class/parameters/path"; }

reset builtin 1; rtl88x2bu; run 3
[ ! -e "$A/insmod" ] && [ -z "$(fwpath)" ] || fail 'built-in install loaded dongle drivers'
reset dongle 0; rtl88x2bu; run 3
[ ! -e "$A/insmod" ] && [ -z "$(fwpath)" ] || fail 'disabled install loaded dongle drivers'
echo 'PASS the service does nothing for built-in Wi-Fi or a disabled install'

reset dongle 1; rtl88x2bu; run 4
[ "$(fwpath)" = "$B/dongle/firmware" ] || fail "firmware path '$(fwpath)'"
[ "$(wc -c < "$R/sys/module/firmware_class/parameters/path")" = "${#B}" ] || :
[ "$(printf '%s' "$B/dongle/firmware" | wc -c)" = "$(wc -c < "$R/sys/module/firmware_class/parameters/path")" ] || fail 'firmware path written with a newline'
want=$(grep '^88x2bu|' "$B/dongle/modules/modules.profile" | cut -d'|' -f2)
[ "$(tr '\n' ' ' < "$A/insmod")" = "$(printf '%s.ko ' $want)" ] || fail "insmod order: $(tr '\n' ' ' < "$A/insmod")"
[ -d "$R/sys/class/net/wlan0" ] || fail 'no wlan0'
[ ! -e "$S/dongle/loading" ] || fail 'restart mark kept after a stable interface'
grep -q 'wlan0 ready (88x2bu)' "$R/data/nemesis/logs/gen5w.kr.portable/dongle.log" || fail 'load not logged'
[ "$(cut -d'|' -f2 "$S/dongle/status")" = ready ] || fail 'connected dongle not shown as ready'
echo 'PASS a plugged RTL8812BU gets package firmware path and modules in profile order, then the mark clears'

reset dongle 1; rtl88x2bu; echo '88x2bu 400000 0 - Live 0x0' > "$A/modules"; run 2
! grep -qx 88x2bu.ko "$A/insmod" || fail 'loaded module inserted again'
echo 'PASS modules already loaded are not inserted again'

reset dongle 1; rtl88x2bu; mkdir -p "$S/dongle"; echo loading > "$S/dongle/loading"; run 3
[ ! -e "$A/insmod" ] || fail 'loaded again after an interrupted load'
[ -f "$S/dongle/blocked" ] && [ ! -e "$S/dongle/loading" ] || fail 'interrupted load not turned into a block'
grep -q '동글 사용을 멈췄습니다' "$A/toast" || fail 'no notice for the block'
touch "$A/unplug-after-first"; run 3
[ ! -e "$S/dongle/blocked" ] || fail 'unplugging did not clear the block'
[ "$(cut -d'|' -f2 "$S/dongle/status")" = waiting ] || fail 'unplugged dongle not shown as waiting'
echo 'PASS a load cut short by a restart blocks loading until the dongle is unplugged'

reset dongle 1; rtl88x2bu; touch "$A/insmod-fail"; run 8
[ "$(grep -c '^88x2bu.ko$' "$A/insmod")" = 3 ] || fail "retries: $(grep -c '^88x2bu.ko$' "$A/insmod")"
[ ! -e "$S/dongle/loading" ] || fail 'failed load left the restart mark'
[ "$(cut -d'|' -f2 "$S/dongle/status")" = failed ] || fail 'failed driver not shown as failed'
echo 'PASS a failing driver load is retried at most 3 times and leaves no restart mark'

reset dongle 1; rtl88x2bu; printf '/vendor/firmware' > "$R/sys/module/firmware_class/parameters/path"; run 2
[ "$(fwpath)" = /vendor/firmware ] || fail 'foreign firmware path replaced'
echo 'PASS a firmware path set by someone else is left unchanged'

reset dongle 1; ar9271; run 4
[ ! -e "$A/insmod" ] || fail '2.4GHz-only dongle was loaded'
grep -q 'NOT USED ath9k_htc' "$R/data/nemesis/logs/gen5w.kr.portable/dongle.log" || fail '2.4GHz-only dongle not logged'
[ "$(grep -c '2.4GHz 전용' "$A/toast")" = 1 ] || fail '2.4GHz-only notice must show once'
[ "$(cut -d'|' -f2 "$S/dongle/status")" = 2g ] || fail '2.4GHz-only dongle not shown on the screen'
echo 'PASS a 2.4GHz-only dongle is not loaded and the driver says why, once'

reset dongle 1; run 3
[ ! -e "$A/insmod" ] || fail 'loaded without a dongle'
echo 'PASS nothing loads while no supported dongle is plugged in'

# Log rotation without wc (absent on the unit): the package helper's size.
reset dongle 1; rtl88x2bu; mkdir -p "$R/data/nemesis/logs/gen5w.kr.portable"
head -c 40000 /dev/zero | tr '\0' x > "$R/data/nemesis/logs/gen5w.kr.portable/dongle.log"
run 2
[ "$(stat -c %s "$R/data/nemesis/logs/gen5w.kr.portable/dongle.log.1")" = 40000 ] || fail 'large log not rotated'
[ "$(stat -c %s "$R/data/nemesis/logs/gen5w.kr.portable/dongle.log")" -lt 4096 ] || fail 'new log not started'
echo 'PASS the dongle log rotates at 32 KiB using the package helper'
