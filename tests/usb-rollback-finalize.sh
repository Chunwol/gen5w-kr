#!/bin/bash
# Exercise the actual USB entry point, not the app recovery wrapper.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
stubs
mkdir -p "$W/usb" "$W/data/nemesis/gen5w-kr-integrated/prior"
cp tools/integrated/*.sh "$W/usb/"
cp tools/integrated/bin/zipstore-host "$W/usb/zipstore"
TX=$W/data/nemesis/gen5w-kr-integrated
echo 1 > "$TX/prior/complete"
echo enabled > "$TX/prior/wireless-mode"
: > "$TX/prior/ap-markers"
echo recovery-required > "$TX/state"
: > "$W/data/nemesis/gen5wkr.noreboot"
run() { (cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/system" IT_NO_REBOOT=1 IT_NEM="$W/nemesis" IT_SHELL=$(command -v mksh) PATH="$W/bin:$PATH" mksh rollback.sh > "$W/out" 2>&1); }
mkdir "$W/data/nemesis/gen5wkr.bootguard.previous"
check 'USB rollback reports invalid boot guard as failure' eval '! run && grep -q "previous boot guard could not be reconciled" "$W/out"'
check 'USB finalization failure retains recoverable state and suppression' eval 'grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
rmdir "$W/data/nemesis/gen5wkr.bootguard.previous"
check 'USB rollback can retry after guard failure is resolved' run
check 'USB successful retry publishes final state and clears suppression' eval 'grep -qx rolled-back "$TX/state" && test ! -e "$W/data/nemesis/gen5wkr.noreboot"'
# An unusable suppression path must fail before restoring any package.
echo recovery-required > "$TX/state"
rm -f "$W/data/nemesis/gen5wkr.noreboot"
mkdir "$W/data/nemesis/gen5wkr.noreboot"
check 'USB rollback rejects an unusable suppression path' eval '! run'
check 'USB suppression failure never publishes success' grep -qx recovery-required "$TX/state"
rmdir "$W/data/nemesis/gen5wkr.noreboot"
check 'USB rollback retries after suppression path is repaired' run
# Fail the final unlink only, after rollback has actually restored the snapshot.
printf '#!/bin/sh\nif [ "$IT_FAIL_CLEAR" = 1 ] && [ "$1" = -f ] && [ "$2" = "$IT_DATA/nemesis/gen5wkr.noreboot" ]; then exit 1; fi\nexec /bin/rm "$@"\n' > "$W/bin/rm"
chmod +x "$W/bin/rm"
echo recovery-required > "$TX/state"
: > "$W/data/nemesis/gen5wkr.noreboot"
export IT_FAIL_CLEAR=1
check 'USB final suppression unlink failure is reported' eval '! run && grep -q "reboot suppression could not be cleared" "$W/out"'
check 'USB failed final unlink retains recoverable state' eval 'grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
unset IT_FAIL_CLEAR
check 'USB final unlink failure can be retried' run
# Refuse only the terminal state rename; the failure trap can still record required.
printf '#!/bin/sh\nif [ "$IT_FAIL_FINAL_STATE" = 1 ] && [ "$1" = "$IT_DATA/nemesis/gen5w-kr-integrated/state.tmp" ] && grep -qx rolled-back "$1"; then exit 1; fi\nexec /bin/mv "$@"\n' > "$W/bin/mv"
chmod +x "$W/bin/mv"
echo recovery-required > "$TX/state"
export IT_FAIL_FINAL_STATE=1
check 'USB final state write failure is reported' eval '! run && grep -q "rollback state could not be recorded" "$W/out"'
check 'USB failed terminal state write retains recovery and suppression' eval 'grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
unset IT_FAIL_FINAL_STATE
check 'USB final state write failure can be retried' run
echo recovering > "$TX/state"
: > "$W/data/nemesis/gen5wkr.noreboot"
mkdir "$W/data/nemesis/gen5wkr.bootguard.previous"
resume() { (cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/system" IT_NO_REBOOT=1 IT_NEM="$W/nemesis" IT_SHELL=$(command -v mksh) PATH="$W/bin:$PATH" mksh -c '. ./common.sh; acquire && begin' > "$W/out" 2>&1); }
check 'new operation refuses interrupted rollback with invalid guard' eval '! resume'
check 'interrupted rollback finalization failure retains recovery and suppression' eval 'grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
rmdir "$W/data/nemesis/gen5wkr.bootguard.previous"
echo recovering > "$TX/state"
: > "$W/data/nemesis/gen5wkr.noreboot"
export IT_FAIL_FINAL_STATE=1
check 'automatic rollback refuses failed terminal state recording' eval '! resume'
check 'automatic rollback state failure retains recovery and suppression' eval 'grep -qx recovery-required "$TX/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
unset IT_FAIL_FINAL_STATE
echo recovery-required > "$TX/state"
echo 'FAILED original localhotspot restore' > "$TX/failure"
(cd "$W/usb" && IT_DATA="$W/data" IT_SYSTEM="$W/system" mksh -c '. ./common.sh; reset_results; report "REFUSED unresolved system recovery required"') > "$W/out" 2>&1
check 'refusal preserves the first original recovery cause' eval '[ "$(head -n 1 "$TX/failure")" = "FAILED original localhotspot restore" ]'
done_tests 'USB rollback finalization'
