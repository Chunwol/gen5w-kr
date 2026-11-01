#!/system/bin/sh
. ./scripts/common.sh
state_load || exit 1
state_discard_stale || exit 1
[ -e "$STATE" ] || { log 'No owned system changes'; exit 0; }
"$NEM" remount rw >/dev/null 2>&1 || exit 1
state_restore
rc=$?
"$NEM" remount ro >/dev/null 2>&1
[ "$rc" = 0 ] || { log 'FAIL: restoration refused/incomplete; backups retained'; exit 1; }
log 'RESTORED: original system bytes and targeted runtime properties'
exit 0
