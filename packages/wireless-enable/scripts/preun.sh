#!/system/bin/sh
. ./scripts/common.sh
state_load || exit 1
state_discard_stale || exit 1
[ -e "$STATE" ] || { log 'No owned system changes'; exit 0; }
err_mount wireless rw "$NEM" || exit 1
state_restore
rc=$?
err_mount wireless ro "$NEM"
[ "$rc" = 0 ] || { log 'FAIL: restoration refused/incomplete; backups retained'; exit 1; }
log 'RESTORED: original system bytes and targeted runtime properties'
exit 0
