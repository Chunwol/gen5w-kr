#!/system/bin/sh
# Stops the service and puts the car's own reminder values back.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
[ ! -L "$STATE" ] && [ ! -L "$STOPPING" ] || exit 1
mkdir -p "$STATE" && echo stop > "$STOPPING" || exit 1
[ -n "$BL_TEST_DATA" ] || sleep 2
if [ -f "$ORIG" ] && [ ! -L "$ORIG" ] && [ -d "$PREFS_DIR" ]; then
    if [ -f "$PREFS" ] || [ -s "$ORIG" ]; then
        write_prefs restore "$ORIG" || { log 'FAILED bluelink: could not restore the reminder values'; exit 1; }
    fi
fi
rm -rf "$STATE"
log 'RESTORED bluelink: original reminder values put back'
exit 0
