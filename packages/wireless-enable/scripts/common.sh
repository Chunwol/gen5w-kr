# Turns on wireless CarPlay / Android Auto by declaring the features the stock
# apps look for, and by letting the Wi-Fi hotspot start. What it touches:
#   /system/etc/permissions/<feature>.xml   add the feature declarations
#   build.prop persist.ium.support           set to carplay (projection kind)
#   <region>/featurexml.cfg                  stop the lines that strip the
#                                            wireless/hotspot features at boot
# Everything is backed up first; uninstall restores the exact original bytes.
# Wi-Fi client (the Settings Wi-Fi menu + joining networks) is optional and off
# by default: it shares one radio with the hotspot, so it can make projection
# flaky. Turn it on with a file named GEN5W-WIFI-CLIENT on the install drive.
#
# Detection, not a car list: installs only where the stock apps have the
# wireless projection code and the Wi-Fi chip answers. Unknown -> refuse, change
# nothing in /system. A bounded disabled-client probe restores its original state.

SYS=${EN_TEST_SYS:-/system}
DATA=${EN_TEST_DATA:-/data}
NEM=${EN_TEST_NEM:-/system/xbin/nemesis}
PERM=$SYS/etc/permissions
BP=$SYS/build.prop
MARK=$DATA/nemesis/backup/gen5w.kr.wireless
LOG=$DATA/nemesis/gen5w.kr.wireless.log
NOREBOOT=$DATA/nemesis/gen5wkr.noreboot
AP_MATCH=$DATA/nemesis/gen5wkr.ap-match
AP_FEATURE=$DATA/nemesis/gen5wkr.ap-hotspot-feature
# Declare the stock hotspot feature unless match mode asked to leave it out.
hotspot_feature_wanted() { [ ! -f "$AP_MATCH" ] || [ -f "$AP_FEATURE" ]; }

CP_XML=com.hkmc.software.connectivity.carplay_wireless.xml
AA_XML=com.hkmc.software.connectivity.androidauto_wireless.xml
HOTSPOT_XML=com.hkmc.software.wifihotspot.xml
WIFI_XML=android.hardware.wifi.xml

log() { echo "$1"; mkdir -p "$DATA/nemesis" 2>/dev/null; echo "$1" >> "$LOG" 2>/dev/null; true; }
toast() {
    am broadcast -a com.hkmc.intent.action.TOAST \
        -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
}
# write a line without printf (the unit's shell has none); keeps no trailing newline worry
putline() { echo "$1"; }

# --- detection -------------------------------------------------------------
# does a stock projection app know the wireless features? (grep the odex text)
has_wireless_code() {
    local _a
    for _a in "$SYS/app/HKMC_DiPO.odex" "$SYS/app/PhoneProjection.odex" "$SYS/app/Iap2ServerApp.odex"; do
        [ -f "$_a" ] || continue
        grep -aqE "carplay_wireless|androidauto_wireless|ConnectivitySSID" "$_a" 2>/dev/null && return 0
    done
    return 1
}
# Positive hardware evidence only. An old driver failure does not prove that
# the physical chip is missing, and an arbitrary SDIO card may be storage.
wifi_hw_observed() {
    local _root=${EN_TEST_HW_ROOT:-/sys} _entry _class
    for _entry in "$_root"/class/net/wlan*; do [ -e "$_entry" ] && return 0; done
    for _entry in "$_root"/bus/sdio/devices/*/class; do
        [ -r "$_entry" ] || continue
        IFS= read -r _class < "$_entry"
        [ "$_class" = 0x07 ] && return 0
    done
    dmesg 2>/dev/null | grep -q 'Firmware up'
}
wifi_probe_restore() {
    [ "$_restore_wifi" = 1 ] || return 0
    _restore_wifi=0
    svc wifi disable >/dev/null 2>&1 || return 1
    local _n=0
    while [ $_n -lt 8 ]; do
        [ "$(settings get global wifi_on 2>/dev/null)" = 0 ] && return 0
        sleep 1; _n=$((_n+1))
    done
    return 1
}
# A subshell confines traps and temporary state to this observation.
# A restore failure is nonzero, distinct from an inconclusive hardware result.
wifi_hw() (
    wifi_hw_observed && { echo yes; exit 0; }
    [ "$(settings get global wifi_on 2>/dev/null)" = 0 ] || { echo unknown; exit 0; }
    local _restore_wifi=1 _n=0
    trap 'wifi_probe_restore || exit 1' 0
    trap 'exit 1' 1 2 15
    # Recheck before enabling: an existing WLAN/AP must never be toggled.
    if wifi_hw_observed; then _restore_wifi=0; echo yes; exit 0; fi
    if svc wifi enable >/dev/null 2>&1; then
        while [ $_n -lt 8 ]; do
            wifi_hw_observed && { echo yes; exit 0; }
            sleep 1; _n=$((_n+1))
        done
    fi
    echo unknown
)
wifi_client_wanted() {
    local _d
    for _d in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1; do
        [ -f "$_d/GEN5W-WIFI-CLIENT" ] && return 0
    done
    return 1
}
# the region/model dir the firmware names for itself; never guess another model's
featurexml_path() {
    local _t _f
    _t=$(getprop ro.mobis.targetdir 2>/dev/null)
    if [ -n "$_t" ] && [ -f "$_t/featurexml.cfg" ]; then echo "$_t/featurexml.cfg"; return 0; fi
    for _f in "$SYS"/etc/featurexml.cfg; do
        [ -f "$_f" ] || continue
        grep -qE 'carplay_wireless|androidauto_wireless|wifihotspot' "$_f" 2>/dev/null && { echo "$_f"; return 0; }
    done
    return 1
}

# --- helpers ---------------------------------------------------------------
file_md5() { local _l; _l=$(md5 "$1" 2>/dev/null) || _l=$(md5sum "$1" 2>/dev/null) || return 1; set -- $_l; echo "$1"; }
sys_rw() { "$NEM" remount rw >/dev/null 2>&1; }
sys_ro() { "$NEM" remount ro >/dev/null 2>&1 || true; }

# Replace a /system file in one step: write a full copy next to it, then rename.
# A power cut mid-write leaves either the old or the new file, never half of one.
# Stock build.prop, featurexml.cfg and permission files are all 0644 root:root.
replace_file() {
    local _src=$1 _dst=$2 _tmp=$2.gen5w-tmp
    [ -f "$_src" ] && [ ! -L "$_dst" ] && [ ! -L "$_tmp" ] || return 1
    rm -f "$_tmp"
    cat "$_src" > "$_tmp" &&
    chmod 644 "$_tmp" &&
    { chown 0:0 "$_tmp" 2>/dev/null || chown 0.0 "$_tmp" 2>/dev/null || true; } &&
    sync && mv -f "$_tmp" "$_dst" || { rm -f "$_tmp"; return 1; }
    [ -x /system/bin/restorecon ] && restorecon "$_dst" 2>/dev/null
    sync
    return 0
}

# add one feature file from files/permissions, note whether it was absent before
add_perm() {
    local _name=$1
    local _dst=$PERM/$_name
    # Preserve the first install's ownership record across reinstalls.
    [ -f "$MARK/perm.$_name.was" ] && return 0
    if [ -e "$_dst" ]; then
        putline present > "$MARK/perm.$_name.was" || return 1
        return 0
    fi
    putline absent > "$MARK/perm.$_name.was" || return 1
    replace_file "files/permissions/$_name" "$_dst" || return 1
    log "added $_dst"
    return 0
}
# remove a feature file only if WE added it (was absent)
del_perm() {
    local _name=$1
    [ -f "$MARK/perm.$_name.was" ] || return 0
    local _was; IFS= read -r _was < "$MARK/perm.$_name.was"
    if [ "$_was" = absent ] && [ -e "$PERM/$_name" ]; then
        rm -f "$PERM/$_name" || return 1
        log "removed $PERM/$_name"
    fi
    return 0
}

# set a persist line in build.prop to a value, saving the whole original file once
set_prop() {
    local _key=$1 _val=$2 _tmp=$MARK/bp.tmp
    : > "$_tmp" || return 1
    local _seen=0 _line
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            "$_key="*) putline "$_key=$_val" >> "$_tmp"; _seen=1 ;;
            *) putline "$_line" >> "$_tmp" ;;
        esac
    done < "$BP"
    [ "$_seen" = 1 ] || putline "$_key=$_val" >> "$_tmp"
    replace_file "$_tmp" "$BP" || return 1
    rm -f "$_tmp"
    log "set $_key=$_val in build.prop"
}

# comment out the featurexml lines that strip the wireless/hotspot features
rewrite_featurexml() {
    local _fx=$1 _tmp=$MARK/fx.tmp _line _n=0
    : > "$_tmp" || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            \#*) putline "$_line" >> "$_tmp" ;;
            *wifihotspot.xml*)
                if ! hotspot_feature_wanted; then putline "$_line" >> "$_tmp"
                else putline "#${_line}" >> "$_tmp"; _n=$((_n+1)); fi ;;
            *carplay_wireless.xml*|*androidauto_wireless.xml*)
                putline "#${_line}" >> "$_tmp"; _n=$((_n+1)) ;;
            *) putline "$_line" >> "$_tmp" ;;
        esac
    done < "$_fx"
    replace_file "$_tmp" "$_fx" || return 1
    rm -f "$_tmp"
    log "featurexml: commented $_n stripping line(s)"
}

# put everything back exactly as it was (used by uninstall and by a failed install)
_restore_all() {
    local _rc=0
    [ -s "$MARK/build.prop" ] && { replace_file "$MARK/build.prop" "$BP" || _rc=1; }
    if [ -f "$MARK/featurexml.path" ] && [ -s "$MARK/featurexml.cfg" ]; then
        IFS= read -r _fx < "$MARK/featurexml.path"
        [ -n "$_fx" ] && { replace_file "$MARK/featurexml.cfg" "$_fx" || _rc=1; }
    fi
    del_perm "$CP_XML" || _rc=1
    del_perm "$AA_XML" || _rc=1
    del_perm "$HOTSPOT_XML" || _rc=1
    del_perm "$WIFI_XML" || _rc=1
    sync
    return $_rc
}

. ./scripts/recovery.sh
