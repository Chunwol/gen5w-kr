#!/system/bin/sh
HOLD_SCRIPT=${0%/*}/install-hold.sh
. "$HOLD_SCRIPT"
install_hold_wait
# Collects bounded, privacy-filtered copies of every gen5w package log for the in-car screen.
# Runs as root next to the HUD service, separate from the wireless supervisor. The screen
# only reads the two files written here. Every size is capped, and a failure only skips
# one round: the loop keeps going and never touches anything outside UI_DIR.
# UI_DIR is a root-owned folder under /data/nemesis. Root never writes into the app's own
# data folder: the app owns that folder and could swap a path for a link between our check
# and our write.
DATA=${UILOG_TEST_DATA:-/data}
SCRIPT_DIR=${0%/*}
. "$SCRIPT_DIR/errors.sh"
ERR_DIR=$DATA/nemesis/gen5wkr.errors
export ERR_DIR
NEMDIR=$DATA/nemesis
UI_DIR=${UILOG_TEST_DIR:-$NEMDIR/gen5wkr.ui}
UI_PARENT=${UI_DIR%/*}
LOGS=$NEMDIR/logs
BRIDGE=$NEMDIR/apps/gen5w.kr.bridge
HOST_READY=${UILOG_TEST_READY:-/data/data/kr.gen5w.wirelesshost/files/bridge-ready}
PROC=${UILOG_TEST_PROC:-/proc}
PROCNET=${UILOG_TEST_PROCNET:-/proc/net}
UPTIME=${UILOG_TEST_UPTIME:-/proc/uptime}
BOOT_ID_FILE=${UILOG_TEST_BOOT_ID:-/proc/sys/kernel/random/boot_id}
LOGCAT=${UILOG_TEST_LOGCAT:-logcat}
INTERVAL=${UILOG_TEST_INTERVAL:-15}
# Switch requests written by the screen (the core app) into its own folder. Root only READS this
# file (never writes into the app's folder) and only accepts the fixed words below; the effect is a
# marker file in the root-owned $NEMDIR, which the packages' own services look at.
REQUEST=${UILOG_TEST_REQUEST:-/data/data/kr.gen5w.core/files/ui-request}
REQ_STEP=${UILOG_TEST_REQ_STEP:-2}
FACT_LINES=110            # lines of unit facts (read-only checks) kept
USB=${UILOG_TEST_USB:-/storage/usb0}
MOUNTS=${UILOG_TEST_MOUNTS:-/proc/mounts}
NETDIR_SYS=${UILOG_TEST_NET:-/sys/class/net}
PM=${UILOG_TEST_PM:-pm}
SAVED=$NEMDIR/gen5wkr.ui-saved   # "<number> <result>" of the last diagnosis save
NEM=${UILOG_TEST_NEM:-/system/xbin/nemesis}
SH=${UILOG_TEST_SH:-/system/bin/sh}
AM=${UILOG_TEST_AM:-/system/bin/am}
APPS=$NEMDIR/apps
REMOVED=$NEMDIR/gen5wkr.ui-removed    # "<number> <result> [package]" of the last in-car removal
MAX_SOURCE_BYTES=131072   # a package log above this is not read at all
PER_SOURCE=25             # newest lines kept per package log
MAX_LINES=200             # lines in the whole log file
LOGCAT_LINES=40
DEEP_LINE=300            # characters per line in the deep section of a saved diagnosis
MAX_LINE=200              # characters per line
# Lines that can carry personal data are dropped (same list as the USB diagnosis).
PRIV='([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{2}:\*\*|[Ss][Ss][Ii][Dd]|[Pp]assw|PASSW|[Pp]assphrase|[Pp]sk|PSK|[Ss]erial|SERIAL|[Ii]mei|IMEI|[Ii]ccid|ICCID|[Mm]sisdn|MSISDN|VIN[=: ]|vin[=: ]|DEVICE_NAME|[Dd]evice ?[Nn]ame|getName|FRQ:|BND:|ALBUM|TITLE|ARTIST|mArtist'

# The parent folder must exist and nothing we write to may be a link. Creates UI_DIR when missing.
prepare() {
    [ -d "$UI_PARENT" ] && [ ! -L "$UI_PARENT" ] || return 1
    [ ! -L "$UI_DIR" ] || return 1
    if [ ! -e "$UI_DIR" ]; then mkdir "$UI_DIR" || return 1; fi
    [ -d "$UI_DIR" ] || return 1
    chmod 755 "$UI_DIR" || return 1
    for _f in status log facts status.tmp log.tmp filter.tmp facts.tmp diag.tmp diag-latest.tmp status-save.tmp facts-save.tmp diag-save.tmp diag-latest-save.tmp diag-latest.txt deep-save.tmp deep-in.tmp; do
        [ ! -L "$UI_DIR/$_f" ] || return 1
    done
    return 0
}

# Byte size from "ls -l": Android toolbox has no link-count column (size is field 4), GNU ls does (field 5).
file_size() {
    _line=$(LC_ALL=C ls -l "$1" 2>/dev/null) || return 1
    set -- $_line
    _size=${5:-}
    case "$_size" in ''|*[!0-9]*) _size=${4:-};; esac
    case "$_size" in ''|*[!0-9]*) return 1;; esac
    print -r -- "$_size"
}

# Appends the last $2 lines of file $3 as "$1|line", never going over MAX_LINES in total.
emit_tail() {
    typeset total=0 skip line
    while IFS= read -r line || [ -n "$line" ]; do total=$((total + 1)); done < "$3"
    skip=$((total - $2))
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
        [ "$NLOG" -lt "$MAX_LINES" ] || return 0
        print -r -- "$1|${line:0:$MAX_LINE}" >> "$UI_DIR/log.tmp"
        NLOG=$((NLOG + 1))
    done < "$3"
}

# One log file: size checked, filtered, newest lines only.
collect_file() {
    typeset file=$1 name=$2 size
    [ -f "$file" ] && [ ! -L "$file" ] || return 0
    [ "$NLOG" -lt "$MAX_LINES" ] || return 0
    size=$(file_size "$file") || return 0
    if [ "$size" -gt "$MAX_SOURCE_BYTES" ]; then
        print -r -- "$name|(로그가 너무 커서 건너뜀)" >> "$UI_DIR/log.tmp"
        NLOG=$((NLOG + 1))
        return 0
    fi
    grep -a -v -E "$PRIV" "$file" > "$UI_DIR/filter.tmp" 2>/dev/null
    emit_tail "$name" "$PER_SOURCE" "$UI_DIR/filter.tmp"
}
# One package log directory: every *.log in it.
collect_source() {
    typeset dir=$1 name=${1##*/} file
    name=${name#gen5w.kr.}
    for file in "$dir"/*.log; do
        collect_file "$file" "$name"
    done
}

collect_log() {
    NLOG=0
    : > "$UI_DIR/log.tmp" || return 1
    # The wireless bridge first, so a busy package cannot push it out of the line budget.
    [ -d "$LOGS/gen5w.kr.bridge" ] && [ ! -L "$LOGS/gen5w.kr.bridge" ] && collect_source "$LOGS/gen5w.kr.bridge"
    # The wireless installer writes its log next to the folders, not inside one.
    collect_file "$NEMDIR/gen5w.kr.wireless.log" wireless
    collect_file "$NEMDIR/gen5wkr.recovery-worker.log" recovery
    # Service output (WAIT/FAIL lines of the bridge, start/stop of our packages) lands in the main
    # NEMESIS log on this unit, not in a package folder: take only our own lines from it.
    typeset nl="$NEMDIR/nemesis.log" nsize
    if [ -f "$nl" ] && [ ! -L "$nl" ] && nsize=$(file_size "$nl") && [ "$nsize" -le 1048576 ] && [ "$NLOG" -lt "$MAX_LINES" ]; then
        grep -a -E 'gen5w|bridge:|wireless' "$nl" 2>/dev/null | grep -a -v -E "$PRIV" > "$UI_DIR/filter.tmp"
        emit_tail nemesis 60 "$UI_DIR/filter.tmp"
    fi
    typeset dir
    for dir in "$LOGS"/gen5w.kr.*; do
        [ -d "$dir" ] && [ ! -L "$dir" ] || continue
        [ "${dir##*/}" != gen5w.kr.bridge ] || continue
        [ "$NLOG" -lt "$MAX_LINES" ] || break
        collect_source "$dir"
    done
    if [ "$NLOG" -lt "$MAX_LINES" ]; then
        $LOGCAT -d -v time 2>/dev/null | grep -a -E 'Gen5w|gen5w|FATAL EXCEPTION' | grep -a -v -E '\[TEST\]|ModeManagerService|getTopPackageName' | grep -a -v -E "$PRIV" > "$UI_DIR/filter.tmp"
        typeset keep=$LOGCAT_LINES room=$((MAX_LINES - NLOG))
        [ "$keep" -le "$room" ] || keep=$room
        emit_tail logcat "$keep" "$UI_DIR/filter.tmp"
    fi
    chmod 644 "$UI_DIR/log.tmp" && mv "$UI_DIR/log.tmp" "$UI_DIR/log"
}

host_alive() {
    typeset pid
    [ -f "$HOST_READY" ] && [ ! -L "$HOST_READY" ] || return 1
    IFS= read -r pid < "$HOST_READY"
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    grep -aq 'kr.gen5w.wirelesshost' "$PROC/$pid/cmdline" 2>/dev/null
}

# The save runs in the background with its own temp file names, so it never meets the main loop.
collect_status() {
    typeset up _rest ts host=dead relay=unknown backend apguard=on wired=no version= line tmp="$UI_DIR/${1:-status}.tmp"
    IFS=' ' read -r up _rest < "$UPTIME" 2>/dev/null
    ts=${up%%.*}
    case "$ts" in ''|*[!0-9]*) ts=;; esac
    host_alive && host=alive
    if [ -d "$BRIDGE" ]; then
        if [ -f "$BRIDGE/app/relay-v039.complete" ]; then relay=on; else relay=off; fi
        if [ -f "$BRIDGE/NEMESIS.data" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in package-version=*) version=${line#package-version=};; esac
            done < "$BRIDGE/NEMESIS.data"
        fi
    fi
    backend=$(getprop persist.gen5w.wifi.backend 2>/dev/null)
    [ -n "$backend" ] || backend=builtin
    [ -e "$NEMDIR/gen5wkr.apguard.off" ] && apguard=off
    [ -e "$NEMDIR/gen5wkr.wireless-disabled" ] && wired=yes
    typeset wlan=missing
    [ -d "$NETDIR_SYS/wlan0" ] && wlan=present
    {
        print -r -- "ts=$ts"
        print -r -- "boot=$(cat "$BOOT_ID_FILE" 2>/dev/null)"
        print -r -- "host=$host"
        print -r -- "relay=$relay"
        print -r -- "backend=$backend"
        print -r -- "version=$version"
        print -r -- "apguard=$apguard"
        print -r -- "wired=$wired"
        print -r -- "sw_wireless=$(switch_state wireless)"
        print -r -- "sw_timer=$(switch_state timer)"
        print -r -- "sw_bluelink=$(switch_state bluelink)"
        print -r -- "sw_adb=$(adb_state)"
        print -r -- "adb_health=$(adb_health)"
        print -r -- "adb_result=$(adb_result)"
        print -r -- "saved=$(saved_state)"
        print -r -- "removed=$(removed_state)"
        print -r -- "wlan=$wlan"
        recovery_status
    } > "$tmp" || return 1
    chmod 644 "$tmp" && mv "$tmp" "$UI_DIR/status"
}

# set_marker <name> <on|off>: off = marker present, on = marker absent. Never follows a link.
set_marker() {
    typeset m="$NEMDIR/gen5wkr.ui-$1-off"
    [ -d "$NEMDIR" ] && [ ! -L "$NEMDIR" ] && [ ! -L "$m" ] || return 1
    case "$2" in
        off) [ -f "$m" ] || : > "$m";;
        on) rm -f "$m";;
    esac
}
# Reads at most 8 lines; only "wireless|timer|bluelink=on|off" is accepted, anything else is ignored.
apply_requests() {
    typeset size rpid waited=0
    [ -f "$REQUEST" ] && [ ! -L "$REQUEST" ] && [ -r "$REQUEST" ] || return 0
    # The app owns this file, so it can be swapped after the checks above (for a pipe that never
    # ends, or a huge line). A real request is a few dozen bytes: refuse anything over 256 bytes,
    # and read in a background process that is stopped after 3 seconds, so this service never hangs.
    size=$(file_size "$REQUEST") || return 0
    [ "$size" -le 256 ] || return 0
    read_requests &
    rpid=$!
    while kill -0 "$rpid" 2>/dev/null && [ "$waited" -lt 3 ]; do sleep 1; waited=$((waited + 1)); done
    if kill -0 "$rpid" 2>/dev/null; then kill "$rpid" 2>/dev/null; fi
    wait "$rpid" 2>/dev/null
    return 0
}
read_requests() {
    typeset line n=0 boot= expires= current up _rest seen_boot=0 seen_expires=0 removal= value recovery=
    typeset -a actions
    # Read the single opened file once; atomic app replacement cannot mix an old
    # envelope with new actions. The parent still bounds hostile reads to 3s.
    while IFS= read -r line; do
        n=$((n + 1))
        [ "$n" -le 10 ] || return 0
        case "$line" in
            boot=*) [ "$seen_boot" = 0 ] || return 0; seen_boot=1; boot=${line#boot=};;
            expires=*) [ "$seen_expires" = 0 ] || return 0; seen_expires=1; expires=${line#expires=};;
            *) actions[${#actions[@]}]=$line;;
        esac
    done < "$REQUEST"
    current=$(cat "$BOOT_ID_FILE" 2>/dev/null)
    [ -n "$current" ] && [ "$boot" = "$current" ] || return 0
    case "$expires" in ''|*[!0-9]*) return 0;; esac
    [ "${#expires}" -le 9 ] || return 0
    IFS=' ' read -r up _rest < "$UPTIME" || return 0
    up=${up%%.*}
    case "$up" in ''|*[!0-9]*) return 0;; esac
    [ "${#up}" -le 9 ] || return 0
    expires=$((10#$expires)); up=$((10#$up))
    [ "$expires" -ge "$up" ] && [ "$expires" -le "$((up + 30))" ] || return 0
    for line in "${actions[@]}"; do
        case "$line" in recovery=*)
            [ "${#actions[@]}" = 1 ] || return 0
            recovery=${line#recovery=}
            handle_recovery "$recovery"; return 0;;
        esac
    done
    if recovery_lock_live; then return 0; fi
    # Recovery owns all changing actions; diagnosis saving remains read-only.
    case "$(cat "$NEMDIR/gen5w-kr-integrated/state" 2>/dev/null)" in recovery-required|applying|removing|recovering)
        for line in "${actions[@]}"; do case "$line" in save=*) handle_save "${line#save=}";; esac; done
        return 0;;
    esac
    # Removal is exclusive. A repeated completed request must not recreate the
    # markers it just cleared, or restart ADB while packages are being removed.
    for line in "${actions[@]}"; do
        case "$line" in remove=*)
            value=${line#remove=}
            case "$value" in ''|*[!0-9]*) continue;; esac
            [ "${#value}" -le 10 ] || continue
            [ -z "$removal" ] || return 0
            removal=$value;;
        esac
    done
    if [ -n "$removal" ]; then handle_remove "$removal"; return 0; fi
    for line in "${actions[@]}"; do
        case "$line" in
            wireless=on|wireless=off|timer=on|timer=off|bluelink=on|bluelink=off)
                # While a removal runs, markers are not put back right after the removal cleared them.
                [ -e "$NEMDIR/gen5wkr.ui-removing" ] || set_marker "${line%%=*}" "${line#*=}" || :;;
            adb=on:*|adb=off:*) handle_adb "${line#adb=}";;
            save=*) handle_save "${line#save=}";;
            remove=*) handle_remove "${line#remove=}";;
        esac
    done
}
# Read-only facts about this unit, for the next version's features (adb, update check, removal).
# Nothing here changes anything. Lines pass the same privacy filter as the log, at most FACT_LINES.
collect_facts() {
    typeset out="$UI_DIR/${1:-facts}.tmp" n=0 line k v
    : > "$out" || return 1
    {
        for k in persist.sys.usb.config sys.usb.config service.adb.tcp.port persist.adb.tcp.port ro.adb.secure ro.product.ota ro.build.version.release; do
            v=$(getprop "$k" 2>/dev/null)
            print -r -- "prop $k=$v"
        done
        print -r -- "-- /data/nemesis (owner, mode)"
        ls -ln "$NEMDIR" 2>/dev/null
        ls -ln "$DATA" 2>/dev/null | grep -a -F " nemesis"
        print -r -- "-- packages matching ota|fota|redbend|nemesis|update"
        "$PM" list packages 2>/dev/null | grep -a -i -E 'ota|redbend|nemesis|update'
        print -r -- "-- wifi (read-only)"
        for k in wifi.interface init.svc.wpa_supplicant init.svc.hostapd init.svc.p2p_supplicant persist.gen5w.wifi.backend wlan.driver.status; do
            print -r -- "prop $k=$(getprop "$k" 2>/dev/null)"
        done
        print -r -- "interfaces: $(ls /sys/class/net 2>/dev/null)"
        for k in wlan0 ap0 p2p0; do
            [ -d "/sys/class/net/$k" ] && print -r -- "$k: $(cat /sys/class/net/$k/operstate 2>/dev/null)"
        done
        ps 2>/dev/null | grep -a -E 'hostapd|wpa_supplicant|dnsmasq|dhcp|wirelesshost'
        print -r -- "-- usb mount"
        grep -a -F "$USB" "$MOUNTS" 2>/dev/null
    } 2>/dev/null | grep -a -v -E "$PRIV" | while IFS= read -r line; do
        [ "$n" -lt "$FACT_LINES" ] || break
        n=$((n + 1))
        print -r -- "${line:0:$MAX_LINE}"
    done >> "$out"
    chmod 644 "$out" && mv "$out" "$UI_DIR/facts"
}

# Deep section of a saved diagnosis (USB file only, never shown on the screen): everything needed to
# find out why the wireless host or the Wi-Fi access point is not working, without a second visit.
# Read-only; every line passes the privacy filter; each part is bounded. Command output arrives on
# stdin: deep_tail <title> <newest lines to keep>.
deep_tail() {
    typeset title=$1 keep=$2 f="$UI_DIR/deep-in.tmp" total=0 skip line
    grep -a -v -E "$PRIV" > "$f" 2>/dev/null
    while IFS= read -r line || [ -n "$line" ]; do total=$((total + 1)); done < "$f"
    skip=$((total - keep))
    print -r -- "-- $title ($total lines)"
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
        print -r -- "${line:0:$DEEP_LINE}"
    done < "$f"
}
deep_logs() {
    typeset file size d n
    for d in "$LOGS"/gen5w.kr.*; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        for file in "$d"/*.log; do
            [ -f "$file" ] && [ ! -L "$file" ] || continue
            size=$(file_size "$file") || size=unknown
            n=${d##*/}; n=${n#gen5w.kr.}
            if [ "$size" = unknown ] || [ "$size" -le 262144 ]; then
                cat "$file" 2>/dev/null | deep_tail "package log $n/${file##*/} ($size bytes)" 120
            else
                print -r -- "-- package log $n/${file##*/}: $size bytes, too large"
            fi
        done
    done
}
# NEMESIS appends service output to logs/<package>/<service>.log with no size limit.
# Keep each of ours under PKG_LOG_MAX: rewrite in place (same file, so the
# NEMESIS O_APPEND writer goes on) with only the newest PKG_LOG_KEEP lines.
PKG_LOG_MAX=${UILOG_TEST_PKG_LOG_MAX:-1048576}
PKG_LOG_KEEP=2000
trim_pkg_logs() {
    typeset d file size tmp total skip line
    for d in "$LOGS"/gen5w.kr.*; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        tmp=$d/.gen5w-trim.tmp
        for file in "$d"/*.log; do
            [ -f "$file" ] && [ ! -L "$file" ] || continue
            size=$(file_size "$file") || continue
            [ "$size" -gt "$PKG_LOG_MAX" ] || continue
            [ ! -L "$tmp" ] || return 0
            total=0
            while IFS= read -r line || [ -n "$line" ]; do total=$((total + 1)); done < "$file"
            skip=$((total - PKG_LOG_KEEP))
            {
                print -r -- "gen5w: trimmed from $size bytes; newest $PKG_LOG_KEEP lines kept"
                while IFS= read -r line || [ -n "$line" ]; do
                    if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
                    print -r -- "$line"
                done < "$file"
            } > "$tmp" 2>/dev/null && cat "$tmp" > "$file" 2>/dev/null
            rm -f "$tmp"
        done
    done
}
# Saved Android log of the logring service (up to 10 MiB), oldest file first.
# Copied whole and unfiltered.
saved_logcat() {
    typeset f d="$NEMDIR/gen5wkr.logs"
    [ -d "$d" ] && [ ! -L "$d" ] || return 0
    for f in "$d/logcat.txt.4" "$d/logcat.txt.3" "$d/logcat.txt.2" "$d/logcat.txt.1" "$d/logcat.txt"; do
        [ -f "$f" ] && [ ! -L "$f" ] && cat "$f" 2>/dev/null
    done
}
deep_markers() {
    typeset f size
    for f in "$NEMDIR"/gen5wkr.*; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        size=$(file_size "$f") || continue
        [ "$size" -le 200 ] || { print -r -- "${f##*/}: $size bytes"; continue; }
        print -r -- "${f##*/}: $(cat "$f" 2>/dev/null)"
    done
}
collect_deep() {
    typeset out="$UI_DIR/${1:-deep}.tmp" hd=/data/data/kr.gen5w.wirelesshost f p
    : > "$out" || return 1
    {
        print -r -- "-- time and boot"
        print -r -- "uptime: $(cat "$UPTIME" 2>/dev/null)"
        print -r -- "boot_completed=$(getprop sys.boot_completed 2>/dev/null) date=$(date 2>/dev/null)"
        print -r -- "-- collector self-check: what the screen log sees"
        err_export
        ls -l "$LOGS" 2>/dev/null
        ls -l "$LOGS/gen5w.kr.bridge" 2>/dev/null
        print -r -- "bridge.log size per collector: $(file_size "$LOGS/gen5w.kr.bridge/bridge.log")"
        ls -l "$UI_DIR" 2>/dev/null
        deep_markers | deep_tail "gen5wkr markers (name: content)" 60
        ls -ln "$NEMDIR/gen5wkr.bootguard" "$NEMDIR/gen5w-kr-integrated" 2>/dev/null | deep_tail "bootguard and integrated folders" 40
        cat "$NEMDIR/gen5w.kr.wireless.log" 2>/dev/null | deep_tail "wireless install log" 150
        cat "$NEMDIR/nemesis.log" 2>/dev/null | grep -a -E 'gen5w|bridge|wireless|reboot|boot|failed|error' | deep_tail "nemesis.log lines about gen5w/boot/errors" 150
        deep_logs
        print -r -- "-- wireless host app"
        ls -ln "$hd" "$hd/files" 2>/dev/null | deep_tail "host app folders" 40
        for f in "$hd"/files/*; do
            [ -f "$f" ] && [ ! -L "$f" ] || continue
            p=$(file_size "$f") || continue
            [ "$p" -le 65536 ] || continue
            cat "$f" 2>/dev/null | deep_tail "host file ${f##*/} ($p bytes)" 40
        done
        err_run core collect service-state dumpsys activity services kr.gen5w.wirelesshost | deep_tail "dumpsys: host service state" 80
        err_run core collect package-state dumpsys package kr.gen5w.wirelesshost | grep -a -E 'versionCode|versionName|userId|codePath|firstInstall|lastUpdate|enabled|stopped|pkgFlags|requested permissions|android.permission|declared' | deep_tail "dumpsys: host package" 60
        err_run core collect packages "$PM" list packages -f | grep -a -i -E 'gen5w|iap2|dipo|carplay|projection|hotspot|wifi|hkmc' | deep_tail "packages (projection/wifi related)" 60
        ps 2>/dev/null | grep -a -E 'gen5w|wirelesshost|hostapd|wpa_supplicant|dnsmasq|dhcp|iap|dipo|DiPO|ium|nemesis|zygote|system_server' | deep_tail "processes" 40
        print -r -- "-- wifi and network"
        getprop 2>/dev/null | grep -a -i -E 'wifi|wlan|hotspot|tether|ap\.|ium|gen5w|carplay|init\.svc\.(hostapd|wpa|dhcp|dnsmasq|p2p|netd)|sys\.boot|ro\.build\.(fingerprint|version\.release)|ro\.product\.(model|name)|net\.' | deep_tail "getprop (wifi, projection, boot)" 90
        for f in wlan0 ap0 p2p0 bt-pan; do ifconfig "$f" 2>&1; done | deep_tail "ifconfig per interface" 40
        err_run core collect netcfg netcfg | deep_tail "netcfg" 20
        ls -ln /data/misc/wifi /data/misc/wifi/sockets /data/misc/dhcp 2>/dev/null | deep_tail "wifi data folders (names only, no contents)" 40
        err_run core collect kernel dmesg | grep -a -i -E 'bcmdhd|dhd|wlan|wifi|wl_|hostapd|p2p|sdio|firmware|nvram|killed process|out of memory' | deep_tail "kernel messages about wifi" 100
        print -r -- "-- storage and mounts (why the USB drive log may refuse to write)"
        cat "$MOUNTS" 2>/dev/null | grep -a -E 'usb|media_rw|fuse|vold|sdcard|storage' | deep_tail "mount table (usb, fuse, storage)" 30
        ls -ln /mnt /mnt/media_rw /storage /dev/block/vold 2>&1 | deep_tail "storage folders" 40
        ls -ln "$USB" 2>&1 | deep_tail "usb root listing (names only)" 60
        print -r -- "-- telematics subscription state read by the stock hotspot menu (read-only; only subscription/status style fields)"
        for f in prov_info service_info; do
            content query --uri "content://com.hkmc.telematics.service.util.db.VehicleSettingProvider/$f" 2>&1 | grep -a -o -i -E '(prov|serv|subscri|status|state|enable|bluelink|hotspot|wifi|expire|valid|type|code)[A-Za-z_]*=[^,]*' | deep_tail "$f (selected fields)" 40
        done
        print -r -- "-- vehicle feature files"
        ls -ln /system/build.prop /system/onebin/oshev_kr/featurexml.cfg /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml /system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml /system/etc/permissions/com.hkmc.software.wifihotspot.xml 2>/dev/null
        grep -a -E 'ium|gen5w|carplay|wireless|hotspot' /system/build.prop 2>/dev/null | deep_tail "build.prop lines" 20
        grep -a -i -E 'wireless|carplay|hotspot|wifi|projection' /system/onebin/oshev_kr/featurexml.cfg 2>/dev/null | deep_tail "featurexml lines" 40
        ls -ln "$BRIDGE/app" 2>/dev/null | deep_tail "bridge app folder" 30
        print -r -- "-- logcat"
        err_run core collect logcat-main "$LOGCAT" -d -v time | grep -a -v -E '\[TEST\]|ModeManagerService|BluetoothPhoneUtils|AudioPolicy|isDiPOActivated|onBTCMBusyStatusChanged|connectProfile is null|mDeletingStatus = 10|getTopPackageName' | grep -a -E 'FATAL|Gen5w|gen5w|wirelesshost|BridgeHost|hostapd|wpa_supplicant|WifiStateMachine|WifiService|SoftAp|[Tt]ether|[Cc]ar[Pp]lay|iAP2|Iap2|DiPO|PhoneProjection|BTCM|Bluetooth|HFP|A2DP|bt_|btif|WirelessPhoneProjection|[Hh]ot[Ss]pot|[Bb]lue[Ll]ink|[Tt]elematics|[Ss]ubscri|WifiManager|[Ww]ifi[Aa]p|[Tt]oast|ActivityManager.*(died|crash|ANR|Killing|Start proc.*gen5w)|StrictMode' | deep_tail "logcat: wireless, wifi, crashes" 450
        print -r -- "-- saved Android log (logring): copied whole to logcat-<n>.txt next to this file"
        print -r -- '-- collection status and first failures'
        err_export
    } 2>/dev/null >> "$out"
    chmod 644 "$out"
}

# The USB must be mounted as a FAT-type filesystem (no links possible); prints nothing, returns 0/1.
usb_fs_ok() {
    typeset src mp fs _r
    while IFS=' ' read -r src mp fs _r; do
        [ "$mp" = "$USB" ] || continue
        case "$fs" in vfat|exfat|texfat|sdfat|fuse) return 0;; esac
    done < "$MOUNTS"
    return 1
}

# Diagnosis save: status + log + facts into one text file on the USB stick (when mounted) and
# always a copy in UI_DIR. Needs a real mount (an unmounted /storage/usb0 is a plain folder).
do_save() {
    typeset n=$1 result=nousb dest tmp f
    collect_facts facts-save || :
    collect_deep deep-save || :
    tmp="$UI_DIR/diag-save.tmp"
    {
        print -r -- "Gen5W KR diagnosis #$n"
        for f in status facts log; do
            print -r -- "===== $f"
            [ -f "$UI_DIR/$f" ] && [ ! -L "$UI_DIR/$f" ] && cat "$UI_DIR/$f"
        done
        print -r -- "===== deep"
        [ -f "$UI_DIR/deep-save.tmp" ] && [ ! -L "$UI_DIR/deep-save.tmp" ] && cat "$UI_DIR/deep-save.tmp"
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; set_saved "$n" fail; return; }
    chmod 644 "$tmp"
    cat "$tmp" > "$UI_DIR/diag-latest-save.tmp" && mv "$UI_DIR/diag-latest-save.tmp" "$UI_DIR/diag-latest.txt" || result=fail
    if usb_fs_ok && [ -d "$USB" ] && [ ! -L "$USB" ]; then
        dest=$USB/gen5w-kr-diag
        # FAT-type sticks cannot hold links; the checks and the no-overwrite write also cover a
        # stick that was prepared by someone else. Every path we write is checked right before use.
        if [ ! -L "$dest" ] && mkdir -p "$dest" 2>/dev/null && [ ! -L "$dest" ]             && [ ! -e "$dest/diag-$n.txt.tmp" ] && [ ! -L "$dest/diag-$n.txt" ]             && ( set -C; cat "$tmp" > "$dest/diag-$n.txt.tmp" ) 2>/dev/null             && [ ! -L "$dest/diag-$n.txt.tmp" ] && mv "$dest/diag-$n.txt.tmp" "$dest/diag-$n.txt" 2>/dev/null; then
            result=usb
            # Full saved Android log next to it. Never fails the save above.
            if [ ! -e "$dest/logcat-$n.txt" ] && [ ! -L "$dest/logcat-$n.txt" ]; then
                ( set -C; saved_logcat > "$dest/logcat-$n.txt" ) 2>/dev/null
                [ -L "$dest/logcat-$n.txt" ] || [ -s "$dest/logcat-$n.txt" ] || rm -f "$dest/logcat-$n.txt" 2>/dev/null
            fi
        else
            [ -L "$dest/diag-$n.txt.tmp" ] || rm -f "$dest/diag-$n.txt.tmp" 2>/dev/null
            result=fail
        fi
    fi
    rm -f "$tmp" "$UI_DIR/deep-save.tmp" "$UI_DIR/deep-in.tmp"
    set_saved "$n" "$result"
}
set_saved() {
    [ ! -L "$SAVED" ] || return 0
    print -r -- "$1 $2" > "$SAVED.tmp" 2>/dev/null && mv "$SAVED.tmp" "$SAVED" 2>/dev/null
}
# A new save number in the request starts one save (the number is digits only, at most 10).
handle_save() {
    typeset n=$1 last _r
    case "$n" in ''|*[!0-9]*) return 0;; esac
    [ "${#n}" -le 10 ] || return 0
    [ -d "$UI_DIR" ] && [ ! -L "$UI_DIR" ] || return 0
    [ ! -L "$SAVED" ] || return 0
    [ -f "$SAVED" ] && IFS=' ' read -r last _r < "$SAVED"
    [ "$last" = "$n" ] && return 0
    set_saved "$n" working
    # In the background: collecting the unit facts can take longer than the request reader's time limit.
    ( do_save "$n"; collect_status status-save || : ) &
}
saved_state() {
    typeset n r
    [ -f "$SAVED" ] && [ ! -L "$SAVED" ] && IFS=' ' read -r n r < "$SAVED"
    print -r -- "${n:-0}:${r:-none}"
}
# adb is a one-time command "on:<number>" / "off:<number>". The last applied number is kept in a root-owned
# file, so the request file left in the app folder from before a reboot cannot switch it on again.
ADBTOK=$NEMDIR/gen5wkr.ui-adb
handle_adb() {
    typeset v=$1 state n last _r result=applied
    state=${v%%:*}
    n=${v#*:}
    case "$n" in ''|*[!0-9]*) return 0;; esac
    [ "${#n}" -le 10 ] || return 0
    [ -d "$NEMDIR" ] && [ ! -L "$NEMDIR" ] && [ ! -L "$ADBTOK" ] || return 0
    [ -f "$ADBTOK" ] && IFS=' ' read -r last _r < "$ADBTOK"
    [ "$last" = "$n" ] && return 0
    [ ! -L "$ADBTOK.tmp" ] || return 0
    # Consume before acting to prevent reboot replay, but retain a visible result.
    print -r -- "$n working" > "$ADBTOK.tmp" 2>/dev/null && mv "$ADBTOK.tmp" "$ADBTOK" 2>/dev/null || return 0
    set_adb "$state" || result=failed
    print -r -- "$n $result" > "$ADBTOK.tmp" 2>/dev/null && mv "$ADBTOK.tmp" "$ADBTOK" 2>/dev/null
}
adb_result() {
    typeset n r
    [ -f "$ADBTOK" ] && [ ! -L "$ADBTOK" ] && IFS=' ' read -r n r < "$ADBTOK"
    print -r -- "${n:-0}:${r:-none}"
}
# adb over the car's Wi-Fi, for this boot only: service.adb.tcp.port is a runtime property and is
# gone after a reboot, and nothing persistent is set. The stock key check (ro.adb.secure) still
# applies. Only restarts adbd when the state really changes.
ADB_PORT=5555
adb_port() {
    typeset p
    p=$(getprop service.adb.tcp.port 2>/dev/null)
    case "$p" in ''|*[!0-9]*) p=0;; esac
    print -r -- "$p"
}
adb_state() { if [ "$(adb_port)" -gt 0 ]; then echo on; else echo off; fi; }
# Inspect kernel socket state, never infer listening from a property alone.
# 0=LISTEN found, 1=readable tables contain no listener, 2=unobservable.
adb_listening() {
    typeset p=$1 file line observed=0
    # This UI controls only 5555 (0x15B3); other externally configured ports are
    # explicitly unobserved, not mislabeled as a verified listener.
    [ "$p" = 5555 ] || return 2
    for file in "$PROCNET/tcp" "$PROCNET/tcp6"; do
        [ -r "$file" ] || continue
        observed=1
        while IFS= read -r line; do
            set -- $line
            [ "${2##*:}" != 15B3 ] || [ "${4:-}" != 0A ] || return 0
        done < "$file"
    done
    [ "$observed" = 1 ] && return 1
    return 2
}
adb_health() {
    typeset p daemon rc
    p=$(adb_port)
    if [ "$p" = 0 ]; then
        adb_listening "$ADB_PORT"; rc=$?
        case "$rc" in 0) echo unexpected-listener;; 1) echo off;; *) echo unknown;; esac
        return
    fi
    daemon=$(getprop init.svc.adbd 2>/dev/null)
    case "$daemon" in running) ;; stopped|stopping|restarting) echo daemon-down; return;; *) echo unknown; return;; esac
    adb_listening "$p"; rc=$?
    case "$rc" in 0) echo listening;; 1) echo not-listening;; *) echo unknown;; esac
}
set_adb() {
    if [ "$1" = on ]; then
        if [ "$(adb_port)" = "$ADB_PORT" ] && [ "$(adb_health)" = listening ]; then return 0; fi
        err_run core adb set-port setprop service.adb.tcp.port "$ADB_PORT" || return 1
    else
        if [ "$(adb_port)" = 0 ]; then
            adb_listening "$ADB_PORT"; [ "$?" != 1 ] || return 0
        fi
        err_run core adb set-port setprop service.adb.tcp.port 0 || return 1
    fi
    err_run core adb stop stop adbd || return 1
    err_run core adb start start adbd
}
# In-car removal of every Gen5W KR package EXCEPT the core app (which runs this service and the
# screen; removing it ends both, so the last step is left to NEMESIS Manager). Same method as the
# USB kit: each package's own preuninstall hook runs first and must succeed (older NEMESIS ignores
# a failing hook), then NEMESIS removes the package. The first failure stops everything and is
# reported; nothing is forced. Runs in the background so the request reader's time limit does not
# cut it off, and a lock marker keeps two removals from overlapping.
REMOVE_IDS='localhotspot drivelog bluelink timer bridge audio wireless dongle'
set_removed() {
    [ ! -L "$REMOVED" ] || return 0
    print -r -- "$1 $2${3:+ $3}" > "$REMOVED.tmp" 2>/dev/null && mv "$REMOVED.tmp" "$REMOVED" 2>/dev/null
}
hook_path() {
    typeset section= line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '['*']') section=$line;;
            preuninstall=*) [ "$section" = '[nemesis]' ] && { print -r -- "${line#*=}"; return 0; };;
        esac
    done < "$1"
    return 1
}
# Stop one package's own services (and the bridge's Android app) before its restore
# hook runs: NEMESIS stops them only after the hook. Core is never removed here,
# so this worker (a child of core's collector) is never stopped by it.
stop_services() {
    typeset tree=$1 id=$2 section= line name mark value
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        case "$line" in
            '['*']') section=$line;;
            name=*) case "$section" in '[service.'*']')
                name=${line#name=}
                case "$name" in ''|*/*|*..*|*[!a-zA-Z0-9_.-]*) return 1;; esac
                "$NEM" service stop "$id/$name" >/dev/null 2>&1 || return 1
                mark=$NEMDIR/pids/$id+$name.stopped
                [ ! -L "$NEMDIR/pids" ] && [ ! -L "$mark" ] && [ -f "$mark" ] || return 1
                IFS= read -r value < "$mark" || return 1
                [ "$value" = 1 ] || return 1;;
            esac;;
        esac
    done < "$tree/NEMESIS.data"
    if [ "$id" = gen5w.kr.bridge ] && [ -x "$AM" ]; then
        "$AM" force-stop kr.gen5w.wirelesshost >/dev/null 2>&1 || return 1
    fi
}
# Same cold boot as the USB removal: the bridge removal puts stock system app
# files (APK/ODEX) back, and the USB kit always cold-boots after that.
cold_reboot() {
    sync
    if [ -n "${UILOG_TEST_REBOOT:-}" ]; then "$UILOG_TEST_REBOOT"; return; fi
    [ -x /system/bin/d_audio ] && /system/bin/d_audio -c reboot force_normal >/dev/null 2>&1 && return 0
    /system/bin/reboot force_normal >/dev/null 2>&1
    /system/bin/reboot >/dev/null 2>&1
}
run_hook() {
    typeset tree=$1 helper path
    [ -d "$tree" ] && [ ! -L "$tree" ] && [ -f "$tree/NEMESIS.data" ] || return 1
    for helper in "$tree"/bin/*; do
        [ ! -f "$helper" ] || { [ ! -L "$helper" ] && chmod 755 "$helper"; } || return 1
    done
    path=$(hook_path "$tree/NEMESIS.data") || return 0
    case "$path" in ''|/*|*..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
    [ -f "$tree/$path" ] && [ ! -L "$tree/$path" ] || return 1
    ( cd "$tree" && "$SH" "$path" ) >/dev/null 2>&1
}
do_remove() {
    typeset n=$1 short id lock="$NEMDIR/gen5wkr.ui-removing"
    typeset tx="$NEMDIR/gen5w-kr-integrated" guard
    [ ! -L "$tx" ] || return 0
    mkdir -p "$tx" || return 0
    guard=$(recovery_guard_path) || return 0
    mkdir "$guard" 2>/dev/null || { set_removed "$n" failed busy; return 0; }
    mkdir "$tx/lock" 2>/dev/null || { rmdir "$guard"; set_removed "$n" failed busy; return 0; }
    typeset lockpid rest
    IFS=' ' read -r lockpid rest < /proc/self/stat || return 0
    print -r -- "$lockpid" > "$tx/lock/pid" || return 0
    rmdir "$guard" || return 0
    trap 'rm -f "$tx/lock/pid"; rmdir "$tx/lock" 2>/dev/null' EXIT
    # Request acceptance precedes this background worker. Another transaction
    # may have failed in between; only this under-lock check authorizes removal.
    if [ -e "$tx/state" ] || [ -L "$tx/state" ]; then
        typeset state
        [ -f "$tx/state" ] && [ ! -L "$tx/state" ] && state=$(cat "$tx/state" 2>/dev/null) ||
            { set_removed "$n" failed recovery-required; return 0; }
        case "$state" in
            committed|rolled-back) ;;
            *) set_removed "$n" failed recovery-required; return 0;;
        esac
    fi
    [ ! -L "$lock" ] && ( set -C; : > "$lock" ) 2>/dev/null || return 0
    set_removed "$n" working
    if [ ! -x "$NEM" ]; then set_removed "$n" failed nemesis; rm -f "$lock"; return 0; fi
    typeset removed_any=no
    for short in $REMOVE_IDS; do
        id=gen5w.kr.$short
        [ -d "$APPS/$id" ] || continue
        set_removed "$n" working "$id"
        if [ ! -L "$APPS/$id" ] && [ -f "$APPS/$id/NEMESIS.data" ] && [ ! -L "$APPS/$id/NEMESIS.data" ]; then
            stop_services "$APPS/$id" "$id" || { set_removed "$n" failed "$id"; rm -f "$lock"; return 0; }
        fi
        removed_any=yes
        if ! run_hook "$APPS/$id"; then set_removed "$n" failed "$id"; rm -f "$lock"; return 0; fi
        if ! "$NEM" uninstall "$id" >/dev/null 2>&1; then set_removed "$n" failed "$id"; rm -f "$lock"; return 0; fi
        [ ! -e "$APPS/$id" ] || set_removed "$n" failed "$id"
        [ ! -e "$APPS/$id" ] || { rm -f "$lock"; return 0; }
    done
    # Markers that only the removed packages looked at (same ones the USB removal clears).
    for _m in wireless-disabled ap-match ap-hotspot-feature ui-wireless-off ui-timer-off ui-bluelink-off; do
        [ -L "$NEMDIR/gen5wkr.$_m" ] || rm -f "$NEMDIR/gen5wkr.$_m"
    done
    # Saved Android log of the logring service (stopped with the package above).
    [ -L "$NEMDIR/gen5wkr.logs" ] || rm -rf "$NEMDIR/gen5wkr.logs"
    set_removed "$n" done
    rm -f "$lock"
    rm -f "$tx/lock/pid"; rmdir "$tx/lock" 2>/dev/null
    [ "$removed_any" = no ] || cold_reboot
}
handle_remove() {
    typeset n=$1 last _r
    case "$n" in ''|*[!0-9]*) return 0;; esac
    [ "${#n}" -le 10 ] || return 0
    [ -d "$NEMDIR" ] && [ ! -L "$NEMDIR" ] || return 0
    [ ! -L "$REMOVED" ] || return 0
    [ -f "$REMOVED" ] && IFS=' ' read -r last _r < "$REMOVED"
    [ "$last" = "$n" ] && return 0
    do_remove "$n" &
}
removed_state() {
    typeset n r id
    [ -f "$REMOVED" ] && [ ! -L "$REMOVED" ] && IFS=' ' read -r n r id < "$REMOVED"
    print -r -- "${n:-0}:${r:-none}${id:+:$id}"
}
switch_state() { if [ -e "$NEMDIR/gen5wkr.ui-$1-off" ]; then echo off; else echo on; fi; }

recovery_guard_path() {
    typeset boot
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    case "$boot" in ''|*[!0-9a-f-]*) return 1;; esac
    [ "${#boot}" = 36 ] || return 1
    echo "$NEMDIR/gen5w-kr-integrated/acquire-guard.$boot"
}
recovery_lock_live() {
    typeset pid rest tx="$NEMDIR/gen5w-kr-integrated" guard
    guard=$(recovery_guard_path) || return 0
    [ ! -e "$guard" ] && [ ! -L "$guard" ] || return 0
    [ -e "$tx/lock" ] || [ -L "$tx/lock" ] || return 1
    [ ! -L "$tx/lock" ] && [ ! -L "$tx/lock/pid" ] && [ -f "$tx/lock/pid" ] || return 0
    IFS=' ' read -r pid rest < "$tx/lock/pid" || return 0
    case "$pid" in ''|*[!0-9]*) return 0;; esac
    [ "${#pid}" -le 9 ] || return 0
    kill -0 "$pid" 2>/dev/null
}
recovery_status() {
    typeset tx="$NEMDIR/gen5w-kr-integrated" rb="$NEMDIR/gen5wkr.recovery/current"
    typeset state=unknown available=no reason=unknown stage=unknown token=0 result=none line n=0
    if [ ! -e "$tx" ]; then state=none
    elif [ ! -L "$tx" ] && [ -f "$tx/state" ] && [ ! -L "$tx/state" ]; then
        case "$(cat "$tx/state")" in
            recovery-required|applying|removing|recovering) state=required;;
            rolled-back) state=restored;;
            committed) state=none;;
        esac
    fi
    # This is preliminary availability only; worker validates every checksum
    # under the transaction lock before it touches /system.
    if [ "$state" = required ]; then
        reason=runner-unavailable
        if [ -d "$rb" ] && [ ! -L "$rb" ] && [ ! -L "${rb%/*}" ] &&
            [ -f "$rb/recovery.sh" ] && [ ! -L "$rb/recovery.sh" ]; then
            reason=snapshot-invalid
            if [ -f "$tx/prior/complete" ] && [ -f "$tx/prior/RECOVERY.md5" ] && [ ! -L "$tx/prior" ] && [ ! -L "$tx/prior/complete" ] && [ ! -L "$tx/prior/RECOVERY.md5" ]; then available=yes; reason=ready; fi
        fi
        recovery_lock_live && { reason=busy; available=no; }
    fi
    if [ -f "$NEMDIR/gen5wkr.recovery-result" ] && [ ! -L "$NEMDIR/gen5wkr.recovery-result" ]; then
        while IFS= read -r line; do
            n=$((n+1)); [ "$n" -le 4 ] || break
            case "$line" in
                recovery_request=*) token=${line#*=}; case "$token" in ''|*[!0-9]*) token=0;; esac; [ "${#token}" -le 10 ] || token=0;;
                recovery_result=working|recovery_result=restored|recovery_result=failed|recovery_result=interrupted) result=${line#*=};;
                recovery_reason=rollback-failed|recovery_reason=interrupted|recovery_reason=snapshot-invalid|recovery_reason=unsafe-path|recovery_reason=runner-unavailable|recovery_reason=stock-recovery-required)
                    [ "$state" = required ] && reason=${line#*=};;
            esac
        done < "$NEMDIR/gen5wkr.recovery-result"
    fi
    if [ "$result" = working ]; then
        if recovery_lock_live; then state=working; available=no
        else result=interrupted; reason=interrupted; fi
    fi
    # An interrupted stock recovery is finished only by the stock recovery USB;
    # the snapshot rollback refuses it, so do not offer the button.
    if [ "$state" = required ] && { [ -e "$tx/stock-recovery-mode" ] || [ -L "$tx/stock-recovery-mode" ]; }; then
        available=no; reason=stock-recovery-required
    fi
    if [ "$state" = none ]; then token=0; result=none; reason=unknown; fi
    # Never print raw failure messages: they can contain paths or identifiers.
    if [ -f "$tx/failure" ] && [ ! -L "$tx/failure" ]; then
        IFS= read -r line < "$tx/failure"
        case "$line" in *gen5w.kr.localhotspot*) stage=localhotspot;; *gen5w.kr.bridge*) stage=bridge;; *gen5w.kr.audio*) stage=audio;; *gen5w.kr.core*) stage=core;; *gen5w.kr.wireless*) stage=wireless;; *) stage=install;; esac
    fi
    echo "recovery_state=$state"
    echo "recovery_available=$available"
    echo "recovery_reason=$reason"
    echo "recovery_stage=$stage"
    echo "recovery_request=$token"
    echo "recovery_result=$result"
}
handle_recovery() {
    typeset token=$1 runner="$NEMDIR/gen5wkr.recovery/current/recovery.sh" last= line
    case "$token" in ''|*[!0-9]*) return 0;; esac
    [ "${#token}" -le 10 ] || return 0
    [ -f "$runner" ] && [ ! -L "$runner" ] && [ ! -L "${runner%/*}" ] && [ ! -L "$NEMDIR/gen5wkr.recovery" ] || return 0
    if [ -f "$NEMDIR/gen5wkr.recovery-result" ] && [ ! -L "$NEMDIR/gen5wkr.recovery-result" ]; then
        IFS= read -r line < "$NEMDIR/gen5wkr.recovery-result"
        [ "$line" != "recovery_request=$token" ] || return 0
    fi
    [ ! -L "$NEMDIR/gen5wkr.recovery-worker.log" ] || return 0
    # No pipes to collector: core removal must not break the recovery worker.
    ( trap '' HUP; exec "$SH" "$SCRIPT_DIR/recovery-launch.sh" "$token" ) </dev/null >/dev/null 2>&1 &
}

round() {
    prepare || return 0
    collect_status || :
    collect_log || :
    # The unit facts do not change while it runs: collected once per start (and again for a save).
    [ -n "$FACTS_DONE" ] || { collect_facts || :; FACTS_DONE=1; }
    rm -f "$UI_DIR/filter.tmp" "$UI_DIR/log.tmp" "$UI_DIR/status.tmp" "$UI_DIR/facts.tmp" "$UI_DIR/diag.tmp" "$UI_DIR/diag-latest.tmp"
}

# A removal that was cut off (ignition off, service restart) leaves its lock and a "working" state
# behind; at start nothing of ours is running yet, so clear the lock and report it as failed.
clear_stale_removal() {
    typeset n r id
    [ -e "$NEMDIR/gen5wkr.ui-removing" ] && [ ! -L "$NEMDIR/gen5wkr.ui-removing" ] || return 0
    recovery_lock_live && return 0
    rm -f "$NEMDIR/gen5wkr.ui-removing"
    [ -f "$REMOVED" ] && [ ! -L "$REMOVED" ] && IFS=' ' read -r n r id < "$REMOVED"
    [ "$r" = working ] && set_removed "${n:-0}" failed "${id:-interrupted}"
}
trap 'exit 0' HUP INT TERM
clear_stale_removal
while :; do
    apply_requests
    trim_pkg_logs
    round
    apply_requests   # the first pass may come before the folder exists (needed by a save)
    [ -z "$UILOG_TEST_ONCE" ] || exit 0
    # Requests are looked at every few seconds so a switch takes effect quickly.
    waited=0
    while [ "$waited" -lt "$INTERVAL" ]; do
        sleep "$REQ_STEP"
        waited=$((waited + REQ_STEP))
        apply_requests
    done
done
