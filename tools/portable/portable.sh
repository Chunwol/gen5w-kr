#!/system/bin/sh
# Explicit entry point: portable candidate never activates on USB insertion.
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
export PORTABLE_HELPER=$BASE/bin/dex-patch
case "$1" in
prepare) shift; exec /system/bin/sh "$BASE/prepare.sh" "$@";;
apply)
    # ODEX overlays must precede app loading; do not restart an active app into
    # an unverified replacement or silently use stale already-loaded code.
    [ "$(getprop init.svc.zygote)" = stopped ] || { echo 'portable: stop Android through the existing maintenance flow first' >&2; exit 1; }
    shift; exec /system/bin/sh "$BASE/overlay.sh" apply "$@";;
runtime) shift; exec /system/bin/sh "$BASE/runtime.sh" "$@";;
plan) shift; exec /system/bin/sh "$BASE/overlay.sh" prepare "$@";;
status|commit|disable) exec /system/bin/sh "$BASE/overlay.sh" "$@";;
*) echo 'usage: portable.sh prepare WORK [FEATURE ...] | plan MANIFEST [FEATURE ...] | runtime enable|status|commit|disable | apply | status | commit | disable' >&2; exit 2;;
esac
