#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./common.sh
acquire || exit 1
reset_results
# Stop and prove our services stopped before any restore hook runs, the same
# way install and rollback do. NEMESIS itself stops a service only after its
# preuninstall hook, and our hooks run even earlier than that.
progress '제거 준비 중: 기존 기능을 잠시 멈추고 확인합니다(1분 정도). USB를 빼지 마세요.'
if q_legacy_version; then report 'WARNING legacy removal: service stop cannot be verified; update NEMESIS separately after removal'
else q_begin || exit 1; fi
begin || exit 1
Q_MUTATING=1
set_state removing || exit 1
rm_step=0; rm_steps=$(count_ids "$REVERSE")
for id in $REVERSE; do
    rm_step=$((rm_step + 1))
    progress "제거 중 ($rm_step/$rm_steps) $(step_name "$id"). USB를 빼지 마세요."
    : > "$TX/attempt.$id"; sync
    safe_remove "$id" || { result "$id" failed; rollback_transaction; exit 1; }
    result "$id" removed
    report "REMOVED $id"
done
[ ! -L "$WIRELESS_OFF" ] && rm -f "$WIRELESS_OFF" || { rollback_transaction; exit 1; }
[ ! -L "$AP_MATCH" ] && [ ! -L "$AP_FEATURE" ] && rm -f "$AP_MATCH" "$AP_FEATURE" || { rollback_transaction; exit 1; }
clear_own_logs
finish remove
