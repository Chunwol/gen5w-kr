#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
dependencies || exit $?
"$NEM" remount rw >/dev/null 2>&1 || exit 1
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
save_original || exit 1
if [ "$AUDIO_STATE" = stock ]; then
    [ ! -L "$STATE/replacement" ] || exit 1
    rm -f "$STATE/replacement" || exit 1
    "$TOOL" apply "$STATE/original" "$STATE/replacement" && patched "$STATE/replacement" || exit 1
    stage_clear || exit 1
    if ! { cp "$STATE/replacement" "$TARGET.gen5w-kr-audio.tmp" &&
            chmod 644 "$TARGET.gen5w-kr-audio.tmp" &&
            chown 0:0 "$TARGET.gen5w-kr-audio.tmp" &&
            patched "$TARGET.gen5w-kr-audio.tmp" &&
            mv "$TARGET.gen5w-kr-audio.tmp" "$TARGET" && patched "$TARGET"; }; then
        # stage_clear proved this path absent before our copy. Remove a partial
        # file from this attempt so a retry does not mistake it for a foreign one.
        [ -L "$TARGET.gen5w-kr-audio.tmp" ] || rm -f "$TARGET.gen5w-kr-audio.tmp"
        restore_target || log 'FAIL audio: restoration failed; backups retained'
        exit 1
    fi
fi
rm -f "$STATE/replacement" || exit 1
sync
sys_ro || exit 1
trap - EXIT
log 'APPLIED audio: formats verified; vehicle playback remains untested'
[ -n "$AUDIO_TEST_SYS" ] || [ -f "$NOREBOOT" ] || exec /system/bin/reboot
exit 0
