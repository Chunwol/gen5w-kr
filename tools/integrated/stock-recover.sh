#!/system/bin/sh
# Explicit stock recovery, never restore/reinstall a prior package generation.
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
acquire || exit 1
case "$(cat "$TX/state" 2>/dev/null)" in
    recovery-required|recovering|applying|removing|committed|rolled-back) ;;
    *) report 'REFUSED stock recovery: unknown transaction state'; exit 1;;
esac
for path in "$NOREBOOT" "$WIRELESS_OFF" "$AP_MATCH" "$AP_FEATURE" "$TX/stock-recovered" "$TX/stock-recovered-boot" "$TX/stock-recovery-mode"; do
    [ ! -L "$path" ] && { [ ! -e "$path" ] || [ -f "$path" ]; } || exit 1
done
if [ -f RECOVERY.md5 ]; then
    . ./recovery-lib.sh
    r_prepare || { report "REFUSED stock recovery bundle: $recovery_reason"; exit 1; }
fi
# Verify every recovery tree before changing any target, even if currently absent.
for id in $ALL_IDS gen5w.kr.dongle; do
    bundle_has "$id" || { report "REFUSED stock recovery: missing verified hook $id"; exit 1; }
done
stock_runtime=$("$NEM" version 2>/dev/null) || stock_runtime=unknown
case "$stock_runtime" in
    1.16.4|1.16.5|1.16.6|1.16.7) q_begin || exit 1;;
    *) q_legacy_version || { report 'REFUSED stock recovery: unknown NEMESIS runtime'; exit 1; }
       report 'WARNING legacy stock recovery: service restart suppression cannot be verified';;
esac
trap 'rc=$?; if [ "$rc" != 0 ]; then [ -L "$NOREBOOT" ] || : > "$NOREBOOT"; set_state recovery-required; fi; transaction_exit "$rc"' EXIT
: > "$NOREBOOT" || exit 1
echo stock-recover > "$TX/stock-recovery-mode" || exit 1
set_state recovering || exit 1
Q_MUTATING=1
# Do not call begin, finish, or rollback_transaction: all can reinstall prior ZIPs.
for id in $REVERSE; do
    safe_remove "$id" || { result "$id" recovery-required; report "RECOVERY REQUIRED: stock removal failed $id"; exit 1; }
    [ ! -e "$APPS/$id" ] && [ ! -L "$APPS/$id" ] || exit 1
    result "$id" removed
done
for id in $ALL_IDS gen5w.kr.dongle; do
    bundle_remove_hook "$id" || { report "RECOVERY REQUIRED: stock verification failed $id"; exit 1; }
done
# Never waive an unknown remount failure. Independently observe the mount flags.
stock_mount_ro() {
    local source point kind options rest count=0 readonly=no mounts=${IT_MOUNTS:-/proc/self/mounts}
    [ -f "$mounts" ] && [ ! -L "$mounts" ] || return 1
    while IFS=' ' read -r source point kind options rest; do
        [ "$point" = "$SYS" ] || continue
        count=$((count+1))
        case ",$options," in *,ro,*) readonly=yes;; *) readonly=no;; esac
    done < "$mounts"
    [ "$count" = 1 ] && [ "$readonly" = yes ]
}
sync
if ! stock_mount_ro; then
    err_mount integrated ro "$NEM" || { report 'RECOVERY REQUIRED: stock bytes restored but read-only remount failed; no reboot'; exit 1; }
    stock_mount_ro || { report 'RECOVERY REQUIRED: read-only system mount not verified; no reboot'; exit 1; }
fi
bootguard_reconcile_previous rolled-back && bootguard_arm remove && bootguard_reconcile_previous committed || {
    report 'RECOVERY REQUIRED: stock boot guard finalization failed'; exit 1;
}
rm -f "$WIRELESS_OFF" "$AP_MATCH" "$AP_FEATURE" || exit 1
echo verified > "$TX/stock-recovered" || exit 1
IFS= read -r stock_boot < /proc/sys/kernel/random/boot_id || exit 1
echo "$stock_boot" > "$TX/stock-recovered-boot" || exit 1
rm -f "$NOREBOOT" || exit 1
set_state committed || exit 1
q_resume || exit 1
case "$stock_runtime" in 1.16.4|1.16.5|1.16.6|1.16.7) ;;
    *)
        [ ! -L GEN5W-ACTION ] && echo status > GEN5W-ACTION || exit 1
        report 'NEXT: official NEMESIS update required after full reboot; installation refused on legacy runtime';;
esac
case "$stock_runtime:${GEN5W_RECOVERY_NEXT:-}" in
    1.16.[4567]:install|1.16.[4567]:update)
        [ ! -L GEN5W-ACTION ] && echo "$GEN5W_RECOVERY_NEXT" > GEN5W-ACTION || exit 1
        report 'NEXT: recovery completed; full reboot and supported NEMESIS required before installation';;
esac
report 'STOCK RECOVERY COMPLETE: prior package snapshot retained, never reinstalled'
write_summary || exit 1
sync
cold_reboot
