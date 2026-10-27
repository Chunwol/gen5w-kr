#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
dependencies || exit $?
log "READY audio: exact $AUDIO_RECIPE ABI and codec dependencies identified"
exit 0
