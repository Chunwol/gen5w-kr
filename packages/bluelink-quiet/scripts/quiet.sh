#!/system/bin/sh
HOLD_SCRIPT=${0%/*}/install-hold.sh
. "$HOLD_SCRIPT"
install_hold && exit 0
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
    if [ -d "$PREFS_DIR" ]; then
        if [ -f "$UI_OFF" ]; then
            # Turned off from the in-car screen: give the car its own reminder values back once.
            if hidden; then
                if write_prefs restore "$ORIG"; then
                    log 'bluelink: turned off from the screen; original reminder values restored'; failed=
                elif [ -z "$failed" ]; then
                    log 'bluelink: settings file not in the expected shape; left unchanged'; failed=1
                fi
            fi
        elif ! hidden; then
            if write_prefs hide; then
                log 'bluelink: monthly reminder hidden'; failed=
            elif [ -z "$failed" ]; then
                log 'bluelink: settings file not in the expected shape; left unchanged'; failed=1
            fi
        fi
    fi
    [ -z "$BL_TEST_ONCE" ] || break
    sleep 15
done
exit 0
