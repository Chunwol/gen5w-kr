#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
# Installed on its own, post.sh would reboot into the change without the
# boot-loop guard, which only the release bundle arms. Every bundle step
# creates the reboot-suppression file before running this check.
if [ -z "$BRIDGE_TEST_SYS" ] && [ ! -f "$NOREBOOT" ]; then
    log 'FAIL: install this package with the release bundle (GEN5W-ACTION), not on its own'
    exit 1
fi
inspect || exit $?
if [ "$VERSION" = v039 ] && { [ -e "$SCRIPT_DIR/../app/relay-v039.complete" ] || [ -L "$SCRIPT_DIR/../app/relay-v039.complete" ]; }; then
    relay_packaged || { log 'FAIL bridge: incomplete or unsafe relay payload'; exit 1; }
fi
[ -f "$SCRIPT_DIR/../app/bridge.dex" ] && [ ! -L "$SCRIPT_DIR/../app/bridge.dex" ] &&
    [ -f "$SCRIPT_DIR/../app/wireless-host.apk" ] && [ ! -L "$SCRIPT_DIR/../app/wireless-host.apk" ] || { log 'FAIL bridge: stock projection host absent'; exit 1; }
log 'READY bridge: exact stock APK/ODEX pair and recovery ownership verified'
