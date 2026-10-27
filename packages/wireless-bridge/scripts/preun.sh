#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
[ "$BRIDGE_OWNED" = yes ] || exit 0
[ ! -L "$STOPPING" ] || exit 1
echo "$OWNER" > "$STOPPING" || exit 1
if [ -z "$BRIDGE_TEST_SYS" ]; then
    /system/bin/am broadcast -a kr.gen5w.wireless.STOP_BRIDGE >/dev/null 2>&1
    sleep 2
fi
"$NEM" remount rw >/dev/null 2>&1 || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
restore_target && stage_clear && cleanup_owned || exit 1
sync
sys_ro || exit 1
trap - EXIT
log 'RESTORED bridge: original ODEX bytes and attributes restored'
