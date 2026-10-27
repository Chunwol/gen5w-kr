#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/profile-common.sh"
clear_ready || exit 1
inspect || exit $?
dependencies || exit $?
"$NEM" remount rw >/dev/null 2>&1 || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
save_original || exit 1
if [ "$PROFILE_STATE" = stock ]; then
    record_boot || exit 1
    [ ! -L "$STATE/replacement" ] || exit 1
    rm -f "$STATE/replacement" || exit 1
    "$TOOL" apply "$STATE/original" "$STATE/replacement" && patched "$STATE/replacement" || exit 1
    stage_clear || exit 1
    if ! { cp "$STATE/replacement" "$TARGET.gen5w-kr-hotspot.tmp" &&
            chmod 644 "$TARGET.gen5w-kr-hotspot.tmp" &&
            chown 0:0 "$TARGET.gen5w-kr-hotspot.tmp" &&
            touch "$TARGET.gen5w-kr-hotspot.tmp" &&
            patched "$TARGET.gen5w-kr-hotspot.tmp" &&
            mv "$TARGET.gen5w-kr-hotspot.tmp" "$TARGET" && patched "$TARGET"; }; then
        # stage_clear proved this path absent before our copy. Remove a partial
        # file from this attempt so a retry does not mistake it for a foreign one.
        [ -L "$TARGET.gen5w-kr-hotspot.tmp" ] || rm -f "$TARGET.gen5w-kr-hotspot.tmp"
        restore_target || log 'FAIL hotspot: restoration failed; backups retained'
        exit 1
    fi
fi
rm -f "$STATE/replacement" || exit 1
clear_stop || exit 1
sync
sys_ro || exit 1
trap - EXIT
log 'APPLIED hotspot: CP mode selects command-local credentials; reboot required; vehicle untested'
[ -n "$PROFILE_TEST_SYS" ] || [ -f "$NOREBOOT" ] || exec /system/bin/reboot
exit 0
