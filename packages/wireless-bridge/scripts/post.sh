#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
"$NEM" remount rw >/dev/null 2>&1 || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
save_original && stage_clear || exit 1
if [ "$BRIDGE_STATE" = stock ]; then
    [ ! -L "$STATE/replacement" ] || exit 1
    rm -f "$STATE/replacement" || exit 1
    "$TOOL" apply "$STATE/original" "$STATE/replacement" && patched "$STATE/replacement" || { restore_target; exit 1; }
    replace_target "$STATE/replacement" patched "$TARGET" "$TOOL" "$STATE/original" "$STATE/staging" || { restore_target; exit 1; }
fi
if [ "$DIPO_STATE" = stock ]; then
    [ ! -L "$STATE/diporeplacement" ] || { restore_target; exit 1; }
    rm -f "$STATE/diporeplacement" || { restore_target; exit 1; }
    if ! { "$DIPO_TOOL" apply "$STATE/dipooriginal" "$STATE/diporeplacement" && dipo_patched "$STATE/diporeplacement" &&
        replace_target "$STATE/diporeplacement" patched "$DIPO_TARGET" "$DIPO_TOOL" "$STATE/dipooriginal" "$STATE/dipostaging"; }; then
        restore_target || log 'FAIL bridge: rollback incomplete; both originals retained'
        exit 1
    fi
fi
patched "$TARGET" && dipo_patched "$DIPO_TARGET" || { restore_target; exit 1; }
rm -f "$STATE/replacement" "$STATE/diporeplacement" || exit 1
[ ! -L "$STOPPING" ] && rm -f "$STOPPING" || exit 1
sync
sys_ro || exit 1
trap - EXIT
log 'APPLIED bridge: stock service shim verified; real transport remains untested'
[ -n "$BRIDGE_TEST_SYS" ] || [ -f "$NOREBOOT" ] || exec /system/bin/reboot
