#!/system/bin/sh
# Registered background mode: no NEMESIS restart loop after a startup failure.
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
exec /system/bin/sh "$BASE/boot.sh" run
