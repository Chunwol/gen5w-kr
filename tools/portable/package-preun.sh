#!/system/bin/sh
# boot.sh retains its rescue outside this package before any maintenance begins.
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
/system/bin/sh "$BASE/debug.sh" off || exit 1
# Give the Bluelink reminder its own values back (settings file only).
/system/bin/sh "$BASE/bluelink/preun.sh" || :
exec /system/bin/sh "$BASE/boot.sh" disable
