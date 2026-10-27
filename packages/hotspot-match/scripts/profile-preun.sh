#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/profile-common.sh"
clear_ready || exit 1
inspect || exit $?
[ "$PROFILE_OWNED" = yes ] || { log 'No owned hotspot changes'; exit 0; }
begin_stop || exit 1
"$NEM" remount rw >/dev/null 2>&1 || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
restore_target && stage_clear && cleanup_owned || exit 1
sync
sys_ro || exit 1
trap - EXIT
log 'RESTORED hotspot: exact original services ODEX bytes'
exit 0
