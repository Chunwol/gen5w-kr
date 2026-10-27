#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
SCRIPT_DIR=$SCRIPT_DIR/../scripts
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
log "Audio library: $AUDIO_STATE; owned original: $AUDIO_OWNED"
exit 0
