#!/system/bin/sh
# Runs as system (the Bluelink apps' own uid). After boot, keeps the reminder
# time far in the future; the stock service can restore an older time from a
# driver profile, so it is checked again every 15 seconds (cheap grep only).
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
GETPROP=${BL_TEST_GETPROP:-getprop}
stock_apps || { log 'bluelink: apps are not the checked stock build; reminder left stock'; exit 0; }
[ -f "$ORIG" ] || { log 'bluelink: original values not saved; reminder left stock'; exit 0; }
until [ "$($GETPROP sys.boot_completed)" = 1 ]; do sleep 5; done
failed=
while [ ! -e "$STOPPING" ]; do
    if [ -d "$PREFS_DIR" ] && ! hidden; then
        if write_prefs hide; then
            log 'bluelink: monthly reminder hidden'; failed=
        elif [ -z "$failed" ]; then
            log 'bluelink: settings file not in the expected shape; left unchanged'; failed=1
        fi
    fi
    [ -z "$BL_TEST_ONCE" ] || break
    sleep 15
done
exit 0
