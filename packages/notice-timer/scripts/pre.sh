#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
dependencies || exit $?
log "READY notice: exact $NOTICE_RECIPE SystemUI pair identified"
exit 0
