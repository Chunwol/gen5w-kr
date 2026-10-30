#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
BG="$W/data/nemesis/gen5wkr.bootguard"
mkdir -p "$BG"
printf 'armed\n' > "$BG/armed"
printf '2\n' > "$BG/count"
printf '3\n' > "$BG/max"

run_helper() {
    env BOOTGUARD_STATE_DIR="$BG" BOOTGUARD_BOOT_ID="${BOOTGUARD_BOOT_ID:-boot-a}" \
        mksh "$ROOT/packages/wireless-bridge/scripts/bootguard-state.sh" "$@"
}

check 'bootguard helper exists and begins under the limit' run_helper begin
check 'begin increments the durable count' grep -qx '3' "$BG/count"
check 'begin is idempotent within one boot' run_helper begin
check 'duplicate begin does not increment the count' grep -qx '3' "$BG/count"

BOOTGUARD_BOOT_ID=boot-b
run_helper begin
rc=$?
check 'failure limit requests recovery' test "$rc" = 2
check 'limit increment is durable' grep -qx '4' "$BG/count"

check 'mark-ok succeeds after a completed boot' run_helper mark-ok
check 'mark-ok resets the consecutive failure count' grep -qx '0' "$BG/count"
check 'mark-ok keeps the guard directory armed for later boots' test -d "$BG"
check 'mark-ok records a durable boot-ok marker' grep -qx 'boot-ok' "$BG/boot-ok"

rm -f "$BG/armed"
if run_helper mark-ok; then
    bad 'mark-ok refuses an unarmed guard'
else
    ok 'mark-ok refuses an unarmed guard'
fi

done_tests bootguard-runtime
