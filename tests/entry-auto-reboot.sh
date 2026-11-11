#!/bin/bash
# A failed change that leaves services held or the change unfinished reboots
# by itself (at most twice in a row per build) instead of just stopping.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
mkdir -p "$W/usb" "$W/bin" "$W/data/nemesis/gen5w-kr-integrated"
cp tools/integrated/{NEMESIS.sh,errors.sh,history.sh,services.sh} "$W/usb/"
echo abcdef01 > "$W/usb/BUILD-REVISION"
printf '#!/bin/sh\necho 1\n' > "$W/bin/getprop"; chmod +x "$W/bin/getprop"
for a in install update remove diag; do printf '#!/bin/sh\necho "FAILED synthetic %s"\nexit 1\n' "$a" > "$W/usb/$a.sh"; done
BOOT=$(cat /proc/sys/kernel/random/boot_id)
TX=$W/data/nemesis/gen5w-kr-integrated
run() { (cd "$W/usb" && PATH="$W/bin:$PATH" IT_SHELL=mksh IT_DATA="$W/data" IT_NO_REBOOT=1 ERR_DIR="$W/private" mksh NEMESIS.sh > "$W/out" 2>&1); }
st() { cat "$W/usb/GEN5W-REPORT/STARTUP.txt"; }
act() { echo "$1" > "$W/usb/GEN5W-ACTION"; }

act install; echo "$BOOT" > "$W/data/nemesis/gen5wkr.install-hold"; echo committed > "$TX/state"
run
check 'nothing changed but services held: reboots by itself' eval 'st | grep -qx auto_reboot=services-held'
check 'the reason and the retry step are on screen and in the USB log' eval 'grep -q "AUTO REBOOT (services-held): nothing was changed" "$W/out" && grep -q "AUTO REBOOT (services-held)" "$W/usb/GEN5W-REPORT/EXEC_LOG.txt"'
check 'the USB keeps the same action for the retry' grep -qx install "$W/usb/GEN5W-ACTION"
check 'reboot count is kept per build' grep -qx 'abcdef01 1' "$TX/auto-reboot"
run
check 'second failure in a row still reboots' eval 'st | grep -qx auto_reboot=services-held && grep -qx "abcdef01 2" "$TX/auto-reboot"'
run
check 'third failure in a row stops rebooting (no loop)' eval '! st | grep -q auto_reboot= && grep -q "AUTO REBOOT STOPPED" "$W/out"'
echo 'other 2' > "$TX/auto-reboot"
run
check 'a new build starts counting again' eval 'st | grep -qx auto_reboot=services-held && grep -qx "abcdef01 1" "$TX/auto-reboot"'

rm -f "$TX/auto-reboot"
echo 00000000-0000-0000-0000-000000000000 > "$W/data/nemesis/gen5wkr.install-hold"
run
check 'hold from an earlier boot is not a reason to reboot' eval '! st | grep -q auto_reboot='
rm -f "$W/data/nemesis/gen5wkr.install-hold"
run
check 'plain refusal with services running: no reboot' eval '! st | grep -q auto_reboot= && test ! -e "$TX/auto-reboot"'

echo "$BOOT" > "$TX/service-uncertain"
run
check 'uncertain stop proof in this boot reboots' eval 'st | grep -qx auto_reboot=stop-proof-uncertain'
rm -f "$TX/service-uncertain" "$TX/auto-reboot"

act remove; echo recovery-required > "$TX/state"
run
check 'unfinished change reboots and sets the USB to restore stock' eval 'st | grep -qx auto_reboot=recovery-required && grep -qx stock-recover "$W/usb/GEN5W-ACTION"'
rm -f "$TX/auto-reboot"
act update
run
check 'unfinished update keeps update (entry turns it into stock recovery)' eval 'st | grep -qx auto_reboot=recovery-required && grep -qx update "$W/usb/GEN5W-ACTION"'

rm -f "$TX/auto-reboot"; echo "$BOOT" > "$W/data/nemesis/gen5wkr.install-hold"
act diag
run
check 'read-only diagnosis never reboots' eval 'test ! -e "$TX/auto-reboot" && ! grep -q "AUTO REBOOT" "$W/out"'

echo 'abcdef01 1' > "$TX/auto-reboot"; echo committed > "$TX/state"
act install; printf '#!/bin/sh\necho OK\nexit 0\n' > "$W/usb/install.sh"
run
check 'success clears the reboot count' test ! -e "$TX/auto-reboot"
rm -rf "$W"
done_tests entry-auto-reboot
