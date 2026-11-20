#!/system/bin/sh
# Background work yields the CPU to Android (zygote, system_server, stock apps);
# children inherit it. VM 2026-11-21: polling at normal priority starved a stock
# provider until the system_server watchdog reset the unit.
renice 10 $$ >/dev/null 2>&1
# Registered background mode: no NEMESIS restart loop after a startup failure.
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
TEST_ROOT=${PORTABLE_TEST_ROOT:-}
SH=${PORTABLE_TEST_SH:-/system/bin/sh}
PERSISTENT_MANIFEST=$TEST_ROOT/data/local/gen5w-portable/persistent/recovery/manifest
PERSISTENT_ENABLED=$TEST_ROOT/data/local/gen5w-portable/boot/enabled
if [ -e "$PERSISTENT_MANIFEST" ] || [ -L "$PERSISTENT_MANIFEST" ]; then
    [ -f "$PERSISTENT_MANIFEST" ] && [ ! -L "$PERSISTENT_MANIFEST" ] || exit 1
    if [ ! -f "$PERSISTENT_ENABLED" ] || [ -L "$PERSISTENT_ENABLED" ] ||
       [ "$(cat "$PERSISTENT_ENABLED" 2>/dev/null)" != 1 ]; then
        echo 'portable service: persistent payload is present but automatic startup is disabled'
        exit 0
    fi
fi
"$SH" "$BASE/persistent-start.sh" run
result=$?
[ "$result" != 3 ] || exec "$SH" "$BASE/boot.sh" run
exit "$result"
