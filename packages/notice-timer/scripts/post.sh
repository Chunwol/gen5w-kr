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
if [ "$NOTICE_STATE" = stock ]; then
    [ ! -L "$STATE/replacement" ] || exit 1
    rm -f "$STATE/replacement" || exit 1
    "$TOOL" apply "$STATE/original" "$STATE/replacement" && patched "$STATE/replacement" || exit 1
    stage_clear || exit 1
    if ! { cp "$STATE/replacement" "$TARGET.gen5w-kr-notice.tmp" &&
            chmod 644 "$TARGET.gen5w-kr-notice.tmp" &&
            chown 0:0 "$TARGET.gen5w-kr-notice.tmp" &&
            touch "$TARGET.gen5w-kr-notice.tmp" &&
            patched "$TARGET.gen5w-kr-notice.tmp" &&
            mv "$TARGET.gen5w-kr-notice.tmp" "$TARGET" && patched "$TARGET"; }; then
        # stage_clear proved this path absent before our copy. Remove a partial
        # file from this attempt so a retry does not mistake it for a foreign one.
        [ -L "$TARGET.gen5w-kr-notice.tmp" ] || rm -f "$TARGET.gen5w-kr-notice.tmp"
        restore_target || log 'FAIL notice: restoration failed; backups retained'
        exit 1
    fi
fi
rm -f "$STATE/replacement" || exit 1
FEATURE_XML=$SYS/etc/permissions/com.mobis.feature.remove_consentscreen.xml
if [ -f "$SCRIPT_DIR/../files/com.mobis.feature.remove_consentscreen.xml" ]; then
    mkdir -p "$SYS/etc/permissions" 2>/dev/null || true
    cp "$SCRIPT_DIR/../files/com.mobis.feature.remove_consentscreen.xml" "$FEATURE_XML.tmp" &&
    chmod 644 "$FEATURE_XML.tmp" && chown 0:0 "$FEATURE_XML.tmp" 2>/dev/null &&
    mv "$FEATURE_XML.tmp" "$FEATURE_XML" || true
fi
if [ -f "$SCRIPT_DIR/../svc/agree.sh" ]; then
    chmod 755 "$SCRIPT_DIR/../svc/agree.sh" 2>/dev/null || true
fi
sync
sys_ro || exit 1
trap - EXIT
log 'APPLIED notice: stock warning retained; eligible auto-close timer 3 seconds; vehicle untested'
[ -n "$NOTICE_TEST_SYS" ] || [ -f "$NOREBOOT" ] || exec /system/bin/reboot
exit 0
