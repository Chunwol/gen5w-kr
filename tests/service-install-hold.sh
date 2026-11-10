#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
mkdir -p "$W/data/nemesis" "$W/system"
mkdir -p "$W/data/nemesis/gen5w-kr-integrated/lock"
echo "$$" > "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
cat /proc/sys/kernel/random/boot_id > "$W/data/nemesis/gen5wkr.install-hold"
start=$(/usr/bin/awk '{print $22}' /proc/$$/stat)
echo "$$:$start" >> "$W/data/nemesis/gen5wkr.install-hold"
chmod 755 "$W"
: > "$W/data/nemesis/gen5wkr.noreboot"
if [ "$(/usr/bin/id -u)" = 0 ] && [ -x /usr/bin/setpriv ]; then
    /usr/bin/setpriv --reuid 65534 --regid 65534 --clear-groups /usr/bin/env IT_DATA="$W/data" /usr/bin/mksh -c '. tools/diagnostics/install-hold.sh; install_hold' > "$W/out" 2>&1
    rc=$?; [ "$rc" = 0 ] || cat "$W/out"
    check 'system-like UID honors a root-owned active transaction' test "$rc" = 0
fi
for script in packages/core/scripts/owner.sh packages/core/scripts/uilog.sh packages/drive-log/scripts/service.sh packages/wireless-bridge/scripts/service.sh packages/consent-timer/scripts/timer.sh packages/bluelink-quiet/scripts/quiet.sh tools/usb-wifi/package/scripts/service.sh; do
    IT_DATA="$W/data" UILOG_TEST_DATA="$W/data" BRIDGE_TEST_DATA="$W/data" BRIDGE_TEST_SYS="$W/system" TIMER_TEST_SYS="$W/system" BL_TEST_DATA="$W/data" BL_TEST_SYS="$W/system" DONGLE_TEST_DATA="$W/data" DONGLE_TEST_SYS="$W/system" /usr/bin/timeout 1 mksh "$script" > "$W/out" 2>&1
    rc=$?
    check "autostart defers before spawning dependencies: $script" eval 'test "$rc" = 0 && grep -qx "DEFERRED installation in progress" "$W/out"'
done
rm "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
IT_DATA="$W/data" mksh -c '. tools/diagnostics/install-hold.sh; install_hold' > "$W/out" 2>&1
check 'interrupted same-boot install stays held after worker exits' test $? = 0
echo "$$" > "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
# Stale hold cannot disable the recovery collector on another boot.
echo '00000000-0000-0000-0000-000000000000' > "$W/data/nemesis/gen5wkr.install-hold"
IT_DATA="$W/data" mksh -c '. tools/diagnostics/install-hold.sh; ! install_hold'
check 'stale prior-boot hold does not disable recovery service startup' test $? = 0
rm -rf "$W"
done_tests service-install-hold
