#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect
rc=$?
# Not ours (no system journal): nothing to restore. A firmware reinstall may have
# left our runtime copy of the stock library in /data; drop it.
if [ "$rc" = 77 ] || { [ "$rc" = 0 ] && [ "$AUDIO_OWNED" = no ]; }; then
    clear_runtime_copy || exit 1
    log 'No owned audio changes'
    exit 0
fi
[ "$rc" = 0 ] || exit "$rc"
err_mount audio rw "$NEM" || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
restore_target && stage_clear && cleanup_owned || exit 1
sync
sys_ro || exit 1
trap - EXIT
log 'RESTORED audio: exact original library bytes'
exit 0
