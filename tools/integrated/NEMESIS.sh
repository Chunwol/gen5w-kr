#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
action=install
if [ -f GEN5W-ACTION ]; then
    IFS= read -r action < GEN5W-ACTION || [ -n "$action" ] || exit 1
    action=${action%$'\r'}
fi
case "$action" in install|update|rollback|remove|status|wired-only|check) ;;
    *) echo 'REFUSED unknown GEN5W-ACTION'; exit 1;; esac
# Only fixed phase names and exit codes; never copy subprocess output or secrets.
[ ! -L GEN5W-REPORT ] || exit 1
mkdir -p GEN5W-REPORT || exit 1
[ ! -L GEN5W-REPORT/STARTUP.txt ] || exit 1
echo "action=$action" > GEN5W-REPORT/STARTUP.txt || exit 1
/system/bin/sh "./$action.sh" > GEN5W-REPORT/EXEC_LOG.txt 2>&1
status=$?
cat GEN5W-REPORT/EXEC_LOG.txt 2>/dev/null
echo "exit=$status" >> GEN5W-REPORT/STARTUP.txt
sync
exit "$status"
