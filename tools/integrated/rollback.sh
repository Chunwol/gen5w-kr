#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
acquire || exit 1
[ -f "$TX/prior/complete" ] || { report 'No complete previous transaction'; exit 1; }
if [ -e "$NOREBOOT" ]; then
    case "$(cat "$TX/state" 2>/dev/null)" in applying|removing|recovering|recovery-required) ;;
        *) report 'REFUSED reboot suppression owned by another operation'; exit 1;; esac
fi
: > "$NOREBOOT"
KEEP_NOREBOOT=1
rollback_transaction || exit 1
bootguard_reconcile_previous rolled-back || {
    : > "$NOREBOOT"
    report 'RECOVERY REQUIRED: previous boot guard could not be reconciled; no reboot'
    exit 1
}
rm -f "$NOREBOOT" || { report 'RECOVERY REQUIRED: reboot suppression could not be cleared'; exit 1; }
write_summary || echo '결과 문서를 USB에 저장하지 못했습니다.'
sync
[ "${IT_NO_REBOOT:-0}" = 1 ] || /system/bin/reboot
