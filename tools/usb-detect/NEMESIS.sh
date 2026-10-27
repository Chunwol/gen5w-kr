#!/system/bin/sh
# Read-only check of what this head unit supports. Changes nothing; writes one
# report to the USB drive. No VIN, serials, phone numbers, keys or /data contents.
export PATH=${GEN5W_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
R=${DETECT_TEST_ROOT:-}
USB=$R/storage/usb0
SYS=$R/system
OUT=$USB/GEN5WKR_DETECT.txt

yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
sum() { set -- $(md5 "$1" 2>/dev/null); echo "${1:-missing}"; }
has() { grep -q "$1" "$2" 2>/dev/null; }
sysui() { for f in $SYS/priv-app/SystemUI.odex $SYS/app/SystemUI.odex; do [ -f "$f" ] && { echo "$f"; return; }; done; }

wifi_hw() {
    local entry class messages
    for entry in "$R"/sys/class/net/wlan*; do [ -e "$entry" ] && { echo yes; return; }; done
    for entry in "$R"/sys/bus/sdio/devices/*/class; do
        [ -r "$entry" ] || continue
        IFS= read -r class < "$entry"
        [ "$class" = 0x07 ] && { echo yes; return; }
    done
    messages=$(dmesg 2>/dev/null)
    case "$messages" in *"Firmware up"*) echo yes;; *) echo unknown;; esac
}

{
    echo "# gen5w-kr detect $(date 2>/dev/null)"
    echo "firmware=$(getprop ro.build.product)"
    echo "android=$(getprop ro.build.version.release)"
    echo "wifi_hardware=$(wifi_hw)"
    for x in $(ls $SYS/etc/permissions 2>/dev/null | grep -iE 'carplay|androidauto|wifi|hotspot|consent'); do
        echo "feature_file=$x"
    done
    U=$(sysui)
    if [ -n "$U" ] && has com.mobis.feature.remove_consentscreen "$U" && has sys.boot.confirm_screen "$U" && has AGREE_USER_LICENSE "$U"; then
        echo "consent_switch=yes"
    else
        echo "consent_switch=no"
    fi
    echo "iap2_library=$(yn [ -f $SYS/framework/com.tcc.iap2.jar ])"
    echo "iap2_server=$(yn [ -f $SYS/app/Iap2ServerApp.apk ])"
    _svc=$(service list 2>/dev/null)
    case "$_svc" in *[Cc]luster*) echo "cluster_service=yes" ;; *) echo "cluster_service=no" ;; esac
    echo "lib_carplay_audio=$(sum $SYS/lib/libCarPlayAudio.so)"
    echo "lib_carplay_core=$(sum $SYS/lib/libCarPlayCore.so)"
    echo "lib_carplay_utils=$(sum $SYS/lib/libCarPlayUtils.so)"
    echo "prop_iap2_wifi=$(getprop persist.sys.iap2.wifi)"
    echo "prop_iap2_iden_wireless=$(getprop persist.iap2.iden.wireless)"
    echo "nemesis=$(yn [ -x $SYS/xbin/nemesis ])"
} > "$OUT" 2>/dev/null
sync
am broadcast -a com.hkmc.intent.action.TOAST \
    -e com.hkmc.intent.extra.TOAST_MESSAGE "확인 완료: USB의 GEN5WKR_DETECT.txt" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
exit 0
