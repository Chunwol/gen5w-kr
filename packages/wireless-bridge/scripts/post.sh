#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
# Every failing step says which one it was; the installer copies this output into
# GEN5W-REPORT/EXEC_LOG.txt.
fail() { log "FAIL bridge: $1"; }
# Undo the files changed so far, then stop.
die() { fail "$1"; restore_target || log 'FAIL bridge: rollback incomplete; originals retained'; exit 1; }
inspect; rc=$?
[ "$rc" = 0 ] || { fail "inspect rc=$rc (state not recognized)"; exit "$rc"; }
apguard_reset || { fail 'could not reset the hotspot start guard'; exit 1; }
"$NEM" remount rw >/dev/null 2>&1 || { fail 'could not remount /system read-write'; exit 1; }
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM
save_original && stage_clear || { fail 'could not save the stock files or clear earlier staging'; exit 1; }
if [ "$BRIDGE_STATE" = legacy-patched ]; then
    # Remove the former custom service-control shim before handing projection
    # ownership to OEM PhoneProjection.
    replace_target "$STATE/original" original "$TARGET" "$TOOL" "$STATE/original" "$STATE/staging" || die 'could not restore the former iAP2 shim'
fi
if relay_packaged; then
    log "STEP bridge: relay packaged; iAP2 state $BRIDGE_STATE, DiPO state $DIPO_STATE"
    [ -n "$BT_TOOL" ] || die 'the iAP2 Bluetooth tool is missing'
    if [ "$BRIDGE_STATE" != bt-patched ]; then
        [ ! -L "$STATE/replacement" ] || die 'iAP2 replacement path is a symlink'
        rm -f "$STATE/replacement" || die 'could not remove an old iAP2 replacement'
        "$BT_TOOL" apply "$STATE/original" "$STATE/replacement" && bt_patched "$STATE/replacement" || die 'the iAP2 Bluetooth patch did not apply to the stock ODEX'
        replace_target "$STATE/replacement" patched "$TARGET" "$BT_TOOL" "$STATE/original" "$STATE/staging" || die 'could not put the patched iAP2 ODEX in place'
        log 'STEP bridge: iAP2 ODEX patched'
    fi
elif [ "$BRIDGE_STATE" != route-patched ]; then
    log "STEP bridge: no relay in this package; iAP2 state $BRIDGE_STATE"
    [ ! -L "$STATE/replacement" ] || die 'iAP2 replacement path is a symlink'
    rm -f "$STATE/replacement" || die 'could not remove an old iAP2 replacement'
    "$ROUTE_TOOL" apply "$STATE/original" "$STATE/replacement" && route_patched "$STATE/replacement" || die 'the iAP2 route patch did not apply to the stock ODEX'
    replace_target "$STATE/replacement" patched "$TARGET" "$ROUTE_TOOL" "$STATE/original" "$STATE/staging" || die 'could not put the patched iAP2 ODEX in place'
    log 'STEP bridge: iAP2 ODEX patched'
fi
if relay_packaged; then
    [ "$DIPO_STATE" = relay ] || install_relay_dipo || die 'the DiPO relay install failed (details above)'
elif [ "$DIPO_STATE" != patched ]; then
    [ ! -L "$STATE/diporeplacement" ] || die 'DiPO replacement path is a symlink'
    rm -f "$STATE/diporeplacement" || die 'could not remove an old DiPO replacement'
    if ! { "$DIPO_TOOL" apply "$STATE/dipooriginal" "$STATE/diporeplacement" && dipo_patched "$STATE/diporeplacement" &&
        replace_target "$STATE/diporeplacement" patched "$DIPO_TARGET" "$DIPO_TOOL" "$STATE/dipooriginal" "$STATE/dipostaging"; }; then
        fail 'the DiPO patch did not apply or could not be put in place'
        restore_target || log 'FAIL bridge: rollback incomplete; both originals retained'
        exit 1
    fi
fi
if [ -n "$GPM_TOOL" ] && [ -f "$GPM_TARGET" ] && [ "$GPM_STATE" = stock ]; then
    [ ! -L "$STATE/gpmreplacement" ] || die 'GPM replacement path is a symlink'
    rm -f "$STATE/gpmreplacement" || die 'could not remove an old GPM replacement'
    if ! { "$GPM_TOOL" apply "$STATE/gpmoriginal" "$STATE/gpmreplacement" && gpm_patched "$STATE/gpmreplacement" &&
        replace_target "$STATE/gpmreplacement" patched "$GPM_TARGET" "$GPM_TOOL" "$STATE/gpmoriginal" "$STATE/gpmstaging"; }; then
        fail 'the GPM patch did not apply or could not be put in place'
        restore_target || log 'FAIL bridge: rollback incomplete; originals retained'
        exit 1
    fi
fi
{ { relay_packaged && bt_patched "$TARGET" && relay_live; } ||
   { ! relay_packaged && route_patched "$TARGET" && dipo_patched "$DIPO_TARGET"; }; } &&
   { [ -z "$GPM_TOOL" ] || [ ! -f "$GPM_TARGET" ] || gpm_patched "$GPM_TARGET"; } || die 'the final check of the patched files failed'
rm -f "$STATE/replacement" "$STATE/diporeplacement" "$STATE/gpmreplacement" || { fail 'could not remove the replacement copies'; exit 1; }
[ ! -L "$STOPPING" ] && rm -f "$STOPPING" || { fail 'could not clear the stopping marker'; exit 1; }
wipe_dalvik || { fail 'cache cleanup failed'; restore_target || log 'FAIL bridge: rollback incomplete; originals retained'; exit 1; }
sync
sys_ro || { fail 'could not remount /system read-only'; exit 1; }
trap - EXIT
log 'APPLIED bridge: OEM PhoneProjection path retained; iAP2 Wi-Fi/RouteGuidance capabilities enabled; live connection and HUD remain unverified'
[ -n "$BRIDGE_TEST_SYS" ] || [ -f "$NOREBOOT" ] || exec /system/bin/reboot
