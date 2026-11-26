#!/system/bin/sh
# Failure evidence only: no service, radio, framework or overlay mutations.
umask 077
BASE=${0%/*}
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
SH=/system/bin/sh
[ -z "$ROOT" ] || SH=$(command -v mksh)
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local p=$1
    while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
plain "$SH" && [ -x "$SH" ] || exit 1
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || exit 1
    case "$BASE" in "$ROOT"/data/*) :;; *) exit 1;; esac
else
    case "$(id)" in uid=0\(*) :;; *) exit 1;; esac
    case "$BASE" in /data/*) :;; *) exit 1;; esac
fi
case "$1" in capture|active) :;; *) exit 2;; esac
reason=$2
case "$reason" in ''|*[!a-zA-Z0-9_=.:\ -]* ) reason=unspecified;; esac
boot=$(cat "$ROOT/proc/sys/kernel/random/boot_id") || exit 1
case "$boot" in ''|*[!a-zA-Z0-9-]*) exit 1;; esac
[ "${#boot}" -le 64 ] || exit 1
STATE=$ROOT/data/local/gen5w-portable
STORE=$STATE/diagnostics
plain "$STATE" && [ -d "$STATE" ] && plain "$STORE" || exit 1
[ -d "$STORE" ] || mkdir "$STORE" || exit 1
chmod 700 "$STORE" || exit 1
# At most six failure boots; never overwrite the first failure of a boot.
prefix=failure; limit=6
if [ "$1" = active ]; then
    case "$2" in ''|*[!0-9]*) exit 2;; esac
    [ "${#2}" -le 10 ] || exit 2
    prefix=active; limit=8
    OUT=$STORE/active-$boot-$2
else
    OUT=$STORE/failure-$boot
fi
plain "$OUT" || exit 1
[ ! -e "$OUT" ] || { [ -d "$OUT" ] && exit 0; exit 1; }
count=0
for dir in "$STORE"/"$prefix"-*; do [ ! -d "$dir" ] || count=$((count+1)); done
if [ "$prefix" = active ] && [ "$count" -ge "$limit" ]; then
    # Retire only flat snapshots already copied and synced to USB. Failures and
    # unexported captures remain intact; the next save can capture current rings.
    for dir in "$STORE"/active-*; do
        plain "$dir" && [ -d "$dir" ] && plain "$dir/EXPORTED" && [ -f "$dir/EXPORTED" ] || continue
        safe=1
        for file in "$dir"/*; do plain "$file" && [ -f "$file" ] || safe=0; done
        [ "$safe" = 1 ] || continue
        for file in "$dir"/*; do rm -f "$file" || exit 1; done
        rmdir "$dir" || exit 1
        count=$((count-1)); [ "$count" -lt "$limit" ] && break
    done
fi
[ "$count" -lt "$limit" ] || { echo 'diagnostics: snapshot limit reached; export before collecting more' >&2; exit 1; }
STAGE=$STORE/.stage-$boot-$$
plain "$STAGE" || exit 1
if [ -e "$STAGE" ]; then
    [ -d "$STAGE" ] && rm -rf "$STAGE" || exit 1
fi
mkdir "$STAGE" && chmod 700 "$STAGE" || exit 1
trap 'rm -rf "$STAGE" 2>/dev/null || :' EXIT
mkdir "$OUT" || exit 1
{
    echo "boot=$boot"
    echo "reason=$reason"
    cat "$ROOT/proc/uptime"
    date
} > "$OUT/START"
# Privacy filtering removed at the user's request (2026-11-26): diagnostics keep every line.
PRIV='^G5W_NO_PRIVACY_FILTER_NEVER_MATCHES^'
PROP_ALLOW='^\[(ro\.build|ro\.product|ro\.board|ro\.hardware|ro\.daudio|ro\.system|ro\.boot\.mode|persist\.ium|persist\.service\.adb|persist\.adb|persist\.iap2|sys\.launcher3|sys\.boot_completed|tcc\.|wifi\.interface|wrap\.|init\.svc\.|log\.tag\.|debug\.gen5wkr)'
WIFI_ALLOW='^(fixture-dump-|Wi-Fi is |Stay-awake|mWifiState|mWifiApState|curState=|mNetworkInfo|interface=|mCountryCode|SoftAp|Tethering|WifiService|WifiStateMachine|DhcpStateMachine|  state=|  mApInterface|  mFrequency|  mChannel)'
BT_ALLOW='^(fixture-dump-|Bluetooth Status|  enabled:|  state:|  scan mode:|  AdapterState|Profile:|  mProfile|  A2dp|  Headset|  Hfp|  Avrcp|  Rfcomm|  Sdp|  mConnectionState|  State:)'
filter_priv() {
    local src=$1 dst=$2 rc=0
    plain "$src" && plain "$dst" || return 1
    grep -a -v -E "$PRIV" "$src" > "$dst" 2>/dev/null; rc=$?
    if [ "$rc" -gt 1 ]; then
        echo '(privacy filter unavailable)' > "$dst"
        return 1
    fi
    return 0
}
copy_raw() {
    plain "$2" && [ -f "$2" ] || return 0
    dd if="$2" of="$OUT/$1" bs=4096 count=32 2>/dev/null
}
copy() {
    local raw="$STAGE/$1.raw" flt="$STAGE/$1.flt" out="$STAGE/$1.out"
    plain "$2" && [ -f "$2" ] && plain "$raw" && plain "$flt" && plain "$out" || return 0
    dd if="$2" of="$raw" bs=4096 count=64 2>/dev/null
    filter_priv "$raw" "$flt" || :
    dd if="$flt" of="$out" bs=4096 count=32 2>/dev/null
    mv "$out" "$OUT/$1"
    rm -f "$raw" "$flt" "$out"
}
file_size() {
    local line size
    line=$(ls -l "$1" 2>/dev/null) || return 1
    set -- $line
    size=${5:-}
    case "$size" in ''|*[!0-9]*) size=${4:-};; esac
    case "$size" in ''|*[!0-9]*) return 1;; esac
    echo "$size"
}
copy_debug() {
    local name=$1 src=$2 blocks=$3 raw="$STAGE/$1.raw" flt="$STAGE/$1.flt"
    local size max_bytes skip=0
    plain "$src" && [ -f "$src" ] && plain "$raw" && plain "$flt" || return 0
    max_bytes=$(( blocks * 4096 ))
    size=$(file_size "$src") || size=0
    if [ "$size" -gt "$max_bytes" ]; then
        skip=$(( (size - max_bytes + 4095) / 4096 ))
        dd if="$src" of="$raw" bs=4096 skip="$skip" count="$blocks" 2>/dev/null || :
    else
        dd if="$src" of="$raw" bs=4096 count="$blocks" 2>/dev/null || :
    fi
    filter_priv "$raw" "$flt" || :
    mv "$flt" "$OUT/$name"
    rm -f "$raw" "$flt"
}
for dir in boot session runtime overlay ap; do
    for file in "$STATE/$dir"/*; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        copy "$dir-${file##*/}" "$file"
    done
done
for name in status log diag-latest.txt restore.log; do copy "manager-$name" "$ROOT/data/nemesis/gen5wkr.ui/$name"; done
copy_raw meminfo.txt "$ROOT/proc/meminfo"
copy_raw net-dev.txt "$ROOT/proc/net/dev"
# The legacy network-ADB switch can overlap the projection AP's subnet on eth0.
# Keep kernel route evidence before Binder queries; never change interfaces here.
copy_raw net-route.txt "$ROOT/proc/net/route"
for name in hud-owner.status hud-health.status hud-variant.status; do
    copy_raw "$name" "$ROOT/data/data/kr.gen5w.core/files/$name"
done
copy_raw dipo-ready.txt "$ROOT/data/data/com.daudio.app.dipo/files/gen5w-portable-ready"
copy_raw installed-candidate.json "$BASE/CANDIDATE.json"
copy_raw installed-SHA256SUMS "$BASE/SHA256SUMS"
copy_raw persistent-manifest.txt "$STATE/persistent/manifest"
if plain "$ROOT/system/lib/libCarPlayAudio.so" && [ -f "$ROOT/system/lib/libCarPlayAudio.so" ]; then
    "$BASE/bin/dex-patch" sha256 "$ROOT/system/lib/libCarPlayAudio.so" > "$OUT/audio-lib-sha256.txt" 2>/dev/null || :
fi
# Wi-Fi chosen at install and the USB dongle service: state, log, loaded
# modules, firmware search path and plugged-in USB device IDs.
copy wifi-backend.txt "$STATE/wifi-backend"
copy wifi-backend-why.txt "$STATE/wifi-backend-why"
for file in "$STATE/dongle"/*; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    copy "dongle-${file##*/}" "$file"
done
copy dongle.log "$ROOT/data/nemesis/logs/gen5w.kr.portable/dongle.log"
copy_raw modules.txt "$ROOT/proc/modules"
copy_raw firmware-path.txt "$ROOT/sys/module/firmware_class/parameters/path"
for v in "$ROOT"/sys/bus/usb/devices/*/idVendor; do
    p=${v%idVendor}idProduct
    [ -f "$v" ] && [ ! -L "$v" ] && [ -f "$p" ] && [ ! -L "$p" ] || continue
    IFS= read -r vid < "$v"; IFS= read -r pid < "$p"
    d=${v%/idVendor}; print -r -- "${d##*/} $vid:$pid"
done > "$OUT/usb-devices.txt" 2>/dev/null
# Trusted kernel interface: /proc/mounts is normally a symlink to self/mounts.
dd if="$ROOT/proc/mounts" of="$OUT/mounts.txt" bs=4096 count=32 2>/dev/null
grab() {
    local name=$1 command cleanup=/system/bin/true part="$STAGE/$1.part" filtered="$STAGE/$1.part.f" allow="$STAGE/$1.part.a" rcfile="$STAGE/$1.rc" staged_out="$STAGE/$1.out" out="$OUT/$1" sup_rc=0 rc=0 mode=default; shift
    command=$(command -v "$1") || { echo unavailable > "$out"; return 0; }
    shift
    [ -z "$ROOT" ] || cleanup=/bin/true
    plain "$part" && plain "$filtered" && plain "$allow" && plain "$rcfile" && plain "$staged_out" && plain "$out" || return 1
    case "$name" in
        properties.txt) mode=prop;;
        wifi.txt) mode=wifi;;
        bluetooth.txt|bluetooth-manager.txt) mode=bt;;
    esac
    G5_PRIV=$PRIV G5_PROP=$PROP_ALLOW G5_WIFI=$WIFI_ALLOW G5_BT=$BT_ALLOW G5_QUOTE='"' \
    "$BASE/bin/dex-patch" supervise 5 "$cleanup" "$SH" -c '
        ulimit -f 2048
        mode=$1; part=$2; allow=$3; filtered=$4; staged_out=$5; rcfile=$6; cmd=$7; shift 7
        "$cmd" "$@" > "$part" 2>&1
        print -r -- "$?" > "$rcfile"
        prc=0
        mode=all # no allow-list / privacy filtering
        case "$mode" in
            prop)
                grep -a -E "$G5_PROP" "$part" > "$allow" 2>/dev/null; prc=$?
                if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                else
                    grep -a -v -E "$G5_PRIV" "$allow" > "$filtered" 2>/dev/null; prc=$?
                    [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered"
                fi;;
            wifi)
                grep -a -E "$G5_WIFI" "$part" > "$allow" 2>/dev/null; prc=$?
                if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                else
                    grep -a -v -F "$G5_QUOTE" "$allow" > "$allow.q" 2>/dev/null; prc=$?
                    if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                    else
                        grep -a -v -E "$G5_PRIV" "$allow.q" > "$filtered" 2>/dev/null; prc=$?
                        [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered"
                    fi
                fi;;
            bt)
                grep -a -E "$G5_BT" "$part" > "$allow" 2>/dev/null; prc=$?
                if [ "$prc" -gt 1 ]; then echo "(privacy filter unavailable)" > "$filtered"
                else
                    grep -a -v -E "$G5_PRIV" "$allow" > "$filtered" 2>/dev/null; prc=$?
                    [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered"
                fi;;
            *)
                grep -a -v -E "$G5_PRIV" "$part" > "$filtered" 2>/dev/null; prc=$?
                [ "$prc" -le 1 ] || echo "(privacy filter unavailable)" > "$filtered";;
        esac
        dd if="$filtered" of="$staged_out" bs=4096 count=64 2>/dev/null
    ' _ "$mode" "$part" "$allow" "$filtered" "$staged_out" "$rcfile" "$command" "$@"
    sup_rc=$?
    if [ -f "$rcfile" ]; then
        IFS= read -r rc < "$rcfile" || rc=1
        case "$rc" in ''|*[!0-9]*) rc=1;; esac
    else
        [ "$sup_rc" -ne 0 ] && rc=124 || rc=1
    fi
    if [ -f "$staged_out" ]; then
        mv "$staged_out" "$out" 2>/dev/null || rm -f "$staged_out"
    fi
    rm -f "$part" "$allow" "$allow.q" "$filtered" "$rcfile" "$staged_out"
    [ -f "$out" ] || echo unavailable > "$out"
    echo "$name|$rc" >> "$OUT/commands.txt"
}
# Capture recent rings and live Binder/system state before large rolling files.
grab logcat-main.txt logcat -d -v time -t 800 -b main
grab logcat-system.txt logcat -d -v time -b system
grab logcat-events.txt logcat -d -v time -b events
grab processes.txt ps
for role in BROKER OWNER; do
    case "$role" in BROKER) pid=$PORTABLE_DIAG_BROKER_PID;; OWNER) pid=$PORTABLE_DIAG_OWNER_PID;; esac
    case "$pid" in ''|*[!0-9]*) continue;; esac
    for file in status limits stat; do copy_raw "$role-$file" "$ROOT/proc/$pid/$file"; done
    grab "$role-fd.txt" ls -l "$ROOT/proc/$pid/fd"
done
grab properties.txt getprop
# AA setup uses the existing OEM RFCOMM/WPP/GPM path, independently of CarPlay.
# Preserve its state and the legacy ADB switches before slower audio/Wi-Fi dumps.
# These two property values contain no SSID, passphrase or device identifier.
grab network-adb-enable.txt getprop persist.service.adb.tcp.enable
grab network-adb-port.txt getprop persist.adb.tcp.port
grab gpm.txt dumpsys gpm
grab audio.txt dumpsys audio
grab audio-flinger.txt dumpsys media.audio_flinger
grab audio-policy.txt dumpsys media.audio_policy
grab dipo.txt dumpsys dipo
grab split.txt dumpsys com.mobis.splitscreen.right.SplitScreenHome
grab wifi.txt dumpsys wifi
grab bluetooth.txt dumpsys bluetooth
grab bluetooth-manager.txt dumpsys bluetooth_manager
grab binder-services.txt service list
# Rolling debug files: active saves recent rings + focus-first to finish well inside supervision budget.
if [ "$prefix" = active ]; then
    copy_debug debug-logcat.log "$STATE/debug/logcat.log" 512
    copy_debug debug-logcat.log.1 "$STATE/debug/logcat.log.1" 512
    copy_debug debug-focus.log "$STATE/debug/focus.log" 256
    copy_debug debug-focus.log.1 "$STATE/debug/focus.log.1" 256
    copy_debug debug-focus-first.log "$STATE/debug/focus-first.log" 1024
else
    for file in "$STATE/debug"/logcat.log "$STATE/debug"/logcat.log.1 "$STATE/debug"/logcat.log.2 "$STATE/debug"/logcat.log.3; do
        copy_debug "debug-${file##*/}" "$file" 1024
    done
    for file in "$STATE/debug"/focus.log "$STATE/debug"/focus.log.1 "$STATE/debug"/focus.log.2 "$STATE/debug"/focus.log.3; do
        copy_debug "debug-${file##*/}" "$file" 256
    done
    copy_debug debug-focus-first.log "$STATE/debug/focus-first.log" 1024
fi
echo done > "$OUT/DONE"
sync
