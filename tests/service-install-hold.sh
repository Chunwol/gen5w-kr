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
    case "$script" in
        # mode=restart: exiting would make NEMESIS relaunch it in a loop.
        packages/core/scripts/owner.sh|packages/core/scripts/uilog.sh) want=124;;
        *) want=0;;
    esac
    check "autostart defers before spawning dependencies: $script" eval 'test "$rc" = "$want" && grep -qx "DEFERRED installation in progress" "$W/out"'
done
# Every mode=restart service must wait (same PID) instead of exiting while held.
for data in packages/*/NEMESIS.data tools/usb-wifi/package/NEMESIS.data; do
    while read -r path; do
        f=${data%/NEMESIS.data}/$path
        check "restart-mode service waits instead of exiting while held: $f" eval 'grep -qx install_hold_wait "$f" && ! grep -q "install_hold && exit" "$f"'
    done < <(awk '/^\[service/{p=""} /^path=/{p=substr($0,6)} /^mode=restart/{print p}' "$data")
done
# The wait keeps one PID while held and returns once the hold is gone.
IT_DATA="$W/data" mksh -c '. tools/diagnostics/install-hold.sh; install_hold_wait; echo RELEASED' > "$W/wait" 2>&1 &
waiter=$!
sleep 3
check 'held restart-mode service stays alive with the same PID' kill -0 "$waiter"
rm "$W/data/nemesis/gen5wkr.install-hold"
for i in 1 2 3 4 5 6; do kill -0 "$waiter" 2>/dev/null || break; sleep 1; done
wait "$waiter"; wrc=$?
check 'held service continues after the hold is released' eval 'test "$wrc" = 0 && grep -qx RELEASED "$W/wait" && test "$(grep -c DEFERRED "$W/wait")" = 1'
cat /proc/sys/kernel/random/boot_id > "$W/data/nemesis/gen5wkr.install-hold"
echo "$$:$start" >> "$W/data/nemesis/gen5wkr.install-hold"
IT_DATA="$W/data" mksh -c '. tools/diagnostics/install-hold.sh; rm "$IT_DATA/nemesis/gen5wkr.noreboot"; install_hold_wait; echo RAN' > "$W/wait" 2>&1
check 'no hold: restart-mode service starts at once' grep -qx RAN "$W/wait"
: > "$W/data/nemesis/gen5wkr.noreboot"
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
