#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./errors.sh
. ./history.sh
# Entry policy runs before common.sh creates a transaction/report context.
report() { echo "$*"; }
. ./services.sh
NEM=${IT_NEM:-/system/xbin/nemesis}
action=install
if [ -f GEN5W-ACTION ]; then
    IFS= read -r action < GEN5W-ACTION || [ -n "$action" ] || exit 1
    action=${action%$'\r'}
fi
case "$action" in install|update|rollback|remove|stock-recover|status|wired-only|check|diag|recovery-prepare) ;;
    *) echo 'REFUSED unknown GEN5W-ACTION'; exit 1;; esac
requested_action=$action
entry_install_supported=no
case "$action" in install|update)
    if q_install_version >/dev/null 2>&1; then
            entry_install_supported=yes
            case "$(cat "${IT_DATA:-/data}/nemesis/gen5w-kr-integrated/state" 2>/dev/null)" in
                recovery-required|recovering|applying|removing)
                    GEN5W_RECOVERY_NEXT=$action; export GEN5W_RECOVERY_NEXT
                    action=stock-recover;;
            esac
    fi;;
esac
case "$action" in check|diag|status) ERR_PERSIST=no; export ERR_PERSIST;; esac
# Only fixed phase names and exit codes; never copy subprocess output or secrets.
# The read-only diagnosis keeps the install report: it uses its own file names.
start=STARTUP.txt log=EXEC_LOG.txt
[ "$action" != diag ] || { start=DIAG_STARTUP.txt; log=DIAG_EXEC_LOG.txt; }
[ ! -L GEN5W-REPORT ] || exit 1
mkdir -p GEN5W-REPORT || exit 1
[ ! -L "GEN5W-REPORT/$start" ] && [ ! -L "GEN5W-REPORT/$log" ] || exit 1
[ ! -L GEN5W-REPORT/ENTRY_STATUS.txt ] || exit 1
persist_after_boot=${ERR_PERSIST:-yes}
ERR_PERSIST=no
export ERR_PERSIST
report_attempt_begin "$action" || { err_event integrated entry archive failed 1 unsafe-or-unwritable; exit 1; }
echo "action=$action" > "GEN5W-REPORT/$start" || exit 1
echo "attempt=$ERR_ATTEMPT" >> "GEN5W-REPORT/$start" || exit 1
# NEMESIS 1.15 runs type=execute without asking while Android is down. Only
# run once Android has booted and the Yes/No dialog was answered.
boot_rc=0
boot_status=$(err_run integrated entry boot-ready getprop sys.boot_completed 2> GEN5W-REPORT/ENTRY_STATUS.txt) || boot_rc=$?
if [ "$boot_rc" != 0 ] || [ "$boot_status" != 1 ]; then
    echo 'refused=android-not-ready' >> "GEN5W-REPORT/$start"
    echo "boot_probe_rc=$boot_rc" >> "GEN5W-REPORT/$start"
    echo 'REFUSED Android is not ready; plug the USB in again after boot'
    exit 1
fi
ERR_PERSIST=$persist_after_boot
export ERR_PERSIST
err_event integrated entry "$action" started 0 android-ready
run_entry_action() {
    typeset action_rc=0 recovery_rc=0 completed_boot= current_boot= recovery_root=${IT_DATA:-/data}/nemesis/gen5w-kr-integrated
    case "$action" in install|update)
        if [ "$entry_install_supported" = yes ] && [ -f "$recovery_root/stock-recovered-boot" ]; then
            IFS= read -r completed_boot < "$recovery_root/stock-recovered-boot" || return 1
            IFS= read -r current_boot < /proc/sys/kernel/random/boot_id || return 1
            [ "$completed_boot" != "$current_boot" ] || { echo 'REFUSED full reboot required after stock recovery before installation'; return 1; }
        fi;;
    esac
    "${IT_SHELL:-/system/bin/sh}" "./$action.sh" || action_rc=$?
    # A failed install already tried snapshot rollback. If that also failed,
    # recover stock once under a newly acquired lock; never recurse into install.
    case "$action:$action_rc" in install:0|update:0) ;;
        install:*|update:*)
            if [ "$entry_install_supported" = yes ] && [ "$(cat "${IT_DATA:-/data}/nemesis/gen5w-kr-integrated/state" 2>/dev/null)" = recovery-required ]; then
                echo 'AUTOMATIC STOCK RECOVERY: prior rollback failed; preserving original install failure'
                "${IT_SHELL:-/system/bin/sh}" ./stock-recover.sh || recovery_rc=$?
                echo "automatic_stock_recovery_exit=$recovery_rc"
            fi;;
    esac
    return "$action_rc"
}
if run_entry_action 2>&1 | report_stream "GEN5W-REPORT/$log"; then
    statuses=("${PIPESTATUS[@]}")
else
    statuses=("${PIPESTATUS[@]}")
fi
operation_status=${statuses[0]}
status=$operation_status
if [ "$operation_status" = 0 ];then operation_result=completed;else operation_result=failed;fi
err_event integrated entry "$action" "$operation_result" "$operation_status" operation-status
if [ "${statuses[1]}" != 0 ];then
    err_event integrated export report failed "${statuses[1]}" write-failed
    [ "$status" != 0 ] || status=1
fi
cat "GEN5W-REPORT/$log" 2>/dev/null
echo "exit=$status" >> "GEN5W-REPORT/$start"
echo "operation_exit=$operation_status" >> "GEN5W-REPORT/$start"
echo "report_exit=${statuses[1]}" >> "GEN5W-REPORT/$start"
# A failed change never just stops. If it left our services held or the
# change unfinished, the only way on is a cold reboot (the installer itself
# refuses to go further in this boot). Do that reboot now instead of leaving
# the unit half-stopped, and leave the USB ready for the next step:
#  - nothing changed: the same action runs again when the USB is inserted;
#  - change unfinished (recovery-required): the next run restores stock.
# At most 2 automatic reboots in a row for one build, so a repeating failure
# cannot loop; then it stops and says so. Never reboots for check/diag/status.
say() { echo "$*"; [ -L "GEN5W-REPORT/$log" ] || echo "$*" >> "GEN5W-REPORT/$log"; }
auto_reboot_after_failure() {
    typeset tx=${IT_DATA:-/data}/nemesis/gen5w-kr-integrated base=${IT_DATA:-/data}/nemesis
    typeset boot= held= state= uncertain= why= rev= count=0 last= counter
    counter=$tx/auto-reboot
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 0
    [ -f "$base/gen5wkr.install-hold" ] && [ ! -L "$base/gen5wkr.install-hold" ] &&
        IFS= read -r held < "$base/gen5wkr.install-hold" && [ "$held" = "$boot" ] && why=services-held
    [ -f "$tx/service-uncertain" ] && [ ! -L "$tx/service-uncertain" ] &&
        IFS= read -r uncertain < "$tx/service-uncertain" && [ "$uncertain" = "$boot" ] && why=${why:-stop-proof-uncertain}
    state=$(cat "$tx/state" 2>/dev/null)
    case "$state" in recovery-required|recovering|applying|removing) why=recovery-required;; esac
    [ -n "$why" ] || return 0
    [ -f BUILD-REVISION ] && IFS= read -r rev < BUILD-REVISION
    if [ -f "$counter" ] && [ ! -L "$counter" ]; then IFS=' ' read -r last count < "$counter"; fi
    case "$count" in ''|*[!0-9]*) count=0;; esac
    [ "$last" = "$rev" ] || count=0
    if [ "$count" -ge 2 ]; then
        say "AUTO REBOOT STOPPED: failed again after $count automatic reboots ($why); no further automatic reboot"
        say 'NEXT: turn the car off and on once, then send GEN5W-REPORT for analysis'
        return 0
    fi
    [ -L "$counter" ] || echo "$rev $((count + 1))" > "$counter"
    if [ "$why" = recovery-required ]; then
        case "$requested_action" in install|update|stock-recover) ;;
            *) [ -L GEN5W-ACTION ] || echo stock-recover > GEN5W-ACTION;;
        esac
        say "AUTO REBOOT ($why): change unfinished; after reboot, insert this USB again to restore stock automatically"
        value='Gen5W 작업이 끝나지 않아 재부팅합니다. 재부팅 후 USB를 다시 꽂으면 순정 복구를 진행합니다.'
    else
        say "AUTO REBOOT ($why): nothing was changed; rebooting to release stopped services. Insert this USB again to retry"
        value='Gen5W 작업을 시작하지 못해 재부팅합니다. 바뀐 것은 없습니다. 재부팅 후 USB를 다시 꽂으면 다시 시도합니다.'
    fi
    echo "auto_reboot=$why" >> "GEN5W-REPORT/$start"
    [ ! -x /system/bin/am ] || /system/bin/am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$value" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || :
    sync
    [ "${IT_NO_REBOOT:-0}" != 1 ] || { echo 'auto_reboot=suppressed-by-test' >> "GEN5W-REPORT/$start"; return 0; }
    sleep 5
    if [ -x /system/bin/d_audio ]; then /system/bin/d_audio -c reboot force_normal; else /system/bin/reboot force_normal || /system/bin/reboot; fi
}
case "$action:$status" in
    install:0|update:0|remove:0|rollback:0|stock-recover:0|wired-only:0)
        rm -f "${IT_DATA:-/data}/nemesis/gen5w-kr-integrated/auto-reboot" 2>/dev/null;;
    install:*|update:*|remove:*|rollback:*|stock-recover:*|wired-only:*)
        auto_reboot_after_failure;;
esac
sync
exit "$status"
