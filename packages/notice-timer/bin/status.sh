#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
SCRIPT_DIR=$SCRIPT_DIR/../scripts
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
log "Stock warning timer: $NOTICE_STATE; owned original: $NOTICE_OWNED"
exit 0
