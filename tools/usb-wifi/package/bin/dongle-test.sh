#!/system/bin/sh
# Explicit USB WLAN diagnostic; does not change the stock Wi-Fi backend.
SYS=${DONGLE_TEST_SYS:-/sys}
USB=${DONGLE_TEST_SYS_BUS:-$SYS/bus/usb/devices}
NET=${DONGLE_TEST_NET_ROOT:-$SYS/class/net}
MOD=${DONGLE_TEST_MOD_DIR:-/system/wifi/dongle}
FW=${DONGLE_TEST_FIRMWARE_DIR:-/system/etc/firmware}
DATA=${DONGLE_TEST_DATA:-/data}
NEM=$DATA/nemesis
REPORT=${DONGLE_TEST_REPORT:-$NEM/gen5w-dongle-test.log}
PROC_MODULES=${DONGLE_TEST_PROC_MODULES:-/proc/modules}
HOSTAPD=${DONGLE_TEST_HOSTAPD:-/system/bin/hostapd}
HOSTAPD_CLI=${DONGLE_TEST_HOSTAPD_CLI:-/system/bin/hostapd_cli}
IFACE=${DONGLE_TEST_IFACE:-wlan0}
APCONF=$NEM/gen5w-dongle-test-hostapd.conf
APPID=$NEM/gen5w-dongle-test-hostapd.pid
LOADED=$NEM/gen5w-dongle-test-loaded

say() { echo "$*"; }
fail() { say "FAIL: $*"; exit 1; }
log() { mkdir -p "${REPORT%/*}" 2>/dev/null; echo "$*" >> "$REPORT"; }
safe_state_paths() {
    [ ! -L "$NEM" ] && { [ ! -e "$NEM" ] || [ -d "$NEM" ]; } || return 1
    for f in "$REPORT" "$APCONF" "$APPID" "$LOADED" "$LOADED.tmp" "$NEM/gen5w-dongle-test-driver"; do
        [ ! -L "$f" ] && { [ ! -e "$f" ] || [ -f "$f" ]; } || return 1
    done
}
set_test() {
    setprop gen5w.dongle.test "$1" || return 1
    [ "$(getprop gen5w.dongle.test 2>/dev/null)" = "$1" ]
}
read_ap_channel() {
    AP_CHANNEL=
    [ -f "$APCONF" ] || return 1
    while IFS= read -r line; do
        case "$line" in channel=*) AP_CHANNEL=${line#channel=}; return 0;; esac
    done < "$APCONF"
    return 1
}

profile() {
    DRIVER=$1; FIRMWARES=; MODULES=; BANDS=; AP=; PROFILE_STATUS=
    [ -f "$MOD/modules.profile" ] || return 1
    PROFILE_MODULE=; MODULES=; FIRMWARES=; BANDS=; AP=; PROFILE_STATUS=
    while IFS='|' read -r candidate candidate_modules candidate_firmware candidate_bands candidate_ap candidate_status; do
        [ "$candidate" = "$DRIVER" ] || continue
        PROFILE_MODULE=$candidate; MODULES=$candidate_modules; FIRMWARES=$candidate_firmware
        BANDS=$candidate_bands; AP=$candidate_ap; PROFILE_STATUS=$candidate_status; break
    done < "$MOD/modules.profile"
    [ "$PROFILE_MODULE" = "$DRIVER" ] && [ -n "$MODULES" ] || return 1
    [ "$PROFILE_STATUS" = ready ] || return 2
    for module in $MODULES; do [ -f "$MOD/$module.ko" ] || return 2; done
    for firmware in $FIRMWARES; do [ -f "$FW/$firmware" ] || return 2; done
}
find_device() {
    USB_ID=; MODALIAS=; MATCHED_DRIVER=
    for v in "$USB"/*/idVendor; do
        [ -r "$v" ] || continue; p=${v%idVendor}idProduct; [ -r "$p" ] || continue
        read -r vid < "$v"; read -r pid < "$p"; USB_ID=$vid:$pid
        alias_file=${v%idVendor}modalias
        if [ -r "$alias_file" ]; then read -r MODALIAS < "$alias_file"
        else MODALIAS="usb:v${vid}p${pid}d0000dc00dsc00dp00ic00isc00ip00in00"; fi
        [ -r "$MOD/modules.alias" ] || continue
        while read -r kind pattern module; do
            [ "$kind" = alias ] || continue
            case "$MODALIAS" in $pattern) MATCHED_DRIVER=$module; break;; esac
        done < "$MOD/modules.alias"
        { [ "$DRIVER" = auto ] || [ "$DRIVER" = manual ] || [ "$MATCHED_DRIVER" = "$DRIVER" ]; } && return 0
    done
    USB_ID=; MODALIAS=; MATCHED_DRIVER=; return 1
}
bound_driver() {
    [ -n "${DONGLE_TEST_BOUND_DRIVER:-}" ] && { echo "$DONGLE_TEST_BOUND_DRIVER"; return 0; }
    # Vendor drivers register a USB driver name that differs from their module name.
    d=$(readlink "$SYS/class/net/$IFACE/device/driver/module" 2>/dev/null) ||
        d=$(readlink "$SYS/class/net/$IFACE/device/driver" 2>/dev/null) || return 1
    echo "${d##*/}"
}
module_key() { case "$1" in *-*) echo "${1%%-*}_${1#*-}";; *) echo "$1";; esac; }
is_selected() { [ -n "$1" ] && [ "$(module_key "$1")" = "$(module_key "$SELECTED")" ]; }
report_state() {
    [ ! -L "$REPORT" ] || fail 'report path is a symlink'
    {
        echo "Driver selected=${SELECTED:-unknown}"
        echo "USB ${USB_ID:-missing}"
        echo "WLAN driver=$(bound_driver 2>/dev/null || echo unbound)"
        echo "Interface $IFACE=$([ -e "$NET/$IFACE" ] && echo present || echo missing)"
        if [ -s "$APPID" ] && [ -f "$APCONF" ]; then
            read_ap_channel || AP_CHANNEL=unknown
            case "$AP_CHANNEL" in
                1) echo 'AP channel=1 (2.4GHz configured; AP and phone association only)' ;;
                149) echo 'AP channel=149 (5GHz configured, as the stock hotspot; hostapd start is radio acceptance)' ;;
                *) echo "AP channel=$AP_CHANNEL (configured; hostapd start is radio acceptance)" ;;
            esac
        fi
    } >> "$REPORT"
}
load_one() {
    module=$1
    proc_module=$module
    case "$proc_module" in *-*) proc_module=${proc_module%%-*}_${proc_module#*-};; esac
    { grep -q "^$module " "$PROC_MODULES" 2>/dev/null || grep -q "^$proc_module " "$PROC_MODULES" 2>/dev/null; } && return 0
    insmod "$MOD/$module.ko" || return 1
    echo "$module" >> "$LOADED"
}
stop_ap() {
    [ ! -L "$APPID" ] && [ ! -L "$APCONF" ] || return 1
    if [ -s "$APPID" ]; then pid=$(cat "$APPID"); case "$pid" in ''|*[!0-9]*) return 1;; esac; kill "$pid" 2>/dev/null || true; rm -f "$APPID"; fi
    rm -f "$APCONF"; rmdir "$NEM/gen5w-dongle-test-ctrl" 2>/dev/null || true
}
unload_new() {
    failed=0
    if [ -f "$LOADED" ]; then
        remaining=$LOADED.tmp
        reverse=$LOADED.reverse
        : > "$reverse" || return 1
        while IFS= read -r module; do
            case "$module" in ''|*[!a-zA-Z0-9_-]*) continue;; esac
            { echo "$module"; cat "$reverse"; } > "$reverse.tmp" || { rm -f "$reverse" "$reverse.tmp"; return 1; }
            mv "$reverse.tmp" "$reverse" || { rm -f "$reverse" "$reverse.tmp"; return 1; }
        done < "$LOADED"
        : > "$remaining" || { rm -f "$reverse"; return 1; }
        while IFS= read -r module; do
            case "$module" in ''|*[!a-zA-Z0-9_-]*) continue;; esac
            if [ "$failed" = 1 ]; then echo "$module" >> "$remaining"; continue; fi
            proc_module=$module
            case "$proc_module" in *-*) proc_module=${proc_module%%-*}_${proc_module#*-};; esac
            rmmod "$proc_module" || { say "WARN: busy module remains loaded: $module"; echo "$module" >> "$remaining"; failed=1; }
        done < "$reverse"
        rm -f "$reverse"
        if [ -s "$remaining" ]; then mv "$remaining" "$LOADED" || return 1; else rm -f "$remaining" "$LOADED"; fi
    fi
    return "$failed"
}
cleanup_start_failure() {
    stop_ap >/dev/null 2>&1 || true
    unload_new >/dev/null 2>&1 || return 1
    set_test 0
}

case "${1:-}" in
    list)
        while IFS='|' read -r DRIVER modules firmware bands ap status; do
            case "$DRIVER" in ''|'#'*) continue;; esac
            if profile "$DRIVER"; then say "$DRIVER: ready (USB ID aliases, modules and firmware present; bands=$BANDS AP=$AP)"; else rc=$?; [ "$rc" = 2 ] && say "$DRIVER: not packaged (required firmware/module missing)" || say "$DRIVER: unsupported"; fi
        done < "$MOD/modules.profile" ;;
    start)
        [ "$#" = 2 ] || fail 'usage: dongle-test.sh start DRIVER'
        safe_state_paths || fail 'unsafe diagnostic state path'
        mkdir -p "$NEM" || fail 'cannot create diagnostic directory'
        SELECTED=$2
        AUTO_SELECT=0
        if [ "$SELECTED" = auto ]; then
            DRIVER=auto
            find_device || fail 'no attached USB device matches the packaged USB modalias catalog'
            SELECTED=$MATCHED_DRIVER
            AUTO_SELECT=1
        else
            DRIVER=manual
            find_device || fail 'no attached USB device found for the manual driver trial'
            if [ "$MATCHED_DRIVER" != "$SELECTED" ]; then
                log "WARN: manual diagnostic trial uses $SELECTED without a matching packaged USB alias (observed ${USB_ID:-unknown})"
                say "WARN: manually trying $SELECTED on USB $USB_ID; this is a diagnostic trial, not an automatic compatibility match"
            fi
        fi
        profile "$SELECTED"
        PROFILE_RC=$?
        if [ "$PROFILE_RC" != 0 ]; then
            [ "$PROFILE_RC" = 2 ] || fail "driver not ready or not packaged: $SELECTED"
            log "WARN: diagnostic trial is trying incomplete profile $SELECTED; firmware may be missing"
            say "WARN: trying incomplete profile $SELECTED for diagnosis; missing firmware can prevent binding"
        fi
        DRIVER=$SELECTED
        if [ "$PROFILE_RC" = 0 ]; then
            for firmware in $FIRMWARES; do [ -f "$FW/$firmware" ] || fail "required firmware is missing: $firmware"; done
        fi
        set_test 1 || fail 'cannot set diagnostic mode property'
        : > "$LOADED" || { set_test 0; fail 'cannot create module journal'; }
        for module in $MODULES; do load_one "$module" || { cleanup_start_failure || fail "module load failed: $module; cleanup incomplete and automatic loader hold retained"; set_test 0 || fail 'module load failed and diagnostic hold could not be cleared'; fail "module load failed: $module"; }; done
        n=0; bound=
        while [ "$n" -lt "${DONGLE_TEST_WAIT:-8}" ]; do bound=$(bound_driver 2>/dev/null || true); is_selected "$bound" && break; sleep 1; n=$((n+1)); done
        is_selected "$bound" || { cleanup_start_failure || fail "interface not bound to $SELECTED (observed ${bound:-none}); cleanup incomplete and automatic loader hold retained"; set_test 0 || fail 'interface bind failed and diagnostic hold could not be cleared'; fail "interface not bound to $SELECTED (observed ${bound:-none})"; }
        echo "$SELECTED" > "$NEM/gen5w-dongle-test-driver"
        report_state; say "READY: $SELECTED on $USB_ID; start AP test explicitly" ;;
    ap-start)
        [ "$#" -le 2 ] || fail 'usage: dongle-test.sh ap-start [2g|5g]'
        BAND=${2:-5g}
        case "$BAND" in
            5g) HWMODE=a; CHANNEL=149; EXPECTED_FREQ=5745; BAND_LABEL=5GHz ;;
            2g) HWMODE=g; CHANNEL=1; EXPECTED_FREQ=2412; BAND_LABEL=2.4GHz ;;
            *) fail 'usage: dongle-test.sh ap-start [2g|5g]' ;;
        esac
        safe_state_paths || fail 'unsafe diagnostic state path'
        SELECTED=$(cat "$NEM/gen5w-dongle-test-driver" 2>/dev/null)
        [ "$(getprop gen5w.dongle.test 2>/dev/null)" = 1 ] && [ -n "$SELECTED" ] || fail 'start a selected driver first'
        profile "$SELECTED" || fail "$SELECTED driver profile is not ready"
        case "$AP:$BAND" in
            yes:*|2g:2g) ;;
            2g:5g) fail "$SELECTED runs an AP on 2.4GHz only; the stock hotspot needs 5GHz channel 149" ;;
            *) fail "$SELECTED AP mode is not enabled by this driver" ;;
        esac
        if [ "$BAND" = 5g ]; then
            case ",$BANDS," in *,5GHz,*) ;; *) fail "$SELECTED does not advertise 5GHz";; esac
        else
            case ",$BANDS," in *,2.4GHz,*) ;; *) fail "$SELECTED does not advertise 2.4GHz";; esac
        fi
        [ -e "$NET/$IFACE" ] && is_selected "$(bound_driver)" || fail 'selected WLAN interface is not bound'
        [ -x "$HOSTAPD" ] || fail "hostapd unavailable: $HOSTAPD"
        [ -x "$HOSTAPD_CLI" ] || fail 'hostapd_cli unavailable; cannot verify AP startup'
        mkdir -p "$NEM" || fail 'cannot create diagnostic directory'; umask 077
        mkdir -p "$NEM/gen5w-dongle-test-ctrl" || fail 'cannot create AP control directory'
        cat > "$APCONF" <<EOF
interface=$IFACE
driver=nl80211
ctrl_interface=$NEM/gen5w-dongle-test-ctrl
ssid=GEN5W-DONGLE-TEST
country_code=KR
hw_mode=$HWMODE
channel=$CHANNEL
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=gen5wkr18
EOF
        "$HOSTAPD" -B -P "$APPID" "$APCONF" || fail 'hostapd failed; inspect vehicle logs'
        [ -s "$APPID" ] || fail 'hostapd did not create pid file'
        state=$("$HOSTAPD_CLI" -p "$NEM/gen5w-dongle-test-ctrl" status 2>/dev/null)
        echo "$state" | grep -q '^state=ENABLED$' || { stop_ap; fail 'hostapd did not reach ENABLED state'; }
        echo "$state" | grep -q "^freq=$EXPECTED_FREQ$" || { stop_ap; fail "hostapd is enabled but did not confirm $EXPECTED_FREQ MHz ($BAND_LABEL)"; }
        log "AP channel=$CHANNEL frequency=$EXPECTED_FREQ ($BAND_LABEL confirmed by hostapd_cli)"; log 'AP station=pending'
        if [ "$BAND" = 2g ]; then
            log '2.4GHz radio test only; not concurrent CarPlay/Bluetooth validation'
            say 'AP started: SSID GEN5W-DONGLE-TEST, password gen5wkr18, channel 1 (2.4 GHz, 2412 MHz confirmed). This tests radio/AP/phone association only, not concurrent CarPlay and Bluetooth.'
        else
            say 'AP started: SSID GEN5W-DONGLE-TEST, password gen5wkr18, channel 149 (5 GHz, 5745 MHz confirmed). Run ap-status after connecting a phone.'
        fi ;;
    ap-status)
        safe_state_paths || fail 'unsafe diagnostic state path'
        [ -s "$APPID" ] && kill -0 "$(cat "$APPID")" 2>/dev/null || fail 'test AP is not running'
        [ -x "$HOSTAPD_CLI" ] || fail 'hostapd_cli unavailable; AP can run, but association cannot be verified on this unit'
        read_ap_channel || fail 'test AP configuration is missing or has no channel'
        stations=$("$HOSTAPD_CLI" -p "$NEM/gen5w-dongle-test-ctrl" all_sta 2>/dev/null)
        echo "$stations" | grep -q '^Station ' || { log 'AP station=pending'; fail 'no associated phone; connect first, then retry'; }
        case "$AP_CHANNEL" in 1) BAND_LABEL=2.4GHz;; 36) BAND_LABEL=5GHz;; *) BAND_LABEL=unknown;; esac
        log "AP station=associated band=$BAND_LABEL channel=$AP_CHANNEL"; say 'PASS: a station is associated to the selected test AP (802.11 only; this does not verify phone projection)' ;;
    ap-stop) stop_ap || fail 'could not stop AP'; log 'AP stopped' ;;
    stop)
        safe_state_paths || fail 'unsafe diagnostic state path'
        stop_ap || say 'WARN: AP cleanup failed'; unload_new; failed=$?
        [ "$failed" = 0 ] || { log 'diagnostic cleanup incomplete; test hold retained'; fail 'module is busy; unplug dongle and run stop again, or reboot'; }
        rm -f "$NEM/gen5w-dongle-test-driver"
        set_test 0 || fail 'modules unloaded but test hold could not be cleared'
        log 'diagnostic mode stopped'
        say 'Diagnostic mode stopped; newly loaded unused modules were unloaded.' ;;
    report)
        safe_state_paths || fail 'unsafe diagnostic state path'
        SELECTED=$(cat "$NEM/gen5w-dongle-test-driver" 2>/dev/null); report_state; cat "$REPORT" 2>/dev/null ;;
    *) fail 'usage: dongle-test.sh {list|start DRIVER|ap-start [2g|5g]|ap-status|ap-stop|stop|report}' ;;
esac
