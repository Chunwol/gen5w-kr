#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
# Installed on its own, post.sh would reboot into the change without the
# boot-loop guard, which only the release bundle arms. Every bundle step
# creates the reboot-suppression file before running this check.
if [ -z "$AUDIO_TEST_SYS" ] && [ ! -f "$NOREBOOT" ]; then
    log 'FAIL: install this package with the release bundle (GEN5W-ACTION), not on its own'
    exit 1
fi
inspect || exit $?
dependencies || exit $?
log "READY audio: exact $AUDIO_RECIPE ABI and codec dependencies identified"
exit 0
