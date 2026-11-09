#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
. ./errors.sh
. ./history.sh
action=install
if [ -f GEN5W-ACTION ]; then
    IFS= read -r action < GEN5W-ACTION || [ -n "$action" ] || exit 1
    action=${action%$'\r'}
fi
case "$action" in install|update|rollback|remove|status|wired-only|check|diag|recovery-prepare) ;;
    *) echo 'REFUSED unknown GEN5W-ACTION'; exit 1;; esac
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
if "${IT_SHELL:-/system/bin/sh}" "./$action.sh" 2>&1 | report_stream "GEN5W-REPORT/$log"; then
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
sync
exit "$status"
