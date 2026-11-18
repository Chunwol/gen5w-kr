#!/system/bin/sh
# boot.sh retains its rescue outside this package before any maintenance begins.
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
/system/bin/sh "$BASE/debug.sh" off || exit 1
exec /system/bin/sh "$BASE/boot.sh" disable
