#!/system/bin/sh
# Registered background mode: no NEMESIS restart loop after a startup failure.
BASE=${0%/*}
exec /system/bin/sh "$BASE/boot.sh" run
