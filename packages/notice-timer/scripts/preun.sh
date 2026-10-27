#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
[ "$NOTICE_OWNED" = yes ] || { log 'No owned notice changes'; exit 0; }
"$NEM" remount rw >/dev/null 2>&1 || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
restore_target && stage_clear && cleanup_owned || exit 1
sync
sys_ro || exit 1
trap - EXIT
log 'RESTORED notice: exact original SystemUI ODEX bytes'
exit 0
