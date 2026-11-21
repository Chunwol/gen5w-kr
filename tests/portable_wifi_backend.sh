#!/bin/bash
# Install-time Wi-Fi choice: built-in Wi-Fi, USB dongle, or none.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v mksh >/dev/null 2>&1 || { echo 'mksh not found'; exit 78; }
t=$(mktemp -d /tmp/g5p-wifi.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
R=$t/root; B=$R/data/bundle; A=$t/act
fail() { echo "FAIL $*" >&2; exit 1; }
# Package payload: the real driver catalog with stand-in module/firmware files.
mkdir -p "$B/dongle/modules" "$B/dongle/firmware" "$A"
cp tools/portable/wifi-backend.sh "$B/"
cp tools/usb-wifi/package/files/modules/modules.alias tools/usb-wifi/package/files/modules/modules.profile "$B/dongle/modules/"
for m in tools/usb-wifi/package/files/modules/*.ko; do : > "$B/dongle/modules/${m##*/}"; done
( cd tools/usb-wifi/package/files/firmware && find . -type f ) | while read -r f; do
    mkdir -p "$B/dongle/firmware/${f%/*}"; : > "$B/dongle/firmware/$f"
done
# Android boundaries: settings/svc toggle a fake wifi_on; enabling built-in
# Wi-Fi creates wlan0 only when the fixture says the chip exists.
cat > "$t/adapter" <<SH
#!/bin/bash
echo "\$1" >> "$A/calls"
case "\$1" in
wifi-on) [ -f "$A/wifi_on" ] || exit 1; cat "$A/wifi_on";;
enable) echo 1 > "$A/wifi_on"; if [ -f "$A/chip" ]; then mkdir -p "$R/sys/class/net/wlan0"; fi;;
disable) [ -f "$A/stuck" ] || { echo 0 > "$A/wifi_on"; rm -rf "$R/sys/class/net/wlan0"; };;
dmesg) [ ! -f "$A/dmesg" ] || cat "$A/dmesg";;
modules) [ ! -f "$A/modules" ] || cat "$A/modules";;
sleep) :;;
*) echo "unexpected op \$1" >> "$A/errors"; exit 1;;
esac
SH
chmod 755 "$t/adapter"
export PORTABLE_TEST_ROOT=$R PORTABLE_TEST_WIFI_ADAPTER=$t/adapter
reset() {
    rm -rf "$R/sys" "$R/data/local" "$R/data/nemesis" "$A"; mkdir -p "$A" "$R/sys/class/net"
}
dongle() { # vendor product: a plugged-in USB device
    mkdir -p "$R/sys/bus/usb/devices/1-1"
    echo "$1" > "$R/sys/bus/usb/devices/1-1/idVendor"; echo "$2" > "$R/sys/bus/usb/devices/1-1/idProduct"
}
dongle5g() { # a plugged-in RTL8812BU: matched on its vendor-class interface
    mkdir -p "$R/sys/bus/usb/devices/1-1:1.0"
    echo 'usb:v0BDApB812d0210dc00dsc00dp00icFFiscFFipFFin00' > "$R/sys/bus/usb/devices/1-1:1.0/modalias"
}
detect() { mksh "$B/wifi-backend.sh" detect; }
expect() { # what expected-output
    local out
    out=$(detect) || fail "$1: detect failed ($out)"
    [ "$out" = "$2" ] || fail "$1: got '$out', want '$2'"
    [ ! -s "$A/errors" ] || { cat "$A/errors" >&2; fail "$1: unexpected Android call"; }
}
never_enabled() { ! grep -qx enable "$A/calls" 2>/dev/null || fail "$1: Wi-Fi was turned on"; }
left_off() { [ "$(cat "$A/wifi_on")" = 0 ] || fail "$1: Wi-Fi left on"; }

reset; mkdir -p "$R/sys/bus/sdio/devices/mmc1:0001:1"; echo 0x07 > "$R/sys/bus/sdio/devices/mmc1:0001:1/class"; echo 0 > "$A/wifi_on"
expect 'SDIO Wi-Fi function' 'builtin|observed'; never_enabled 'SDIO Wi-Fi function'
echo 'PASS built-in Wi-Fi seen on SDIO is used without turning Wi-Fi on'

reset; echo 0 > "$A/wifi_on"; touch "$A/chip"; dongle5g
expect 'probe finds built-in chip' 'builtin|probe'; left_off 'probe finds built-in chip'
grep -qx enable "$A/calls" && grep -qx disable "$A/calls" || fail 'probe did not toggle Wi-Fi'
echo 'PASS Wi-Fi off: turned on for the check, built-in wins over a plugged dongle, turned off again'

reset; echo 0 > "$A/wifi_on"
expect 'no chip, no dongle' 'none|probe-none'; left_off 'no chip, no dongle'
echo 'PASS no built-in Wi-Fi and no dongle: none, Wi-Fi off again'

reset; echo 0 > "$A/wifi_on"; dongle5g
expect 'no chip, RTL8812BU dongle' 'dongle|probe-none'; left_off 'no chip, RTL8812BU dongle'
echo 'PASS no built-in Wi-Fi and a dongle that can host the 5GHz hotspot: dongle'

reset; echo 0 > "$A/wifi_on"; dongle 0cf3 9271
expect 'no chip, 2.4GHz-only AR9271' 'none|probe-none-2g-only-dongle'; left_off 'no chip, 2.4GHz-only AR9271'
echo 'PASS a 2.4GHz-only dongle is not chosen and the reason is reported'

reset; echo 0 > "$A/wifi_on"; mkdir -p "$R/sys/bus/usb/devices/1-1:1.0"
echo 'usb:v0BDApB812d0210dc00dsc00dp00icFFiscFFipFFin00' > "$R/sys/bus/usb/devices/1-1:1.0/modalias"
expect 'interface modalias (RTL8812BU)' 'dongle|probe-none'
echo 'PASS a dongle is matched on the kernel interface modalias'

reset; echo 0 > "$A/wifi_on"; dongle 0cf3 1002
grep -q 'v0CF3p1002.* carl9170' "$B/dongle/modules/modules.alias" || fail 'fixture: carl9170 alias missing'
expect 'incomplete driver profile' 'none|probe-none'
echo 'PASS a dongle whose driver profile is incomplete is not chosen'

reset; echo 0 > "$A/wifi_on"; dongle 050d 705e
grep -q '^rtl8187|.*|no|ready$' "$B/dongle/modules/modules.profile" || fail 'fixture: rtl8187 profile is not ready without AP'
expect 'ready dongle without AP mode' 'none|probe-none'
echo 'PASS a dongle that cannot run an access point (wireless CarPlay needs one) is not chosen'

reset; echo 0 > "$A/wifi_on"; touch "$A/stuck"; dongle5g
if out=$(detect); then fail "Wi-Fi stuck on was accepted ($out)"; fi
[ "$out" = 'error|wifi-still-on' ] || fail "stuck Wi-Fi reported '$out'"
echo 'PASS Wi-Fi that does not turn off again stops the install'

reset; echo 0 > "$A/wifi_on"; mkdir -p "$R/data/nemesis"; : > "$R/data/nemesis/gen5wkr.force-dongle"
expect 'USB override' 'dongle|forced'; never_enabled 'USB override'
echo 'PASS GEN5W-FORCE-DONGLE chooses the dongle without probing'

reset; echo 0 > "$A/wifi_on"; mkdir -p "$R/data/local/gen5w-portable/persistent/recovery"
printf 'GEN5W-RECOVERY-MANIFEST|2\n/system/wifi/bcmdhd.ko|file|x\n' > "$R/data/local/gen5w-portable/persistent/recovery/manifest"
expect 'installed stand-in' 'dongle|installed'; never_enabled 'installed stand-in'
echo 'PASS an update keeps the installed dongle stand-in without probing it'

reset; dongle5g
expect 'settings unreadable' 'none|settings-unreadable'; never_enabled 'settings unreadable'
echo 'PASS unknown Wi-Fi state never swaps the driver, even with a dongle'

reset; echo 1 > "$A/wifi_on"; mkdir -p "$R/sys/class/net/wlan0"; echo '88x2bu 61000 0 - Live 0x0' > "$A/modules"; dongle5g
expect 'wlan0 from a loaded dongle driver' 'dongle|wifi-on-no-interface'; never_enabled 'wlan0 from a loaded dongle driver'
echo 'PASS a wlan interface made by a loaded dongle driver is not taken for built-in Wi-Fi'

reset; echo 1 > "$A/wifi_on"; echo '[ 3.1] dhd_bus_start: Firmware up: op_mode=0x0005' > "$A/dmesg"
expect 'Broadcom firmware in kernel log' 'builtin|observed'
echo 'PASS Broadcom firmware start in the kernel log counts as built-in Wi-Fi'

reset
[ "$(mksh "$B/wifi-backend.sh" get)" = unknown ] || fail 'get without a record'
mkdir -p "$R/data/nemesis"; : > "$R/data/nemesis/gen5wkr.force-dongle"
mksh "$B/wifi-backend.sh" record dongle >/dev/null
[ "$(mksh "$B/wifi-backend.sh" get)" = dongle ] || fail 'recorded backend not read back'
[ ! -e "$R/data/nemesis/gen5wkr.force-dongle" ] || fail 'force marker survived the install'
if mksh "$B/wifi-backend.sh" record usb >/dev/null 2>&1; then fail 'unknown backend recorded'; fi
[ "$(mksh "$B/wifi-backend.sh" get)" = dongle ] || fail 'rejected record changed the saved backend'
echo 'PASS record/get keep one validated backend and consume the USB override'

mksh "$B/wifi-backend.sh" record none probe-none-2g-only-dongle >/dev/null
[ "$(cat "$R/data/local/gen5w-portable/wifi-backend-why")" = 2g-only ] || fail '2.4GHz-only reason not recorded'
mksh "$B/wifi-backend.sh" record none probe-none >/dev/null
[ ! -e "$R/data/local/gen5w-portable/wifi-backend-why" ] || fail 'old 2.4GHz-only reason survived a new install'
echo 'PASS the install records when a 2.4GHz-only dongle was the reason and clears it later'
