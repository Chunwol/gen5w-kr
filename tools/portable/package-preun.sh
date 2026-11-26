#!/system/bin/sh
# boot.sh retains its rescue outside this package before any maintenance begins.
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
/system/bin/sh "$BASE/debug.sh" off || exit 1
# Give the Bluelink reminder its own values back (settings file only).
/system/bin/sh "$BASE/bluelink/preun.sh" || :
# Restore only our owned network-ADB values before disabling startup.
/system/bin/sh "$BASE/network-adb.sh" restore || exit 1
exec /system/bin/sh "$BASE/boot.sh" disable
