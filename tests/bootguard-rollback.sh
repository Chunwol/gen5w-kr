#!/bin/bash
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp "$ROOT/tools/integrated/rollback.sh" "$W/rollback.sh"
cat > "$W/common.sh" <<'SH'
TX=$CASE_DIR/transaction
NOREBOOT=$CASE_DIR/no-reboot
acquire() { :; }
report() { printf '%s\n' "$1" >> "$CASE_DIR/report"; }
rollback_transaction() {
    [ "$KEEP_NOREBOOT" = 1 ] || rm -f "$NOREBOOT"
    : > "$CASE_DIR/restored"
}
bootguard_reconcile_previous() {
    printf '%s\n' "$1" > "$CASE_DIR/reconciled"
    [ -f "$NOREBOOT" ] || return 1
    [ "$RECONCILE_FAIL" != 1 ]
}
write_summary() { : > "$CASE_DIR/summary"; }
sync() { :; }
SH
mkdir -p "$W/case/transaction/prior"
touch "$W/case/transaction/prior/complete"
check 'manual rollback reconciles guard' env CASE_DIR="$W/case" IT_NO_REBOOT=1 mksh "$W/rollback.sh"
check 'manual rollback requests rolled-back generation' grep -qx rolled-back "$W/case/reconciled"
check 'successful reconciliation clears reboot suppression' test ! -e "$W/case/no-reboot"
rm -f "$W/case/summary" "$W/case/reconciled"
if env CASE_DIR="$W/case" RECONCILE_FAIL=1 IT_NO_REBOOT=1 mksh "$W/rollback.sh"; then
    bad 'manual rollback refuses unresolved guard'
else
    ok 'manual rollback refuses unresolved guard'
fi
check 'unresolved guard retains reboot suppression' test -f "$W/case/no-reboot"
check 'unresolved guard does not report successful summary' test ! -e "$W/case/summary"
done_tests bootguard-rollback
