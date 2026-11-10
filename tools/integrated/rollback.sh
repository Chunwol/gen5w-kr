#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
acquire || exit 1
[ ! -e "$TX/stock-recovery-mode" ] && [ ! -L "$TX/stock-recovery-mode" ] || {
    report 'REFUSED snapshot rollback after stock recovery; use GEN5W-ACTION=stock-recover'; exit 1;
}
[ -f "$TX/prior/complete" ] || { report 'No complete previous transaction'; exit 1; }
[ ! -L "$NOREBOOT" ] || { report 'REFUSED linked reboot suppression'; exit 1; }
if [ -e "$NOREBOOT" ]; then
    case "$(cat "$TX/state" 2>/dev/null)" in applying|removing|recovering|recovery-required) ;;
        *) report 'REFUSED reboot suppression owned by another operation'; exit 1;; esac
fi
# Once this operation owns suppression, every failed exit remains retryable.
trap 'rc=$?; if [ "$rc" != 0 ]; then [ -L "$NOREBOOT" ] || : > "$NOREBOOT"; set_state recovery-required; fi; transaction_exit "$rc"' EXIT
: > "$NOREBOOT" || exit 1
KEEP_NOREBOOT=1
rollback_transaction || exit 1
bootguard_reconcile_previous rolled-back || {
    : > "$NOREBOOT"
    report 'RECOVERY REQUIRED: previous boot guard could not be reconciled; no reboot'
    exit 1
}
rm -f "$NOREBOOT" || { report 'RECOVERY REQUIRED: reboot suppression could not be cleared'; exit 1; }
set_state rolled-back || { report 'RECOVERY REQUIRED: rollback state could not be recorded'; exit 1; }
trap 'transaction_exit $?' EXIT
write_summary || echo '결과 문서를 USB에 저장하지 못했습니다.'
sync
# Rollback rewrites patched ODEX too: boot cold like install and remove.
cold_reboot
