#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/profile-common.sh"
inspect || exit $?
dependencies || exit $?
log "READY hotspot: exact $PROFILE_RECIPE services/framework pair identified"
exit 0
