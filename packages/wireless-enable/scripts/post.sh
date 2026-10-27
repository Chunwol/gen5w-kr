#!/system/bin/sh
. ./scripts/common.sh
state_load || exit 1
sys_rw || exit 1
if state_unsealed; then state_discard_plan || exit 1; fi
if [ -e "$STATE" ]; then
    state_apply && setprop persist.ium.support carplay
    rc=$?
    if [ -f "$STATE/runtime.wifi" ]; then setprop persist.wifi.state 3 || rc=1; fi
else
    state_begin || { sys_ro; exit 1; }
    rc=0
    getprop persist.ium.support > "$STATE/runtime.ium" || rc=1
    cp "$BP" "$MARK/desired.bp" || { sys_ro; exit 1; }
    original_bp=$BP; BP=$MARK/desired.bp
    set_prop persist.ium.support carplay || rc=1
    if wifi_client_wanted; then
        set_prop persist.wifi.state 3 && getprop persist.wifi.state > "$STATE/runtime.wifi" || rc=1
    fi
    BP=$original_bp
    state_plan "$BP" "$MARK/desired.bp" || rc=1
    fx=$(featurexml_path) || fx=
    if [ -n "$fx" ]; then
        cp "$fx" "$MARK/desired.fx" && rewrite_featurexml "$MARK/desired.fx" && state_plan "$fx" "$MARK/desired.fx" || rc=1
    fi
    for name in "$CP_XML" "$AA_XML" "$HOTSPOT_XML"; do
        [ -e "$PERM/$name" ] || state_plan "$PERM/$name" "files/permissions/$name" || rc=1
    done
    if wifi_client_wanted; then
        [ -e "$PERM/$WIFI_XML" ] || state_plan "$PERM/$WIFI_XML" "files/permissions/$WIFI_XML" || rc=1
    fi
    if [ "$rc" = 0 ]; then
        state_seal && state_apply && setprop persist.ium.support carplay || rc=1
        if [ -f "$STATE/runtime.wifi" ]; then setprop persist.wifi.state 3 || rc=1; fi
    else
        rm -rf "$STATE" "$MARK"
        rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
    fi
fi
if [ "$rc" != 0 ]; then
    [ ! -f "$STATE/manifest.md5" ] || { rm -f "$STATE/complete"; state_restore; }
    sys_ro; log 'FAIL: installation; recovery retained if restoration failed'; exit 1
fi
sys_ro; sync
log 'APPLIED: wireless; verified durable recovery'
[ -z "$EN_TEST_SYS" ] && [ ! -f "$NOREBOOT" ] || exit 0
exec /system/bin/reboot
exit 1
