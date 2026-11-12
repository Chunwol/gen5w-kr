#!/system/bin/sh
# boot.sh retains its rescue outside this package before any maintenance begins.
BASE=${0%/*}
exec /system/bin/sh "$BASE/boot.sh" disable
