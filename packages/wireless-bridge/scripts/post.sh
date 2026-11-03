#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
apguard_reset || exit 1
"$NEM" remount rw >/dev/null 2>&1 || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
save_original && stage_clear || exit 1
if [ "$BRIDGE_STATE" = patched ]; then
    # A previous bridge build replaced the OEM service entry point. Restore the
    # byte-verified stock app before asking PhoneProjection to own the session.
    replace_target "$STATE/original" original "$TARGET" "$TOOL" "$STATE/original" "$STATE/staging" || { restore_target; exit 1; }
fi
if [ "$DIPO_STATE" != patched ]; then
    [ ! -L "$STATE/diporeplacement" ] || { restore_target; exit 1; }
    rm -f "$STATE/diporeplacement" || { restore_target; exit 1; }
    if ! { "$DIPO_TOOL" apply "$STATE/dipooriginal" "$STATE/diporeplacement" && dipo_patched "$STATE/diporeplacement" &&
        replace_target "$STATE/diporeplacement" patched "$DIPO_TARGET" "$DIPO_TOOL" "$STATE/dipooriginal" "$STATE/dipostaging"; }; then
        restore_target || log 'FAIL bridge: rollback incomplete; both originals retained'
        exit 1
    fi
fi
if [ -n "$GPM_TOOL" ] && [ -f "$GPM_TARGET" ] && [ "$GPM_STATE" = stock ]; then
    [ ! -L "$STATE/gpmreplacement" ] || { restore_target; exit 1; }
    rm -f "$STATE/gpmreplacement" || { restore_target; exit 1; }
    if ! { "$GPM_TOOL" apply "$STATE/gpmoriginal" "$STATE/gpmreplacement" && gpm_patched "$STATE/gpmreplacement" &&
        replace_target "$STATE/gpmreplacement" patched "$GPM_TARGET" "$GPM_TOOL" "$STATE/gpmoriginal" "$STATE/gpmstaging"; }; then
        restore_target || log 'FAIL bridge: rollback incomplete; originals retained'
        exit 1
    fi
fi
original "$TARGET" && dipo_patched "$DIPO_TARGET" && { [ -z "$GPM_TOOL" ] || [ ! -f "$GPM_TARGET" ] || gpm_patched "$GPM_TARGET"; } || { restore_target; exit 1; }
rm -f "$STATE/replacement" "$STATE/diporeplacement" "$STATE/gpmreplacement" || exit 1
[ ! -L "$STOPPING" ] && rm -f "$STOPPING" || exit 1
wipe_dalvik || { restore_target || log 'FAIL bridge: cache cleanup failed; originals retained'; exit 1; }
sync
sys_ro || exit 1
trap - EXIT
log 'APPLIED bridge: app requests OEM PhoneProjection; Wi-Fi and CarPlay remain unverified'
[ -n "$BRIDGE_TEST_SYS" ] || [ -f "$NOREBOOT" ] || exec /system/bin/reboot
